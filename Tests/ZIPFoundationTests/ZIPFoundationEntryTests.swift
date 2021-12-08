//
//  ZIPFoundationEntryTests.swift
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
    func testEntryWrongDataLengthErrorConditions() {
        let emptyCDS = Entry.CentralDirectoryStructure(data: Data(),
                                                       additionalDataProvider: {_ -> Data in
                                                        return Data() })
        XCTAssertNil(emptyCDS)
        let emptyLFH = Entry.LocalFileHeader(data: Data(),
                                             additionalDataProvider: {_ -> Data in
                                                return Data() })
        XCTAssertNil(emptyLFH)
        let emptyDD = Entry.DefaultDataDescriptor(data: Data(),
                                                  additionalDataProvider: {_ -> Data in
                                                    return Data() })
        XCTAssertNil(emptyDD)
        let emptyZIP64DD = Entry.ZIP64DataDescriptor(data: Data(),
                                                     additionalDataProvider: {_ -> Data in
                                                        return Data() })
        XCTAssertNil(emptyZIP64DD)
    }

    func testEntryInvalidSignatureErrorConditions() {
        let invalidCDS = Entry.CentralDirectoryStructure(data: Data(count: Entry.CentralDirectoryStructure.size),
                                                         additionalDataProvider: {_ -> Data in
                                                            return Data() })
        XCTAssertNil(invalidCDS)
        let invalidLFH = Entry.LocalFileHeader(data: Data(count: Entry.LocalFileHeader.size),
                                               additionalDataProvider: {_ -> Data in
                                                return Data() })
        XCTAssertNil(invalidLFH)
    }

    func testEntryInvalidAdditionalDataErrorConditions() {
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x03, 0x14, 0x00,
                                 0x08, 0x00, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        let invalidAddtionalDataCDS = Entry.CentralDirectoryStructure(data: Data(cdsBytes)) { _ -> Data in
            return Data()
        }
        XCTAssertNil(invalidAddtionalDataCDS)
        let lfhBytes: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x00,
                                 0x08, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]
        let invalidAddtionalDataLFH = Entry.LocalFileHeader(data: Data(lfhBytes)) { _ -> Data in
            return Data()
        }
        XCTAssertNil(invalidAddtionalDataLFH)
        let cds2Bytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x03, 0x14, 0x00,
                                  0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                  0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                  0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                  0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        let cds2 = Entry.CentralDirectoryStructure(data: Data(cds2Bytes)) { _ -> Data in
            throw AdditionalDataError.encodingError
        }
        XCTAssertNil(cds2)
        let lfhBytes2: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
                                  0x08, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00,
                                  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                  0x00, 0x00, 0x01, 0x00, 0x00, 0x00]
        let lfh2 = Entry.LocalFileHeader(data: Data(lfhBytes2)) { _ -> Data in
            throw AdditionalDataError.encodingError
        }
        XCTAssertNil(lfh2)
    }

    func testEntryInvalidPathEncodingErrorConditions() {
        // Use bytes that are invalid code units in UTF-8 to trigger failed initialization
        // of the path String.
        let invalidPathBytes: [UInt8] = [0xFF]
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x03, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes)) { _ -> Data in
            return Data(invalidPathBytes)
        }
        let lfhBytes: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
                                 0x08, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]
        let lfh = Entry.LocalFileHeader(data: Data(lfhBytes)) { _ -> Data in
            return Data(invalidPathBytes)
        }
        guard let central = cds else {
            XCTFail("Failed to read central directory structure.")
            return
        }
        guard let local = lfh else {
            XCTFail("Failed to read local file header.")
            return
        }
        guard let entry = Entry(centralDirectoryStructure: central, localFileHeader: local) else {
            XCTFail("Failed to read entry.")
            return
        }
        XCTAssertTrue(entry.path == "")
    }

    func testEntryMissingDataDescriptorErrorCondition() {
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x03, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes)) { _ -> Data in
            return Data()
        }
        let lfhBytes: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
                                 0x08, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        let lfh = Entry.LocalFileHeader(data: Data(lfhBytes)) { _ -> Data in
            return Data()
        }
        guard let central = cds else {
            XCTFail("Failed to read central directory structure.")
            return
        }
        guard let local = lfh else {
            XCTFail("Failed to read local file header.")
            return
        }
        guard let entry = Entry(centralDirectoryStructure: central, localFileHeader: local) else {
            XCTFail("Failed to read entry.")
            return
        }
        XCTAssertTrue(entry.checksum == 0)
    }

    func testEntryTypeDetectionHeuristics() {
        // Set the upper byte of .versionMadeBy to 0x15.
        // This exercises the code path that deals with invalid OSTypes.
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x15, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes)) { _ -> Data in
            guard let pathData = "/".data(using: .utf8) else { throw AdditionalDataError.encodingError }
            return pathData
        }
        let lfhBytes: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
                                 0x08, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]
        let lfh = Entry.LocalFileHeader(data: Data(lfhBytes)) { _ -> Data in
            guard let pathData = "/".data(using: .utf8) else { throw AdditionalDataError.encodingError }
            return pathData
        }
        guard let central = cds else {
            XCTFail("Failed to read central directory structure.")
            return
        }
        guard let local = lfh else {
            XCTFail("Failed to read local file header.")
            return
        }
        guard let entry = Entry(centralDirectoryStructure: central, localFileHeader: local) else {
            XCTFail("Failed to read entry.")
            return
        }
        XCTAssertTrue(entry.type == .directory)
    }

    func testEntryValidDataDescriptor() {
        let ddBytes: [UInt8] = [0x50, 0x4b, 0x07, 0x08, 0x00, 0x00, 0x00, 0x00,
                                0x0a, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00]
        let dataDescriptor = Entry.DefaultDataDescriptor(data: Data(ddBytes),
                                                         additionalDataProvider: {_ -> Data in
                                                            return Data() })
        XCTAssertEqual(dataDescriptor?.uncompressedSize, 10)
        XCTAssertEqual(dataDescriptor?.compressedSize, 10)
        // The DataDescriptor signature is not mandatory.
        let ddBytesWithoutSignature: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x00,
                                                0x0a, 0x00, 0x00, 0x00, 0x50, 0x4b, 0x07, 0x08]
        let dataDescriptorWithoutSignature = Entry.DefaultDataDescriptor(data: Data(ddBytesWithoutSignature),
                                                                         additionalDataProvider: {_ -> Data in
                                                                            return Data() })
        XCTAssertEqual(dataDescriptorWithoutSignature?.uncompressedSize, 10)
        XCTAssertEqual(dataDescriptorWithoutSignature?.compressedSize, 10)
    }
}
