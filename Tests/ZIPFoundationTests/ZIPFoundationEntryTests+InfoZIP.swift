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

/// The ISO 8859-1 encoded file name "É¶.txt" and its Unicode Path field as written by Info-ZIP's `zip` 3.0.
private let legacyFileName: [UInt8] = [0xc9, 0xb6, 0x2e, 0x74, 0x78, 0x74]
private let unicodePathField: [UInt8] = [0x75, 0x70, 0x0d, 0x00, 0x01, 0x31, 0x4d, 0x39, 0xbb,
                                         0xc3, 0x89, 0xc2, 0xb6, 0x2e, 0x74, 0x78, 0x74]
private let timestampField: [UInt8] = [0x55, 0x54, 0x05, 0x00, 0x01, 0xc0, 0xc2, 0x19, 0x69]

/// Returns a Unicode Path field that is valid for `legacyFileName`.
private func unicodePathField(name: [UInt8], version: UInt8 = 1) -> [UInt8] {
    return [0x75, 0x70, UInt8(5 + name.count), 0x00, version, 0x31, 0x4d, 0x39, 0xbb] + name
}

private func scan(_ extraField: [UInt8], fileName: [UInt8] = legacyFileName) -> String? {
    return Entry.CentralDirectoryStructure.scanForInfoZIPUnicodePath(in: Data(extraField),
                                                                     fileNameData: Data(fileName))
}

extension ZIPFoundationTests {

    static var infoZIPTests: [(String, (ZIPFoundationTests) -> () throws -> Void)] {
        return [
            ("testInfoZIPUnicodePathScan", testInfoZIPUnicodePathScan),
            ("testInfoZIPUnicodePathScanInvalidFields", testInfoZIPUnicodePathScanInvalidFields),
            ("testInfoZIPUnicodePathScanMultipleFields", testInfoZIPUnicodePathScanMultipleFields),
            ("testInfoZIPUnicodePathScanEmptyName", testInfoZIPUnicodePathScanEmptyName),
            ("testInfoZIPUnicodePath", testInfoZIPUnicodePath),
            ("testInfoZIPUnicodePathWithLegacyEncoding", testInfoZIPUnicodePathWithLegacyEncoding),
            ("testInfoZIPUnicodePathWithInvalidFields", testInfoZIPUnicodePathWithInvalidFields),
            ("testInfoZIPUnicodePathPrecedence", testInfoZIPUnicodePathPrecedence),
            ("testInfoZIPUnicodePathWithPathEncoding", testInfoZIPUnicodePathWithPathEncoding),
            ("testRemoveEntryPreservesInfoZIPUnicodePath", testRemoveEntryPreservesInfoZIPUnicodePath),
            ("testRemoveEntryDropsInfoZIPUnicodePathOfZIP64Entry",
             testRemoveEntryDropsInfoZIPUnicodePathOfZIP64Entry)
        ]
    }

    // MARK: - Parser

    func testInfoZIPUnicodePathScan() {
        XCTAssertEqual(scan(unicodePathField), "É¶.txt")
        XCTAssertEqual(scan(timestampField + unicodePathField), "É¶.txt")
        XCTAssertEqual(scan(unicodePathField + timestampField), "É¶.txt")
        // Trailing garbage that is too short for a header or that claims more data than available.
        XCTAssertEqual(scan(unicodePathField + [0x00, 0x00, 0x00]), "É¶.txt")
        XCTAssertEqual(scan(unicodePathField + [0x99, 0x99, 0xff, 0xff, 0x00]), "É¶.txt")
        XCTAssertNil(scan([]))
        XCTAssertNil(scan(timestampField))
        XCTAssertNil(scan(timestampField + timestampField))
        // The indices of sliced data don't start at zero.
        let extraFieldData = Data([0xff, 0xff] + unicodePathField).dropFirst(2)
        let fileNameData = Data([0xff] + legacyFileName).dropFirst(1)
        let path = Entry.CentralDirectoryStructure.scanForInfoZIPUnicodePath(in: extraFieldData,
                                                                             fileNameData: fileNameData)
        XCTAssertEqual(path, "É¶.txt")
    }

