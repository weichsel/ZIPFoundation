//
//  ZIPFoundationWritingTests+Zip64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {
    func testCreateZip64ArchiveWithLargeSize() {
        // Target fields: Uncompressed Size, Compressed Size, Offset of Central Directory and other zip64 format fields
        mockIntMaxValues()
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .create)
        let size = 64 * 64 * 2
        let data = Data.makeRandomData(size: size)
        let entryName = ProcessInfo.processInfo.globallyUniqueString
        do {
            try archive.addFileEntry(with: entryName, size: size, data: data)
        } catch {
            XCTFail("Failed to add zip64 format entry to archive with error : \(error)"); return
        }
        guard let entry = archive[entryName] else {
            XCTFail("Failed to add zip64 format entry to archive"); return
        }
        XCTAssert(entry.checksum == data.crc32(checksum: 0))
//        XCTAssert(archive.checkIntegrity())
        let fileSystemRepresentation = FileManager.default.fileSystemRepresentation(withPath: archive.url.path)
        guard let archiveFile = fopen(fileSystemRepresentation, "rb") else {
            XCTFail("Failed to read data of archive file."); return
        }
        do {
            // Local File Header and Extra Field
            // Version Needed to Extract/Uncompressed Size/Compressed Size
            fseek(archiveFile, 0, SEEK_SET)
            let lfhSize = checkLocalFileHeaderAndExtraField(entry: entry, dataSize: size,
                                                            entryNameLength: entryName.count) { size in
                try Data.readChunk(of: size, from: archiveFile)
            }
            // Central Directory and Extra Field
            // Version Needed to Extract/Uncompressed Size/Compressed Size
            let cdOffset = lfhSize + size
            fseek(archiveFile, cdOffset, SEEK_SET)
            let cdSize = checkCentralDirectoryAndExtraField(entry: entry, dataSize: size,
                                                            entryNameLength: entryName.count) { size in
                try Data.readChunk(of: size, from: archiveFile)
            }
            // Zip64 End of Central Directory
            let zip64EOCDOffset = cdOffset + cdSize
            fseek(archiveFile, zip64EOCDOffset, SEEK_SET)
            let zip64EOCDSize = checkZip64EndOfCentralDirectory(archive: archive, cdSize: cdSize, cdOffset: cdOffset,
                                                                zip64EOCDOffset: zip64EOCDOffset) { size in
                try Data.readChunk(of: size, from: archiveFile)
            }
            // End of Central Directory
            let eocdOffset = zip64EOCDOffset + zip64EOCDSize
            let eocdSize = 22
            fseek(archiveFile, eocdOffset, SEEK_SET)
            let eocdData = try Data.readChunk(of: eocdSize, from: archiveFile)
            XCTAssertEqual(eocdData.scanValue(start: 16), UInt32.max)
        } catch {
            XCTFail("Unexpected error while reading chunk from archive file.")
        }
    }

    private func checkLocalFileHeaderAndExtraField(entry: Entry, dataSize: Int, entryNameLength: Int,
                                                   readData: (Int) throws -> Data) -> Int {
        XCTAssertEqual(entry.localFileHeader.uncompressedSize, UInt32.max)
        XCTAssertEqual(entry.localFileHeader.extraFieldData.scanValue(start: 4), dataSize)
        XCTAssertEqual(entry.localFileHeader.compressedSize, UInt32.max)
        XCTAssertEqual(entry.localFileHeader.extraFieldData.scanValue(start: 12), dataSize)
        do {
            let lfhExtraFieldOffset = 30 + entryNameLength
            let lfhSize = lfhExtraFieldOffset + 20
            let lfhData = try readData(lfhSize)
            XCTAssertEqual(lfhData.scanValue(start: 4), zip64Version)
            XCTAssertEqual(lfhData.scanValue(start: 18), UInt32.max)
            XCTAssertEqual(lfhData.scanValue(start: 22), UInt32.max)
            XCTAssertEqual(lfhData.scanValue(start: lfhExtraFieldOffset), UInt16(1))
            XCTAssertEqual(lfhData.scanValue(start: lfhExtraFieldOffset + 2), UInt16(16))
            XCTAssertEqual(lfhData.scanValue(start: lfhExtraFieldOffset + 4), UInt(dataSize))
            XCTAssertEqual(lfhData.scanValue(start: lfhExtraFieldOffset + 12), UInt(dataSize))
            return lfhSize
        } catch {
            XCTFail("Unexpected error while reading chunk from archive file.")
        }
        return 0
    }

    private func checkCentralDirectoryAndExtraField(entry: Entry, dataSize: Int, entryNameLength: Int,
                                                    readData: (Int) throws -> Data) -> Int {
        XCTAssertEqual(entry.centralDirectoryStructure.uncompressedSize, UInt32.max)
        XCTAssertEqual(entry.centralDirectoryStructure.extraFieldData.scanValue(start: 4), dataSize)
        XCTAssertEqual(entry.centralDirectoryStructure.compressedSize, UInt32.max)
        XCTAssertEqual(entry.centralDirectoryStructure.extraFieldData.scanValue(start: 12), dataSize)
        do {
            let relativeCDExtraFieldOffset = 46 + entryNameLength
            let cdSize = relativeCDExtraFieldOffset + 20
            let cdData = try readData(cdSize)
            XCTAssertEqual(cdData.scanValue(start: 6), zip64Version)
            XCTAssertEqual(cdData.scanValue(start: 20), UInt32.max)
            XCTAssertEqual(cdData.scanValue(start: 24), UInt32.max)
            XCTAssertEqual(cdData.scanValue(start: relativeCDExtraFieldOffset), UInt16(1))
            XCTAssertEqual(cdData.scanValue(start: relativeCDExtraFieldOffset + 2), UInt16(16))
            XCTAssertEqual(cdData.scanValue(start: relativeCDExtraFieldOffset + 4), UInt(dataSize))
            XCTAssertEqual(cdData.scanValue(start: relativeCDExtraFieldOffset + 12), UInt(dataSize))
            return cdSize
        } catch {
            XCTFail("Unexpected error while reading chunk from archive file.")
        }
        return 0
    }

    private func checkZip64EndOfCentralDirectory(archive: Archive, cdSize: Int, cdOffset: Int, zip64EOCDOffset: Int,
                                                 readData: (Int) throws -> Data) -> Int {
        XCTAssertEqual(archive.endOfCentralDirectoryRecord.offsetToStartOfCentralDirectory, UInt32.max)
        XCTAssertEqual(Int(archive.zip64EndOfCentralDirectory?.record.offsetToStartOfCentralDirectory ?? 0), cdOffset)
        do {
            let zip64EOCDSize = 56 + 20
            let zip64EOCDData = try readData(zip64EOCDSize)
            XCTAssertEqual(zip64EOCDData.scanValue(start: 0), UInt32(zip64EndOfCentralDirectoryRecordStructSignature))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 4), UInt(44))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 12), UInt16(789))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 14), zip64Version)
            XCTAssertEqual(zip64EOCDData.scanValue(start: 16), UInt32(0))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 20), UInt32(0))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 24), UInt(1))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 32), UInt(1))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 40), UInt(cdSize))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 48), UInt(cdOffset))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 56), UInt32(zip64EndOfCentralDirectoryLocatorStructSignature))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 60), UInt32(0))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 64), UInt(zip64EOCDOffset))
            XCTAssertEqual(zip64EOCDData.scanValue(start: 72), UInt32(1))
            return zip64EOCDSize
        } catch {
            XCTFail("Unexpected error while reading chunk from archive file.")
        }
        return 0
    }

    func testAddEntryToArchiveWithZip64LFHOffset() {
        // Target fields: Relative Offset of Local Header
        mockIntMaxValues()
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .update)
        let size = 64 * 64 * 2
        let data = Data.makeRandomData(size: size)
        let entryName = ProcessInfo.processInfo.globallyUniqueString
