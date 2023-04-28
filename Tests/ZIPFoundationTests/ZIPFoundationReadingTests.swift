//
//  ZIPFoundationReadingTests.swift
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

    func testExtractUncompressedFolderEntries() {
        let archive = self.archive(for: #function, mode: .read)
        for entry in archive {
            do {
                // Test extracting to memory
                var checksum = try archive.extract(entry, bufferSize: 32, consumer: { _ in })
                XCTAssert(entry.checksum == checksum)
                // Test extracting to file
                var fileURL = self.createDirectory(for: #function)
                fileURL.appendPathComponent(entry.path)
                checksum = try archive.extract(entry, to: fileURL)
                XCTAssert(entry.checksum == checksum)
                let fileManager = FileManager()
                XCTAssertTrue(fileManager.itemExists(at: fileURL))
                if entry.type == .file {
                    let fileData = try Data(contentsOf: fileURL)
                    let checksum = fileData.crc32(checksum: 0)
                    XCTAssert(checksum == entry.checksum)
                }
            } catch {
                XCTFail("Failed to unzip uncompressed folder entries")
            }
        }
    }

    func testExtractCompressedFolderEntries() {
        let archive = self.archive(for: #function, mode: .read)
        for entry in archive {
            do {
                // Test extracting to memory
                var checksum = try archive.extract(entry, bufferSize: 128, consumer: { _ in })
                XCTAssert(entry.checksum == checksum)
                // Test extracting to file
                var fileURL = self.createDirectory(for: #function)
                fileURL.appendPathComponent(entry.path)
                checksum = try archive.extract(entry, to: fileURL)
                XCTAssert(entry.checksum == checksum)
                let fileManager = FileManager()
                XCTAssertTrue(fileManager.itemExists(at: fileURL))
                if entry.type != .directory {
                    let fileData = try Data(contentsOf: fileURL)
                    let checksum = fileData.crc32(checksum: 0)
                    XCTAssert(checksum == entry.checksum)
                }
            } catch {
                XCTFail("Failed to unzip compressed folder entries")
            }
        }
    }

    func testExtractUncompressedDataDescriptorArchive() {
        let archive = self.archive(for: #function, mode: .read)
        for entry in archive {
            do {
                let checksum = try archive.extract(entry, consumer: { _ in })
                XCTAssert(entry.checksum == checksum)
            } catch {
                XCTFail("Failed to unzip data descriptor archive")
            }
        }
    }

    func testExtractCompressedDataDescriptorArchive() {
        let archive = self.archive(for: #function, mode: .read)
        for entry in archive {
            do {
                let checksum = try archive.extract(entry, consumer: { _ in })
                XCTAssert(entry.checksum == checksum)
            } catch {
                XCTFail("Failed to unzip data descriptor archive")
            }
        }
    }

    func testExtractPreferredEncoding() {
        let encoding = String.Encoding.utf8
        let archive = self.archive(for: #function, mode: .read, preferredEncoding: encoding)
        XCTAssertTrue(archive.checkIntegrity())
        let imageEntry = archive["data/pic👨‍👩‍👧‍👦🎂.jpg"]
        XCTAssertNotNil(imageEntry)
        let textEntry = archive["data/Benoît.txt"]
        XCTAssertNotNil(textEntry)
    }

    func testExtractMSDOSArchive() {
        let archive = self.archive(for: #function, mode: .read)
        for entry in archive {
            do {
                let checksum = try archive.extract(entry, consumer: { _ in })
                XCTAssert(entry.checksum == checksum)
            } catch {
                XCTFail("Failed to unzip MSDOS archive")
            }
        }
    }

    func testExtractErrorConditions() {
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertNotNil(archive)
        guard let fileEntry = archive["testZipItem.png"] else {
            XCTFail("Failed to obtain test asset from archive.")
            return
        }
        XCTAssertNotNil(fileEntry)
        do {
            _ = try archive.extract(fileEntry, to: archive.url)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileWriteFileExists)
        } catch {
            XCTFail("Unexpected error while trying to extract entry to existing URL.")
            return
        }
        guard let linkEntry = archive["testZipItemLink"] else {
            XCTFail("Failed to obtain test asset from archive.")
            return
        }
        do {
            let longFileName = String(repeating: ProcessInfo.processInfo.globallyUniqueString, count: 100)
            var overlongURL = URL(fileURLWithPath: NSTemporaryDirectory())
            overlongURL.appendPathComponent(longFileName)
            _ = try archive.extract(fileEntry, to: overlongURL)
        } catch let error as POSIXError {
            XCTAssert(error.code == POSIXErrorCode.ENAMETOOLONG)
        } catch {
            XCTFail("Unexpected error while trying to extract entry to invalid URL.")
            return
        }
        XCTAssertNotNil(linkEntry)
        do {
            _ = try archive.extract(linkEntry, to: archive.url)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileWriteFileExists)
        } catch {
            XCTFail("Unexpected error while trying to extract link entry to existing URL.")
            return
        }
    }

    func testCorruptFileErrorConditions() {
        let archiveURL = self.resourceURL(for: #function, pathExtension: "zip")
        let fileManager = FileManager()
        let destinationFileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: archiveURL.path)
        let destinationFile: FILEPointer = fopen(destinationFileSystemRepresentation, "r+b")

        do {
            fseek(destinationFile, 64, SEEK_SET)
            // We have to inject a large enough zeroes block to guarantee that libcompression
            // detects the failure when reading the stream
            _ = try Data.write(chunk: Data(count: 512*1024), to: destinationFile)
            fclose(destinationFile)
            guard let archive = Archive(url: archiveURL, accessMode: .read) else {
                XCTFail("Failed to read archive.")
                return
            }
            guard let entry = archive["data.random"] else {
                XCTFail("Failed to read entry.")
                return
            }
            _ = try archive.extract(entry, consumer: { _ in })
        } catch let error as Data.CompressionError {
            XCTAssert(error == Data.CompressionError.corruptedData)
        } catch {
            XCTFail("Unexpected error while testing an archive with corrupt entry data.")
        }
    }

    func testCorruptSymbolicLinkErrorConditions() {
        let archive = self.archive(for: #function, mode: .read)
        for entry in archive {
            do {
                var tempFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
                tempFileURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
                _ = try archive.extract(entry, to: tempFileURL)
            } catch let error as Archive.ArchiveError {
                XCTAssert(error == .invalidEntryPath)
            } catch {
                XCTFail("Unexpected error while trying to extract entry with invalid symbolic link.")
            }
        }
    }

    func testInvalidCompressionMethodErrorConditions() {
        let archive = self.archive(for: #function, mode: .read)
        for entry in archive {
            do {
                _ = try archive.extract(entry, consumer: { (_) in })
            } catch let error as Archive.ArchiveError {
                XCTAssert(error == .invalidCompressionMethod)
            } catch {
                XCTFail("Unexpected error while trying to extract entry with invalid compression method link.")
            }
        }
    }

    func testExtractEncryptedArchiveErrorConditions() {
        let archive = self.archive(for: #function, mode: .read)
        var entriesRead = 0
        for _ in archive {
            entriesRead += 1
        }
        // We currently don't support encryption so we expect failed initialization for entry objects.
        XCTAssert(entriesRead == 0)
    }

    func testExtractInvalidBufferSizeErrorConditions() {
        let archive = self.archive(for: #function, mode: .read)
        let entry = archive["text.txt"]!
        XCTAssertThrowsError(try archive.extract(entry, to: URL(fileURLWithPath: ""), bufferSize: 0, skipCRC32: true))
        let archive2 = self.archive(for: #function, mode: .read)
        let entry2 = archive2["text.txt"]!
        XCTAssertThrowsError(try archive2.extract(entry2, bufferSize: 0, skipCRC32: true, consumer: { _ in }))
    }

    func testExtractUncompressedEmptyFile() {
        // We had a logic error, where completion handlers for empty entries were not called
        // Ensure that this edge case works
        var didCallCompletion = false
        let archive = self.archive(for: #function, mode: .read)
        guard let entry = archive["empty.txt"] else { XCTFail("Failed to extract entry."); return }

        do {
            _ = try archive.extract(entry) { (data) in
                XCTAssertEqual(data.count, 0)
                didCallCompletion = true
            }
        } catch {
            XCTFail("Unexpected error while trying to extract empty file of uncompressed archive.")
        }
        XCTAssert(didCallCompletion)
    }

    func testExtractUncompressedEntryCancelation() {
        let archive = self.archive(for: #function, mode: .read)
        guard let entry = archive["original"] else { XCTFail("Failed to extract entry."); return }
        let progress = archive.makeProgressForReading(entry)
        do {
            var readCount = 0
            _ = try archive.extract(entry, bufferSize: 1, progress: progress) { (data) in
                readCount += data.count
                if readCount == 4 { progress.cancel() }
            }
        } catch let error as Archive.ArchiveError {
            XCTAssert(error == Archive.ArchiveError.cancelledOperation)
            XCTAssertEqual(progress.fractionCompleted, 0.5, accuracy: .ulpOfOne)
        } catch {
            XCTFail("Unexpected error while trying to cancel extraction.")
        }
    }

    func testExtractCompressedEntryCancelation() {
        let archive = self.archive(for: #function, mode: .read)
        guard let entry = archive["random"] else { XCTFail("Failed to extract entry."); return }
        let progress = archive.makeProgressForReading(entry)
        do {
            var readCount = 0
            _ = try archive.extract(entry, bufferSize: 256, progress: progress) { (data) in
                readCount += data.count
                if readCount == 512 { progress.cancel() }
            }
        } catch let error as Archive.ArchiveError {
            XCTAssert(error == Archive.ArchiveError.cancelledOperation)
            XCTAssertEqual(progress.fractionCompleted, 0.5, accuracy: .ulpOfOne)
        } catch {
            XCTFail("Unexpected error while trying to cancel extraction.")
        }
    }

    func testReadCompressedDataAtOffset() throws {
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

    func testProgressHelpers() {
        let tempPath = NSTemporaryDirectory()
        var nonExistantURL = URL(fileURLWithPath: tempPath)
        nonExistantURL.appendPathComponent("invalid.path")
        let archive = self.archive(for: #function, mode: .update)
        XCTAssert(archive.totalUnitCountForAddingItem(at: nonExistantURL) == -1)
    }

    func testDetectEntryType() {
        let archive = self.archive(for: #function, mode: .read)
        let expectedData: [String: Entry.EntryType] = [
            "META-INF/": .directory,
            "META-INF/container.xml": .file
        ]
        for entry in archive {
            XCTAssertEqual(entry.type, expectedData[entry.path])
        }
    }

    func testCRC32Check() {
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        do {
            try fileManager.unzipItem(at: archive.url, to: destinationURL)
        } catch let error as Archive.ArchiveError {
            XCTAssert(error == Archive.ArchiveError.invalidCRC32)
            return
        } catch {
            XCTFail("Extraction should fail with an archive error")
        }
        XCTFail("Extraction should fail")
    }

    func testTraversalAttack() {
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        do {
            try fileManager.unzipItem(at: archive.url, to: destinationURL)
        } catch {
            XCTAssert((error as? CocoaError)?.code == .fileReadInvalidFileName); return
        }
        XCTFail("Extraction should fail")
    }
}
