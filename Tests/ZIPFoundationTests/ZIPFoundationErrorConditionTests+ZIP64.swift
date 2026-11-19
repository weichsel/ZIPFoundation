//
//  ZIPFoundationErrorConditionTests+ZIP64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {

    func testWriteEOCDWithTooLargeSizeOfCentralDirectory() {
        let archive = self.archive(for: #function, mode: .create)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: .max,
                                                                                numberOfEntries: 0)
        XCTAssertSwiftError(
            try archive.writeEndOfCentralDirectory(centralDirectoryStructure: makeMockCentralDirectory()!,
                                                   startOfCentralDirectory: 0,
                                                   startOfEndOfCentralDirectory: 0,
                                                   operation: .add),
            throws: Archive.ArchiveError.invalidCentralDirectorySize)
    }

    func testWriteEOCDWithTooLargeCentralDirectoryOffset() {
        let archive = self.archive(for: #function, mode: .create)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: 0,
                                                                                numberOfEntries: .max)
        XCTAssertSwiftError(
            try archive.writeEndOfCentralDirectory(centralDirectoryStructure: makeMockCentralDirectory()!,
                                                   startOfCentralDirectory: 0,
                                                   startOfEndOfCentralDirectory: 0,
                                                   operation: .add),
            throws: Archive.ArchiveError.invalidCentralDirectoryEntryCount)
    }

    func testWriteEOCDWithTooSmallCentralDirectory() {
        let archive = self.archive(for: #function, mode: .create)
        // The written central directory ends before it starts.
        XCTAssertSwiftError(
            try archive.writeEndOfCentralDirectory(centralDirectoryStructure: makeMockCentralDirectory()!,
                                                   startOfCentralDirectory: 1,
                                                   startOfEndOfCentralDirectory: 0,
                                                   operation: .remove),
            throws: Archive.ArchiveError.invalidCentralDirectorySize)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: 1024,
                                                                                numberOfEntries: 0)
        XCTAssertSwiftError(
            try archive.writeEndOfCentralDirectory(centralDirectoryStructure: makeMockCentralDirectory()!,
                                                   startOfCentralDirectory: 0,
                                                   startOfEndOfCentralDirectory: 0,
                                                   operation: .remove),
            throws: Archive.ArchiveError.invalidCentralDirectoryEntryCount)
    }

    func testAddEntryWithInvalidZIP64CentralDirectory() {
        let archive = self.archive(for: #function, mode: .create)
        let addEntry = {
            try archive.addEntry(with: "a", type: .file, uncompressedSize: Int64(0), provider: { _, _ in Data() })
        }
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: 0,
                                                                                numberOfEntries: 0,
                                                                                offsetToStartOfCentralDirectory: .max)
        XCTAssertSwiftError(try addEntry(), throws: Archive.ArchiveError.invalidCentralDirectoryOffset)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: .max,
                                                                                numberOfEntries: 0)
        XCTAssertSwiftError(try addEntry(), throws: Archive.ArchiveError.invalidCentralDirectorySize)
        // A central directory that claims to be larger than the archive must not be read or rewritten.
        let archiveSize = try? FileManager().attributesOfItem(atPath: archive.url.path)[.size] as? UInt64
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: 1 << 26,
                                                                                numberOfEntries: 0)
        XCTAssertSwiftError(try addEntry(), throws: Archive.ArchiveError.invalidCentralDirectorySize)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: 1 << 50,
                                                                                numberOfEntries: 0)
        XCTAssertSwiftError(try addEntry(), throws: Archive.ArchiveError.invalidCentralDirectorySize)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: 0,
                                                                                numberOfEntries: 0,
                                                                                offsetToStartOfCentralDirectory: 1 << 9)
        XCTAssertSwiftError(try addEntry(), throws: Archive.ArchiveError.invalidCentralDirectorySize)
        let updatedSize = try? FileManager().attributesOfItem(atPath: archive.url.path)[.size] as? UInt64
        XCTAssertEqual(updatedSize, archiveSize)
    }

    func testIterateEntryWithOverflowingZIP64DataDescriptor() {
        // The entry uses a data descriptor and has a size of `UInt64.max` in its ZIP64 extended information.
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertEqual(archive.map { $0.path }, ["a"])
    }

    func testExtractEntryWithInvalidZIP64Size() throws {
        // The entry has a size of `UInt64.max` in its ZIP64 extended information.
        let archive = self.archive(for: #function, mode: .read)
        let entry = try XCTUnwrap(archive["a"])
        XCTAssertEqual(archive.totalUnitCountForReading(entry), .max)
        XCTAssertSwiftError(try archive.extract(entry, consumer: { _ in }),
                            throws: Archive.ArchiveError.invalidEntrySize)
    }

    func testUnzipItemWithInvalidZIP64SizeProgress() {
        // Both entries have a size of `UInt64.max`, so the sum of the entry sizes exceeds `Int64.max`.
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        let progress = Progress(totalUnitCount: 0)
        XCTAssertSwiftError(try FileManager().unzipItem(at: archive.url, to: destinationURL, progress: progress),
                            throws: Archive.ArchiveError.invalidEntrySize)
        XCTAssertEqual(progress.totalUnitCount, .max)
    }

    func testExtractEntryWithZIP64SizeExceedingArchive() throws {
        // The entry has a size of `Int64.max`, which is more data than the archive can provide.
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertSwiftError(try archive.extract(XCTUnwrap(archive["a"]), consumer: { _ in }),
                            throws: Data.DataError.unreadableFile)
    }

    func testRemoveEntryWithInvalidZIP64Size() throws {
        // Entry "a" has a size of `UInt64.max` in its ZIP64 extended information. Entry "b" is valid.
        let archive = self.archive(for: #function, mode: .update)
        let entryA = try XCTUnwrap(archive["a"])
        let entryB = try XCTUnwrap(archive["b"])
        XCTAssertEqual(archive.totalUnitCountForRemoving(entryA), 0)
        XCTAssertSwiftError(try archive.remove(entryB), throws: Archive.ArchiveError.invalidLocalHeaderSize)
        // Removing the invalid entry doesn't depend on its size. The valid entry is kept.
        XCTAssertNoThrow(try archive.remove(entryA))
        XCTAssertEqual(archive.map { $0.path }, ["b"])
    }

    func testExtractCompressedEntryWithInvalidZIP64Size() throws {
        let archive = self.archive(for: #function, mode: .create)
        try archive.addEntry(with: "a", type: .file, uncompressedSize: Int64(1), compressionMethod: .deflate,
                             provider: { _, _ in Data([0]) })
        let original = try XCTUnwrap(archive["a"])
        // Only the compressed size is invalid; progress can still represent the uncompressed size.
        let zip64Information = ZIP64ExtendedInformation(dataSize: 16, uncompressedSize: 1,
                                                        compressedSize: UInt64(Int64.max) + 1,
                                                        relativeOffsetOfLocalHeader: 0, diskNumberStart: 0)
        let directory = try self.makeZIP64CentralDirectory(from: original.centralDirectoryStructure,
                                                           placeholderOffsets: [20, 24],
                                                           zip64Information: zip64Information)
        let entry = try XCTUnwrap(Entry(centralDirectoryStructure: directory,
                                        localFileHeader: original.localFileHeader))
        let progress = Progress(totalUnitCount: 0)
        XCTAssertSwiftError(try archive.extract(entry, progress: progress, consumer: { _ in
            XCTFail("Invalid compressed size must be rejected before delivering data.")
        }), throws: Archive.ArchiveError.invalidEntrySize)
        XCTAssertEqual(progress.totalUnitCount, 1)
        XCTAssertEqual(progress.completedUnitCount, 0)
    }

    func testExtractEntryWithInvalidZIP64DataOffset() throws {
        let archive = self.archive(for: #function, mode: .create)
        try archive.addEntry(with: "a", type: .file, uncompressedSize: Int64(0), provider: { _, _ in Data() })
        let original = try XCTUnwrap(archive["a"])
        // The header offset fits Int64, but adding the local header makes the data offset exceed it.
        let zip64Information = ZIP64ExtendedInformation(dataSize: 8, uncompressedSize: 0, compressedSize: 0,
                                                        relativeOffsetOfLocalHeader: UInt64(Int64.max),
                                                        diskNumberStart: 0)
        let directory = try self.makeZIP64CentralDirectory(from: original.centralDirectoryStructure,
                                                           placeholderOffsets: [42],
                                                           zip64Information: zip64Information)
        let entry = try XCTUnwrap(Entry(centralDirectoryStructure: directory,
                                        localFileHeader: original.localFileHeader))
        XCTAssertSwiftError(try archive.extract(entry, consumer: { _ in
            XCTFail("Invalid data offset must be rejected before delivering data.")
        }), throws: Archive.ArchiveError.invalidLocalHeaderDataOffset)
    }

    // MARK: - Helper

    /// Returns a copy of `structure` that uses the values of `zip64Information`. ZIP64 values only apply to
    /// fields that contain the placeholder `UInt32.max`, so the fields at `placeholderOffsets` are overwritten.
    private func makeZIP64CentralDirectory(from structure: Entry.CentralDirectoryStructure,
                                           placeholderOffsets: [Int],
                                           zip64Information: Entry.ZIP64ExtendedInformation) throws
    -> Entry.CentralDirectoryStructure {
        var data = structure.data
        for offset in placeholderOffsets {
            data.replaceSubrange(offset..<offset + 4, with: [UInt8](repeating: 0xff, count: 4))
        }
        let fixedSize = Entry.CentralDirectoryStructure.size
        let additionalData = data.subdata(in: fixedSize..<data.count)
        var directory = try XCTUnwrap(Entry.CentralDirectoryStructure(data: data.subdata(in: 0..<fixedSize),
                                                                      additionalDataProvider: { _ in additionalData }))
        directory.extraFields = [zip64Information]
        return directory
    }

    private func makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: UInt64, numberOfEntries: UInt64,
                                                    offsetToStartOfCentralDirectory: UInt64 = 0)
    -> Archive.ZIP64EndOfCentralDirectory {
        let record = Archive.ZIP64EndOfCentralDirectoryRecord(sizeOfZIP64EndOfCentralDirectoryRecord: UInt64(44),
                                                              versionMadeBy: UInt16(789),
                                                              versionNeededToExtract: Archive.Version.v45.rawValue,
                                                              numberOfDisk: 0, numberOfDiskStart: 0,
                                                              totalNumberOfEntriesOnDisk: 0,
                                                              totalNumberOfEntriesInCentralDirectory: numberOfEntries,
                                                              sizeOfCentralDirectory: sizeOfCentralDirectory,
                                                              offsetToStartOfCentralDirectory:
                                                                offsetToStartOfCentralDirectory,
                                                              zip64ExtensibleDataSector: Data())
        let locator = Archive.ZIP64EndOfCentralDirectoryLocator(numberOfDiskWithZIP64EOCDRecordStart: 0,
                                                                relativeOffsetOfZIP64EOCDRecord: 0,
                                                                totalNumberOfDisk: 1)
        return Archive.ZIP64EndOfCentralDirectory(record: record, locator: locator)
    }

    private func makeMockCentralDirectory() -> Entry.CentralDirectoryStructure? {
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x15, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        guard let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes),
                                                        additionalDataProvider: { count -> Data in
            let pathData = Data("/".utf8)
            XCTAssert(count == pathData.count)
            return pathData
        }) else {
            XCTFail("Failed to read central directory structure.")
            return nil
        }
        return cds
    }
}
