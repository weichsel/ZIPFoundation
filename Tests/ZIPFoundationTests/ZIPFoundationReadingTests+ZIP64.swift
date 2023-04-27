//
//  ZIPFoundationReadingTests+ZIP64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2023 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
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

    func testReadZIP64CompressedDataAtOffset() throws {
        let archive = self.archive(for: #function, mode: .read)
        guard let entryA = archive["a.txt"] else { XCTFail("Failed to extract entry."); return }
        XCTAssertEqual("1a", String(data: try archive.extract(with: entryA, offset: 0, size: 2), encoding: .utf8))
        XCTAssertEqual("1b", String(data: try archive.extract(with: entryA, offset: 3, size: 2), encoding: .utf8))
        XCTAssertEqual("1c", String(data: try archive.extract(with: entryA, offset: 6, size: 2), encoding: .utf8))
        XCTAssertEqual("1d", String(data: try archive.extract(with: entryA, offset: 9, size: 2), encoding: .utf8))

        guard let entryB = archive["b.txt"] else { XCTFail("Failed to extract entry."); return }
        XCTAssertEqual("2a", String(data: try archive.extract(with: entryB, offset: 0, size: 2), encoding: .utf8))
        XCTAssertEqual("2b", String(data: try archive.extract(with: entryB, offset: 3, size: 2), encoding: .utf8))
        XCTAssertEqual("2c", String(data: try archive.extract(with: entryB, offset: 6, size: 2), encoding: .utf8))
        XCTAssertEqual("2d", String(data: try archive.extract(with: entryB, offset: 9, size: 2), encoding: .utf8))

        guard let entryC = archive["c.txt"] else { XCTFail("Failed to extract entry."); return }
        XCTAssertEqual("3a", String(data: try archive.extract(with: entryC, offset: 0, size: 2), encoding: .utf8))
        XCTAssertEqual("3b", String(data: try archive.extract(with: entryC, offset: 3, size: 2), encoding: .utf8))
        XCTAssertEqual("3c", String(data: try archive.extract(with: entryC, offset: 6, size: 2), encoding: .utf8))
        XCTAssertEqual("3d", String(data: try archive.extract(with: entryC, offset: 9, size: 2), encoding: .utf8))

        guard let entryD = archive["d.txt"] else { XCTFail("Failed to extract entry."); return }
        XCTAssertEqual("4a", String(data: try archive.extract(with: entryD, offset: 0, size: 2), encoding: .utf8))
        XCTAssertEqual("4b", String(data: try archive.extract(with: entryD, offset: 3, size: 2), encoding: .utf8))
        XCTAssertEqual("4c", String(data: try archive.extract(with: entryD, offset: 6, size: 2), encoding: .utf8))
        XCTAssertEqual("4d", String(data: try archive.extract(with: entryD, offset: 9, size: 2), encoding: .utf8))
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
}
