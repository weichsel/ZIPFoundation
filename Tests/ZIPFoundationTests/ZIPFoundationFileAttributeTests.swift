//
//  ZIPFoundationFileAttributeTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import XCTest
#if canImport(Android)
import Android
#endif
@testable import ZIPFoundation

extension ZIPFoundationTests {

    func testFileAttributeHelperMethods() {
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x15, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        guard let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes),
                                                        additionalDataProvider: { count -> Data in
            let pathData = Data("/".utf8)
            XCTAssert(count == pathData.count)
            return pathData
        }) else {
            XCTFail("Failed to read central directory structure."); return
        }
        let lfhBytes: [UInt8] = [0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x08, 0x08,
                                 0x08, 0x00, 0xab, 0x85, 0x77, 0x47, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        guard let lfh = Entry.LocalFileHeader(data: Data(lfhBytes),
                                              additionalDataProvider: { _ -> Data in return Data() })
        else {
            XCTFail("Failed to read local file header."); return
        }
        guard let entry = Entry(centralDirectoryStructure: cds, localFileHeader: lfh) else {
            XCTFail("Failed to create test entry."); return
        }
        let attributes = FileManager.attributes(from: entry)
        guard let permissions = attributes[.posixPermissions] as? UInt16 else {
            XCTFail("Failed to read file attributes."); return
        }
        XCTAssert(permissions == defaultDirectoryPermissions)
    }

    func testSymlinkPermissionsTransferErrorConditions() {
        // Applying permissions on symlinks is only relevant on Darwin platforms.
#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        let fileManager = FileManager()
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        XCTAssertSwiftError(try fileManager.setAttributes([:], ofItemAtURL: assetURL, traverseLink: false),
                            throws: Entry.EntryError.missingPermissionsAttributeError)
        let permissions = NSNumber(value: Int16(0o753))
        let tempPath = NSTemporaryDirectory()
        var nonExistentURL = URL(fileURLWithPath: tempPath)
        nonExistentURL.appendPathComponent("invalid.path")
        XCTAssertPOSIXError(try fileManager.setAttributes([.posixPermissions: permissions],
                                                          ofItemAtURL: nonExistentURL, traverseLink: false),
                            throwsErrorWithCode: .ENOENT)
#endif
    }

    func testSymlinkModificationDateTransferErrorConditions() {
#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || os(Linux)
        let fileManager = FileManager()
        var assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let tempPath = NSTemporaryDirectory()
        var nonExistentURL = URL(fileURLWithPath: tempPath)
        nonExistentURL.appendPathComponent("invalid.path")
        let providedPermissions = NSNumber(value: Int16(0o753))
        XCTAssertSwiftError(try fileManager.setAttributes([.posixPermissions: providedPermissions],
                                                          ofItemAtURL: assetURL, traverseLink: false),
                            throws: Entry.EntryError.missingModificationDateAttributeError)
        XCTAssertPOSIXError(try fileManager.setSymlinkModificationDate(Date(), ofItemAtURL: nonExistentURL),
                            throwsErrorWithCode: .ENOENT)
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: providedPermissions, .modificationDate: Date()]
#if os(Linux)
        // Setting the modification date of a symlink is best effort on Linux.
        XCTAssertNoThrow(try fileManager.setAttributes(attributes, ofItemAtURL: nonExistentURL, traverseLink: false))
#else
        XCTAssertPOSIXError(try fileManager.setAttributes(attributes, ofItemAtURL: nonExistentURL,
                                                          traverseLink: false),
                            throwsErrorWithCode: .ENOENT)
#endif
#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        var resourceValues = URLResourceValues()
        resourceValues.isUserImmutable = true
        try? assetURL.setResourceValues(resourceValues)
        defer {
            resourceValues.isUserImmutable = false
            try? assetURL.setResourceValues(resourceValues)
        }
        XCTAssertPOSIXError(try fileManager.setSymlinkModificationDate(Date(), ofItemAtURL: assetURL),
                            throwsErrorWithCode: .EPERM)
