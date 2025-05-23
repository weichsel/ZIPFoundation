//
//  Archive+Writing.swift
//  ZIPFoundation
//
//  Copyright © 2017-2024 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
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
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        let modDate = try FileManager.fileModificationDateTimeForItem(at: fileURL)
        let uncompressedSize = type == .directory ? 0 : try FileManager.fileSizeForItem(at: fileURL)
        let permissions = try FileManager.permissionsForItem(at: fileURL)
        var provider: Provider
        switch type {
        case .file:
            let entryFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
            guard let entryFile: FILEPointer = fopen(entryFileSystemRepresentation, "rb") else {
                throw POSIXError(errno, path: url.path)
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
        guard self.offsetToStartOfCentralDirectory <= .max else { throw ArchiveError.invalidCentralDirectoryOffset }
        var startOfCD = Int64(self.offsetToStartOfCentralDirectory)
        fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
        let existingSize = self.sizeOfCentralDirectory
        let existingData = try Data.readChunk(of: Int(existingSize), from: self.archiveFile)
        fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
        let fileHeaderStart = Int64(ftello(self.archiveFile))
        let modDateTime = modificationDate.fileModificationDateTime
        defer { fflush(self.archiveFile) }
        do {
            // Local File Header
            var localFileHeader = try self.writeLocalFileHeader(path: path, compressionMethod: compressionMethod,
                                                                size: (UInt64(uncompressedSize), 0), checksum: 0,
                                                                modificationDateTime: modDateTime)
            // File Data
            let (written, checksum) = try self.writeEntry(uncompressedSize: uncompressedSize, type: type,
                                                          compressionMethod: compressionMethod, bufferSize: bufferSize,
                                                          progress: progress, provider: provider)
            startOfCD = Int64(ftello(self.archiveFile))
            // Write the local file header a second time. Now with compressedSize (if applicable) and a valid checksum.
            fseeko(self.archiveFile, off_t(fileHeaderStart), SEEK_SET)
            localFileHeader = try self.writeLocalFileHeader(path: path, compressionMethod: compressionMethod,
                                                            size: (UInt64(uncompressedSize), UInt64(written)),
                                                            checksum: checksum, modificationDateTime: modDateTime)
            // Central Directory
            fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
            _ = try Data.writeLargeChunk(existingData, size: existingSize, bufferSize: bufferSize, to: archiveFile)
            let permissions = permissions ?? (type == .directory ? defaultDirectoryPermissions : defaultFilePermissions)
            let externalAttributes = FileManager.externalFileAttributesForEntry(of: type, permissions: permissions)
            let centralDir = try self.writeCentralDirectoryStructure(localFileHeader: localFileHeader,
                                                                     relativeOffset: UInt64(fileHeaderStart),
                                                                     externalFileAttributes: externalAttributes)
            // End of Central Directory Record (including ZIP64 End of Central Directory Record/Locator)
            let startOfEOCD = UInt64(ftello(self.archiveFile))
            let eocd = try self.writeEndOfCentralDirectory(centralDirectoryStructure: centralDir,
                                                           startOfCentralDirectory: UInt64(startOfCD),
                                                           startOfEndOfCentralDirectory: startOfEOCD, operation: .add)
            (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = eocd
        } catch ArchiveError.cancelledOperation {
            try rollback(UInt64(fileHeaderStart), (existingData, existingSize), bufferSize, eocdRecord, zip64EOCD)
            throw ArchiveError.cancelledOperation
        }
    }
    
    /// Remove ZIP `Entry` objects from the receiver.
    ///
    /// - Parameters:
    ///   - entries: The `Entry` objects to remove. Can be a single entry or multiple entries.
    ///   - bufferSize: The maximum size for the read and write buffers used during removal.
    ///   - progress: A progress object that can be used to track or cancel the remove operation.
    /// - Throws: An error if any `Entry` is malformed or the receiver is not writable.
    public func remove(_ entries: [Entry], bufferSize: Int = defaultReadChunkSize, progress: Progress? = nil) throws {
        guard self.accessMode != .read else { throw ArchiveError.unwritableArchive }
        guard !entries.isEmpty else { return }
        
        // Check if we can use the efficient truncation method
        if canUseTruncationForRemoval(entries: entries) {
            try removeEntriesUsingTruncation(entries: entries, progress: progress)
        } else {
            try removeEntriesUsingRewrite(entries: entries, bufferSize: bufferSize, progress: progress)
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
        try remove([entry], bufferSize: bufferSize, progress: progress)
    }
    
    func error(fromPOSIXErrorCode code: Int32) -> Error {
        guard let errorCode = POSIXErrorCode(rawValue: code) else { return ArchiveError.unknownError }
        return POSIXError(errorCode)
    }
    
    func entries(beforeEntry startEntry: Entry) -> [Entry] {
        var result = [Entry]()
        for entry in self {
            if entry == startEntry { break }
            result.append(entry)
        }
        return result
    }
    
    func updateOffsetInCentralDirectory(centralDirectoryStructure: CentralDirectoryStructure,
                                        updatedOffset: UInt64) -> CentralDirectoryStructure {
        let zip64ExtendedInformation = Entry.ZIP64ExtendedInformation(
            zip64ExtendedInformation: centralDirectoryStructure.zip64ExtendedInformation, offset: updatedOffset)
        let offsetInCD = updatedOffset < maxOffsetOfLocalFileHeader ? UInt32(updatedOffset) : UInt32.max
        return CentralDirectoryStructure(centralDirectoryStructure: centralDirectoryStructure,
                                         zip64ExtendedInformation: zip64ExtendedInformation,
                                         relativeOffset: offsetInCD)
    }
    
    func rollback(_ localFileHeaderStart: UInt64, _ existingCentralDirectory: (data: Data, size: UInt64),
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
            archive = try Archive(data: Data(), accessMode: .create,
                                  pathEncoding: self.pathEncoding)
#else
            fatalError("Memory archives are unsupported.")
#endif
        } else {
            let manager = FileManager()
            let tempDir = URL.temporaryReplacementDirectoryURL(for: self)
            let uniqueString = ProcessInfo.processInfo.globallyUniqueString
            let tempArchiveURL = tempDir.appendingPathComponent(uniqueString)
            try manager.createParentDirectoryStructure(for: tempArchiveURL)
            let tempArchive = try Archive(url: tempArchiveURL, accessMode: .create)
            archive = tempArchive
            url = tempDir
        }
        return (archive, url)
    }
    
    /// Determines if the removal can use the efficient truncation method.
    ///
    /// Truncation can be used when removing consecutive entries at the end of the archive.
    ///
    /// - Parameter entries: The entries to be removed.
    /// - Returns: True if truncation can be used, false otherwise.
    private func canUseTruncationForRemoval(entries: [Entry]) -> Bool {
        guard !entries.isEmpty else { return false }
        
        // Sort entries by their offset in the archive
        let sortedEntries = entries.sorted { $0.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader < $1.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader }
        
        // Get all entries in the archive as an array
        let allEntries = Array(self)
        
        // Sort all entries by their offset
        let sortedAllEntries = allEntries.sorted { $0.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader < $1.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader }
        
        // Find the first entry to remove in the sorted list
        guard let firstEntryToRemove = sortedEntries.first,
              let firstIndex = sortedAllEntries.firstIndex(where: { $0.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader == firstEntryToRemove.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader }) else {
            return false
        }
        
        // Check if the entries to remove are consecutive and at the end
        let endIndex = sortedAllEntries.count - 1
        let expectedConsecutiveCount = endIndex - firstIndex + 1
        
        // If we're removing exactly the consecutive entries at the end
        if entries.count == expectedConsecutiveCount {
            // Verify they are actually consecutive
            for i in 0..<entries.count {
                let expectedEntry = sortedAllEntries[firstIndex + i]
                if !entries.contains(where: { $0.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader == expectedEntry.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader }) {
                    return false
                }
            }
            return true
        }
        
        return false
    }
    
    /// Removes entries using the efficient truncation method.
    ///
    /// - Parameters:
    ///   - entries: The entries to remove.
    ///   - progress: Progress tracking object.
    /// - Throws: An error if the operation fails.
    private func removeEntriesUsingTruncation(entries: [Entry], progress: Progress?) throws {
        // Sort entries by offset to find the first one to remove
        let sortedEntries = entries.sorted { $0.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader < $1.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader }
        guard let firstEntryToRemove = sortedEntries.first else { return }
        
        let remainingEntries = self.entries(beforeEntry: firstEntryToRemove)
        guard self.offsetToStartOfCentralDirectory <= .max else { throw ArchiveError.invalidCentralDirectoryOffset }
        
        // Set up progress
        progress?.totalUnitCount = Int64(entries.reduce(0) { $0 + $1.localSize })
        
        // Rescue all preceding entries in the central directory as a data copy
        let startOfCD = self.offsetToStartOfCentralDirectory
        let entryCDStartOffset = firstEntryToRemove.directoryIndex
        fseeko(self.archiveFile, off_t(startOfCD), SEEK_SET)
        let remainingCDSize = entryCDStartOffset - startOfCD
        let remainingCDData = try Data.readChunk(of: Int(remainingCDSize), from: self.archiveFile)
        
        // Truncate everything from the local entry (including the central directory)
        defer { fflush(self.archiveFile) }
        let entryLocalStartOffset = firstEntryToRemove.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader
        let archiveFD = fileno(self.archiveFile)
        guard archiveFD != -1, ftruncate(archiveFD, off_t(entryLocalStartOffset)) != -1 else {
            throw error(fromPOSIXErrorCode: errno)
        }
        
        // Update progress
        progress?.completedUnitCount = progress?.totalUnitCount ?? 0
        
        // Re-append the central directory with the remaining entries
        let newStartOfCD = entryLocalStartOffset
        fseeko(self.archiveFile, off_t(0), SEEK_END)
        _ = try Data.write(chunk: remainingCDData, to: self.archiveFile)
        
        // Append the End of Central Directory Record (including ZIP64 End of Central Directory Record/Locator)
        let startOfEOCD = UInt64(ftello(self.archiveFile))
        let eocd = try self.writeEndOfCentralDirectory(totalNumberOfEntries: UInt64(remainingEntries.count),
                                                       sizeOfCentralDirectory: remainingCDSize,
                                                       offsetOfCentralDirectory: newStartOfCD,
                                                       offsetOfEndOfCentralDirectory: startOfEOCD)
        (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = eocd
    }
    
    /// Removes entries using the traditional rewrite method.
    ///
    /// - Parameters:
    ///   - entries: The entries to remove.
    ///   - bufferSize: Buffer size for I/O operations.
    ///   - progress: Progress tracking object.
    /// - Throws: An error if the operation fails.
    private func removeEntriesUsingRewrite(entries: [Entry], bufferSize: Int, progress: Progress?) throws {
        let (tempArchive, tempDir) = try self.makeTempArchive()
        defer { tempDir.map { try? FileManager().removeItem(at: $0) } }
        
        let entriesToRemove = Set(entries.map { $0.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader })
        
        // Calculate total work for progress tracking
        var totalWork: Int64 = 0
        for entry in self {
            if !entriesToRemove.contains(entry.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader) {
                totalWork += Int64(entry.localSize)
            }
        }
        progress?.totalUnitCount = totalWork
        
        var centralDirectoryData = Data()
        var totalRemovedSize: UInt64 = 0
        
        for currentEntry in self {
            let cds = currentEntry.centralDirectoryStructure
            let shouldRemove = entriesToRemove.contains(cds.effectiveRelativeOffsetOfLocalHeader)
            
            if !shouldRemove {
                let entryStart = cds.effectiveRelativeOffsetOfLocalHeader
                fseeko(self.archiveFile, off_t(entryStart), SEEK_SET)
                
                let provider: Provider = { (_, chunkSize) -> Data in
                    return try Data.readChunk(of: chunkSize, from: self.archiveFile)
                }
                let consumer: Consumer = { data in
                    if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                    _ = try Data.write(chunk: data, to: tempArchive.archiveFile)
                    progress?.completedUnitCount += Int64(data.count)
                }
                
                guard currentEntry.localSize <= .max else { throw ArchiveError.invalidLocalHeaderSize }
                _ = try Data.consumePart(of: Int64(currentEntry.localSize), chunkSize: bufferSize,
                                         provider: provider, consumer: consumer)
                
                let updatedCentralDirectory = updateOffsetInCentralDirectory(centralDirectoryStructure: cds,
                                                                             updatedOffset: entryStart - totalRemovedSize)
                centralDirectoryData.append(updatedCentralDirectory.data)
            } else {
                totalRemovedSize += currentEntry.localSize
            }
        }
        
        let startOfCentralDirectory = UInt64(ftello(tempArchive.archiveFile))
        _ = try Data.write(chunk: centralDirectoryData, to: tempArchive.archiveFile)
        let startOfEndOfCentralDirectory = UInt64(ftello(tempArchive.archiveFile))
        tempArchive.endOfCentralDirectoryRecord = self.endOfCentralDirectoryRecord
        tempArchive.zip64EndOfCentralDirectory = self.zip64EndOfCentralDirectory
        
        // Use the first entry as a representative for the central directory structure
        let representativeEntry = entries.first!
        let ecodStructure = try
        tempArchive.writeEndOfCentralDirectory(centralDirectoryStructure: representativeEntry.centralDirectoryStructure,
                                               startOfCentralDirectory: startOfCentralDirectory,
                                               startOfEndOfCentralDirectory: startOfEndOfCentralDirectory,
                                               operation: .remove)
        (tempArchive.endOfCentralDirectoryRecord, tempArchive.zip64EndOfCentralDirectory) = ecodStructure
        (self.endOfCentralDirectoryRecord, self.zip64EndOfCentralDirectory) = ecodStructure
        fflush(tempArchive.archiveFile)
        try self.replaceCurrentArchive(with: tempArchive)
    }
    
    /// Replaces the current archive with the provided archive.
    ///
    /// - Parameter archive: The archive to replace the current one with.
    /// - Throws: An error if the replacement fails.
    func replaceCurrentArchive(with archive: Archive) throws {
        if self.isMemoryArchive {
#if swift(>=5.0)
            guard let data = archive.data else {
                throw ArchiveError.unwritableArchive
            }
            
            let config = try Archive.makeBackingConfiguration(for: data, mode: .update)
            self.archiveFile = config.file
            self.memoryFile = config.memoryFile
            self.endOfCentralDirectoryRecord = config.endOfCentralDirectoryRecord
            self.zip64EndOfCentralDirectory = config.zip64EndOfCentralDirectory
#endif
        } else {
            let fileManager = FileManager()
#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
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
            guard let file = fopen(fileSystemRepresentation, "rb+") else { throw ArchiveError.unreadableArchive }
            
            self.archiveFile = file
        }
    }
}
