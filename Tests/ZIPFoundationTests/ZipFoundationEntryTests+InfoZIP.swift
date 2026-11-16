//
//  ZIPFoundationEntryTests+InfoZIP.swift
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

    func testEntryScanForInfoZIP() {
        let extraFieldBytesWithInfoZIP: [UInt8] = [0x75, 0x70, 0x37, 0x00, 0x01, 0xa3, 0xdb, 0xf3, 0x25,
                                                   0xe4, 0xbf, 0xa1, 0xe9, 0x93, 0xb6, 0xe8, 0xa7, 0x84,
                                                   0xe7, 0xab, 0xa0, 0xe3, 0x80, 0x94, 0x32, 0x30, 0x32,
                                                   0x35, 0xe3, 0x80, 0x95, 0x32, 0x37, 0x34, 0xe5, 0x8f,
                                                   0xb7, 0xef, 0xbc, 0x88, 0xe9, 0x99, 0x84, 0xe4, 0xbb,
                                                   0xb6, 0xef, 0xbc, 0x89, 0x5f, 0x54, 0x65, 0x73, 0x74,
                                                   0x2e, 0x64, 0x6f, 0x63, 0x78]
        let infoZIP = Entry.InfoZIPUnicodePath.scanForUnicodePath(in: Data(extraFieldBytesWithInfoZIP))
        XCTAssertEqual(infoZIP?.headerID, Archive.ExtraFieldHeaderID.infoZIPUnicodePath.rawValue)
        XCTAssertNotNil(infoZIP)
    }

    func testEntryScanForTruncatedInfoZIP() {
        // A Unicode Path field without a payload, followed by another field.
        let emptyField: [UInt8] = [0x75, 0x70, 0x00, 0x00, 0x99, 0x99, 0x00, 0x00]
        XCTAssertNil(Entry.InfoZIPUnicodePath.scanForUnicodePath(in: Data(emptyField)))
        // A Unicode Path field that is too short to contain a version and a CRC32.
        let shortField: [UInt8] = [0x75, 0x70, 0x04, 0x00, 0x01, 0x00, 0x00, 0x00]
        XCTAssertNil(Entry.InfoZIPUnicodePath.scanForUnicodePath(in: Data(shortField)))
    }

    func testInfoZIPUnicodePathWithTruncatedField() {
        // The Unicode Path fields of both entries are too short. The header file names have to be used.
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertEqual(archive.map { $0.path }, ["a", "b"])
    }

    func testInfoZIPUnicodePath() {
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        XCTAssertNoThrow(try fileManager.unzipItem(at: archive.url, to: destinationURL))
    }
}
