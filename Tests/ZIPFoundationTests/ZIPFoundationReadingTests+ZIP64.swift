//
//  ZIPFoundationReadingTests+ZIP64.swift
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

    // MARK: - helpers

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
