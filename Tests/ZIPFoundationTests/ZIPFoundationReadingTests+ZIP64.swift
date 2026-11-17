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

    func testRemoveEntryNextToZIP64EntryWithDefaultDataDescriptor() throws {
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
}
