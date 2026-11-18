//
//  ZIPFoundationReadingTests+ZIP64.swift
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

    private enum StoreType {
        case memory
        case file
    }

    private enum ZIP64ReadingTestsError: Error, CustomStringConvertible {
        case failedToReadEntry(name: String)
        case failedToExtractEntry(type: StoreType)

        var description: String {
            switch self {
            case .failedToReadEntry(let name):
                return "Failed to read entry: \(name)."
            case .failedToExtractEntry(let type):
                return "Failed to extract item to \(type)"
            }
        }
    }

    func testExtractUncompressedZIP64Entries() {
        do {
            try extractEntryFromZIP64Archive(for: #function)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testExtractCompressedZIP64Entries() {
        do {
            try extractEntryFromZIP64Archive(for: #function)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testExtractEntryWithZIP64DataDescriptor() {
        do {
            try extractEntryFromZIP64Archive(for: #function, reservedFileName: "simple.data")
        } catch {
            XCTFail("\(error)")
        }
        // The size of the only entry includes its data descriptor. The central directory follows it.
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertNotNil(archive["simple.data"]?.zip64DataDescriptor)
        XCTAssertEqual(archive["simple.data"]?.localSize, archive.offsetToStartOfCentralDirectory)
    }

    // MARK: - Helpers

    private func extractEntryFromZIP64Archive(for testFunction: String, reservedFileName: String? = nil) throws {
        let archive = self.archive(for: testFunction, mode: .read)
        let fileName = reservedFileName ?? testFunction.replacingOccurrences(of: "()", with: ".png")
        guard let entry = archive[fileName] else {
            throw ZIP64ReadingTestsError.failedToReadEntry(name: fileName)
        }
        do {
            // Test extracting to memory
            let checksum = try archive.extract(entry, bufferSize: 32, consumer: { _ in })
            XCTAssert(entry.checksum == checksum)
        } catch {
            throw ZIP64ReadingTestsError.failedToExtractEntry(type: .memory)
        }
        do {
            // Test extracting to file
            var fileURL = self.createDirectory(for: testFunction)
            fileURL.appendPathComponent(entry.path)
            let checksum = try archive.extract(entry, to: fileURL)
            XCTAssert(entry.checksum == checksum)
            let fileManager = FileManager()
            XCTAssertTrue(fileManager.itemExists(at: fileURL))
            if entry.type == .file {
                let fileData = try Data(contentsOf: fileURL)
                let checksum = fileData.crc32(checksum: 0)
                XCTAssert(checksum == entry.checksum)
            }
        } catch {
            throw ZIP64ReadingTestsError.failedToExtractEntry(type: .file)
        }
    }

    func testIterateZIP64EntryWithDefaultDataDescriptor() throws {
        // Entry "a.txt" requires version 4.5, but its data descriptor has 4 byte sizes.
        let archive = self.archive(for: #function, mode: .read)
        let entry = try XCTUnwrap(archive["a.txt"])
        XCTAssertTrue(entry.centralDirectoryStructure.isZIP64)
        XCTAssertNil(entry.zip64DataDescriptor)
        XCTAssertEqual(entry.uncompressedSize, 240)
        XCTAssertEqual(entry.compressedSize, 17)
        XCTAssertEqual(archive.map { $0.path }, ["a.txt", "b.txt"])
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveEntryNextToDefaultDataDescriptor() throws {
        // Entry "a.txt" has ZIP64 extended information for its offset and a data descriptor with 4 byte sizes.
        let archive = self.archive(for: #function, mode: .update)
        XCTAssertEqual(archive["a.txt"]?.uncompressedSize, 240)
        try archive.remove(XCTUnwrap(archive["pad.txt"]))
        XCTAssertEqual(archive.map { $0.path }, ["a.txt", "c.txt"])
        XCTAssertEqual(archive["a.txt"]?.uncompressedSize, 240)
        XCTAssertEqual(archive["a.txt"]?.compressedSize, 17)
        XCTAssert(archive.checkIntegrity())
        try archive.remove(XCTUnwrap(archive["c.txt"]))
        XCTAssertEqual(archive.map { $0.path }, ["a.txt"])
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveEntryNextToWrongDefaultDataDescriptor() throws {
        // Entry "a.txt" has ZIP64 extended information for its offset and a data descriptor with 4 byte sizes.
        // The descriptor states a wrong compressed size, so neither descriptor layout matches the central directory.
        let archive = self.archive(for: #function, mode: .update)
        let entry = try XCTUnwrap(archive["a.txt"])
        XCTAssertTrue(entry.centralDirectoryStructure.isZIP64)
        XCTAssertNil(entry.zip64DataDescriptor)
        XCTAssertEqual(entry.dataDescriptor?.compressedSize, 4)
        try archive.remove(XCTUnwrap(archive["pad.txt"]))
        let reopenedArchive = try Archive(url: archive.url, accessMode: .read)
        XCTAssertEqual(reopenedArchive.map { $0.path }, ["a.txt", "c.txt"])
        XCTAssert(reopenedArchive.checkIntegrity())
        // The following entry starts right after the descriptor.
        let entryA = try XCTUnwrap(reopenedArchive["a.txt"])
        let entryC = try XCTUnwrap(reopenedArchive["c.txt"])
        XCTAssertEqual(entryC.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader,
                       entryA.dataOffset + entryA.compressedSize + 16)
        let content = Data(String(repeating: "hello world\n", count: 20).utf8)
        for path in ["a.txt", "c.txt"] {
            var data = Data()
            _ = try reopenedArchive.extract(XCTUnwrap(reopenedArchive[path])) { data.append($0) }
            XCTAssertEqual(data, content)
        }
    }

    func testRemoveEntryNextToWrongZIP64DataDescriptor() throws {
        // Entry "a.txt" has ZIP64 extended information in its local file header and a data descriptor
        // with 8 byte sizes. The descriptor states a wrong compressed size, so neither descriptor layout
        // matches the central directory.
        let archive = self.archive(for: #function, mode: .update)
        let entry = try XCTUnwrap(archive["a.txt"])
        XCTAssertTrue(entry.centralDirectoryStructure.isZIP64)
        XCTAssertNil(entry.dataDescriptor)
        XCTAssertEqual(entry.zip64DataDescriptor?.compressedSize, 4)
        try archive.remove(XCTUnwrap(archive["pad.txt"]))
        let reopenedArchive = try Archive(url: archive.url, accessMode: .read)
        XCTAssertEqual(reopenedArchive.map { $0.path }, ["a.txt", "c.txt"])
        XCTAssert(reopenedArchive.checkIntegrity())
        // The following entry starts right after the descriptor.
        let entryA = try XCTUnwrap(reopenedArchive["a.txt"])
        let entryC = try XCTUnwrap(reopenedArchive["c.txt"])
        XCTAssertEqual(entryC.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader,
                       entryA.dataOffset + entryA.compressedSize + 24)
        let content = Data(String(repeating: "hello world\n", count: 20).utf8)
        for path in ["a.txt", "c.txt"] {
            var data = Data()
            _ = try reopenedArchive.extract(XCTUnwrap(reopenedArchive[path])) { data.append($0) }
            XCTAssertEqual(data, content)
        }
    }
}
