//
//  Archive+EntryOperation.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension Archive {
    /// Write files, directories or symlinks to the receiver.
    ///
    /// - Parameters:
    ///   - path: The path that is used to identify an `Entry` within the `Archive` file.
    ///   - baseURL: The base URL of the resource to add.
    ///              The `baseURL` combined with `path` must form a fully qualified file URL.
    ///   - compressionMethod: Indicates the `CompressionMethod` that should be applied to `Entry`.
    ///                        By default, no compression will be applied.
    ///   - bufferSize: The maximum size of the write buffer and the compression buffer (if needed).
    ///   - progress: A progress object that can be used to track or cancel the add operation.
    /// - Throws: An error if the source file cannot be read or the receiver is not writable.
    public func addEntry(with path: String, relativeTo baseURL: URL,
                         compressionMethod: CompressionMethod = .none,
                         bufferSize: UInt32 = defaultWriteChunkSize, progress: Progress? = nil) throws {
        let fileURL = baseURL.appendingPathComponent(path)

        try self.addEntry(with: path, fileURL: fileURL, compressionMethod: compressionMethod,
                          bufferSize: bufferSize, progress: progress)
    }

    /// Write files, directories or symlinks to the receiver.
    ///
    /// - Parameters:
    ///   - path: The path that is used to identify an `Entry` within the `Archive` file.
    ///   - fileURL: An absolute file URL referring to the resource to add.
    ///   - compressionMethod: Indicates the `CompressionMethod` that should be applied to `Entry`.
    ///                        By default, no compression will be applied.
    ///   - bufferSize: The maximum size of the write buffer and the compression buffer (if needed).
    ///   - progress: A progress object that can be used to track or cancel the add operation.
    /// - Throws: An error if the source file cannot be read or the receiver is not writable.
    public func addEntry(with path: String, fileURL: URL, compressionMethod: CompressionMethod = .none,
                         bufferSize: UInt32 = defaultWriteChunkSize, progress: Progress? = nil) throws {
        let fileManager = FileManager()
        guard fileManager.itemExists(at: fileURL) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        let type = try FileManager.typeForItem(at: fileURL)
        // symlinks do not need to be readable
        guard type == .symlink || fileManager.isReadableFile(atPath: fileURL.path) else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: url.path])
        }
        let modDate = try FileManager.fileModificationDateTimeForItem(at: fileURL)
        let uncompressedSize = type == .directory ? 0 : try FileManager.fileSizeForItem(at: fileURL)
        let permissions = try FileManager.permissionsForItem(at: fileURL)
        var provider: Provider
        switch type {
        case .file:
            let entryFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
            guard let entryFile: UnsafeMutablePointer<FILE> = fopen(entryFileSystemRepresentation, "rb") else {
                throw CocoaError(.fileNoSuchFile)
            }
            defer { fclose(entryFile) }
            provider = { _, _ in return try Data.readChunk(of: Int(bufferSize), from: entryFile) }
            try self.addEntry(with: path, type: type, uncompressedSize: uncompressedSize,
                              modificationDate: modDate, permissions: permissions,
                              compressionMethod: compressionMethod, bufferSize: bufferSize,
                              progress: progress, provider: provider)
        case .directory:
            provider = { _, _ in return Data() }
            try self.addEntry(with: path.hasSuffix("/") ? path : path + "/",
                              type: type, uncompressedSize: uncompressedSize,
                              modificationDate: modDate, permissions: permissions,
                              compressionMethod: compressionMethod, bufferSize: bufferSize,
                              progress: progress, provider: provider)
        case .symlink:
            provider = { _, _ -> Data in
                let linkDestination = try fileManager.destinationOfSymbolicLink(atPath: fileURL.path)
                let linkFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: linkDestination)
                let linkLength = Int(strlen(linkFileSystemRepresentation))
                let linkBuffer = UnsafeBufferPointer(start: linkFileSystemRepresentation, count: linkLength)
                return Data(buffer: linkBuffer)
            }
            try self.addEntry(with: path, type: type, uncompressedSize: uncompressedSize,
                              modificationDate: modDate, permissions: permissions,
                              compressionMethod: compressionMethod, bufferSize: bufferSize,
                              progress: progress, provider: provider)
        }
    }

    /// Write files, directories or symlinks to the receiver.
    ///
    /// - Parameters:
    ///   - path: The path that is used to identify an `Entry` within the `Archive` file.
    ///   - type: Indicates the `Entry.EntryType` of the added content.
    ///   - uncompressedSize: The uncompressed size of the data that is going to be added with `provider`.
    ///   - modificationDate: A `Date` describing the file modification date of the `Entry`.
    ///                       Default is the current `Date`.
    ///   - permissions: POSIX file permissions for the `Entry`.
    ///                  Default is `0`o`644` for files and symlinks and `0`o`755` for directories.
    ///   - compressionMethod: Indicates the `CompressionMethod` that should be applied to `Entry`.
    ///                        By default, no compression will be applied.
    ///   - bufferSize: The maximum size of the write buffer and the compression buffer (if needed).
    ///   - progress: A progress object that can be used to track or cancel the add operation.
    ///   - provider: A closure that accepts a position and a chunk size. Returns a `Data` chunk.
    /// - Throws: An error if the source data is invalid or the receiver is not writable.
    public func addEntry(with path: String, type: Entry.EntryType, uncompressedSize: UInt,
                         modificationDate: Date = Date(), permissions: UInt16? = nil,
                         compressionMethod: CompressionMethod = .none, bufferSize: UInt32 = defaultWriteChunkSize,
                         progress: Progress? = nil, provider: Provider) throws {
        guard self.accessMode != .read else { throw ArchiveError.unwritableArchive }
        // Directories and symlinks cannot be compressed
        let compressionMethod = type == .file ? compressionMethod : .none
        guard uncompressedSize <= Int64.max else {
            throw ArchiveError.invalidUncompressedSize
        }
        progress?.totalUnitCount = type == .directory ? defaultDirectoryUnitCount : Int64(uncompressedSize)
        let endOfCentralDirRecord = self.endOfCentralDirectoryRecord
        let zip64EOCD = self.zip64EndOfCentralDirectory
        let existingStartOfCD = zip64EOCD?.record.offsetToStartOfCentralDirectory
            ?? UInt(endOfCentralDirRecord.offsetToStartOfCentralDirectory)
        guard existingStartOfCD <= Int.max else {
            throw ArchiveError.invalidStartOfCentralDirectoryOffset
        }
        var startOfCDInt = Int(existingStartOfCD)
        fseek(self.archiveFile, startOfCDInt, SEEK_SET)
        let sizeOfCD = zip64EOCD?.record.sizeOfCentralDirectory ?? UInt(endOfCentralDirRecord.sizeOfCentralDirectory)
        guard sizeOfCD <= Int.max else {
            throw ArchiveError.invalidSizeOfCentralDirectory
        }
        let existingCentralDirData = try Data.readChunk(of: Int(sizeOfCD), from: self.archiveFile)
        fseek(self.archiveFile, startOfCDInt, SEEK_SET)
        let localFileHeaderStart = ftell(self.archiveFile)
        let modDateTime = modificationDate.fileModificationDateTime
        defer { fflush(self.archiveFile) }
        do {
            // Local File Header
            var localFileHeader = try self.writeLocalFileHeader(path: path, compressionMethod: compressionMethod,
                                                                size: (uncompressedSize, 0), checksum: 0,
                                                                modificationDateTime: modDateTime)
            // File Data
            let (written, checksum) = try self.writeEntry(uncompressedSize: uncompressedSize, type: type,
                                                          compressionMethod: compressionMethod, bufferSize: bufferSize,
                                                          progress: progress, provider: provider)
            startOfCDInt = ftell(self.archiveFile)
            // Local File Header
            // Write the local file header a second time. Now with compressedSize (if applicable) and a valid checksum.
            fseek(self.archiveFile, localFileHeaderStart, SEEK_SET)
            localFileHeader = try self.writeLocalFileHeader(path: path, compressionMethod: compressionMethod,
                                                            size: (uncompressedSize, written),
                                                            checksum: checksum, modificationDateTime: modDateTime)
            // Central Directory
            fseek(self.archiveFile, startOfCDInt, SEEK_SET)
            _ = try Data.write(chunk: existingCentralDirData, to: self.archiveFile)
            let permissions = permissions ?? (type == .directory ? defaultDirectoryPermissions : defaultFilePermissions)
            let externalAttributes = FileManager.externalFileAttributesForEntry(of: type, permissions: permissions)
            let offset = UInt(localFileHeaderStart)
            let centralDir = try self.writeCentralDirectoryStructure(localFileHeader: localFileHeader,
                                                                     relativeOffset: offset,
                                                                     externalFileAttributes: externalAttributes)
            // End of Central Directory Record (including Zip64 End of Central Directory Record/Locator)
            let startOfEOCDInt = ftell(self.archiveFile)
            let eocdStructure = try self.writeEndOfCentralDirectory(centralDirectoryStructure: centralDir,
                                                                        startOfCentralDirectory: startOfCDInt,
                                                                        startOfEndOfCentralDirectory: startOfEOCDInt,
                                                                        operation: .add)
            (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = eocdStructure
        } catch ArchiveError.cancelledOperation {
            try rollback(localFileHeaderStart, existingCentralDirData, endOfCentralDirRecord, zip64EOCD)
            throw ArchiveError.cancelledOperation
        }
    }

    /// Remove a ZIP `Entry` from the receiver.
    ///
    /// - Parameters:
    ///   - entry: The `Entry` to remove.
    ///   - bufferSize: The maximum size for the read and write buffers used during removal.
    ///   - progress: A progress object that can be used to track or cancel the remove operation.
    /// - Throws: An error if the `Entry` is malformed or the receiver is not writable.
    public func remove(_ entry: Entry, bufferSize: UInt32 = defaultReadChunkSize, progress: Progress? = nil) throws {
        guard self.accessMode != .read else { throw ArchiveError.unwritableArchive }
        let (tempArchive, tempDir) = try self.makeTempArchive()
        defer { tempDir.map { try? FileManager().removeItem(at: $0) } }
        progress?.totalUnitCount = self.totalUnitCountForRemoving(entry)
        var centralDirectoryData = Data()
        var offset = 0
        for currentEntry in self {
            let centralDirectoryStructure = currentEntry.centralDirectoryStructure
            if currentEntry != entry {
                let entryStart = Int(currentEntry.centralDirectoryStructure.relativeOffsetOfLocalHeader)
                fseek(self.archiveFile, entryStart, SEEK_SET)
                let provider: Provider = { (_, chunkSize) -> Data in
                    return try Data.readChunk(of: Int(chunkSize), from: self.archiveFile)
                }
                let consumer: Consumer = {
                    if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                    _ = try Data.write(chunk: $0, to: tempArchive.archiveFile)
                    progress?.completedUnitCount += Int64($0.count)
                }
                _ = try Data.consumePart(of: Int(currentEntry.localSize), chunkSize: Int(bufferSize),
                                         provider: provider, consumer: consumer)
                let centralDir = CentralDirectoryStructure(centralDirectoryStructure: centralDirectoryStructure,
                                                           offset: UInt32(offset))
                centralDirectoryData.append(centralDir.data)
            } else { offset = currentEntry.localSize }
        }
        let startOfCentralDirectory = ftell(tempArchive.archiveFile)
        _ = try Data.write(chunk: centralDirectoryData, to: tempArchive.archiveFile)
        let startOfEndOfCentralDirectory = ftell(tempArchive.archiveFile)
        tempArchive.endOfCentralDirectoryRecord = self.endOfCentralDirectoryRecord
        tempArchive.zip64EndOfCentralDirectory = self.zip64EndOfCentralDirectory
        let ecodStructure = try
            tempArchive.writeEndOfCentralDirectory(centralDirectoryStructure: entry.centralDirectoryStructure,
                                                   startOfCentralDirectory: startOfCentralDirectory,
                                                   startOfEndOfCentralDirectory: startOfEndOfCentralDirectory,
                                                   operation: .remove)
        (tempArchive.endOfCentralDirectoryRecord, tempArchive.zip64EndOfCentralDirectory) = ecodStructure
        (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = ecodStructure
        fflush(tempArchive.archiveFile)
        try self.replaceCurrentArchive(with: tempArchive)
    }
}