    func testInfoZIPUnicodePathScanInvalidFields() {
        var field = unicodePathField
        // Unknown versions
        field[4] = 2
        XCTAssertNil(scan(field))
        field[4] = 0
        XCTAssertNil(scan(field))
        // The CRC32 doesn't match the file name.
        field = unicodePathField
        field[5] ^= 1
        XCTAssertNil(scan(field))
        XCTAssertNil(scan(unicodePathField, fileName: Array("renamed.txt".utf8)))
        XCTAssertNil(scan(unicodePathField, fileName: []))
        // The name is not valid UTF-8.
        field = unicodePathField
        field[9] = 0xff
        XCTAssertNil(scan(field))
        // Fields that are too short for a version and a CRC32.
        XCTAssertNil(scan([0x75, 0x70, 0x04, 0x00, 0x01, 0x31, 0x4d, 0x39] + timestampField))
        XCTAssertNil(scan([0x75, 0x70, 0x00, 0x00] + timestampField))
        XCTAssertNil(scan([0x75, 0x70, 0x00, 0x00]))
        XCTAssertNil(scan([0x75, 0x70]))
        // Fields that claim more data than available.
        XCTAssertNil(scan(Array(unicodePathField.dropLast())))
        XCTAssertNil(scan(Array(unicodePathField.prefix(9))))
        field = unicodePathField
        field[2] = 0xff
        field[3] = 0xff
        XCTAssertNil(scan(field))
        // Scanning stops at malformed extra fields.
        XCTAssertNil(scan([0x99, 0x99, 0xff, 0xff] + unicodePathField))
    }

    func testInfoZIPUnicodePathScanMultipleFields() {
        let first = unicodePathField(name: Array("first.txt".utf8))
        let last = unicodePathField(name: Array("last.txt".utf8))
        let unknownVersion = unicodePathField(name: Array("unknown.txt".utf8), version: 2)
        // The last valid field is used.
        XCTAssertEqual(scan(first + last), "last.txt")
        XCTAssertEqual(scan(first + timestampField + last), "last.txt")
        // Scanning stops at the first invalid field.
        XCTAssertEqual(scan(first + unknownVersion), "first.txt")
        XCTAssertEqual(scan(first + unknownVersion + last), "first.txt")
        XCTAssertNil(scan(unknownVersion + last))
    }

    func testInfoZIPUnicodePathScanEmptyName() {
        // A field without a name indicates that the file name is UTF-8 encoded.
        let utf8FileName = Array("ä.txt".utf8)
        let utf8Indicator: [UInt8] = [0x75, 0x70, 0x05, 0x00, 0x01, 0xb5, 0xaa, 0x82, 0x00]
        XCTAssertEqual(scan(utf8Indicator, fileName: utf8FileName), "ä.txt")
        XCTAssertEqual(scan(timestampField + utf8Indicator, fileName: utf8FileName), "ä.txt")
        // The file name is not valid UTF-8.
        let invalidFileName: [UInt8] = [0x84, 0x2e, 0x74, 0x78, 0x74]
        XCTAssertNil(scan([0x75, 0x70, 0x05, 0x00, 0x01, 0x15, 0xbf, 0xdf, 0x21], fileName: invalidFileName))
        // The name ends at the first NUL byte.
        XCTAssertEqual(scan(unicodePathField(name: Array("a.txt".utf8) + [0x00])), "a.txt")
        XCTAssertEqual(scan(unicodePathField(name: Array("a.txt".utf8) + [0x00, 0x62, 0xff])), "a.txt")
        // The bytes of `legacyFileName` are also valid UTF-8.
        XCTAssertEqual(scan(unicodePathField(name: [0x00, 0x61])), "\u{0276}.txt")
    }

    // MARK: - Archives

