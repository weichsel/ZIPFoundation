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
    typealias ZIP64ExtendedInformation = Entry.ZIP64ExtendedInformation

    func testEntryZIP64ExtraField() {
        let extraFieldBytesIncludingSizeFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00]
        let zip64ExtraField1 = ZIP64ExtendedInformation(data: Data(extraFieldBytesIncludingSizeFields),
                                                        fields: [.compressedSize, .uncompressedSize])
        XCTAssertNotNil(zip64ExtraField1)
        let extraFieldBytesIncludingOtherFields: [UInt8] = [0x01, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                            0x00, 0x00, 0x00, 0x0a, 0x0, 0x00, 0x00, 0x0a]
        let zip64ExtraField2 = ZIP64ExtendedInformation(data: Data(extraFieldBytesIncludingOtherFields),
                                                        fields: [.relativeOffsetOfLocalHeader, .diskNumberStart])
        XCTAssertNotNil(zip64ExtraField2)

        let updatedZIP64ExtraField1 = ZIP64ExtendedInformation(zip64ExtendedInformation: zip64ExtraField1, offset: 10)
        XCTAssertEqual(updatedZIP64ExtraField1?.relativeOffsetOfLocalHeader,
                       zip64ExtraField1?.relativeOffsetOfLocalHeader)
        XCTAssertEqual(updatedZIP64ExtraField1?.dataSize, zip64ExtraField1?.dataSize)
        let updatedZIP64ExtraField2 = ZIP64ExtendedInformation(zip64ExtendedInformation: zip64ExtraField2,
                                                               offset: Int64(UInt32.max) + 1)
        XCTAssertEqual(updatedZIP64ExtraField2?.relativeOffsetOfLocalHeader, Int64(UInt32.max) + 1)
        XCTAssertEqual(updatedZIP64ExtraField2?.dataSize, zip64ExtraField2?.dataSize)
    }

    func testEntryZIP64FieldOnlyHasUncompressedSize() {
        // Including both original and compressed file size fields. (at least in the Local header)
        let expectedZIP64ExtraFieldBytes: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                                     0x00, 0x00, 0x00, 0x00]
        let zip64Field = ZIP64ExtendedInformation(dataSize: 16,
                                                  uncompressedSize: 10,
                                                  compressedSize: 0,
                                                  relativeOffsetOfLocalHeader: 0,
                                                  diskNumberStart: 0)
        XCTAssertEqual(zip64Field.data, Data(expectedZIP64ExtraFieldBytes))
    }

    func testEntryZIP64FieldIncludingDiskNumberStart() {
        let expectedZIP64ExtraFieldBytes: [UInt8] = [0x01, 0x00, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00]
        let zip64Field = ZIP64ExtendedInformation(dataSize: 4,
                                                  uncompressedSize: 0,
                                                  compressedSize: 0,
                                                  relativeOffsetOfLocalHeader: 0,
                                                  diskNumberStart: 10)
        XCTAssertEqual(zip64Field.data, Data(expectedZIP64ExtraFieldBytes))
    }

    func testEntryValidZIP64DataDescriptor() {
        let zip64DDBytes: [UInt8] = [0x50, 0x4b, 0x07, 0x08, 0x00, 0x00, 0x00, 0x00,
                                     0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                     0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let zip64DataDescriptor = Entry.ZIP64DataDescriptor(data: Data(zip64DDBytes),
                                                            additionalDataProvider: {_ -> Data in
                                                                return Data() })
        XCTAssertEqual(zip64DataDescriptor?.uncompressedSize, 10)
        XCTAssertEqual(zip64DataDescriptor?.compressedSize, 10)
    }

    func testEntryWithZIP64ExtraField() {
        // Central Directory
        let extraFieldBytesIncludingSizeFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                           0x00, 0x00, 0x00, 0x00]
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x15, 0x2d, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0xff, 0xff,
                                 0xff, 0xff, 0xff, 0xff, 0x01, 0x00, 0x14, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        guard let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes),
                                                        additionalDataProvider: { count -> Data in
                                                            guard let name = "/".data(using: .utf8) else {
                                                                throw AdditionalDataError.encodingError
                                                            }
                                                            let extra = name + Data(extraFieldBytesIncludingSizeFields)
                                                            XCTAssert(count == extra.count)
                                                            return extra
                                                        }) else {
            XCTFail("Failed to read central directory structure."); return
        }
        XCTAssertNotNil(cds.extraFields)
        XCTAssertEqual(cds.exactCompressedSize, 10)
        XCTAssertEqual(cds.exactUncompressedSize, 10)
        // Entry
        let lfhBytes: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
                                 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x0a, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        guard let lfh = Entry.LocalFileHeader(data: Data(lfhBytes),
                                              additionalDataProvider: { _ -> Data in
                                                return Data()
                                              }) else {
            XCTFail("Failed to read local file header."); return
        }
        guard let entry = Entry(centralDirectoryStructure: cds, localFileHeader: lfh) else {
            XCTFail("Failed to create test entry."); return
        }
        XCTAssertNotNil(entry.zip64ExtendedInformation)
        XCTAssertEqual(entry.compressedSize, 10)
        XCTAssertEqual(entry.uncompressedSize, 10)
    }

    func testEntryInvalidZIP64ExtraFieldErrorConditions() {
        let emptyExtraField = ZIP64ExtendedInformation(data: Data(),
                                                       fields: [.compressedSize])
        XCTAssertNil(emptyExtraField)
        let extraFieldBytesIncludingExtraByte: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                          0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                          0x00, 0x00, 0x00, 0x00, 0x00]
        let invalidExtraField1 = ZIP64ExtendedInformation(data: Data(extraFieldBytesIncludingExtraByte),
                                                          fields: [.compressedSize, .uncompressedSize])
        XCTAssertNil(invalidExtraField1)
        let extraFieldBytesMissingByte: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                   0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                   0x00, 0x00, 0x00]
        let invalidExtraField2 = ZIP64ExtendedInformation(data: Data(extraFieldBytesMissingByte),
                                                          fields: [.compressedSize, .uncompressedSize])
        XCTAssertNil(invalidExtraField2)
        let extraFieldBytesWithWrongFields: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00]
        let invalidExtraField3 = ZIP64ExtendedInformation(data: Data(extraFieldBytesWithWrongFields),
                                                          fields: [.compressedSize])
        XCTAssertNil(invalidExtraField3)
        let extraFieldBytesWithWrongFieldLength: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                            0x00, 0x00, 0x00, 0x00]
        let invalidExtraField4 = ZIP64ExtendedInformation(data: Data(extraFieldBytesWithWrongFieldLength),
                                                          fields: [.diskNumberStart])
        XCTAssertNil(invalidExtraField4)
    }

    func testEntryScanForZIP64Field() {
        let extraFieldBytesWithZIP64Field: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                      0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                      0x00, 0x00, 0x00, 0x00]
        let zip64Field1 = ZIP64ExtendedInformation.scanForZIP64Field(in: Data(extraFieldBytesWithZIP64Field),
                                                                     fields: [.uncompressedSize, .compressedSize])
        XCTAssertNotNil(zip64Field1)
        let extraFieldBytesWithZIP64Field2: [UInt8] = [0x09, 0x00, 0x04, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                       0x00, 0x00, 0x00, 0x00]
        let zip64Field2 = ZIP64ExtendedInformation.scanForZIP64Field(in: Data(extraFieldBytesWithZIP64Field2),
                                                                     fields: [.uncompressedSize, .compressedSize])
        XCTAssertNotNil(zip64Field2)
    }

    func testEntryScanForZIP64FieldErrorConditions() {
        let emptyExtraField = ZIP64ExtendedInformation.scanForZIP64Field(in: Data(), fields: [])
        XCTAssertNil(emptyExtraField)
        let extraFieldBytesWithoutZIP64Field: [UInt8] = [0x09, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                         0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                         0x00, 0x00, 0x00, 0x00]
        let noZIP64Field = ZIP64ExtendedInformation.scanForZIP64Field(in: Data(extraFieldBytesWithoutZIP64Field),
                                                                      fields: [])
        XCTAssertNil(noZIP64Field)
    }
}
