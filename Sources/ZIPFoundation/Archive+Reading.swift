//
//  Archive+Reading.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import Foundation
#if canImport(Android)
import Android
#endif

extension Archive {
    /// Read a ZIP `Entry` from the receiver and write it to `url`.
    ///
    /// - Important: `url` is used as is. Unlike `FileManager.unzipItem(at:to:)`, this method doesn't check
    ///              that `url` is located within a destination directory. Entry paths can contain `..` components
    ///              or start with a path delimiter, and the file system follows symlinks in `url`, including
    ///              symlinks that were extracted from the archive before. Callers that build `url` from
    ///              `entry.path` have to validate the resulting location themselves.
    ///
    /// - Parameters:
    ///   - entry: The ZIP `Entry` to read.
    ///   - url: The destination file URL.
    ///   - bufferSize: The maximum size of the read buffer and the decompression buffer (if needed).
    ///   - skipCRC32: Optional flag to skip calculation of the CRC32 checksum to improve performance.
    ///   - symlinksValidWithin: Any symlink target that resolves outside this URL is rejected for security reasons.
    ///                          Defaults to the directory that contains the symlink.
    ///                          Pass `.rootFS` to allow symlinks to point anywhere on the filesystem.
    ///   - progress: A progress object that can be used to track or cancel the extract operation.
    /// - Returns: The checksum of the processed content or 0 if the `skipCRC32` flag was set to `true`.
    /// - Throws: An error if the destination file cannot be written or the entry contains malformed content.
    public func extract(_ entry: Entry, to url: URL, bufferSize: Int = defaultReadChunkSize,
                        skipCRC32: Bool = false,
                        symlinksValidWithin: URL? = nil,
                        progress: Progress? = nil) throws -> CRC32 {
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
            let consumer = { _ = try Data.write(chunk: $0, to: destinationFile) }
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
            let linkPath: String
            (linkPath, checksum) = try self.readSymbolicLinkDestination(of: entry, bufferSize: bufferSize,
                                                                        skipCRC32: skipCRC32, progress: progress)

            // The link destination has to be resolved through the file system to account for
            // symlinks created by preceding entries. (e.g. `a -> .` followed by `b -> a/..`)
            let parentURL = url.deletingLastPathComponent()
            let isContained = URL.isSymlinkDestination(linkPath, ofSymlinkIn: parentURL,
                                                       containedIn: symlinksValidWithin ?? parentURL)
            guard isContained else { throw ArchiveError.uncontainedSymlink }

            try fileManager.createParentDirectoryStructure(for: url)
            try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: linkPath)
        }
        try fileManager.transferAttributes(from: entry, toItemAtURL: url)
        return checksum
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
        guard entry.dataOffset <= Int64.max else { throw ArchiveError.invalidLocalHeaderDataOffset }
        fseeko(self.archiveFile, zip_off_t(entry.dataOffset), SEEK_SET)
        progress?.totalUnitCount = self.totalUnitCountForReading(entry)
        switch entry.type {
        case .file, .symlink:
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
        }
        return checksum
    }
}

extension Archive {

    func readSymbolicLinkDestination(of entry: Entry, bufferSize: Int, skipCRC32: Bool,
                                     progress: Progress? = nil) throws -> (String, CRC32) {
        // The sizes of the entry can't be trusted. Collecting the destination stops at the size limit,
        // so that a small compressed entry can't allocate an arbitrary amount of memory.
        let size = entry.readSize
        guard size <= maxSymbolicLinkDestinationSize else { throw ArchiveError.invalidEntryPath }

        // The link destination of compressed symlinks can be delivered in multiple chunks.
        var linkData = Data()
        let checksum = try self.extract(entry, bufferSize: bufferSize, skipCRC32: skipCRC32, progress: progress,
                                        consumer: { (data) in
            guard linkData.count + data.count <= maxSymbolicLinkDestinationSize else {
                throw ArchiveError.invalidEntryPath
            }
            linkData.append(data)
        })
        guard let linkPath = String(data: linkData, encoding: .utf8) else { throw ArchiveError.invalidEntryPath }
        // A destination with a NUL byte can't be represented as a file system path.
        guard linkPath.utf8.contains(0) == false else { throw ArchiveError.invalidEntryPath }

        return (linkPath, checksum)
    }
}
