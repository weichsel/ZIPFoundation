//
//  ZIPFoundationEntryTests+Zip64.swift
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
    func testEntryZip64ExtraField() {
        let extraFieldBytesIncludingSizeFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00]
        let zip64ExtraField1 = Entry.Zip64ExtendedInformation(data: Data(extraFieldBytesIncludingSizeFields),
                                                             fields: [.compressedSize, .uncompressedSize])
        XCTAssertNotNil(zip64ExtraField1)
        let extraFieldBytesIncludingOtherFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                            0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00]
        let zip64ExtraField2 = Entry.Zip64ExtendedInformation(data: Data(extraFieldBytesIncludingOtherFields),
                                                              fields: [.relativeOffsetOfLocalHeader, .diskNumberStart])
        XCTAssertNotNil(zip64ExtraField2)
    }

    func testEntryZip64FieldOnlyHasUncompressedSize() {
        // Including both original and compressed file size fields. (at least in the Local header)
        let expectedZip64ExtraFieldBytes: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0x00]
        let zip64Field = Entry.Zip64ExtendedInformation(dataSize: 16,
                                                        uncompressedSize: 10,
                                                        compressedSize: 0,
                                                        relativeOffsetOfLocalHeader: 0,
                                                        diskNumberStart: 0)
        XCTAssertEqual(zip64Field.data, Data(expectedZip64ExtraFieldBytes))
    }

    func testEntryZip64FieldIncludingDiskNumberStart() {
        let expectedZip64ExtraFieldBytes: [UInt8] = [0x01, 0x00, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00]
        let zip64Field = Entry.Zip64ExtendedInformation(dataSize: 4,
                                                        uncompressedSize: 0,
                                                        compressedSize: 0,
                                                        relativeOffsetOfLocalHeader: 0,
                                                        diskNumberStart: 10)
        XCTAssertEqual(zip64Field.data, Data(expectedZip64ExtraFieldBytes))
    }

    func testEntryInvalidZip64ExtraFieldErrorConditions() {
        let emptyExtraField = Entry.Zip64ExtendedInformation(data: Data(),
                                                             fields: [.compressedSize])
        XCTAssertNil(emptyExtraField)
        let extraFieldBytesIncludingExtraByte: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                          0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                          0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidExtraField1 = Entry.Zip64ExtendedInformation(data: Data(extraFieldBytesIncludingExtraByte),
                                                                fields: [.compressedSize, .uncompressedSize])
        XCTAssertNil(invalidExtraField1)
        let extraFieldBytesMissingByte: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                   0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                   0x00, 0x00, 0x00]
        let invalidExtraField2 = Entry.Zip64ExtendedInformation(data: Data(extraFieldBytesMissingByte),
                                                                fields: [.compressedSize, .uncompressedSize])
        XCTAssertNil(invalidExtraField2)
        let extraFieldBytesWithWrongFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00]
        let invalidExtraField3 = Entry.Zip64ExtendedInformation(data: Data(extraFieldBytesWithWrongFields),
                                                                fields: [.compressedSize])
        XCTAssertNil(invalidExtraField3)
        let extraFieldBytesWithWrongFieldLength: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                            0x00, 0x00, 0x00, 0x00]
        let invalidExtraField4 = Entry.Zip64ExtendedInformation(data: Data(extraFieldBytesWithWrongFieldLength),
                                                                fields: [.diskNumberStart])
        XCTAssertNil(invalidExtraField4)
    }

    func testEntryScanForZip64Field() {
        let extraFieldBytesWithZip64Field: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                      0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                      0x00, 0x00, 0x00, 0x00]
        let zip64Field1 = Entry.Zip64ExtendedInformation.scanForZip64Field(in: Data(extraFieldBytesWithZip64Field),
                                                                           fields: [.uncompressedSize, .compressedSize])
        XCTAssertNotNil(zip64Field1)
        let extraFieldBytesWithZip64Field2: [UInt8] = [0x09, 0x00, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00]
        let zip64Field2 = Entry.Zip64ExtendedInformation.scanForZip64Field(in: Data(extraFieldBytesWithZip64Field2),
                                                                           fields: [.uncompressedSize, .compressedSize])
        XCTAssertNotNil(zip64Field2)
    }

    func testEntryScanForZip64FieldErrorConditions() {
        let emptyExtraField = Entry.Zip64ExtendedInformation.scanForZip64Field(in: Data(), fields: [])
        XCTAssertNil(emptyExtraField)
        let extraFieldBytesWithoutZip64Field: [UInt8] = [0x09, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                         0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                         0x00, 0x00, 0x00, 0x00]
        let noZip64Field = Entry.Zip64ExtendedInformation.scanForZip64Field(in: Data(extraFieldBytesWithoutZip64Field),
                                                                            fields: [])
        XCTAssertNil(noZip64Field)
    }
}
