//
//  ZIPFoundationErrorConditionTests.swift
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
    func testArchiveReadErrorConditions() {
        let nonExistantURL = URL(fileURLWithPath: "/nothing")
        let nonExistantArchive = Archive(url: nonExistantURL, accessMode: .read)
        XCTAssertNil(nonExistantArchive)
        var unreadableArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let processInfo = ProcessInfo.processInfo
        unreadableArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
        let noPermissionAttributes = [FileAttributeKey.posixPermissions: NSNumber(value: Int16(0o000))]
        let fileManager = FileManager()
        var result = fileManager.createFile(atPath: unreadableArchiveURL.path, contents: nil,
                                            attributes: noPermissionAttributes)
        XCTAssert(result == true)
        let unreadableArchive = Archive(url: unreadableArchiveURL, accessMode: .read)
        XCTAssertNil(unreadableArchive)
        var noEndOfCentralDirectoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        noEndOfCentralDirectoryArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
        let fullPermissionAttributes = [FileAttributeKey.posixPermissions: NSNumber(value: defaultFilePermissions)]
        result = fileManager.createFile(atPath: noEndOfCentralDirectoryArchiveURL.path, contents: nil,
                                        attributes: fullPermissionAttributes)
        XCTAssert(result == true)
        let noEndOfCentralDirectoryArchive = Archive(url: noEndOfCentralDirectoryArchiveURL,
                                                     accessMode: .read)
        XCTAssertNil(noEndOfCentralDirectoryArchive)
    }

    func testArchiveIteratorErrorConditions() {
        var didFailToMakeIteratorAsExpected = true
        // Construct an archive that only contains an EndOfCentralDirectoryRecord
        // with a number of entries > 0.
        // While the initializer is expected to work for such archives, iterator creation
        // should fail.
        let invalidCentralDirECDS: [UInt8] = [0x50, 0x4B, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00,
                                              0x01, 0x00, 0x01, 0x00, 0x5A, 0x00, 0x00, 0x00,
                                              0x2A, 0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidCentralDirECDSData = Data(invalidCentralDirECDS)
        let processInfo = ProcessInfo.processInfo
        var invalidCentralDirArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        invalidCentralDirArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
        let fileManager = FileManager()
        let result = fileManager.createFile(atPath: invalidCentralDirArchiveURL.path,
                                            contents: invalidCentralDirECDSData,
                                            attributes: nil)
        XCTAssert(result == true)
        guard let invalidCentralDirArchive = Archive(url: invalidCentralDirArchiveURL,
                                                     accessMode: .read) else {
            XCTFail("Failed to read archive.")
            return
        }
        for _ in invalidCentralDirArchive {
            didFailToMakeIteratorAsExpected = false
        }
        XCTAssertTrue(didFailToMakeIteratorAsExpected)
        let archive = self.archive(for: #function, mode: .read)
        do {
            var invalidLocalFHArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
            invalidLocalFHArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
            var invalidLocalFHArchiveData = try Data(contentsOf: archive.url)
            // Construct an archive with a corrupt LocalFileHeader.
            // While the initializer is expected to work for such archives, iterator creation
            // should fail.
            invalidLocalFHArchiveData[26] = 0xFF
            try invalidLocalFHArchiveData.write(to: invalidLocalFHArchiveURL)
            guard let invalidLocalFHArchive = Archive(url: invalidLocalFHArchiveURL,
                                                      accessMode: .read) else {
                XCTFail("Failed to read local file header.")
                return
            }
            for _ in invalidLocalFHArchive {
                didFailToMakeIteratorAsExpected = false
            }
        } catch {
            XCTFail("Unexpected error while testing iterator error conditions.")
        }
        XCTAssertTrue(didFailToMakeIteratorAsExpected)
    }

    func testArchiveInvalidDataErrorConditions() {
        let ecdrInvalidCommentBytes: [UInt8] = [0x50, 0x4B, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00,
                                                0x01, 0x00, 0x01, 0x00, 0x5A, 0x00, 0x00, 0x00,
                                                0x2A, 0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidECDRCommentData = Data(ecdrInvalidCommentBytes)
        let invalidECDRComment = Archive.EndOfCentralDirectoryRecord(data: invalidECDRCommentData,
                                                                     additionalDataProvider: {_ -> Data in
                                                                        throw AdditionalDataError.invalidDataError })
        XCTAssertNil(invalidECDRComment)
        let ecdrInvalidCommentLengthBytes: [UInt8] = [0x50, 0x4B, 0x05, 0x06, 0x00, 0x00, 0x00, 0x00,
                                                      0x01, 0x00, 0x01, 0x00, 0x5A, 0x00, 0x00, 0x00,
                                                      0x2A, 0x00, 0x00, 0x00, 0x00, 0x01]
        let invalidECDRCommentLengthData = Data(ecdrInvalidCommentLengthBytes)
        let invalidECDRCommentLength = Archive.EndOfCentralDirectoryRecord(data: invalidECDRCommentLengthData,
                                                                           additionalDataProvider: {_ -> Data in
                                                                            return Data() })
        XCTAssertNil(invalidECDRCommentLength)
    }
}
