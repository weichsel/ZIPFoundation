//
//  ZIPFoundationEntryTests+ZIP64.swift
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
    func testEntryZIP64ExtraField() {
        let extraFieldBytesIncludingSizeFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00]
        let zip64ExtraField1 = Entry.ZIP64ExtendedInformation(data: Data(extraFieldBytesIncludingSizeFields),
                                                             fields: [.compressedSize, .uncompressedSize])
        XCTAssertNotNil(zip64ExtraField1)
        let extraFieldBytesIncludingOtherFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                            0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00]
        let zip64ExtraField2 = Entry.ZIP64ExtendedInformation(data: Data(extraFieldBytesIncludingOtherFields),
                                                              fields: [.relativeOffsetOfLocalHeader, .diskNumberStart])
        XCTAssertNotNil(zip64ExtraField2)
        // TODO: chen test extraFields, validFields.
    }

    func testEntryZIP64FieldOnlyHasUncompressedSize() {
        // Including both original and compressed file size fields. (at least in the Local header)
        let expectedZIP64ExtraFieldBytes: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0x00]
        let zip64Field = Entry.ZIP64ExtendedInformation(dataSize: 16,
                                                        uncompressedSize: 10,
                                                        compressedSize: 0,
                                                        relativeOffsetOfLocalHeader: 0,
                                                        diskNumberStart: 0)
        XCTAssertEqual(zip64Field.data, Data(expectedZIP64ExtraFieldBytes))
    }

    func testEntryZIP64FieldIncludingDiskNumberStart() {
        let expectedZIP64ExtraFieldBytes: [UInt8] = [0x01, 0x00, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00]
        let zip64Field = Entry.ZIP64ExtendedInformation(dataSize: 4,
                                                        uncompressedSize: 0,
                                                        compressedSize: 0,
                                                        relativeOffsetOfLocalHeader: 0,
                                                        diskNumberStart: 10)
        XCTAssertEqual(zip64Field.data, Data(expectedZIP64ExtraFieldBytes))
    }

    func testEntryInvalidZIP64ExtraFieldErrorConditions() {
        let emptyExtraField = Entry.ZIP64ExtendedInformation(data: Data(),
                                                             fields: [.compressedSize])
        XCTAssertNil(emptyExtraField)
        let extraFieldBytesIncludingExtraByte: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                          0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                          0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidExtraField1 = Entry.ZIP64ExtendedInformation(data: Data(extraFieldBytesIncludingExtraByte),
                                                                fields: [.compressedSize, .uncompressedSize])
        XCTAssertNil(invalidExtraField1)
        let extraFieldBytesMissingByte: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                   0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                   0x00, 0x00, 0x00]
        let invalidExtraField2 = Entry.ZIP64ExtendedInformation(data: Data(extraFieldBytesMissingByte),
                                                                fields: [.compressedSize, .uncompressedSize])
        XCTAssertNil(invalidExtraField2)
        let extraFieldBytesWithWrongFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00]
        let invalidExtraField3 = Entry.ZIP64ExtendedInformation(data: Data(extraFieldBytesWithWrongFields),
                                                                fields: [.compressedSize])
        XCTAssertNil(invalidExtraField3)
        let extraFieldBytesWithWrongFieldLength: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                            0x00, 0x00, 0x00, 0x00]
        let invalidExtraField4 = Entry.ZIP64ExtendedInformation(data: Data(extraFieldBytesWithWrongFieldLength),
                                                                fields: [.diskNumberStart])
        XCTAssertNil(invalidExtraField4)
    }

    func testEntryScanForZIP64Field() {
        let extraFieldBytesWithZIP64Field: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                      0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                      0x00, 0x00, 0x00, 0x00]
        let zip64Field1 = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: Data(extraFieldBytesWithZIP64Field),
                                                                           fields: [.uncompressedSize, .compressedSize])
        XCTAssertNotNil(zip64Field1)
        let extraFieldBytesWithZIP64Field2: [UInt8] = [0x09, 0x00, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00]
        let zip64Field2 = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: Data(extraFieldBytesWithZIP64Field2),
                                                                           fields: [.uncompressedSize, .compressedSize])
        XCTAssertNotNil(zip64Field2)
    }

    func testEntryScanForZIP64FieldErrorConditions() {
        let emptyExtraField = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: Data(), fields: [])
        XCTAssertNil(emptyExtraField)
        let extraFieldBytesWithoutZIP64Field: [UInt8] = [0x09, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                         0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                         0x00, 0x00, 0x00, 0x00]
        let noZIP64Field = Entry.ZIP64ExtendedInformation.scanForZIP64Field(in: Data(extraFieldBytesWithoutZIP64Field),
                                                                            fields: [])
        XCTAssertNil(noZIP64Field)
    }
}
