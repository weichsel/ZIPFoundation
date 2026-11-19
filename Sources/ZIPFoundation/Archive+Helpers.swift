//
//  Archive+Helpers.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import Foundation

extension Archive {

    // MARK: - Reading

    func readUncompressed(entry: Entry, bufferSize: Int, skipCRC32: Bool,
                          progress: Progress? = nil, with consumer: Consumer) throws -> CRC32 {
        // The file data of an uncompressed entry is read in full, even if its uncompressed size differs,
        // e.g. for symlinks of writers that stored a wrong uncompressed size. Reading doesn't verify
        // the checksum. Callers compare the returned checksum with `Entry.checksum`.
        let size = entry.compressedSize
        return try self.readUncompressed(size: size, bufferSize: bufferSize, skipCRC32: skipCRC32,
                                         progress: progress, with: consumer)
    }

    func readUncompressed(size: UInt64, bufferSize: Int, skipCRC32: Bool,
                          progress: Progress? = nil, with consumer: Consumer) throws -> CRC32 {
        guard size <= Int64.max else { throw ArchiveError.invalidEntrySize }
        return try Data.consumePart(of: Int64(size), chunkSize: bufferSize, skipCRC32: skipCRC32,
                                    provider: { (_, chunkSize) -> Data in
                                        return try Data.readChunk(of: chunkSize, from: self.archiveFile)
                                    }, consumer: { (data) in
                                        if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                                        try consumer(data)
                                        progress?.completedUnitCount += Int64(data.count)
                                    })
    }

    func readCompressed(entry: Entry, bufferSize: Int, skipCRC32: Bool,
                        progress: Progress? = nil, with consumer: Consumer) throws -> CRC32 {
        let size = entry.compressedSize
        guard size <= Int64.max else { throw ArchiveError.invalidEntrySize }
        return try Data.decompress(size: Int64(size), bufferSize: bufferSize, skipCRC32: skipCRC32,
                                   provider: { (_, chunkSize) -> Data in
                                    return try Data.readChunk(of: chunkSize, from: self.archiveFile)
                                   }, consumer: { (data) in
                                    if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                                    try consumer(data)
                                    progress?.completedUnitCount += Int64(data.count)
                                   })
    }

