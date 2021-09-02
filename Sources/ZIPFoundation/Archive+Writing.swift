//
//  Archive+Writing.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension Archive {
    enum ModifyOperation: Int {
        case remove = -1
        case add = 1
    }

    typealias EndOfCentralDirectoryStructure = (EndOfCentralDirectoryRecord, ZIP64EndOfCentralDirectory?)

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
                         bufferSize: Int = defaultWriteChunkSize, progress: Progress? = nil) throws {
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
                         bufferSize: Int = defaultWriteChunkSize, progress: Progress? = nil) throws {
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
            provider = { _, _ in return try Data.readChunk(of: bufferSize, from: entryFile) }
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
    public func addEntry(with path: String, type: Entry.EntryType, uncompressedSize: Int64,
                         modificationDate: Date = Date(), permissions: UInt16? = nil,
                         compressionMethod: CompressionMethod = .none, bufferSize: Int = defaultWriteChunkSize,
                         progress: Progress? = nil, provider: Provider) throws {
        guard self.accessMode != .read else { throw ArchiveError.unwritableArchive }
        // Directories and symlinks cannot be compressed
        let compressionMethod = type == .file ? compressionMethod : .none
        progress?.totalUnitCount = type == .directory ? defaultDirectoryUnitCount : uncompressedSize
        let (eocdRecord, zip64EOCD) = (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory)
        var startOfCD = self.offsetToStartOfCentralDirectory
        fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
        let existingCDSize = self.sizeOfCentralDirectory
        let existingCDData = try Data.readChunk(of: Int(existingCDSize), from: self.archiveFile)
        fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
        let localFileHeaderStart = Int64(ftello(self.archiveFile))
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
            startOfCD = Int64(ftello(self.archiveFile))
            // Local File Header
            // Write the local file header a second time. Now with compressedSize (if applicable) and a valid checksum.
            fseeko(self.archiveFile, off_t(localFileHeaderStart), SEEK_SET)
            localFileHeader = try self.writeLocalFileHeader(path: path, compressionMethod: compressionMethod,
                                                            size: (uncompressedSize, written),
                                                            checksum: checksum, modificationDateTime: modDateTime)
            // Central Directory
            fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
            _ = try Data.writeLargeChunk(existingCDData, size: existingCDSize, bufferSize: bufferSize, to: archiveFile)
            let permissions = permissions ?? (type == .directory ? defaultDirectoryPermissions : defaultFilePermissions)
            let externalAttributes = FileManager.externalFileAttributesForEntry(of: type, permissions: permissions)
            let centralDir = try self.writeCentralDirectoryStructure(localFileHeader: localFileHeader,
                                                                     relativeOffset: localFileHeaderStart,
                                                                     externalFileAttributes: externalAttributes)
            // End of Central Directory Record (including ZIP64 End of Central Directory Record/Locator)
            let startOfEOCD = Int64(ftello(self.archiveFile))
            let eocdStructure = try self.writeEndOfCentralDirectory(centralDirectoryStructure: centralDir,
                                                                    startOfCentralDirectory: startOfCD,
                                                                    startOfEndOfCentralDirectory: startOfEOCD,
                                                                    operation: .add)
            (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = eocdStructure
        } catch ArchiveError.cancelledOperation {
            try rollback(localFileHeaderStart, (existingCDData, existingCDSize), bufferSize, eocdRecord, zip64EOCD)
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
    public func remove(_ entry: Entry, bufferSize: Int = defaultReadChunkSize, progress: Progress? = nil) throws {
        guard self.accessMode != .read else { throw ArchiveError.unwritableArchive }
        let (tempArchive, tempDir) = try self.makeTempArchive()
        defer { tempDir.map { try? FileManager().removeItem(at: $0) } }
        progress?.totalUnitCount = self.totalUnitCountForRemoving(entry)
        var centralDirectoryData = Data()
        var offset: Int64 = 0
        for currentEntry in self {
            let centralDirectoryStructure = currentEntry.centralDirectoryStructure
            if currentEntry != entry {
                let entryStart = centralDirectoryStructure.exactRelativeOffsetOfLocalHeader
                fseeko(self.archiveFile, off_t(entryStart), SEEK_SET)
                let provider: Provider = { (_, chunkSize) -> Data in
                    return try Data.readChunk(of: chunkSize, from: self.archiveFile)
                }
                let consumer: Consumer = {
                    if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                    _ = try Data.write(chunk: $0, to: tempArchive.archiveFile)
                    progress?.completedUnitCount += Int64($0.count)
                }
                _ = try Data.consumePart(of: currentEntry.localSize, chunkSize: bufferSize,
                                         provider: provider, consumer: consumer)
                let updatedCentralDirectory = updateOffsetInCentralDirectory(cds: centralDirectoryStructure,
                                                                             updatedOffset: entryStart - offset)
                centralDirectoryData.append(updatedCentralDirectory.data)
            } else { offset = currentEntry.localSize }
        }
        let startOfCentralDirectory = Int64(ftello(tempArchive.archiveFile))
        _ = try Data.write(chunk: centralDirectoryData, to: tempArchive.archiveFile)
        let startOfEndOfCentralDirectory = Int64(ftello(tempArchive.archiveFile))
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

    // MARK: - Helpers

    func replaceCurrentArchive(with archive: Archive) throws {
        fclose(self.archiveFile)
        if self.isMemoryArchive {
            #if swift(>=5.0)
            guard let data = archive.data,
                  let config = Archive.configureMemoryBacking(for: data, mode: .update) else {
                throw ArchiveError.unwritableArchive
            }

            self.archiveFile = config.file
            self.memoryFile = config.memoryFile
            self.endOfCentralDirectoryRecord = config.endOfCentralDirectoryRecord
            self.zip64EndOfCentralDirectory = config.zip64EndOfCentralDirectory
            #endif
        } else {
            let fileManager = FileManager()
            #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
            do {
                _ = try fileManager.replaceItemAt(self.url, withItemAt: archive.url)
            } catch {
                _ = try fileManager.removeItem(at: self.url)
                _ = try fileManager.moveItem(at: archive.url, to: self.url)
            }
            #else
            _ = try fileManager.removeItem(at: self.url)
            _ = try fileManager.moveItem(at: archive.url, to: self.url)
            #endif
            let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: self.url.path)
            self.archiveFile = fopen(fileSystemRepresentation, "rb+")
        }
    }

    func writeEntry(uncompressedSize: Int64, type: Entry.EntryType,
                    compressionMethod: CompressionMethod, bufferSize: Int, progress: Progress? = nil,
                    provider: Provider) throws -> (sizeWritten: Int64, crc32: CRC32) {
        var checksum = CRC32(0)
        var sizeWritten = Int64(0)
        switch type {
        case .file:
            switch compressionMethod {
            case .none:
                (sizeWritten, checksum) = try self.writeUncompressed(size: uncompressedSize,
                                                                     bufferSize: bufferSize,
                                                                     progress: progress, provider: provider)
            case .deflate:
                (sizeWritten, checksum) = try self.writeCompressed(size: uncompressedSize,
                                                                   bufferSize: bufferSize,
                                                                   progress: progress, provider: provider)
            }
        case .directory:
            _ = try provider(0, 0)
            if let progress = progress { progress.completedUnitCount = progress.totalUnitCount }
        case .symlink:
            let (linkSizeWritten, linkChecksum) = try self.writeSymbolicLink(size: Int(uncompressedSize),
                                                                             provider: provider)
            (sizeWritten, checksum) = (Int64(linkSizeWritten), linkChecksum)
            if let progress = progress { progress.completedUnitCount = progress.totalUnitCount }
        }
        return (sizeWritten, checksum)
    }

    func writeLocalFileHeader(path: String, compressionMethod: CompressionMethod,
                              size: (uncompressed: Int64, compressed: Int64), checksum: CRC32,
                              modificationDateTime: (UInt16, UInt16)) throws -> LocalFileHeader {
        // We always set Bit 11 in generalPurposeBitFlag, which indicates an UTF-8 encoded path.
        guard let fileNameData = path.data(using: .utf8) else { throw ArchiveError.invalidEntryPath }

        var uncompressedSizeOfLFH = UInt32(0)
        var compressedSizeOfLFH = UInt32(0)
        var extraFieldLength = UInt16(0)
        var zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?
        var versionNeededToExtract = UInt16(20)
        // ZIP64 Extended Information in the Local header MUST include BOTH original and compressed file size fields.
        if size.uncompressed >= maxUncompressedSize || size.compressed >= maxCompressedSize {
            uncompressedSizeOfLFH = .max
            compressedSizeOfLFH = .max
            extraFieldLength = UInt16(20) // 2 + 2 + 8 + 8
            versionNeededToExtract = zip64Version
            zip64ExtendedInformation = Entry.ZIP64ExtendedInformation(dataSize: extraFieldLength - 4,
                                                                      uncompressedSize: size.uncompressed,
                                                                      compressedSize: size.compressed,
                                                                      relativeOffsetOfLocalHeader: 0,
                                                                      diskNumberStart: 0)
        } else {
            uncompressedSizeOfLFH = UInt32(size.uncompressed)
            compressedSizeOfLFH = UInt32(size.compressed)
        }

        let localFileHeader = LocalFileHeader(versionNeededToExtract: versionNeededToExtract,
                                              generalPurposeBitFlag: UInt16(2048),
                                              compressionMethod: compressionMethod.rawValue,
                                              lastModFileTime: modificationDateTime.1,
                                              lastModFileDate: modificationDateTime.0, crc32: checksum,
                                              compressedSize: compressedSizeOfLFH,
                                              uncompressedSize: uncompressedSizeOfLFH,
                                              fileNameLength: UInt16(fileNameData.count),
                                              extraFieldLength: extraFieldLength, fileNameData: fileNameData,
                                              extraFieldData: zip64ExtendedInformation?.data ?? Data())
        _ = try Data.write(chunk: localFileHeader.data, to: self.archiveFile)
        return localFileHeader
    }

    func writeCentralDirectoryStructure(localFileHeader: LocalFileHeader, relativeOffset: Int64,
                                        externalFileAttributes: UInt32) throws -> CentralDirectoryStructure {
        var extraUncompressedSize: Int64?
        var extraCompressedSize: Int64?
        var extraOffset: Int64?
        var relativeOffsetOfCD = UInt32(0)
        var extraFieldLength = UInt16(0)
        var zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?
        if localFileHeader.uncompressedSize == .max || localFileHeader.compressedSize == .max {
            let zip64Field = Entry.ZIP64ExtendedInformation
                .scanForZIP64Field(in: localFileHeader.extraFieldData, fields: [.uncompressedSize, .compressedSize])
            extraUncompressedSize = zip64Field?.uncompressedSize
            extraCompressedSize = zip64Field?.compressedSize
        }
        if relativeOffset >= maxOffsetOfLocalFileHeader {
            extraOffset = relativeOffset
            relativeOffsetOfCD = .max
        } else {
            relativeOffsetOfCD = UInt32(relativeOffset)
        }
        extraFieldLength = [extraUncompressedSize, extraCompressedSize, extraOffset]
            .compactMap { $0 }
            .reduce(UInt16(0), { $0 + UInt16(MemoryLayout.size(ofValue: $1)) })
        if extraFieldLength > 0 {
            // Size of extra fields, shouldn't include the leading 4 bytes
            zip64ExtendedInformation = Entry.ZIP64ExtendedInformation(dataSize: extraFieldLength,
                                                                      uncompressedSize: extraUncompressedSize ?? 0,
                                                                      compressedSize: extraCompressedSize ?? 0,
                                                                      relativeOffsetOfLocalHeader: extraOffset ?? 0,
                                                                      diskNumberStart: 0)
            extraFieldLength += Entry.ZIP64ExtendedInformation.headerSize
        }
        let centralDirectory = CentralDirectoryStructure(localFileHeader: localFileHeader,
                                                         fileAttributes: externalFileAttributes,
                                                         relativeOffset: relativeOffsetOfCD,
                                                         extraField: (extraFieldLength,
                                                                      zip64ExtendedInformation?.data ?? Data()))
        _ = try Data.write(chunk: centralDirectory.data, to: self.archiveFile)
        return centralDirectory
    }

    func writeEndOfCentralDirectory(centralDirectoryStructure: CentralDirectoryStructure,
                                    startOfCentralDirectory: Int64,
                                    startOfEndOfCentralDirectory: Int64,
                                    operation: ModifyOperation) throws -> EndOfCentralDirectoryStructure {
        var record = self.endOfCentralDirectoryRecord

        let sizeOfCD = self.sizeOfCentralDirectory
        let numberOfTotalEntries = self.totalNumberOfEntriesInCentralDirectory

        let countChange = operation.rawValue
        var dataLength = centralDirectoryStructure.extraFieldLength
        dataLength += centralDirectoryStructure.fileNameLength
        dataLength += centralDirectoryStructure.fileCommentLength
        let cdDataLengthChange = countChange * (Int(dataLength) + CentralDirectoryStructure.size)
        guard Int64.max - sizeOfCD >= cdDataLengthChange else {
            throw ArchiveError.invalidSizeOfCentralDirectory
        }
        let updatedSizeOfCD = sizeOfCD + Int64(cdDataLengthChange)
        guard UInt64.max - numberOfTotalEntries >= countChange else {
            throw ArchiveError.invalidNumberOfEntriesInCentralDirectory
        }
        let updatedNumberOfEntries: UInt64 = {
            switch operation {
            case .add: return numberOfTotalEntries + UInt64(countChange)
            case .remove: return numberOfTotalEntries - UInt64(-countChange)
            }
        }()
        let sizeOfCDForEOCD = updatedSizeOfCD >= maxSizeOfCentralDirectory
            ? UInt32.max
            : UInt32(updatedSizeOfCD)
        let numberOfTotalEntriesForEOCD = updatedNumberOfEntries >= maxTotalNumberOfEntries
            ? UInt16.max
            : UInt16(updatedNumberOfEntries)
        let offsetOfCDForEOCD = startOfCentralDirectory >= maxOffsetOfCentralDirectory
            ? UInt32.max
            : UInt32(startOfCentralDirectory)
        // ZIP64 End of Central Directory
        var zip64eocd: ZIP64EndOfCentralDirectory?
        if numberOfTotalEntriesForEOCD == .max || offsetOfCDForEOCD == .max || sizeOfCDForEOCD == .max {
            zip64eocd = try self.writeZIP64EOCD(totalNumberOfEntries: updatedNumberOfEntries,
                                                sizeOfCentralDirectory: updatedSizeOfCD,
                                                offsetOfCentralDirectory: startOfCentralDirectory,
                                                offsetOfEndOfCentralDirectory: startOfEndOfCentralDirectory)
        }
        record = EndOfCentralDirectoryRecord(record: record, numberOfEntriesOnDisk: numberOfTotalEntriesForEOCD,
                                             numberOfEntriesInCentralDirectory: numberOfTotalEntriesForEOCD,
                                             updatedSizeOfCentralDirectory: sizeOfCDForEOCD,
                                             startOfCentralDirectory: offsetOfCDForEOCD)
        _ = try Data.write(chunk: record.data, to: self.archiveFile)
        return (record, zip64eocd)
    }

    func rollback(_ localFileHeaderStart: Int64, _ existingCentralDirectory: (data: Data, size: Int64),
                  _ bufferSize: Int, _ endOfCentralDirRecord: EndOfCentralDirectoryRecord,
                  _ zip64EndOfCentralDirectory: ZIP64EndOfCentralDirectory?) throws {
        fflush(self.archiveFile)
        ftruncate(fileno(self.archiveFile), off_t(localFileHeaderStart))
        fseeko(self.archiveFile, off_t(localFileHeaderStart), SEEK_SET)
        _ = try Data.writeLargeChunk(existingCentralDirectory.data, size: existingCentralDirectory.size,
                                     bufferSize: bufferSize, to: archiveFile)
        _ = try Data.write(chunk: existingCentralDirectory.data, to: self.archiveFile)
        if let zip64EOCD = zip64EndOfCentralDirectory {
            _ = try Data.write(chunk: zip64EOCD.data, to: self.archiveFile)
        }
        _ = try Data.write(chunk: endOfCentralDirRecord.data, to: self.archiveFile)
    }

    func makeTempArchive() throws -> (Archive, URL?) {
        var archive: Archive
        var url: URL?
        if self.isMemoryArchive {
            #if swift(>=5.0)
            guard let tempArchive = Archive(data: Data(), accessMode: .create,
                                            preferredEncoding: self.preferredEncoding) else {
                throw ArchiveError.unwritableArchive
            }
            archive = tempArchive
            #else
            fatalError("Memory archives are unsupported.")
            #endif
        } else {
            let manager = FileManager()
            let tempDir = URL.temporaryReplacementDirectoryURL(for: self)
            let uniqueString = ProcessInfo.processInfo.globallyUniqueString
            let tempArchiveURL = tempDir.appendingPathComponent(uniqueString)
            try manager.createParentDirectoryStructure(for: tempArchiveURL)
            guard let tempArchive = Archive(url: tempArchiveURL, accessMode: .create) else {
                throw ArchiveError.unwritableArchive
            }
            archive = tempArchive
            url = tempDir
        }
        return (archive, url)
    }

    // MARK: - Private

    private func writeUncompressed(size: Int64, bufferSize: Int, progress: Progress? = nil,
                                   provider: Provider) throws -> (sizeWritten: Int64, checksum: CRC32) {
        var position: Int64 = 0
        var sizeWritten: Int64 = 0
        var checksum = CRC32(0)
        while position < size {
            if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
            let readSize = (size - position) >= bufferSize ? bufferSize : Int(size - position)
            let entryChunk = try provider(position, readSize)
            checksum = entryChunk.crc32(checksum: checksum)
            sizeWritten += Int64(try Data.write(chunk: entryChunk, to: self.archiveFile))
            position += Int64(bufferSize)
            progress?.completedUnitCount = sizeWritten
        }
        return (sizeWritten, checksum)
    }

    private func writeCompressed(size: Int64, bufferSize: Int, progress: Progress? = nil,
                                 provider: Provider) throws -> (sizeWritten: Int64, checksum: CRC32) {
        var sizeWritten: Int64 = 0
        let consumer: Consumer = { data in sizeWritten += Int64(try Data.write(chunk: data, to: self.archiveFile)) }
        let checksum = try Data.compress(size: size, bufferSize: bufferSize,
                                         provider: { (position, size) -> Data in
                                            if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                                            let data = try provider(position, size)
                                            progress?.completedUnitCount += Int64(data.count)
                                            return data
                                         }, consumer: consumer)
        return(sizeWritten, checksum)
    }

    private func writeSymbolicLink(size: Int, provider: Provider) throws -> (sizeWritten: Int, checksum: CRC32) {
        // The reported size of a symlink is the number of characters in the path it points to.
        let linkData = try provider(0, size)
        let checksum = linkData.crc32(checksum: 0)
        let sizeWritten = try Data.write(chunk: linkData, to: self.archiveFile)
        return (sizeWritten, checksum)
    }

    private func writeZIP64EOCD(totalNumberOfEntries: UInt64,
                                sizeOfCentralDirectory: Int64,
                                offsetOfCentralDirectory: Int64,
                                offsetOfEndOfCentralDirectory: Int64) throws -> ZIP64EndOfCentralDirectory {
        var zip64EOCD: ZIP64EndOfCentralDirectory = self.zip64EndOfCentralDirectory ?? {
            // Shouldn't include the leading 12 bytes: (size - 12 = 44)
            let record = ZIP64EndOfCentralDirectoryRecord(sizeOfZIP64EndOfCentralDirectoryRecord: UInt64(44),
                                                          versionMadeBy: UInt16(789),
                                                          versionNeededToExtract: zip64Version,
                                                          numberOfDisk: 0, numberOfDiskStart: 0,
                                                          totalNumberOfEntriesOnDisk: 0,
                                                          totalNumberOfEntriesInCentralDirectory: 0,
                                                          sizeOfCentralDirectory: 0,
                                                          offsetToStartOfCentralDirectory: 0,
                                                          zip64ExtensibleDataSector: Data())
            let locator = ZIP64EndOfCentralDirectoryLocator(numberOfDiskWithZIP64EOCDRecordStart: 0,
                                                            relativeOffsetOfZIP64EOCDRecord: 0,
                                                            totalNumberOfDisk: 1)
            return ZIP64EndOfCentralDirectory(record: record, locator: locator)
        }()

        let updatedRecord = ZIP64EndOfCentralDirectoryRecord(record: zip64EOCD.record,
                                                             numberOfEntriesOnDisk: totalNumberOfEntries,
                                                             numberOfEntriesInCD: totalNumberOfEntries,
                                                             sizeOfCentralDirectory: sizeOfCentralDirectory,
                                                             offsetToStartOfCD: offsetOfCentralDirectory)
        let updatedLocator = ZIP64EndOfCentralDirectoryLocator(locator: zip64EOCD.locator,
                                                               offsetOfZIP64EOCDRecord: offsetOfEndOfCentralDirectory)
        zip64EOCD = ZIP64EndOfCentralDirectory(record: updatedRecord, locator: updatedLocator)
        _ = try Data.write(chunk: zip64EOCD.data, to: self.archiveFile)
        return zip64EOCD
    }

    private func updateOffsetInCentralDirectory(cds: CentralDirectoryStructure,
                                                updatedOffset: Int64) -> CentralDirectoryStructure {
        let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation(
            zip64ExtendedInformation: cds.zip64ExtendedInformation, offset: updatedOffset)
        let offsetInCD = updatedOffset < maxOffsetOfLocalFileHeader ? UInt32(updatedOffset) : UInt32.max
        return CentralDirectoryStructure(centralDirectoryStructure: cds,
                                         zip64ExtendedInformation: zip64ExtendedInformation,
                                         relativeOffset: offsetInCD)
    }
}
