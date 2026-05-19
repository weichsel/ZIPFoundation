//
//  Archive+Reading.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension Archive {

    /// Mutable byte counter shared across one or more `extract` calls to enforce a cumulative cap
    /// on decompressed output. Constructed at the top of `unzipItem` and threaded through each
    /// per-entry extract so a single archive-wide budget can be enforced regardless of how many
    /// entries (or AppleDouble companions) are extracted.
    final class ByteBudget {
        let limit: Int64
        var consumed: Int64 = 0

        init(limit: Int64) { self.limit = limit }

        /// Wraps `consumer` so each chunk is charged against the budget before being forwarded.
        /// Throws `ArchiveError.extractedByteLimitExceeded` if the cumulative total would exceed
        /// `limit`. The check runs before the inner consumer, so the inner side effect (file
        /// write, in-memory append) does not happen for the overshooting chunk.
        func wrap(_ consumer: @escaping Consumer) -> Consumer {
            return { data in
                self.consumed += Int64(data.count)
                if self.consumed > self.limit { throw ArchiveError.extractedByteLimitExceeded }
                try consumer(data)
            }
        }
    }

    /// Read a ZIP `Entry` from the receiver and write it to `url`.
    ///
    /// - Parameters:
    ///   - entry: The ZIP `Entry` to read.
    ///   - url: The destination file URL.
    ///   - bufferSize: The maximum size of the read buffer and the decompression buffer (if needed).
    ///   - skipCRC32: Optional flag to skip calculation of the CRC32 checksum to improve performance.
    ///   - symlinksValidWithin: Any symlink target that resolves outside this URL is rejected for security reasons.
    ///                          Pass `.rootFS` to allow symlinks to point anywhere on the filesystem.
    ///   - maxExtractedBytes: Optional cap on the number of decompressed bytes this call may produce
    ///                        (including any AppleDouble companion). `ArchiveError.extractedByteLimitExceeded`
    ///                        is thrown if the limit is crossed. Use this to defend against zip bombs when
    ///                        extracting untrusted archives. Partial output on disk is not cleaned up on
    ///                        throw — the caller is responsible for that. Default is `nil` (no limit).
    ///   - progress: A progress object that can be used to track or cancel the extract operation.
    ///   - preservesAppleMetadata: On Darwin platforms, look up the matching `__MACOSX/.../._<name>`
    ///                             AppleDouble companion entry in the archive (if any) and apply its
    ///                             extended attributes, Finder info, and resource fork to the file at
    ///                             `url` after extraction. No-op when `entry` is itself a companion.
    ///                             Default is `true`.
    /// - Returns: The checksum of the processed content or 0 if the `skipCRC32` flag was set to `true`.
    /// - Throws: An error if the destination file cannot be written or the entry contains malformed content.
    public func extract(_ entry: Entry, to url: URL, bufferSize: Int = defaultReadChunkSize,
                        skipCRC32: Bool = false,
                        symlinksValidWithin: URL? = nil,
                        maxExtractedBytes: Int64? = nil,
                        progress: Progress? = nil,
                        preservesAppleMetadata: Bool = true) throws -> CRC32 {
        return try self.extract(entry, to: url, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                symlinksValidWithin: symlinksValidWithin,
                                budget: maxExtractedBytes.map { ByteBudget(limit: $0) },
                                progress: progress,
                                preservesAppleMetadata: preservesAppleMetadata)
    }

    /// Internal extract that accepts a shared `ByteBudget`. Used by `unzipItem` to enforce a single
    /// archive-wide byte cap across all entries.
    func extract(_ entry: Entry, to url: URL, bufferSize: Int = defaultReadChunkSize,
                 skipCRC32: Bool = false,
                 symlinksValidWithin: URL? = nil,
                 budget: ByteBudget?,
                 progress: Progress? = nil,
                 preservesAppleMetadata: Bool = true) throws -> CRC32 {
        guard bufferSize > 0 else {
            throw ArchiveError.invalidBufferSize
        }
        let fileManager = FileManager()
        var checksum = CRC32(0)
        switch entry.type {
        case .file:
            guard fileManager.itemExists(at: url) == false else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
            }
            try fileManager.createParentDirectoryStructure(for: url)
            let destinationRepresentation = fileManager.fileSystemRepresentation(withPath: url.path)
            guard let destinationFile: FILEPointer = fopen(destinationRepresentation, "wb+") else {
                throw POSIXError(errno, path: url.path)
            }
            defer { fclose(destinationFile) }
            let rawConsumer: Consumer = { _ = try Data.write(chunk: $0, to: destinationFile) }
            let consumer = budget?.wrap(rawConsumer) ?? rawConsumer
            checksum = try self.extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                        progress: progress, consumer: consumer)
        case .directory:
            let consumer = { (_: Data) in
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
            checksum = try self.extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                        progress: progress, consumer: consumer)
        case .symlink:
            guard fileManager.itemExists(at: url) == false else {
                throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: url.path])
            }
            let rawConsumer: Consumer = { (data: Data) in
                guard let linkPath = String(data: data, encoding: .utf8) else { throw ArchiveError.invalidEntryPath }

                let parentURL = url.deletingLastPathComponent()
                let isAbsolutePath = (linkPath as NSString).isAbsolutePath
                let linkURL = URL(fileURLWithPath: linkPath, relativeTo: isAbsolutePath ? nil : parentURL)
                let isContained = linkURL.isContained(in: symlinksValidWithin ?? parentURL)
                guard isContained else { throw ArchiveError.uncontainedSymlink }

                try fileManager.createParentDirectoryStructure(for: url)
                try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: linkPath)
            }
            let consumer = budget?.wrap(rawConsumer) ?? rawConsumer
            checksum = try self.extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                        progress: progress, consumer: consumer)
        }
        try fileManager.transferAttributes(from: entry, toItemAtURL: url)
        if preservesAppleMetadata {
            try self.applyAppleDoubleCompanionIfPresent(for: entry, to: url, bufferSize: bufferSize,
                                                        skipCRC32: skipCRC32, budget: budget)
        }
        return checksum
    }

    // MARK: - AppleDouble helpers

    /// Looks up the `__MACOSX/.../._<name>` companion for `entry` within the archive and, if found,
    /// applies the encoded Apple metadata to the file at `url`. No-op when `entry` is itself a
    /// companion, when no companion exists, or on non-Darwin platforms.
    func applyAppleDoubleCompanionIfPresent(for entry: Entry, to url: URL,
                                            bufferSize: Int = defaultReadChunkSize,
                                            skipCRC32: Bool = false,
                                            budget: ByteBudget? = nil) throws {
#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        // Companion entries do not have companions of their own.
        guard FileManager.realEntryPath(fromAppleDoubleCompanionPath: entry.path) == nil else { return }
        guard let companionPath = FileManager.appleDoubleCompanionPath(forEntryPath: entry.path) else { return }
        guard let companion = self[companionPath] else { return }
        var buffer = Data()
        let rawConsumer: Consumer = { buffer.append($0) }
        let consumer = budget?.wrap(rawConsumer) ?? rawConsumer
        _ = try self.extract(companion, bufferSize: bufferSize, skipCRC32: skipCRC32,
                             consumer: consumer)
        guard let payload = AppleDoublePayload.decode(buffer) else { return }
        FileManager.applyAppleDoublePayload(payload, to: url)
#else
        _ = (entry, url, bufferSize, skipCRC32, budget)
#endif
    }

    /// Read a ZIP `Entry` from the receiver and forward its contents to a `Consumer` closure.
    ///
    /// - Parameters:
    ///   - entry: The ZIP `Entry` to read.
    ///   - bufferSize: The maximum size of the read buffer and the decompression buffer (if needed).
    ///   - skipCRC32: Optional flag to skip calculation of the CRC32 checksum to improve performance.
    ///   - progress: A progress object that can be used to track or cancel the extract operation.
    ///   - consumer: A closure that consumes contents of `Entry` as `Data` chunks.
    /// - Returns: The checksum of the processed content or 0 if the `skipCRC32` flag was set to `true`..
    /// - Throws: An error if the destination file cannot be written or the entry contains malformed content.
    public func extract(_ entry: Entry, bufferSize: Int = defaultReadChunkSize, skipCRC32: Bool = false,
                        progress: Progress? = nil, consumer: Consumer) throws -> CRC32 {
        guard bufferSize > 0 else {
            throw ArchiveError.invalidBufferSize
        }
        var checksum = CRC32(0)
        let localFileHeader = entry.localFileHeader
        guard entry.dataOffset <= .max else { throw ArchiveError.invalidLocalHeaderDataOffset }
        fseeko(self.archiveFile, off_t(entry.dataOffset), SEEK_SET)
        progress?.totalUnitCount = self.totalUnitCountForReading(entry)
        switch entry.type {
        case .file:
            guard let compressionMethod = CompressionMethod(rawValue: localFileHeader.compressionMethod) else {
                throw ArchiveError.invalidCompressionMethod
            }
            switch compressionMethod {
            case .none: checksum = try self.readUncompressed(entry: entry, bufferSize: bufferSize,
                                                             skipCRC32: skipCRC32, progress: progress, with: consumer)
            case .deflate: checksum = try self.readCompressed(entry: entry, bufferSize: bufferSize,
                                                              skipCRC32: skipCRC32, progress: progress, with: consumer)
            }
        case .directory:
            try consumer(Data())
            progress?.completedUnitCount = self.totalUnitCountForReading(entry)
        case .symlink:
            checksum = try self.readSymbolicLink(entry: entry, bufferSize: bufferSize,
                                                 skipCRC32: skipCRC32, progress: progress, with: consumer)

        }
        return checksum
    }
}
