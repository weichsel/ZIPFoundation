//
//  ZIPFoundationFileManagerTests+ZIP64.swift
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
    private enum ZIP64FileManagerTestsError: Error, CustomStringConvertible {
        case failedToZipItem(url: URL)
        case failedToReadArchive(url: URL)
        case failedToUnzipItem

        var description: String {
            switch self {
            case .failedToZipItem(let assetURL):
                return "Failed to zip item at URL: \(assetURL)."
            case .failedToReadArchive(let fileArchiveURL):
                return "Failed to read archive at URL: \(fileArchiveURL)."
            case .failedToUnzipItem:
                return "Failed to unzip item."
            }
        }
    }

    func testZipCompressedZIP64Item() {
        do {
            try archiveZIP64Item(for: #function, compressionMethod: .deflate)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testZipUncompressedZIP64Item() {
        do {
            try archiveZIP64Item(for: #function, compressionMethod: .none)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testUnzipCompressedZIP64Item() {
        // compressed(deflate) by zip 3.0 via command line: zip -r -fz
        do {
            try unarchiveZIP64Item(for: #function)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testUnzipUncompressedZIP64Item() {
        // stored by zip 3.0 via command line: zip -0 -fz
        do {
            try unarchiveZIP64Item(for: #function)
        } catch {
            XCTFail("\(error)")
        }
    }

    // MARK: - helpers

    private func archiveZIP64Item(for testFunction: String, compressionMethod: CompressionMethod) throws {
        mockIntMaxValues(int32Factor: 16, int16Factor: 16)
        defer { resetIntMaxValues() }
        let assetURL = self.resourceURL(for: testFunction, pathExtension: "png")
        var fileArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        fileArchiveURL.appendPathComponent(self.archiveName(for: testFunction))
        do {
            try FileManager().zipItem(at: assetURL, to: fileArchiveURL, compressionMethod: compressionMethod)
        } catch {
            throw ZIP64FileManagerTestsError.failedToZipItem(url: assetURL)
        }
        guard let archive = Archive(url: fileArchiveURL, accessMode: .read) else {
            throw ZIP64FileManagerTestsError.failedToZipItem(url: fileArchiveURL)
        }
        XCTAssertNotNil(archive[assetURL.lastPathComponent])
        XCTAssert(archive.checkIntegrity())
    }

    private func unarchiveZIP64Item(for testFunction: String) throws {
        // File Structure:
        // testUnzipCompressedZIP64Item.zip/
        //   ├─ directory
        //   ├─ testLink
        //   ├─ nested
        //     ├─ nestedLink
        //     ├─ faust copy.txt
        //     ├─ deep
        //       ├─ another.random
        //   ├─ faust.txt
        //   ├─ empty
        //   ├─ data.random
        //   ├─ random.data
        let fileManager = FileManager()
        let archive = self.archive(for: testFunction, mode: .read)
        let destinationURL = self.createDirectory(for: testFunction)
        do {
            try fileManager.unzipItem(at: archive.url, to: destinationURL)
        } catch {
            throw ZIP64FileManagerTestsError.failedToUnzipItem
        }
        var itemsExist = false
        for entry in archive {
            let directoryURL = destinationURL.appendingPathComponent(entry.path)
            itemsExist = fileManager.itemExists(at: directoryURL)
            if !itemsExist { break }
        }
        XCTAssert(itemsExist)
    }
}
