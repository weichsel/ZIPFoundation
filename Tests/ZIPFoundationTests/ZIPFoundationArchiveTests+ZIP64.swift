//
//  ZIPFoundationArchiveTests+ZIP64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2024 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
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
        let eocdRecordWithWrongVersion: [UInt8] = [0x50, 0x4b, 0x06, 0x06, 0x2c, 0x00, 0x00, 0x00,
                                                   0x00, 0x00, 0x00, 0x00, 0x1e, 0x03, 0x14, 0x00,
                                                   0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                   0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                   0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                   0x4c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                   0x5a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidEOCDRecord3 = Archive.ZIP64EndOfCentralDirectoryRecord(data: Data(eocdRecordWithWrongVersion),
                                                                          additionalDataProvider: {_ -> Data in
                                                                             return Data() })
        XCTAssertNil(invalidEOCDRecord3)
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
}
