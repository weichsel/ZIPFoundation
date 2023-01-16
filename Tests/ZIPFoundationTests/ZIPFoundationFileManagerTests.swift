//
//  ZIPFoundationFileManagerTests.swift
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

    func testZipItem() {
        let fileManager = FileManager()
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        var fileArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        fileArchiveURL.appendPathComponent(self.archiveName(for: #function))
        do {
            try fileManager.zipItem(at: assetURL, to: fileArchiveURL)
        } catch { XCTFail("Failed to zip item at URL:\(assetURL)") }
        guard let archive = Archive(url: fileArchiveURL, accessMode: .read) else {
            XCTFail("Failed to read archive."); return
        }
        XCTAssertNotNil(archive[assetURL.lastPathComponent])
        XCTAssert(archive.checkIntegrity())
        var directoryURL = ZIPFoundationTests.tempZipDirectoryURL
        directoryURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        var directoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let pathComponent = self.archiveName(for: #function, suffix: "Directory")
        directoryArchiveURL.appendPathComponent(pathComponent)
        var parentDirectoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let parentPathComponent = self.archiveName(for: #function, suffix: "ParentDirectory")
        parentDirectoryArchiveURL.appendPathComponent(parentPathComponent)
        var compressedDirectoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let compressedPathComponent = self.archiveName(for: #function, suffix: "CompressedDirectory")
        compressedDirectoryArchiveURL.appendPathComponent(compressedPathComponent)
        let newAssetURL = directoryURL.appendingPathComponent(assetURL.lastPathComponent)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createDirectory(at: directoryURL.appendingPathComponent("nested"),
                                            withIntermediateDirectories: true, attributes: nil)
            try fileManager.copyItem(at: assetURL, to: newAssetURL)
            try fileManager.createSymbolicLink(at: directoryURL.appendingPathComponent("link"),
                                               withDestinationURL: newAssetURL)
            try fileManager.zipItem(at: directoryURL, to: directoryArchiveURL)
            try fileManager.zipItem(at: directoryURL, to: parentDirectoryArchiveURL, shouldKeepParent: false)
            try fileManager.zipItem(at: directoryURL, to: compressedDirectoryArchiveURL, compressionMethod: .deflate)
        } catch { XCTFail("Unexpected error while trying to zip via fileManager.") }
        guard let directoryArchive = Archive(url: directoryArchiveURL, accessMode: .read) else {
            XCTFail("Failed to read archive."); return
        }
        XCTAssert(directoryArchive.checkIntegrity())
        guard let parentDirectoryArchive = Archive(url: parentDirectoryArchiveURL, accessMode: .read) else {
            XCTFail("Failed to read archive."); return
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
        } catch { XCTFail("Unexpected error while trying to zip via fileManager.") }
        do {
            let unwritableURL = URL(fileURLWithPath: "/test.zip")
            try fileManager.zipItem(at: URL(fileURLWithPath: NSTemporaryDirectory()), to: unwritableURL)
            XCTFail("Error when zipping to non writable archive not raised")
        } catch let error as Archive.ArchiveError { XCTAssert(error == .unwritableArchive)
        } catch { XCTFail("Unexpected error while trying to zip via fileManager.") }
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
        } catch let error as CocoaError {
            XCTAssert(error.code == CocoaError.fileReadNoPermission)
        } catch {
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
            XCTFail("Failed to extract item."); return
        }
        var itemsExist = false
        for entry in archive {
            let directoryURL = destinationURL.appendingPathComponent(entry.path)
            itemsExist = fileManager.itemExists(at: directoryURL)
            if !itemsExist { break }
        }
        XCTAssert(itemsExist)
    }

    func testUnzipItemWithPreferredEncoding() {
        let fileManager = FileManager()
        let encoding = String.Encoding.utf8
        let archive = self.archive(for: #function, mode: .read, preferredEncoding: encoding)
        let destinationURL = self.createDirectory(for: #function)
        do {
            try fileManager.unzipItem(at: archive.url, to: destinationURL, preferredEncoding: encoding)
        } catch {
            XCTFail("Failed to extract item."); return
        }
        var itemsExist = false
        for entry in archive {
            let directoryURL = destinationURL.appendingPathComponent(entry.path(using: encoding))
            itemsExist = fileManager.itemExists(at: directoryURL)
            if !itemsExist { break }
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
        } catch { XCTFail("Unexpected error while trying to unzip via fileManager."); return }
        do {
            try fileManager.createParentDirectoryStructure(for: existingURL)
            fileManager.createFile(atPath: existingURL.path, contents: Data(), attributes: nil)
            try fileManager.unzipItem(at: existingArchiveURL, to: destinationURL)
            XCTFail("Error when unzipping archive to existing destination not raised")
        } catch let error as CocoaError {
            XCTAssertTrue(error.code == CocoaError.fileWriteFileExists)
        } catch {
            XCTFail("Unexpected error while trying to unzip via fileManager."); return
        }
        let nonZipArchiveURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            try fileManager.unzipItem(at: nonZipArchiveURL, to: destinationURL)
            XCTFail("Error when trying to unzip non-archive not raised")
        } catch let error as Archive.ArchiveError {
            XCTAssertTrue(error == .unreadableArchive)
        } catch { XCTFail("Unexpected error while trying to unzip via fileManager."); return }
    }
}
