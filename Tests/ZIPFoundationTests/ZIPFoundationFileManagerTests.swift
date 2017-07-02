//
//  ZIPFoundationFileManagerTests.swift
//  ZIPFoundation
//
//  Copyright © 2017 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {
    func testZipItem() {
        let fileManager = FileManager()
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        var fileArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        fileArchiveURL.appendPathComponent(self.pathComponent(for: #function))
        fileArchiveURL.appendPathExtension("zip")
        do {
            try fileManager.zipItem(at: assetURL, to: fileArchiveURL)
        } catch { XCTFail("Failed to zip item at URL:\(assetURL)") }
        guard let archive = Archive(url: fileArchiveURL, accessMode: .read) else {
            XCTFail()
            return
        }
        XCTAssertNotNil(archive[assetURL.lastPathComponent])
        XCTAssert(archive.checkIntegrity())
        var directoryURL = ZIPFoundationTests.tempZipDirectoryURL
        directoryURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        var directoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let pathComponent = self.pathComponent(for: #function) + "Directory"
        directoryArchiveURL.appendPathComponent(pathComponent)
        directoryArchiveURL.appendPathExtension("zip")
        var parentDirectoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let parentPathComponent = self.pathComponent(for: #function) + "ParentDirectory"
        parentDirectoryArchiveURL.appendPathComponent(parentPathComponent)
        parentDirectoryArchiveURL.appendPathExtension("zip")
        let newAssetURL = directoryURL.appendingPathComponent(assetURL.lastPathComponent)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: directoryURL.appendingPathComponent("nested"),
                                            withIntermediateDirectories: true, attributes: nil)
            try fileManager.copyItem(at: assetURL, to: newAssetURL)
            try fileManager.createSymbolicLink(at: directoryURL.appendingPathComponent("link"),
                                               withDestinationURL: newAssetURL)
            try fileManager.zipItem(at: directoryURL, to: directoryArchiveURL)
            try fileManager.zipItem(at: directoryURL, to: parentDirectoryArchiveURL, shouldKeepParent: true)
        } catch { XCTFail("Unexpected error while trying to zip via fileManager.") }
        guard let directoryArchive = Archive(url: directoryArchiveURL, accessMode: .read) else {
            XCTFail(); return
        }
        XCTAssert(directoryArchive.checkIntegrity())
        guard let parentDirectoryArchive = Archive(url: parentDirectoryArchiveURL, accessMode: .read) else {
            XCTFail(); return
        }
        XCTAssert(parentDirectoryArchive.checkIntegrity())
    }

    func testZipItemErrorConditions() {
        let fileManager = FileManager()
        do {
            try fileManager.zipItem(at: URL(fileURLWithPath: "/nothing"), to: URL(fileURLWithPath: "/nowhere"))
            XCTFail("Error when zipping non-existant archive not raised")
        } catch let error as CocoaError { XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to zip via fileManager.")
        }
        do {
            try fileManager.zipItem(at: URL(fileURLWithPath: NSTemporaryDirectory()),
                                    to: URL(fileURLWithPath: NSTemporaryDirectory()))
            XCTFail("Error when zipping directory to already existing destination not raised")
        } catch let error as CocoaError { XCTAssert(error.code == CocoaError.fileWriteFileExists)
        } catch {
            XCTFail("Unexpected error while trying to zip via fileManager.")
        }
        do {
            let unwritableURL = URL(fileURLWithPath: "/test.zip")
            try fileManager.zipItem(at: URL(fileURLWithPath: NSTemporaryDirectory()), to: unwritableURL)
            XCTFail("Error when zipping to non writable archive not raised")
        } catch let error as Archive.ArchiveError { XCTAssert(error == .unwritableArchive)
        } catch {
            XCTFail("Unexpected error while trying to zip via fileManager.")
        }
        var directoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let pathComponent = self.pathComponent(for: #function) + "Directory"
        directoryArchiveURL.appendPathComponent(pathComponent)
        directoryArchiveURL.appendPathExtension("zip")
        var unreadableFileURL = ZIPFoundationTests.tempZipDirectoryURL
        do {
            unreadableFileURL.appendPathComponent(pathComponent)
            unreadableFileURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
            try fileManager.createParentDirectoryStructure(for: unreadableFileURL)
            let noPermissionAttributes = [FileAttributeKey.posixPermissions: Int16(0o000)]
            let result = fileManager.createFile(atPath: unreadableFileURL.path, contents: nil,
                                                        attributes: noPermissionAttributes)
            XCTAssert(result == true)
            try fileManager.zipItem(at: unreadableFileURL.deletingLastPathComponent(), to: directoryArchiveURL)
        } catch let error as CocoaError { XCTAssert(error.code == CocoaError.fileReadNoPermission) } catch {
            XCTFail("Unexpected error while trying to zip via fileManager.")
        }
    }

    func testUnzipItem() {
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        do {
            try fileManager.unzipItem(at: archive.url, to: destinationURL)
        } catch {
            XCTFail("Failed to extract item.")
            return
        }
        var itemsExist = false
        for entry in archive {
            let directoryURL = destinationURL.appendingPathComponent(entry.path)
            itemsExist = fileManager.fileExists(atPath: directoryURL.path)
            if !itemsExist {
                break
            }
        }
        XCTAssert(itemsExist)
    }

    func testUnzipItemErrorConditions() {
        var nonexistantArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        nonexistantArchiveURL.appendPathComponent("invalid")
        let existingArchiveURL = self.resourceURL(for: #function, pathExtension: "zip")
        let destinationURL = ZIPFoundationTests.tempZipDirectoryURL
        var existingURL = destinationURL
        existingURL.appendPathComponent("test")
        existingURL.appendPathComponent("faust.txt")
        let fileManager = FileManager()
        do {
            try fileManager.unzipItem(at: nonexistantArchiveURL, to: ZIPFoundationTests.tempZipDirectoryURL)
            XCTFail("Error when unzipping non-existant archive not raised")
        } catch let error as CocoaError {
            XCTAssertTrue(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to unzip via fileManager.")
            return
        }
        do {
            try fileManager.createParentDirectoryStructure(for: existingURL)
            fileManager.createFile(atPath: existingURL.path, contents: Data(), attributes: nil)
            try fileManager.unzipItem(at: existingArchiveURL, to: destinationURL)
            XCTFail("Error when unzipping archive to existing destination not raised")
        } catch let error as CocoaError {
            XCTAssertTrue(error.code == CocoaError.fileWriteFileExists)
        } catch {
            XCTFail("Unexpected error while trying to unzip via fileManager.")
            return
        }
        let nonZipArchiveURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            try fileManager.unzipItem(at: nonZipArchiveURL, to: destinationURL)
            XCTFail("Error when trying to unzip non-archive not raised")
        } catch let error as Archive.ArchiveError {
            XCTAssertTrue(error == .unreadableArchive)
        } catch {
            XCTFail("Unexpected error while trying to unzip via fileManager.")
            return
        }
    }

    func testDirectoryCreationHelperMethods() {
        let fileManager = FileManager()
        let processInfo = ProcessInfo.processInfo
        var nestedURL = ZIPFoundationTests.tempZipDirectoryURL
        nestedURL.appendPathComponent(processInfo.globallyUniqueString)
        nestedURL.appendPathComponent(processInfo.globallyUniqueString)
        do {
            try fileManager.createParentDirectoryStructure(for: nestedURL)
        } catch { XCTFail() }
    }

    func testFileAttributeHelperMethods() {
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x15, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        guard let cds = Entry.CentralDirectoryStructure(data: Data(bytes: cdsBytes),
                                                        additionalDataProvider: { count -> Data in
                                                            guard let pathData = "/".data(using: .utf8) else {
                                                                throw AdditionalDataError.encodingError
                                                            }
                                                            XCTAssert(count == pathData.count)
                                                            return pathData
        }) else {
            XCTFail()
            return
        }
        var attributes = FileManager.attributes(from: cds)
        guard let permissions = attributes[.posixPermissions] as? UInt16 else {
            XCTFail()
            return
        }
        XCTAssert(permissions == defaultPermissions)
    }

    func testFilePermissionErrorConditions() {
        do {
            let deviceURL = URL(fileURLWithPath: "/dev/zero")
            _ = try FileManager.permissionsForItem(at: deviceURL)
            let unreadableURL = URL(fileURLWithPath: "/unreadable")
            _ = try FileManager.permissionsForItem(at: unreadableURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail()
            return
        }
    }

    func testFilePermissionHelperMethods() {
        var permissions = FileManager.permissions(for: UInt32(777), osType: .unix)
        XCTAssert(permissions == defaultPermissions)
        permissions = FileManager.permissions(for: UInt32(0), osType: .msdos)
        XCTAssert(permissions == defaultPermissions)
    }

    func testFileModificationDateHelperMethods() {
        guard let nonFileURL = URL(string: "https://www.peakstep.com/") else {
            XCTFail()
            return
        }
        let nonExistantURL = URL(fileURLWithPath: "/nonexistant")
        do {
            _ = try FileManager.fileModificationDateTimeForItem(at: nonFileURL)
            _ = try FileManager.fileModificationDateTimeForItem(at: nonExistantURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to retrieve file modification date")
        }
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
        let nonExistantURL = URL(fileURLWithPath: "/nonexistant")
        do {
            _ = try FileManager.fileSizeForItem(at: nonExistantURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to retrieve file size")
        }
    }

    func testFileTypeHelperMethods() {
        let nonExistantURL = URL(fileURLWithPath: "/nonexistant")
        do {
            _ = try FileManager.typeForItem(at: nonExistantURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to retrieve file type")
        }
        guard let nonFileURL = URL(string: "https://www.peakstep.com") else {
            XCTFail()
            return
        }
        do {
            _ = try FileManager.typeForItem(at: nonFileURL)
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoSuchFile)
        } catch {
            XCTFail("Unexpected error while trying to retrieve file type")
        }
    }
}