#endif
#endif
    }

    func testFilePermissionHelperMethods() {
        var permissions = FileManager.permissions(for: UInt32(777), osType: .unix, entryType: .file)
        XCTAssert(permissions == defaultFilePermissions)
        permissions = FileManager.permissions(for: UInt32(0), osType: .msdos, entryType: .file)
        XCTAssert(permissions == defaultFilePermissions)
        permissions = FileManager.permissions(for: UInt32(0), osType: .msdos, entryType: .directory)
        XCTAssert(permissions == defaultDirectoryPermissions)
        // Directories that are marked as regular files get the execute permission wherever reading is permitted.
        let regularFileType = UInt32(S_IFREG) << 16
        permissions = FileManager.permissions(for: regularFileType | 0o644 << 16, osType: .unix, entryType: .directory)
        XCTAssertEqual(permissions, 0o755)
        permissions = FileManager.permissions(for: regularFileType | 0o600 << 16, osType: .unix, entryType: .directory)
        XCTAssertEqual(permissions, 0o700)
        permissions = FileManager.permissions(for: regularFileType | 0o644 << 16, osType: .unix, entryType: .file)
        XCTAssertEqual(permissions, 0o644)
        let directoryType = UInt32(S_IFDIR) << 16
        permissions = FileManager.permissions(for: directoryType | 0o644 << 16, osType: .unix, entryType: .directory)
        XCTAssertEqual(permissions, 0o644)
        // Without file type bits, the stored permissions are the ones that were intended for the directory.
        permissions = FileManager.permissions(for: 0o744 << 16, osType: .unix, entryType: .directory)
        XCTAssertEqual(permissions, 0o744)
    }

    func testUnzipDirectoryEntryMarkedAsFile() throws {
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        try fileManager.unzipItem(at: archive.url, to: destinationURL)
        for (directory, expectedPermissions) in [("directory", 0o755), ("private", 0o700)] {
            let directoryURL = destinationURL.appendingPathComponent(directory)
            let attributes = try fileManager.attributesOfItem(atPath: directoryURL.path)
            XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeDirectory)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, expectedPermissions)
            XCTAssert(fileManager.itemExists(at: directoryURL.appendingPathComponent("file.txt")))
        }
    }

    func testFileModificationDateHelperMethods() {
        guard let nonFileURL = URL(string: "https://www.peakstep.com/") else {
            XCTFail("Failed to create file URL."); return
        }

        XCTAssertCocoaError(try FileManager.fileModificationDateTimeForItem(at: nonFileURL),
                            throwsErrorWithCode: CocoaError.fileReadNoSuchFile)
        let nonExistentURL = URL(fileURLWithPath: "/nonexistant")
        XCTAssertCocoaError(try FileManager.fileModificationDateTimeForItem(at: nonExistentURL),
                            throwsErrorWithCode: CocoaError.fileReadNoSuchFile)
        let msDOSDate = Date(timeIntervalSince1970: TimeInterval(Int.min)).fileModificationDate
        XCTAssert(msDOSDate == 0)
        let msDOSTime = Date(timeIntervalSince1970: TimeInterval(Int.min)).fileModificationTime
        XCTAssert(msDOSTime == 0)
        let invalidEarlyMSDOSDate = Date(timeIntervalSince1970: 0).fileModificationDate
        XCTAssert(invalidEarlyMSDOSDate == 33)
        let invalidLateMSDOSDate = Date(timeIntervalSince1970: 4102444800).fileModificationDate
        XCTAssert(invalidLateMSDOSDate == 60961)
    }

    func testFileSizeHelperMethods() {
        let nonExistentURL = URL(fileURLWithPath: "/nonexistant")
        XCTAssertCocoaError(try FileManager.fileSizeForItem(at: nonExistentURL),
                            throwsErrorWithCode: CocoaError.fileReadNoSuchFile)
    }

    func testFileTypeHelperMethods() {
        let nonExistentURL = URL(fileURLWithPath: "/nonexistant")
        XCTAssertCocoaError(try FileManager.typeForItem(at: nonExistentURL),
                            throwsErrorWithCode: CocoaError.fileReadNoSuchFile)
        guard let nonFileURL = URL(string: "https://www.peakstep.com") else {
            XCTFail("Failed to create test URL."); return
        }

        XCTAssertCocoaError(try FileManager.typeForItem(at: nonFileURL),
                            throwsErrorWithCode: CocoaError.fileReadNoSuchFile)
    }

    func testFileModificationDate() {
        var testDateComponents = DateComponents()
        testDateComponents.calendar = Calendar(identifier: Calendar.Identifier.gregorian)
        testDateComponents.timeZone = TimeZone(identifier: "UTC")
        testDateComponents.year = 2000
        testDateComponents.month = 1
        testDateComponents.day = 1
        testDateComponents.hour = 12
        testDateComponents.minute = 30
        testDateComponents.second = 10
        guard let testDate = testDateComponents.date else {
            XCTFail("Failed to create test date/timestamp"); return
        }
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .create)
        do {
            try fileManager.setAttributes([.modificationDate: testDate], ofItemAtPath: assetURL.path)
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
            guard let entry = archive["\(assetURL.lastPathComponent)"] else {
                throw Archive.ArchiveError.unreadableArchive
            }
            guard let fileDate = entry.fileAttributes[.modificationDate] as? Date else {
                throw CocoaError(CocoaError.fileReadUnknown)
            }
            let currentTimeInterval = testDate.timeIntervalSinceReferenceDate
            let fileTimeInterval = fileDate.timeIntervalSinceReferenceDate
            // ZIP uses MSDOS timestamps, which provide very poor accuracy
            // https://blogs.msdn.microsoft.com/oldnewthing/20151030-00/?p=91881
            XCTAssertEqual(currentTimeInterval, fileTimeInterval, accuracy: 2.0)
        } catch { XCTFail("Failed to test last file modification date") }
    }

    func testPOSIXPermissions() {
        let permissions = NSNumber(value: Int16(0o753))
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .create)
        do {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: assetURL.path)
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
            guard let entry = archive["\(assetURL.lastPathComponent)"] else {
                throw Archive.ArchiveError.unreadableArchive
            }
            guard let filePermissions = entry.fileAttributes[.posixPermissions] as? NSNumber else {
                throw CocoaError(CocoaError.fileReadUnknown)
            }
            XCTAssert(permissions.int16Value == filePermissions.int16Value)
        } catch { XCTFail("Failed to test POSIX permissions") }
    }
}
