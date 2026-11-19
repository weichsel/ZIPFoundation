//
//  ZIPFoundationErrorConditionTests.swift
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

    func testArchiveInvalidEOCDRecordConditions() {
        let emptyECDR = Archive.EndOfCentralDirectoryRecord(data: Data(),
                                                            additionalDataProvider: {_ -> Data in
            return Data() })
        XCTAssertNil(emptyECDR)
        let invalidECDRData = Data(count: 22)
        let invalidECDR = Archive.EndOfCentralDirectoryRecord(data: invalidECDRData,
                                                              additionalDataProvider: {_ -> Data in
            return Data() })
        XCTAssertNil(invalidECDR)
    }

    func testArchiveWithTrailingData() throws {
        let archive = self.archive(for: #function, mode: .create)
        try archive.addEntry(with: "a", type: .file, uncompressedSize: Int64(1), provider: { _, _ in Data([0]) })
        let archiveData = try Data(contentsOf: archive.url)
        let trailingDataURL = ZIPFoundationTests.tempZipDirectoryURL.appendingPathComponent("trailingData.zip")
        // The end of central directory record is followed by more data than a ZIP file comment can hold.
        // Different sizes move the signature of the record across the boundaries of the scanned chunks.
        let scannedSize = Int(maxDirectoryEndOffset)
        for trailingDataSize in [scannedSize, 70000] + (0...4).map({ scannedSize + 3 * defaultReadChunkSize + $0 }) {
            try (archiveData + Data(count: trailingDataSize)).write(to: trailingDataURL)
            let trailingDataArchive = try Archive(url: trailingDataURL, accessMode: .read)
            XCTAssertEqual(trailingDataArchive.map { $0.path }, ["a"])
            XCTAssert(trailingDataArchive.checkIntegrity())
        }
        try Data(count: scannedSize + 3 * defaultReadChunkSize).write(to: trailingDataURL)
        XCTAssertSwiftError(try Archive(url: trailingDataURL, accessMode: .read),
                            throws: Archive.ArchiveError.missingEndOfCentralDirectoryRecord)
    }

    func testRemoveEntryBeforeStoredSymlinkWithWrongSize() throws {
        // The stored symlink "link" states an uncompressed size of 4 bytes, but stores a 13 byte destination.
        let archive = self.archive(for: #function, mode: .update)
        try archive.remove(XCTUnwrap(archive["first"]))
        let reopenedArchive = try Archive(url: archive.url, accessMode: .read)
        XCTAssertEqual(reopenedArchive.map { $0.path }, ["link", "file"])
        XCTAssert(reopenedArchive.checkIntegrity())
        var linkData = Data()
        _ = try reopenedArchive.extract(XCTUnwrap(reopenedArchive["link"])) { linkData.append($0) }
        XCTAssertEqual(linkData, Data("a-long-target".utf8))
    }

    func testRemoveEntryBeforeStoredSymlinkWithDataDescriptor() throws {
        // The 13-byte target is followed by a descriptor reporting an uncompressed size of 4.
        let archive = self.archive(for: #function, mode: .update)
        try archive.remove(XCTUnwrap(archive["first"]))
        let reopenedArchive = try Archive(url: archive.url, accessMode: .read)
        XCTAssertEqual(reopenedArchive.map { $0.path }, ["link", "file"])
        let link = try XCTUnwrap(reopenedArchive["link"])
        let descriptor = try XCTUnwrap(link.dataDescriptor)
        let target = Data("a-long-target".utf8)
        XCTAssertEqual(descriptor.compressedSize, UInt32(target.count))
        XCTAssertEqual(descriptor.uncompressedSize, 4)
        XCTAssertEqual(descriptor.crc32, target.crc32(checksum: 0))
        let bytes = try Data(contentsOf: archive.url)
        XCTAssertEqual(bytes.dropFirst(Int(link.dataOffset)).prefix(target.count), target)
        var fileData = Data()
        _ = try reopenedArchive.extract(XCTUnwrap(reopenedArchive["file"])) { fileData.append($0) }
        XCTAssertEqual(fileData, Data("abc".utf8))
    }

    func testRemoveEntryBeforeWrongDataDescriptorSize() throws {
        // The data descriptor of the deflated entry "data" states a compressed size of 4 bytes.
        // The central directory states the actual size.
        let archive = self.archive(for: #function, mode: .update)
        let entry = try XCTUnwrap(archive["data"])
        XCTAssertEqual(entry.dataDescriptor?.compressedSize, 4)
        XCTAssertNotEqual(entry.centralDirectoryStructure.effectiveCompressedSize, 4)
        try archive.remove(XCTUnwrap(archive["first"]))
        let reopenedArchive = try Archive(url: archive.url, accessMode: .read)
        XCTAssertEqual(reopenedArchive.map { $0.path }, ["data", "file"])
        XCTAssert(reopenedArchive.checkIntegrity())
        var data = Data()
        _ = try reopenedArchive.extract(XCTUnwrap(reopenedArchive["data"])) { data.append($0) }
        XCTAssertEqual(data, Data(String(repeating: "compressible ", count: 8).utf8))
    }

    func testExtractStoredFileWithWrongUncompressedSize() throws {
        // The central directory of the stored entry "data" states an uncompressed size of 5 bytes,
        // but its file data is 3 bytes long.
        let archive = self.archive(for: #function, mode: .read)
        let entry = try XCTUnwrap(archive["data"])
        XCTAssertEqual(entry.uncompressedSize, 5)
        let progress = archive.makeProgressForReading(entry)
        var data = Data()
        let checksum = try archive.extract(entry, progress: progress) { data.append($0) }
        XCTAssertEqual(data, Data("abc".utf8))
        XCTAssertEqual(checksum, entry.checksum)
        XCTAssertEqual(progress.totalUnitCount, 3)
        XCTAssertEqual(progress.completedUnitCount, 3)
    }

    func testReadEntryWithWrongDataDescriptorSizes() throws {
        // The data descriptor of the deflated entry "data" states a compressed size of 4 bytes
        // and an uncompressed size of 8 bytes. The central directory states the actual sizes.
        let archive = self.archive(for: #function, mode: .read)
        let entry = try XCTUnwrap(archive["data"])
        XCTAssertEqual(entry.dataDescriptor?.compressedSize, 4)
        XCTAssertEqual(entry.dataDescriptor?.uncompressedSize, 8)
        let content = Data(String(repeating: "compressible ", count: 8).utf8)
        XCTAssertEqual(entry.compressedSize, entry.centralDirectoryStructure.effectiveCompressedSize)
        XCTAssertEqual(entry.uncompressedSize, UInt64(content.count))
        let progress = archive.makeProgressForReading(entry)
        var data = Data()
        _ = try archive.extract(entry, progress: progress) { data.append($0) }
        XCTAssertEqual(data, content)
        XCTAssertEqual(progress.totalUnitCount, Int64(content.count))
        XCTAssertEqual(progress.completedUnitCount, progress.totalUnitCount)
    }

    func testUnzipEntryWithWrongDataDescriptor() throws {
        // The data descriptor of the deflated entry "data" states wrong sizes and a wrong checksum.
        // The central directory states the actual values.
        let archive = self.archive(for: #function, mode: .read)
        let entry = try XCTUnwrap(archive["data"])
        let content = Data(String(repeating: "compressible ", count: 8).utf8)
        XCTAssertEqual(entry.dataDescriptor?.compressedSize, 4)
        XCTAssertNotEqual(entry.dataDescriptor?.crc32, content.crc32(checksum: 0))
        XCTAssertEqual(entry.checksum, content.crc32(checksum: 0))
        let destinationURL = self.createDirectory(for: #function)
        try FileManager().unzipItem(at: archive.url, to: destinationURL)
        XCTAssertEqual(try Data(contentsOf: destinationURL.appendingPathComponent("data")), content)
    }

    func testRemoveEntryBeforeUnsignedDataDescriptor() throws {
        // All entries of the archive end in data descriptors without signatures. The removal has to
        // copy the remaining entries including their 12 byte descriptors. A wrong descriptor length
        // also shifts the start of the written central directory.
        let archive = self.archive(for: #function, mode: .update)
        let entry = try XCTUnwrap(archive["data"])
        XCTAssertEqual(entry.dataDescriptor?.hasSignature, false)
        XCTAssertEqual(entry.dataDescriptor?.encodedSize, 12)
        try archive.remove(XCTUnwrap(archive["first"]))
        let reopenedArchive = try Archive(url: archive.url, accessMode: .read)
        XCTAssertEqual(reopenedArchive.map { $0.path }, ["data", "file"])
        XCTAssert(reopenedArchive.checkIntegrity())
        // The following entry starts right after the descriptor.
        let dataEntry = try XCTUnwrap(reopenedArchive["data"])
        let fileEntry = try XCTUnwrap(reopenedArchive["file"])
        XCTAssertEqual(fileEntry.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader,
                       dataEntry.dataOffset + dataEntry.compressedSize + 12)
        var data = Data()
        _ = try reopenedArchive.extract(dataEntry) { data.append($0) }
        XCTAssertEqual(data, Data(String(repeating: "compressible ", count: 8).utf8))
        // The last entry ends in a 12 byte descriptor without a signature too.
        try archive.remove(try XCTUnwrap(archive["data"]))
        XCTAssertEqual(archive.map { $0.path }, ["file"])
        XCTAssert(archive.checkIntegrity())
        let movedFileEntry = try XCTUnwrap(archive["file"])
        XCTAssertEqual(movedFileEntry.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader, 0)
        XCTAssertEqual(archive.offsetToStartOfCentralDirectory,
                       movedFileEntry.dataOffset + movedFileEntry.compressedSize + 12)
    }

    func testDirectoryCreationHelperMethods() {
        let processInfo = ProcessInfo.processInfo
        var nestedURL = ZIPFoundationTests.tempZipDirectoryURL
        nestedURL.appendPathComponent(processInfo.globallyUniqueString)
        nestedURL.appendPathComponent(processInfo.globallyUniqueString)
        do {
            try FileManager().createParentDirectoryStructure(for: nestedURL)
        } catch { XCTFail("Failed to create parent directory.") }
    }

    func testTemporaryReplacementDirectoryURL() throws {
        let archive = self.archive(for: #function, mode: .create)
        var tempURLs = Set<URL>()
        defer { for url in tempURLs { try? FileManager.default.removeItem(at: url) } }
        // We choose 2000 temp directories to test workaround for http://openradar.appspot.com/50553219
        for _ in 1...2000 {
            let tempDir = URL.temporaryReplacementDirectoryURL(for: archive)
            XCTAssertFalse(tempURLs.contains(tempDir), "Temp directory URL should be unique. \(tempDir)")
            tempURLs.insert(tempDir)
        }

#if swift(>=5.0) && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || os(Linux))
        // Also cover the fallback codepath in the helper method to generate a unique temp URL.
        // In-memory archives have no filesystem representation and therefore don't need a per-volume
        // temp URL.
        let memoryArchive = try Archive(data: Data(), accessMode: .create)
        let memoryTempURL = URL.temporaryReplacementDirectoryURL(for: memoryArchive)
        XCTAssertNotNil(memoryTempURL, "Temporary URL creation for in-memory archive failed.")
#endif
    }
}

extension XCTestCase {

    func XCTAssertSwiftError<T, E: Error & Equatable>(_ expression: @autoclosure () throws -> T,
                                                      throws error: E,
                                                      in file: StaticString = #file,
                                                      line: UInt = #line) {
        var thrownError: Error?
        XCTAssertThrowsError(try expression(), file: file, line: line) { thrownError = $0}
        XCTAssertTrue(thrownError is E, "Unexpected error type: \(type(of: thrownError))", file: file, line: line)
        XCTAssertEqual(thrownError as? E, error, file: file, line: line)
    }

    func XCTAssertPOSIXError<T>(_ expression: @autoclosure () throws -> T,
                                throwsErrorWithCode code: POSIXError.Code,
                                in file: StaticString = #file,
                                line: UInt = #line) {
        var thrownError: POSIXError?
        XCTAssertThrowsError(try expression(), file: file, line: line) { thrownError = $0 as? POSIXError }
        XCTAssertNotNil(thrownError, file: file, line: line)
        XCTAssertTrue(thrownError?.code == code, file: file, line: line)
    }

    func XCTAssertCocoaError<T>(_ expression: @autoclosure () throws -> T,
                                throwsErrorWithCode code: CocoaError.Code,
                                in file: StaticString = #file,
                                line: UInt = #line) {
        var thrownError: CocoaError?
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        XCTAssertThrowsError(try expression(), file: file, line: line) { thrownError = $0 as? CocoaError}
        #else
        XCTAssertThrowsError(try expression(), file: file, line: line) {
            // For unknown reasons, some errors in the `NSCocoaErrorDomain` can't be cast to `CocoaError` on Linux.
            // We manually re-create them here as `CocoaError` to work around this.
            thrownError = CocoaError(.init(rawValue: ($0 as NSError).code))
        }
        #endif
        XCTAssertNotNil(thrownError, file: file, line: line)
        XCTAssertTrue(thrownError?.code == code, file: file, line: line)
    }
}

extension Archive {
    func checkIntegrity() -> Bool {
        var isCorrect = false
        do {
            for entry in self {
                let checksum = try self.extract(entry, consumer: { _ in })
                isCorrect = checksum == entry.checksum
                guard isCorrect else { break }
            }
        } catch { return false }
        return isCorrect
    }
}