    func testInfoZIPUnicodePath() {
        // Created by Info-ZIP's `zip` 3.0 in an ISO 8859-1 locale. The local and the central directory headers
        // of all entries with non-ASCII names contain ISO 8859-1 file names and Unicode Path fields.
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertEqual(archive.map { $0.path }, ["Ö³Ü¹/", "Ö³Ü¹/Å².txt", "É¶.txt", "ascii.txt"])
        XCTAssertEqual(archive.map { $0.type }, [.directory, .file, .file, .file])
        XCTAssertNil(archive["ascii.txt"]?.centralDirectoryStructure.infoZIPUnicodePath)
        guard let entry = archive["Ö³Ü¹/Å².txt"] else {
            XCTFail("Failed to retrieve entry by its Unicode Path."); return
        }
        XCTAssertFalse(entry.centralDirectoryStructure.usesUTF8PathEncoding)
        XCTAssertEqual(entry.path(using: .isoLatin1), "Ö³Ü¹/Å².txt")
        XCTAssertEqual(entry.path(using: .codepage437), "╓│▄╣/┼▓.txt")
        let destinationURL = self.createDirectory(for: #function)
        XCTAssertNoThrow(try FileManager().unzipItem(at: archive.url, to: destinationURL))
        XCTAssertEqual(try? Data(contentsOf: destinationURL.appendingPathComponent("Ö³Ü¹/Å².txt")),
                       Data("hello\n".utf8))
        XCTAssertEqual(try? Data(contentsOf: destinationURL.appendingPathComponent("É¶.txt")),
                       Data("world\n".utf8))
    }

    func testInfoZIPUnicodePathWithLegacyEncoding() {
        // The headers contain GB 18030 file names and Unicode Path fields.
        let archive = self.archive(for: #function, mode: .read)
        XCTAssertEqual(archive.map { $0.path }, ["目录/图片.txt", "通知.txt"])
        XCTAssertNotNil(archive["目录/图片.txt"])
        let destinationURL = self.createDirectory(for: #function)
        XCTAssertNoThrow(try FileManager().unzipItem(at: archive.url, to: destinationURL))
        XCTAssertEqual(try? Data(contentsOf: destinationURL.appendingPathComponent("目录/图片.txt")),
                       Data("hello\n".utf8))
        XCTAssertEqual(try? Data(contentsOf: destinationURL.appendingPathComponent("通知.txt")),
                       Data("world\n".utf8))
    }

    func testInfoZIPUnicodePathWithInvalidFields() {
        // The Unicode Path fields of all entries are invalid. The CP437 header file names have to be used.
        let archive = self.archive(for: #function, mode: .read)
        let paths = ["unknown-version-ü.txt", "version-zero-ü.txt", "crc-mismatch-ü.txt", "invalid-utf8-ü.txt",
                     "truncated-ü.txt", "no-data-ü.txt", "overrun-ü.txt", "marker-ü.txt"]
        XCTAssertEqual(archive.map { $0.path }, paths)
        XCTAssertEqual(archive.map { $0.path(using: .codepage437) }, paths)
        XCTAssertEqual(archive.compactMap { archive[$0.path]?.path }, paths)
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        XCTAssertNoThrow(try fileManager.unzipItem(at: archive.url, to: destinationURL))
        for path in paths {
            XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent(path)), path)
        }
    }

    func testInfoZIPUnicodePathPrecedence() {
        let archive = self.archive(for: #function, mode: .read)
        let paths = ["bit11-ä.txt",          // UTF-8 flagged file name, valid field
                     "marker-ä.txt",         // UTF-8 file name without flag, field without name
                     "local-only-ä.txt",     // valid field in the local header only
                     "central-only-☃.txt",   // valid field in the central directory header only
                     "central-name-☃.txt",   // different file names and fields in both headers
                     "two-valid-☃.txt",      // two valid fields
                     "valid-invalid-☃.txt",  // valid field followed by an invalid field
                     "invalid-valid-ä.txt",  // invalid field followed by a valid field
                     "nul-☃.txt",            // name with data after a NUL byte
                     "other-fields-☃.txt"]   // valid field between another field and trailing garbage
        XCTAssertEqual(archive.map { $0.path }, paths)
        XCTAssertEqual(archive.compactMap { archive[$0.path]?.path }, paths)
        XCTAssertEqual(archive["bit11-ä.txt"]?.centralDirectoryStructure.usesUTF8PathEncoding, true)
        XCTAssertNil(archive["bit11-ä.txt"]?.centralDirectoryStructure.infoZIPUnicodePath)
        XCTAssertEqual(archive["marker-ä.txt"]?.centralDirectoryStructure.usesUTF8PathEncoding, false)
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        XCTAssertNoThrow(try fileManager.unzipItem(at: archive.url, to: destinationURL))
        for path in paths {
            XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent(path)), path)
        }
    }

    func testInfoZIPUnicodePathWithPathEncoding() {
        // An explicit path encoding always decodes the header file names.
        let fixture = "testInfoZIPUnicodePathWithLegacyEncoding"
        let archive = self.archive(for: fixture, mode: .read, preferredEncoding: .isoLatin1)
        XCTAssertEqual(archive.map { $0.path(using: .isoLatin1) }, ["Ä¿Â¼/Í¼Æ¬.txt", "Í¨Öª.txt"])
        XCTAssertNil(archive["通知.txt"])
        XCTAssertEqual(archive["Í¨Öª.txt"]?.path(using: .isoLatin1), "Í¨Öª.txt")
        XCTAssertEqual(archive["Í¨Öª.txt"]?.path, "通知.txt")
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        XCTAssertNoThrow(try fileManager.unzipItem(at: archive.url, to: destinationURL, pathEncoding: .isoLatin1))
        XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent("Ä¿Â¼/Í¼Æ¬.txt")))
        XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent("Í¨Öª.txt")))
        XCTAssertFalse(fileManager.itemExists(at: destinationURL.appendingPathComponent("通知.txt")))
    }

    // MARK: - Removing Entries

    func testRemoveEntryPreservesInfoZIPUnicodePath() {
        // Extra fields of entries without ZIP64 extended information are copied when rewriting
        // the central directory.
        let archive = self.archive(for: "testInfoZIPUnicodePath", mode: .update)
        guard let entry = archive["Ö³Ü¹/"] else {
            XCTFail("Failed to retrieve entry by its Unicode Path."); return
        }
        let extraFieldData = archive["É¶.txt"]?.centralDirectoryStructure.extraFieldData
        XCTAssertNoThrow(try archive.remove(entry))
        XCTAssertEqual(archive.map { $0.path }, ["Ö³Ü¹/Å².txt", "É¶.txt", "ascii.txt"])
        XCTAssertEqual(archive["É¶.txt"]?.centralDirectoryStructure.extraFieldData, extraFieldData)
        XCTAssert(archive.checkIntegrity())
        let updatedArchive = try? Archive(url: archive.url, accessMode: .read, pathEncoding: nil)
        XCTAssertEqual(updatedArchive?.map { $0.path }, ["Ö³Ü¹/Å².txt", "É¶.txt", "ascii.txt"])
    }

    func testRemoveEntryDropsInfoZIPUnicodePathOfZIP64Entry() {
        // The second entry has ZIP64 extended information and a Unicode Path in both headers.
        let archive = self.archive(for: #function, mode: .update)
        XCTAssertEqual(archive.map { $0.path }, ["remove.txt", "zip64-☃.txt"])
        XCTAssertNotNil(archive["zip64-☃.txt"]?.zip64ExtendedInformation)
        guard let entry = archive["remove.txt"] else {
            XCTFail("Failed to retrieve entry from archive."); return
        }
        XCTAssertNoThrow(try archive.remove(entry))
        // Rewriting the central directory only keeps the ZIP64 extended information of ZIP64 entries.
        // All other extra fields are lost and the CP437 header file name is used. This pins the current behavior.
        XCTAssertEqual(archive.map { $0.path }, ["zip64-ä.txt"])
        XCTAssertEqual(archive["zip64-ä.txt"]?.centralDirectoryStructure.extraFieldData.count, 20)
        XCTAssertNotNil(archive["zip64-ä.txt"]?.zip64ExtendedInformation)
        XCTAssert(archive.checkIntegrity())
    }
}
