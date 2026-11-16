//
//  ZIPFoundationArchiveTests+ZIP64.swift
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

    func testArchiveZIP64EOCDRecord() {
        let eocdRecordBytes: [UInt8] = [0x50, 0x4b, 0x06, 0x06, 0x2c, 0x00, 0x00, 0x00,
                                        0x00, 0x00, 0x00, 0x00, 0x2d, 0x00, 0x03, 0x15,
                                        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                        0x4c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                        0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let zip64EOCDRecord = Archive.ZIP64EndOfCentralDirectoryRecord(data: Data(eocdRecordBytes),
                                                                       additionalDataProvider: {_ -> Data in
                                                                        return Data() })
        XCTAssertNotNil(zip64EOCDRecord)
    }

    func testArchiveInvalidZIP64EOCERecordConditions() {
        let emptyEOCDRecord = Archive.ZIP64EndOfCentralDirectoryRecord(data: Data(),
                                                                       additionalDataProvider: {_ -> Data in
                                                                        return Data() })
        XCTAssertNil(emptyEOCDRecord)
        let eocdRecordIncludingExtraByte: [UInt8] = [0x50, 0x4b, 0x06, 0x06, 0x2c, 0x00, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0x00, 0x2d, 0x00, 0x03, 0x15,
                                                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x4c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x00, 0x00]
        let invalidEOCDRecord = Archive.ZIP64EndOfCentralDirectoryRecord(data: Data(eocdRecordIncludingExtraByte),
                                                                         additionalDataProvider: {_ -> Data in
                                                                            return Data() })
        XCTAssertNil(invalidEOCDRecord)
        let eocdRecordMissingByte: [UInt8] = [0x50, 0x4b, 0x06, 0x06, 0x2c, 0x00, 0x00, 0x00,
                                              0x00, 0x00, 0x00, 0x00, 0x2d, 0x00, 0x03, 0x15,
                                              0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                              0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidEOCDRecord2 = Archive.ZIP64EndOfCentralDirectoryRecord(data: Data(eocdRecordMissingByte),
                                                                          additionalDataProvider: {_ -> Data in
                                                                             return Data() })
        XCTAssertNil(invalidEOCDRecord2)
        // Some ZIP producers (e.g. Microsoft Outlook OLM export) write valid ZIP64
        // structures with versionNeededToExtract < 4.5. These should be accepted.
        let eocdRecordWithLowVersion: [UInt8] = [0x50, 0x4b, 0x06, 0x06, 0x2c, 0x00, 0x00, 0x00,
                                                  0x00, 0x00, 0x00, 0x00, 0x1e, 0x03, 0x14, 0x00,
                                                  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                  0x4c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                  0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let lowVersionEOCDRecord = Archive.ZIP64EndOfCentralDirectoryRecord(data: Data(eocdRecordWithLowVersion),
                                                                            additionalDataProvider: {_ -> Data in
                                                                               return Data() })
        XCTAssertNotNil(lowVersionEOCDRecord)
    }

    func testArchiveZIP64EOCDLocator() {
        let eocdLocatorBytes: [UInt8] = [0x50, 0x4b, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00,
                                         0x9a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                         0x01, 0x00, 0x00, 0x00]
        let zip64EOCDRecord = Archive.ZIP64EndOfCentralDirectoryLocator(data: Data(eocdLocatorBytes),
                                                                        additionalDataProvider: {_ -> Data in
                                                                            return Data() })
        XCTAssertNotNil(zip64EOCDRecord)
    }

    func testArchiveInvalidZIP64EOCDLocatorConditions() {
        let emptyEOCDLocator = Archive.ZIP64EndOfCentralDirectoryLocator(data: Data(),
                                                                         additionalDataProvider: {_ -> Data in
                                                                            return Data() })
        XCTAssertNil(emptyEOCDLocator)
        let eocdLocatorIncludingExtraByte: [UInt8] = [0x50, 0x4b, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00,
                                                      0x9a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                      0x01, 0x00, 0x00, 0x00, 0x00]
        let invalidEOCDLocator = Archive.ZIP64EndOfCentralDirectoryLocator(data: Data(eocdLocatorIncludingExtraByte),
                                                                           additionalDataProvider: {_ -> Data in
                                                                            return Data() })
        XCTAssertNil(invalidEOCDLocator)
        let eocdLocatorMissingByte: [UInt8] = [0x50, 0x4b, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00,
                                               0x9a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidEOCDLocator2 = Archive.ZIP64EndOfCentralDirectoryLocator(data: Data(eocdLocatorMissingByte),
                                                                           additionalDataProvider: {_ -> Data in
                                                                            return Data() })
        XCTAssertNil(invalidEOCDLocator2)
    }

    func testReadZIP64ArchiveWithLowVersionNeededToExtract() throws {
        // The ZIP64 end of central directory record has a "version needed to extract" of 1.0 and
        // the only entry is a ZIP64 entry with a local header offset of 0.
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertEqual(archive.map { $0.path }, ["a"])
        var extractedData = Data()
        _ = try archive.extract(XCTUnwrap(archive["a"]), consumer: { extractedData.append($0) })
        XCTAssertEqual(extractedData, Data("a".utf8))
    }
}

extension ZIPFoundationTests {

    // MARK: - ZIP64 Helpers

    // It's not practical to create compressed files that exceed the size limit every time for test,
    // so provide helper methods to mock the maximum size limit

    func mockIntMaxValues(int32Factor: Int = 64, int16Factor: Int = 64) {
        maxUInt32 = UInt32(int32Factor * int32Factor)
        maxUInt16 = UInt16(int16Factor)
    }

    func resetIntMaxValues() {
        maxUInt32 = .max
        maxUInt16 = .max
    }
}
