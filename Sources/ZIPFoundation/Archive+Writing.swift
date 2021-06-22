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

    func writeLocalFileHeader(path: String, compressionMethod: CompressionMethod,
                                      size: (uncompressed: UInt, compressed: UInt), checksum: CRC32,
                                      modificationDateTime: (UInt16, UInt16)) throws -> LocalFileHeader {
        // We always set Bit 11 in generalPurposeBitFlag, which indicates an UTF-8 encoded path.
        guard let fileNameData = path.data(using: .utf8) else { throw ArchiveError.invalidEntryPath }

        var uncompressedSizeOfLFH = UInt32(0)
        var compressedSizeOfLFH = UInt32(0)
        var extraFieldLength = UInt16(0)
        var zip64ExtendedInformation: Entry.Zip64ExtendedInformation?
        var versionNeededToExtract = UInt16(20)
        // Zip64 Extended Information in the Local header MUST include BOTH original compressed file size fields.
        if size.uncompressed >= maxUncompressedSize || size.compressed >= maxCompressedSize {
            uncompressedSizeOfLFH = UInt32.max
            compressedSizeOfLFH = UInt32.max
            extraFieldLength = UInt16(20) // 2 + 2 + 8 + 8
            versionNeededToExtract = zip64Version
            zip64ExtendedInformation = Entry.Zip64ExtendedInformation(dataSize: extraFieldLength - 4,
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

    func writeEntry(uncompressedSize: UInt, type: Entry.EntryType,
                            compressionMethod: CompressionMethod, bufferSize: UInt32, progress: Progress? = nil,
                            provider: Provider) throws -> (sizeWritten: UInt, crc32: CRC32) {
        var checksum = CRC32(0)
        var sizeWritten = UInt(0)
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
            (sizeWritten, checksum) = try self.writeSymbolicLink(size: uncompressedSize,
                                                                 provider: provider)
            if let progress = progress { progress.completedUnitCount = progress.totalUnitCount }
        }
        return (sizeWritten, checksum)
    }

    func writeCentralDirectoryStructure(localFileHeader: LocalFileHeader, relativeOffset: UInt,
                                                externalFileAttributes: UInt32) throws -> CentralDirectoryStructure {
        var extraUncompressedSize: UInt?
        var extraCompressedSize: UInt?
        var extraOffset: UInt?
        var relativeOffsetOfCD = UInt32(0)
        var extraFieldLength = UInt16(0)
        var zip64ExtendedInformation: Entry.Zip64ExtendedInformation?
        if localFileHeader.uncompressedSize == UInt32.max || localFileHeader.compressedSize == UInt32.max {
            let zip64Field = Entry.Zip64ExtendedInformation
                .scanForZip64Field(in: localFileHeader.extraFieldData, fields: [.uncompressedSize, .compressedSize])
            extraUncompressedSize = zip64Field?.uncompressedSize
            extraCompressedSize = zip64Field?.compressedSize
            extraFieldLength += UInt16(16)
        }
        if relativeOffset >= maxOffsetOfLocalFileHeader {
            extraOffset = relativeOffset
            relativeOffsetOfCD = UInt32.max
            extraFieldLength += UInt16(8)
        } else {
            relativeOffsetOfCD = UInt32(relativeOffset)
        }
        extraFieldLength = [extraUncompressedSize, extraCompressedSize, extraOffset]
            .compactMap { $0 }
            .reduce(UInt16(0), { $0 + UInt16(MemoryLayout.size(ofValue: $1)) })
        if extraFieldLength > 0 {
            extraFieldLength += 4
            zip64ExtendedInformation = Entry.Zip64ExtendedInformation(dataSize: extraFieldLength - 4,
                                                                      uncompressedSize: extraUncompressedSize ?? 0,
                                                                      compressedSize: extraCompressedSize ?? 0,
                                                                      relativeOffsetOfLocalHeader: extraOffset ?? 0,
                                                                      diskNumberStart: 0)
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
                                            startOfCentralDirectory: Int,
                                            startOfEndOfCentralDirectory: Int,
                                            operation: ModifyOperation) throws -> EndOfCentralDirectoryRecord {
        var record = self.endOfCentralDirectoryRecord
        let zip64Record = self.zip64EndOfCentralDirectory?.record

        let sizeOfCD = zip64Record?.sizeOfCentralDirectory ?? UInt(record.sizeOfCentralDirectory)
        let numberOfTotalEntries = zip64Record?.totalNumberOfEntriesInCentralDirectory
            ?? UInt(record.totalNumberOfEntriesInCentralDirectory)

        let countChange = operation.rawValue
        var dataLength = Int(centralDirectoryStructure.extraFieldLength)
        dataLength += Int(centralDirectoryStructure.fileNameLength)
        dataLength += Int(centralDirectoryStructure.fileCommentLength)
        let cdDataLengthChange = countChange * (dataLength + CentralDirectoryStructure.size)
        let updatedSizeOfCD = Int(sizeOfCD) + cdDataLengthChange
        let updatedNumberOfEntries = Int(numberOfTotalEntries) + countChange
        let sizeOfCDForEOCD = updatedSizeOfCD >= maxSizeOfCentralDirectory
            ? UInt32.max
            : UInt32(updatedSizeOfCD)
        let numberOfTotalEntriesForEOCD = updatedNumberOfEntries >= maxTotalNumberOfEntries
            ? UInt16.max
            : UInt16(updatedNumberOfEntries)
        let offsetOfCDForEOCD = startOfCentralDirectory >= maxOffsetOfCentralDirectory
            ? UInt32.max
            : UInt32(startOfCentralDirectory)
        // Zip64 End of Central Directory
        if self.zip64EndOfCentralDirectory != nil || numberOfTotalEntriesForEOCD == UInt16.max
            || offsetOfCDForEOCD == UInt32.max || sizeOfCDForEOCD == UInt32.max {
            let zip64eocd = try self.writeZip64EOCD(totalNumberOfEntries: updatedNumberOfEntries,
                                                    sizeOfCentralDirectory: updatedSizeOfCD,
                                                    offsetOfCentralDirectory: startOfCentralDirectory,
                                                    offsetOfEndOfCentralDirectory: startOfEndOfCentralDirectory)
            self.zip64EndOfCentralDirectory = zip64eocd
        }
        record = EndOfCentralDirectoryRecord(record: record, numberOfEntriesOnDisk: numberOfTotalEntriesForEOCD,
                                             numberOfEntriesInCentralDirectory: numberOfTotalEntriesForEOCD,
                                             updatedSizeOfCentralDirectory: sizeOfCDForEOCD,
                                             startOfCentralDirectory: offsetOfCDForEOCD)
        _ = try Data.write(chunk: record.data, to: self.archiveFile)
        return record
    }

    func rollback(_ localFileHeaderStart: Int, _ existingCentralDirectoryData: Data,
                          _ endOfCentralDirRecord: EndOfCentralDirectoryRecord) throws {
        fflush(self.archiveFile)
        ftruncate(fileno(self.archiveFile), off_t(localFileHeaderStart))
        fseek(self.archiveFile, localFileHeaderStart, SEEK_SET)
        _ = try Data.write(chunk: existingCentralDirectoryData, to: self.archiveFile)
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

    private func writeUncompressed(size: UInt, bufferSize: UInt32, progress: Progress? = nil,
                                   provider: Provider) throws -> (sizeWritten: UInt, checksum: CRC32) {
        var position = 0
        var sizeWritten = 0
        var checksum = CRC32(0)
        while position < size {
            if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
            let readSize = (Int(size) - position) >= bufferSize ? Int(bufferSize) : (Int(size) - position)
            let entryChunk = try provider(Int(position), Int(readSize))
            checksum = entryChunk.crc32(checksum: checksum)
            sizeWritten += try Data.write(chunk: entryChunk, to: self.archiveFile)
            position += Int(bufferSize)
            progress?.completedUnitCount = Int64(sizeWritten)
        }
        return (UInt(sizeWritten), checksum)
    }

    private func writeCompressed(size: UInt, bufferSize: UInt32, progress: Progress? = nil,
                                 provider: Provider) throws -> (sizeWritten: UInt, checksum: CRC32) {
        var sizeWritten = 0
        let consumer: Consumer = { data in sizeWritten += try Data.write(chunk: data, to: self.archiveFile) }
        let checksum = try Data.compress(size: Int(size), bufferSize: Int(bufferSize),
                                         provider: { (position, size) -> Data in
                                            if progress?.isCancelled == true { throw ArchiveError.cancelledOperation }
                                            let data = try provider(position, size)
                                            progress?.completedUnitCount += Int64(data.count)
                                            return data
                                         }, consumer: consumer)
        return(UInt(sizeWritten), checksum)
    }

    private func writeSymbolicLink(size: UInt, provider: Provider) throws -> (sizeWritten: UInt, checksum: CRC32) {
        let linkData = try provider(0, Int(size))
        let checksum = linkData.crc32(checksum: 0)
        let sizeWritten = try Data.write(chunk: linkData, to: self.archiveFile)
        return (UInt(sizeWritten), checksum)
    }

    private func writeZip64EOCD(totalNumberOfEntries: Int,
                                sizeOfCentralDirectory: Int,
                                offsetOfCentralDirectory: Int,
                                offsetOfEndOfCentralDirectory: Int) throws -> Zip64EndOfCentralDirectory {
        var zip64EOCD: Zip64EndOfCentralDirectory = self.zip64EndOfCentralDirectory ?? {
            let record = Zip64EndOfCentralDirectoryRecord(sizeOfZip64EndOfCentralDirectoryRecord: UInt(44),
                                                          versionMadeBy: UInt16(789),
                                                          versionNeededToExtract: zip64Version,
                                                          numberOfDisk: 0, numberOfDiskStart: 0,
                                                          totalNumberOfEntriesOnDisk: 0,
                                                          totalNumberOfEntriesInCentralDirectory: 0,
                                                          sizeOfCentralDirectory: 0,
                                                          offsetToStartOfCentralDirectory: 0,
                                                          zip64ExtensibleDataSector: Data())
            let locator = Zip64EndOfCentralDirectoryLocator(numberOfDiskWithZip64EOCDRecordStart: 0,
                                                            relativeOffsetOfZip64EOCDRecord: 0,
                                                            totalNumberOfDisk: 1)
            return Zip64EndOfCentralDirectory(record: record, locator: locator)
        }()

        let updatedRecord = Zip64EndOfCentralDirectoryRecord(record: zip64EOCD.record,
                                                             numberOfEntriesOnDisk: UInt(totalNumberOfEntries),
                                                             numberOfEntriesInCD: UInt(totalNumberOfEntries),
                                                             sizeOfCentralDirectory: UInt(sizeOfCentralDirectory),
                                                             offsetToStartOfCD: UInt(offsetOfCentralDirectory))
        let offsetOfEOCDUInt = UInt(offsetOfEndOfCentralDirectory)
        let updatedLocator = Zip64EndOfCentralDirectoryLocator(locator: zip64EOCD.locator,
                                                               offsetOfZip64EOCDRecord: offsetOfEOCDUInt)
        zip64EOCD = Zip64EndOfCentralDirectory(record: updatedRecord, locator: updatedLocator)
        _ = try Data.write(chunk: zip64EOCD.data, to: self.archiveFile)
        return zip64EOCD
    }
}