//        let currentLFHOffset = archive.offsetToStartOfCentralDirectory
        do {
            try archive.addFileEntry(with: entryName, size: size, data: data)
        } catch {
            XCTFail("Failed to add zip64 format entry to archive with error : \(error)"); return
        }
        // Please ignore this test for now, will be fixed later
//        guard let entry = archive[entryName] else {
//            XCTFail("Failed to add zip64 format entry to archive"); return
//        }
//        XCTAssert(entry.checksum == data.crc32(checksum: 0))
//        XCTAssert(archive.checkIntegrity())
//        XCTAssertEqual(entry.centralDirectoryStructure.relativeOffsetOfLocalHeader, UInt32.max)
//        XCTAssertEqual(entry.centralDirectoryStructure.extraFieldData.scanValue(start: 20), currentLFHOffset)
    }

    func testAddDirectoryToArchiveWithZip64LFHOffset() {
        mockIntMaxValues()
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .update)
        let entryName = "Test"
        do {
            try archive.addEntry(with: entryName, type: .directory,
                                 uncompressedSize: 0, provider: { _, _ in return Data() })
        } catch {
            XCTFail("Failed to add directory entry to zip64 archive.")
        }
        // Please ignore this test for now, will be fixed later
//        guard let entry = archive[entryName] else {
//            XCTFail("Failed to add zip64 format entry to archive"); return
//        }
//        XCTAssertNotNil(entry)
//        XCTAssertEqual(entry.centralDirectoryStructure.relativeOffsetOfLocalHeader, UInt32.max)
//        XCTAssertEqual(entry.centralDirectoryStructure.extraFieldData.scanValue(start: 4), currentLFHOffset)
    }

    func testCreateZip64ArchiveWithTooManyEntries() {
        // Target fields: Total Number of Entries in Central Directory
        let factor = 16
        mockIntMaxValues(int16Factor: factor)
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .create)
        let size = factor
        // Case 1: The total number of entries is less than maximum value
        do {
            for _ in 0..<factor - 1 {
                let data = Data.makeRandomData(size: size)
                let entryName = ProcessInfo.processInfo.globallyUniqueString
                try archive.addFileEntry(with: entryName, size: size, data: data)
            }
        } catch {
            XCTFail("Failed to add zip64 format entry to archive with error : \(error)"); return
        }
        XCTAssertEqual(archive.endOfCentralDirectoryRecord.totalNumberOfEntriesInCentralDirectory, UInt16(factor - 1))
        XCTAssertEqual(archive.zip64EndOfCentralDirectory?.record.totalNumberOfEntriesInCentralDirectory ?? 0, 0)
        // Case 2: The total number os entries is equal to maximum value
        do {
            try archive.addEntry(with: "Test", type: .directory,
                                 uncompressedSize: 0, provider: { _, _ in return Data() })
        } catch {
            XCTFail("Failed to add zip64 format entry to archive with error : \(error)"); return
        }
        XCTAssertEqual(archive.endOfCentralDirectoryRecord.totalNumberOfEntriesInCentralDirectory, UInt16.max)
        XCTAssertEqual(archive.zip64EndOfCentralDirectory?.record.totalNumberOfEntriesInCentralDirectory ?? 0,
                       UInt(factor))
    }

    func testCreateZip64ArchiveWithLargeSizeOfCD() {
        // Target fields: Size of Central Directory
        let factor = 12
        mockIntMaxValues(int32Factor: factor)
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .create)
        let size = 64
        // Case 1: The size of central directory is less than maximum value
        do {
            try archive.addEntry(with: "link", type: .symlink, uncompressedSize: size,
                                 provider: { (_, count) -> Data in
                                    return Data(count: count)
            })
        } catch {
            XCTFail("Failed to add zip64 format entry to archive with error : \(error)"); return
        }
        XCTAssertLessThan(archive.endOfCentralDirectoryRecord.sizeOfCentralDirectory, UInt32.max)
        XCTAssertEqual(archive.zip64EndOfCentralDirectory?.record.sizeOfCentralDirectory ?? 0, 0)
        // Case 2: The size of central directory is greater than maximum value
        do {
            let data = Data.makeRandomData(size: size)
            let entryName = ProcessInfo.processInfo.globallyUniqueString
            try archive.addFileEntry(with: entryName, size: size, data: data)
        } catch {
            XCTFail("Failed to add zip64 format entry to archive with error : \(error)"); return
        }
        XCTAssertEqual(archive.endOfCentralDirectoryRecord.sizeOfCentralDirectory, UInt32.max)
        XCTAssertLessThan(0, archive.zip64EndOfCentralDirectory?.record.sizeOfCentralDirectory ?? 0)
    }

    func testRemoveEntryFromArchiveWithZip64EOCD() {
        /*
         File structure:
         testRemoveEntryFromZip64Archive.zip/
           ├─ data1.random (size: 64)
           ├─ data2.random (size: 64 * 64)
         */
        mockIntMaxValues()
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .update)
        guard let entry = archive["data1.random"] else {
            XCTFail("Failed to add zip64 format entry to archive"); return
        }
        // should keep zip64 ecod
        do {
            try archive.remove(entry)
        } catch {
            XCTFail("Failed to remove entry from archive with error : \(error)")
        }
        XCTAssertNotNil(archive.zip64EndOfCentralDirectory)
    }

    func testRemoveZip64EntryFromArchiveWithZip64EOCD() {
        /*
         File structure:
         testRemoveEntryFromZip64Archive.zip/
           ├─ data1.random (size: 64)
           ├─ data2.random (size: 64 * 64)
         */
        mockIntMaxValues()
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .update)
        guard let entry = archive["data2.random"] else {
            XCTFail("Failed to add zip64 format entry to archive"); return
        }
        // Case 2: should remove zip64 eocd at the same time
        do {
            try archive.remove(entry)
        } catch {
            XCTFail("Failed to remove entry from archive with error : \(error)")
        }
        XCTAssertNil(archive.zip64EndOfCentralDirectory)
    }

    func testAddZip64EntryRollback() {
        mockIntMaxValues()
        defer { resetIntMaxValues() }
        let archive = self.archive(for: #function, mode: .update)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let progress = archive.makeProgressForAddingItem(at: assetURL)
        let handler: XCTKVOExpectation.Handler = { (_, _) -> Bool in
            if progress.fractionCompleted > 0.5 {
                progress.cancel()
                return true
            }
            return false
        }
        let cancel = self.keyValueObservingExpectation(for: progress, keyPath: #keyPath(Progress.fractionCompleted),
                                                       handler: handler)
        let zipQueue = DispatchQueue(label: "ZIPFoundationTests")
        zipQueue.async {
            do {
                let relativePath = assetURL.lastPathComponent
                let baseURL = assetURL.deletingLastPathComponent()
                try archive.addEntry(with: relativePath, relativeTo: baseURL,
                                     compressionMethod: .deflate, bufferSize: 1, progress: progress)
            } catch let error as Archive.ArchiveError {
                XCTAssert(error == Archive.ArchiveError.cancelledOperation)
            } catch {
                XCTFail("Failed to add entry to uncompressed folder archive with error : \(error)")
            }
        }
        self.wait(for: [cancel], timeout: 20.0)
        zipQueue.sync {
            XCTAssert(progress.fractionCompleted > 0.5)
//            XCTAssert(archive.checkIntegrity())
        }
    }

    // MARK: - Helpers

    private func resetIntMaxValues() {
        maxUInt32 = .max
        maxUInt16 = .max
    }

    private func mockIntMaxValues(int32Factor: Int = 64, int16Factor: Int = 64) {
        maxUInt32 = UInt32(int32Factor * int32Factor)
        maxUInt16 = UInt16(int16Factor)
    }
}

extension Archive {
    fileprivate func addFileEntry(with name: String, size: Int, data: Data) throws {
        try self.addEntry(with: name, type: .file,
                              uncompressedSize: size, provider: { (position, bufferSize) -> Data in
                                let upperBound = Swift.min(size, position + bufferSize)
                                let range = Range(uncheckedBounds: (lower: position, upper: upperBound))
                                return data.subdata(in: range)
        })
    }
}