    // MARK: - Writing

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
                              size: (uncompressed: UInt64, compressed: UInt64), checksum: CRC32,
                              modificationDateTime: (UInt16, UInt16)) throws -> LocalFileHeader {
        // We always set Bit 11 in generalPurposeBitFlag, which indicates an UTF-8 encoded path.
        let fileNameData = Data(path.utf8)
        var uncompressedSizeOfLFH = UInt32(0)
        var compressedSizeOfLFH = UInt32(0)
        var extraFieldLength = UInt16(0)
        var zip64ExtendedInformation: Entry.ZIP64ExtendedInformation?
        var versionNeededToExtract = Version.v20.rawValue
        // ZIP64 Extended Information in the Local header MUST include BOTH original and compressed file size fields.
        if size.uncompressed >= maxUncompressedSize || size.compressed >= maxCompressedSize {
            uncompressedSizeOfLFH = .max
            compressedSizeOfLFH = .max
            extraFieldLength = UInt16(20) // 2 + 2 + 8 + 8
            versionNeededToExtract = Version.v45.rawValue
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

    func writeCentralDirectoryStructure(localFileHeader: LocalFileHeader, relativeOffset: UInt64,
                                        externalFileAttributes: UInt32) throws -> CentralDirectoryStructure {
        var extraUncompressedSize: UInt64?
        var extraCompressedSize: UInt64?
        var extraOffset: UInt64?
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
            extraFieldLength += UInt16(ExtraField.headerSize)
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
                                    startOfCentralDirectory: UInt64,
                                    startOfEndOfCentralDirectory: UInt64,
                                    operation: ModifyOperation) throws -> EndOfCentralDirectoryStructure {
        var record = self.endOfCentralDirectoryRecord
        let sizeOfCD = self.sizeOfCentralDirectory
        let numberOfTotalEntries = self.totalNumberOfEntriesInCentralDirectory
        let countChange = operation.rawValue
        var dataLength = centralDirectoryStructure.extraFieldLength
        dataLength += centralDirectoryStructure.fileNameLength
        dataLength += centralDirectoryStructure.fileCommentLength
        let cdDataLengthChange = countChange * (Int(dataLength) + CentralDirectoryStructure.size)
        let (updatedSizeOfCD, updatedNumberOfEntries): (UInt64, UInt64) = try {
            switch operation {
            case .add:
                guard .max - sizeOfCD >= cdDataLengthChange else {
                    throw ArchiveError.invalidCentralDirectorySize
                }
                guard .max - numberOfTotalEntries >= countChange else {
                    throw ArchiveError.invalidCentralDirectoryEntryCount
                }
                return (sizeOfCD + UInt64(cdDataLengthChange), numberOfTotalEntries + UInt64(countChange))
            case .remove:
                // The central directory structures of the remaining entries can change their size when their
                // ZIP64 extended information is updated. The size of the written central directory has to be used.
                // The size that the receiver states is therefore not required to be valid.
                guard startOfEndOfCentralDirectory >= startOfCentralDirectory else {
                    throw ArchiveError.invalidCentralDirectorySize
                }
                guard numberOfTotalEntries >= -countChange else {
                    throw ArchiveError.invalidCentralDirectoryEntryCount
                }
                return (startOfEndOfCentralDirectory - startOfCentralDirectory,
                        numberOfTotalEntries - UInt64(-countChange))
            }
        }()
        let sizeOfCDForEOCD = updatedSizeOfCD >= maxSizeOfCentralDirectory ? UInt32.max : UInt32(updatedSizeOfCD)
        let numberOfTotalEntriesForEOCD = updatedNumberOfEntries >= maxTotalNumberOfEntries
            ? UInt16.max
            : UInt16(updatedNumberOfEntries)
        let offsetOfCDForEOCD = startOfCentralDirectory >= maxOffsetOfCentralDirectory
            ? UInt32.max
            : UInt32(startOfCentralDirectory)
        // ZIP64 End of Central Directory
        var zip64EOCD: ZIP64EndOfCentralDirectory?
        if numberOfTotalEntriesForEOCD == .max || offsetOfCDForEOCD == .max || sizeOfCDForEOCD == .max {
            zip64EOCD = try self.writeZIP64EOCD(totalNumberOfEntries: updatedNumberOfEntries,
                                                sizeOfCentralDirectory: updatedSizeOfCD,
                                                offsetOfCentralDirectory: startOfCentralDirectory,
                                                offsetOfEndOfCentralDirectory: startOfEndOfCentralDirectory)
        }
        record = EndOfCentralDirectoryRecord(record: record, numberOfEntriesOnDisk: numberOfTotalEntriesForEOCD,
                                             numberOfEntriesInCentralDirectory: numberOfTotalEntriesForEOCD,
                                             updatedSizeOfCentralDirectory: sizeOfCDForEOCD,
                                             startOfCentralDirectory: offsetOfCDForEOCD)
        _ = try Data.write(chunk: record.data, to: self.archiveFile)
        return (record, zip64EOCD)
    }

    func writeUncompressed(size: Int64, bufferSize: Int, progress: Progress? = nil,
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

    func writeCompressed(size: Int64, bufferSize: Int, progress: Progress? = nil,
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

    func writeSymbolicLink(size: Int, provider: Provider) throws -> (sizeWritten: Int, checksum: CRC32) {
        // The reported size of a symlink is the number of characters in the path it points to.
        let linkData = try provider(0, size)
        let checksum = linkData.crc32(checksum: 0)
        let sizeWritten = try Data.write(chunk: linkData, to: self.archiveFile)
        return (sizeWritten, checksum)
    }

    func writeZIP64EOCD(totalNumberOfEntries: UInt64,
                        sizeOfCentralDirectory: UInt64,
                        offsetOfCentralDirectory: UInt64,
                        offsetOfEndOfCentralDirectory: UInt64) throws -> ZIP64EndOfCentralDirectory {
        var zip64EOCD: ZIP64EndOfCentralDirectory = self.zip64EndOfCentralDirectory ?? {
            // Shouldn't include the leading 12 bytes: (size - 12 = 44)
            let record = ZIP64EndOfCentralDirectoryRecord(sizeOfZIP64EndOfCentralDirectoryRecord: UInt64(44),
                                                          versionMadeBy: UInt16(789),
                                                          versionNeededToExtract: Version.v45.rawValue,
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
}

extension Archive {

    // MARK: - End of Central Directory

    static func scanForEndOfCentralDirectoryRecord(in file: FILEPointer)
    -> EndOfCentralDirectoryStructure? {
        var eocdOffset: UInt64 = 0
        var index = minEndOfCentralDirectoryOffset
        fseeko(file, 0, SEEK_END)
        let archiveLength = Int64(ftello(file))
        guard archiveLength >= 0 else { return nil }

        while eocdOffset == 0 && index < maxDirectoryEndOffset && index <= archiveLength {
            fseeko(file, zip_off_t(archiveLength - index), SEEK_SET)
            var potentialDirectoryEndTag: UInt32 = UInt32()
            fread(&potentialDirectoryEndTag, 1, MemoryLayout<UInt32>.size, file)
            if potentialDirectoryEndTag == UInt32(endOfCentralDirectoryStructSignature) {
                eocdOffset = UInt64(archiveLength - index)
                return self.endOfCentralDirectoryStructure(in: file, at: eocdOffset)
            }
            index += 1
        }
        // A record that is followed by more data than a ZIP file comment can hold is not within reach of
        // the scan above. The remaining part of the file is searched in chunks.
        guard let offset = self.scanForEndOfCentralDirectorySignature(in: file,
                                                                      before: archiveLength - index + 1) else {
            return nil
        }
        return self.endOfCentralDirectoryStructure(in: file, at: offset)
    }

    static func endOfCentralDirectoryStructure(in file: FILEPointer, at eocdOffset: UInt64)
    -> EndOfCentralDirectoryStructure? {
        guard let eocd: EndOfCentralDirectoryRecord = Data.readStruct(from: file, at: eocdOffset) else {
            return nil
        }
        let zip64EOCD = scanForZIP64EndOfCentralDirectory(in: file, eocdOffset: eocdOffset)
        return (eocd, zip64EOCD)
    }

    /// Searches for the last end of central directory signature that starts before `endOffset`.
    static func scanForEndOfCentralDirectorySignature(in file: FILEPointer, before endOffset: Int64)
    -> UInt64? {
        var signature = UInt32(endOfCentralDirectoryStructSignature).littleEndian
        let signatureData = Data(bytes: &signature, count: MemoryLayout<UInt32>.size)
        let chunkSize = Int64(defaultReadChunkSize)
        // A signature that starts before `end` can extend past it.
        var end = endOffset + Int64(signatureData.count - 1)
        while end >= Int64(signatureData.count) {
            let start = Swift.max(0, end - chunkSize)
            fseeko(file, zip_off_t(start), SEEK_SET)
            guard let chunk = try? Data.readChunk(of: Int(end - start), from: file),
                  chunk.count == Int(end - start) else { return nil }
            if let range = chunk.range(of: signatureData, options: .backwards) {
                return UInt64(start) + UInt64(range.lowerBound - chunk.startIndex)
            }
            guard start > 0 else { return nil }
            // Consecutive chunks overlap, so that a signature at a chunk boundary is found.
            end = start + Int64(signatureData.count - 1)
        }
        return nil
    }

    static func scanForZIP64EndOfCentralDirectory(in file: FILEPointer, eocdOffset: UInt64)
    -> ZIP64EndOfCentralDirectory? {
        guard UInt64(ZIP64EndOfCentralDirectoryLocator.size) < eocdOffset else { return nil }

        let locatorOffset = eocdOffset - UInt64(ZIP64EndOfCentralDirectoryLocator.size)
        guard UInt64(ZIP64EndOfCentralDirectoryRecord.size) < locatorOffset else { return nil }

        let recordOffset = locatorOffset - UInt64(ZIP64EndOfCentralDirectoryRecord.size)
        guard let locator: ZIP64EndOfCentralDirectoryLocator = Data.readStruct(from: file, at: locatorOffset),
              let record: ZIP64EndOfCentralDirectoryRecord = Data.readStruct(from: file, at: recordOffset) else {
            return nil
        }
        return ZIP64EndOfCentralDirectory(record: record, locator: locator)
    }
}
