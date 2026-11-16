//
//  ZIPFoundationEntryTests+ZIP64.swift
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
            let name = Data("/".utf8)
            let extra = name + Data(extraFieldBytesIncludingSizeFields)
            XCTAssert(count == extra.count)
            return extra
        }) else {
            XCTFail("Failed to read central directory structure."); return
        }
        XCTAssertNotNil(cds.extraFields)
        XCTAssertEqual(cds.effectiveCompressedSize, 10)
        XCTAssertEqual(cds.effectiveUncompressedSize, 10)
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
        // A field without values is well-formed, also at the end of the extra field data.
        let emptyZIP64Field: [UInt8] = [0x01, 0x00, 0x00, 0x00]
        XCTAssertNotNil(ZIP64ExtendedInformation.scanForZIP64Field(in: Data(emptyZIP64Field + timestampField),
                                                                   fields: []))
        XCTAssertNotNil(ZIP64ExtendedInformation.scanForZIP64Field(in: Data(timestampField + emptyZIP64Field),
                                                                   fields: []))
        // The indices of sliced data don't start at zero.
        let slice = Data([0xff, 0xff] + timestampField + extraFieldBytesWithZIP64Field).dropFirst(2)
        let zip64Field3 = ZIP64ExtendedInformation.scanForZIP64Field(in: slice,
                                                                     fields: [.uncompressedSize, .compressedSize])
        XCTAssertEqual(zip64Field3?.uncompressedSize, 10)
        XCTAssertEqual(zip64Field3?.compressedSize, 10)
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
        // A field that claims more data than is available ends the scan.
        let truncatedField: [UInt8] = [0x98, 0x98, 0x08, 0x00, 0xcc]
        let zip64Field: [UInt8] = [0x01, 0x00, 0x08, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssertNil(ZIP64ExtendedInformation.scanForZIP64Field(in: Data(truncatedField + zip64Field),
                                                                fields: [.relativeOffsetOfLocalHeader]))
        // Only the first ZIP64 field is taken into account.
        XCTAssertNil(ZIP64ExtendedInformation.scanForZIP64Field(in: Data(zip64SizeField + zip64Field),
                                                                fields: [.relativeOffsetOfLocalHeader]))
    }

    // MARK: - Updating Central Directory Structures

    func testUpdatedCentralDirectoryStructureKeepsOtherExtraFields() throws {
        // The entry needs ZIP64 extended information for its sizes. It also has a timestamp field.
        let structure = try self.makeCentralDirectoryStructure(sizes: .max, relativeOffset: 200,
                                                               extraField: timestampField + zip64SizeField
                                                               + [0x00, 0x00])
        let updatedStructure = try self.updatedCentralDirectoryStructure(structure, offset: 100)
        // The extra fields keep their order. Trailing data that is not a well-formed extra field is preserved.
        XCTAssertEqual(updatedStructure.extraFieldData, structure.extraFieldData)
        XCTAssertEqual(updatedStructure.extraFieldLength, UInt16(updatedStructure.extraFieldData.count))
        XCTAssertEqual(updatedStructure.effectiveUncompressedSize, 10)
        XCTAssertEqual(updatedStructure.relativeOffsetOfLocalHeader, 100)
        let reparsedStructure = try self.parseCentralDirectoryStructure(from: updatedStructure.data)
        XCTAssertEqual(reparsedStructure.effectiveCompressedSize, 10)
    }

    func testUpdatedCentralDirectoryStructureKeepsVersionNeededToExtract() throws {
        // Versions can also be required by other features than ZIP64, like the compression method.
        for version: UInt16 in [20, 45, 63] {
            let structure = try self.makeCentralDirectoryStructure(version: version, relativeOffset: 200,
                                                                   extraField: timestampField)
            let updatedStructure = try self.updatedCentralDirectoryStructure(structure, offset: 100)
            XCTAssertEqual(updatedStructure.versionNeededToExtract, version)
            XCTAssertEqual(updatedStructure.extraFieldData, Data(timestampField))
        }
        // ZIP64 extended information requires at least version 4.5.
        var structure = try self.makeCentralDirectoryStructure(version: 20, sizes: .max, extraField: zip64SizeField)
        XCTAssertEqual(try self.updatedCentralDirectoryStructure(structure, offset: 100).versionNeededToExtract, 45)
        structure = try self.makeCentralDirectoryStructure(version: 63, sizes: .max, extraField: zip64SizeField)
        XCTAssertEqual(try self.updatedCentralDirectoryStructure(structure, offset: 100).versionNeededToExtract, 63)
        // Only the lower byte holds the version. The upper byte is preserved.
        structure = try self.makeCentralDirectoryStructure(version: 0x0314, sizes: .max, extraField: zip64SizeField)
        XCTAssertEqual(try self.updatedCentralDirectoryStructure(structure, offset: 100).versionNeededToExtract,
                       0x032d)
    }

    func testUpdatedCentralDirectoryStructureRemovesUnneededZIP64Field() throws {
        // The entry only needs ZIP64 extended information for its offset.
        let zip64OffsetField: [UInt8] = [0x01, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]
        let structure = try self.makeCentralDirectoryStructure(relativeOffset: .max,
                                                               extraField: zip64OffsetField + timestampField)
        XCTAssertEqual(structure.effectiveRelativeOffsetOfLocalHeader, UInt64(UInt32.max) + 1)
        // The updated offset fits into the central directory structure.
        let updatedStructure = try self.updatedCentralDirectoryStructure(structure, offset: 100)
        XCTAssertEqual(updatedStructure.extraFieldData, Data(timestampField))
        XCTAssertNil(updatedStructure.zip64ExtendedInformation)
        XCTAssertEqual(updatedStructure.effectiveRelativeOffsetOfLocalHeader, 100)
        XCTAssertEqual(updatedStructure.versionNeededToExtract, 45)
        // The lower version of an entry without a data descriptor is unchanged.
        var lowVersionStructure = try self.makeCentralDirectoryStructure(version: 20, relativeOffset: .max,
                                                                         extraField: zip64OffsetField)
        var updatedLowVersionStructure = try self.updatedCentralDirectoryStructure(lowVersionStructure, offset: 100)
        XCTAssertEqual(updatedLowVersionStructure.extraFieldData, Data())
        XCTAssertEqual(updatedLowVersionStructure.versionNeededToExtract, 20)
        // An entry with a data descriptor stays marked as ZIP64, so that its data descriptor is read as before.
        lowVersionStructure = try self.makeCentralDirectoryStructure(version: 20, flags: 0x0808, relativeOffset: .max,
                                                                     extraField: zip64OffsetField)
        XCTAssertTrue(lowVersionStructure.usesDataDescriptor)
        XCTAssertTrue(lowVersionStructure.isZIP64)
        updatedLowVersionStructure = try self.updatedCentralDirectoryStructure(lowVersionStructure, offset: 100)
        XCTAssertEqual(updatedLowVersionStructure.extraFieldData, Data())
        XCTAssertEqual(updatedLowVersionStructure.versionNeededToExtract, 45)
        XCTAssertTrue(updatedLowVersionStructure.isZIP64)
    }

    func testUpdatedCentralDirectoryStructureWithZeroZIP64Values() throws {
        let zip64Offset: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00]
        let updatedOffset = UInt64(UInt32.max) + 1
        let updatedZIP64Offset: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]
        // The sizes of the entry are stored in the ZIP64 extended information, but one or both are zero.
        let zeroSize = [UInt8](repeating: 0, count: 8)
        let nonZeroSize: [UInt8] = [0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        for zip64Sizes in [zeroSize + zeroSize, zeroSize + nonZeroSize, nonZeroSize + zeroSize] {
            let extraField = [0x01, 0x00, 0x18, 0x00] + zip64Sizes + zip64Offset
            let structure = try self.makeCentralDirectoryStructure(sizes: .max, relativeOffset: .max,
                                                                   extraField: extraField)
            // The updated offset still needs ZIP64 extended information.
            var updatedStructure = try self.updatedCentralDirectoryStructure(structure, offset: updatedOffset)
            XCTAssertEqual(updatedStructure.extraFieldData,
                           Data([0x01, 0x00, 0x18, 0x00] + zip64Sizes + updatedZIP64Offset))
            var reparsedStructure = try self.parseCentralDirectoryStructure(from: updatedStructure.data)
            XCTAssertEqual(reparsedStructure.effectiveRelativeOffsetOfLocalHeader, updatedOffset)
            XCTAssertEqual(reparsedStructure.effectiveUncompressedSize, structure.effectiveUncompressedSize)
            // The updated offset fits into the central directory structure. The sizes still need a ZIP64 field.
            updatedStructure = try self.updatedCentralDirectoryStructure(structure, offset: 100)
            XCTAssertEqual(updatedStructure.extraFieldData, Data([0x01, 0x00, 0x10, 0x00] + zip64Sizes))
            reparsedStructure = try self.parseCentralDirectoryStructure(from: updatedStructure.data)
            XCTAssertNotNil(reparsedStructure.zip64ExtendedInformation)
            XCTAssertEqual(reparsedStructure.effectiveCompressedSize, structure.effectiveCompressedSize)
            XCTAssertEqual(reparsedStructure.effectiveRelativeOffsetOfLocalHeader, 100)
        }
    }

    func testUpdatedCentralDirectoryStructureWithExceedingExtraFieldLength() throws {
        // The extra fields don't leave enough room for an additional offset in the ZIP64 extended information.
        let otherField: [UInt8] = [0x99, 0x99, 0xe7, 0xff] + [UInt8](repeating: 0, count: 0xffe7)
        let structure = try self.makeCentralDirectoryStructure(sizes: .max, relativeOffset: 200,
                                                               extraField: zip64SizeField + otherField)
        XCTAssertEqual(structure.extraFieldLength, .max)
        XCTAssertNotNil(Entry.CentralDirectoryStructure(centralDirectoryStructure: structure, updatedOffset: 100))
        self.mockIntMaxValues()
        defer { self.resetIntMaxValues() }
        XCTAssertNil(Entry.CentralDirectoryStructure(centralDirectoryStructure: structure, updatedOffset: 5000))
    }

    func testExtraFieldDataReplacingZIP64Field() {
        let zip64Field: [UInt8] = [0x01, 0x00, 0x08, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let replacement = Data(zip64SizeField)
        // A field that claims more data than is available. It is preserved like padding bytes.
        let truncatedField: [UInt8] = [0x98, 0x98, 0x08, 0x00, 0xcc]
        let data = Data(timestampField + zip64Field + timestampField + zip64Field + truncatedField)
        // The first ZIP64 field is replaced in place. Additional ZIP64 fields are removed.
        XCTAssertEqual(ZIP64ExtendedInformation.extraFieldData(replacingZIP64FieldIn: data, with: replacement),
                       Data(timestampField + zip64SizeField + timestampField + truncatedField))
        XCTAssertEqual(ZIP64ExtendedInformation.extraFieldData(replacingZIP64FieldIn: data, with: nil),
                       Data(timestampField + timestampField + truncatedField))
        XCTAssertEqual(ZIP64ExtendedInformation.extraFieldData(replacingZIP64FieldIn: Data(), with: nil), Data())
        // The indices of sliced data don't start at zero.
        let slice = Data([0xff, 0xff] + zip64Field + timestampField).dropFirst(2)
        XCTAssertEqual(ZIP64ExtendedInformation.extraFieldData(replacingZIP64FieldIn: slice, with: nil),
                       Data(timestampField))
    }

    func testEntryZIP64FieldContainingFields() {
        let zip64Field = ZIP64ExtendedInformation(dataSize: 0, uncompressedSize: 10, compressedSize: 0,
                                                  relativeOffsetOfLocalHeader: 11, diskNumberStart: 12)
        // Values that are zero have to be included if their field is requested.
        let sizeFieldBytes: [UInt8] = [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                       0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssertEqual(zip64Field.data(containing: [.uncompressedSize, .compressedSize]), Data(sizeFieldBytes))
        let otherFieldBytes: [UInt8] = [0x01, 0x00, 0x0c, 0x00, 0x0b, 0x00, 0x00, 0x00,
                                        0x00, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00]
        XCTAssertEqual(zip64Field.data(containing: [.diskNumberStart, .relativeOffsetOfLocalHeader]),
                       Data(otherFieldBytes))
        // An updated offset is stored instead of the offset of the field.
        let updatedOffsetFieldBytes: [UInt8] = [0x01, 0x00, 0x08, 0x00, 0x0d, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssertEqual(zip64Field.data(containing: [.relativeOffsetOfLocalHeader], relativeOffsetOfLocalHeader: 13),
                       Data(updatedOffsetFieldBytes))
    }

    // MARK: - Helper

    private var timestampField: [UInt8] { [0x55, 0x54, 0x05, 0x00, 0x01, 0xc0, 0xc2, 0x19, 0x69] }
    private var zip64SizeField: [UInt8] {
        [0x01, 0x00, 0x10, 0x00, 0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
         0x0a, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    }

    private func updatedCentralDirectoryStructure(_ structure: Entry.CentralDirectoryStructure,
                                                  offset: UInt64) throws -> Entry.CentralDirectoryStructure {
        return try XCTUnwrap(Entry.CentralDirectoryStructure(centralDirectoryStructure: structure,
                                                             updatedOffset: offset))
    }

    private func makeCentralDirectoryStructure(version: UInt16 = 45, flags: UInt16 = 0x0800, sizes: UInt32 = 10,
                                               relativeOffset: UInt32 = 0,
                                               extraField: [UInt8]) throws -> Entry.CentralDirectoryStructure {
        func bytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
            return (0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
        }
        let fileName = Data("a".utf8)
        var data: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x03] + bytes(version) + bytes(flags)
        data += [0x00, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00, 0x00, 0x00]
        data += bytes(sizes) + bytes(sizes)
        data += bytes(UInt16(fileName.count)) + bytes(UInt16(extraField.count))
        data += [UInt8](repeating: 0, count: 10)
        data += bytes(relativeOffset)
        return try self.parseCentralDirectoryStructure(from: Data(data) + fileName + Data(extraField))
    }

    private func parseCentralDirectoryStructure(from data: Data) throws -> Entry.CentralDirectoryStructure {
        let fixedSize = Entry.CentralDirectoryStructure.size
        let additionalData = data.subdata(in: fixedSize..<data.count)
        return try XCTUnwrap(Entry.CentralDirectoryStructure(data: data.subdata(in: 0..<fixedSize),
                                                             additionalDataProvider: { _ in additionalData }))
    }
}
