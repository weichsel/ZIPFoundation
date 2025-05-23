//
//  ZIPFoundationWritingTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2024 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {

    func testCreateArchiveAddUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add uncompressed entry archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddCompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL, compressionMethod: .deflate)
        } catch {
            XCTFail("Failed to add compressed entry folder archive : \(error)")
        }
        let entry = archive[assetURL.lastPathComponent]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddDirectory() {
        let archive = self.archive(for: #function, mode: .create)
        do {
            try archive.addEntry(with: "Test", type: .directory,
                                 uncompressedSize: Int64(0), provider: { _, _ in return Data()})
        } catch {
            XCTFail("Failed to add directory entry without file system representation to archive.")
        }
        let testEntry = archive["Test"]
        XCTAssertNotNil(testEntry)
        let uniqueString = ProcessInfo.processInfo.globallyUniqueString
        let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uniqueString)
        do {
            let fileManager = FileManager()
            try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            let relativePath = tempDirectoryURL.lastPathComponent
            let baseURL = tempDirectoryURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath + "/", relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add directory entry to archive.")
        }
        let entry = archive[tempDirectoryURL.lastPathComponent + "/"]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddSymbolicLink() {
        let archive = self.archive(for: #function, mode: .create)
        let rootDirectoryURL = ZIPFoundationTests.tempZipDirectoryURL.appendingPathComponent("SymbolicLinkDirectory")
        let symbolicLinkURL = rootDirectoryURL.appendingPathComponent("test.link")
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let fileManager = FileManager()
        do {
            try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            try fileManager.createSymbolicLink(atPath: symbolicLinkURL.path, withDestinationPath: assetURL.path)
            let relativePath = symbolicLinkURL.lastPathComponent
            let baseURL = symbolicLinkURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add symbolic link to archive")
        }
        let entry = archive[symbolicLinkURL.lastPathComponent]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
        do {
            try archive.addEntry(with: "link", type: .symlink, uncompressedSize: Int64(10),
                                 provider: { (_, count) -> Data in
                return Data(count: count)
            })
        } catch {
            XCTFail("Failed to add symbolic link to archive")
        }
        let entry2 = archive["link"]
        XCTAssertNotNil(entry2)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddEntryErrorConditions() {
        let archive = self.archive(for: #function, mode: .create)
        let tempPath = NSTemporaryDirectory()
        var nonExistantURL = URL(fileURLWithPath: tempPath)
        nonExistantURL.appendPathComponent("invalid.path")
        let nonExistantRelativePath = nonExistantURL.lastPathComponent
        let nonExistantBaseURL = nonExistantURL.deletingLastPathComponent()
        XCTAssertCocoaError(try archive.addEntry(with: nonExistantRelativePath, relativeTo: nonExistantBaseURL),
                            throwsErrorWithCode: .fileReadNoSuchFile)
        // Cover the error code path when `fopen` fails during entry addition.
        let assetURL = self.resourceURL(for: #function, pathExtension: "txt")
        let entryAddition = {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            self.XCTAssertPOSIXError(try archive.addEntry(with: relativePath, relativeTo: baseURL),
                                     throwsErrorWithCode: .EMFILE)
        }
        self.runWithFileDescriptorLimit(0) {
            try? entryAddition()
        }
    }

    func testArchiveAddEntryErrorConditions() {
        let readonlyArchive = self.archive(for: #function, mode: .read)
        XCTAssertSwiftError(try readonlyArchive.addEntry(with: "Test",
                                                         type: .directory,
                                                         uncompressedSize: Int64(0),
                                                         provider: { _, _ in return Data() }),
                            throws: Archive.ArchiveError.unwritableArchive)
    }

    func testCreateArchiveAddZeroSizeUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "txt")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add zero-size uncompressed entry to archive with error : \(error)")
        }
        let entry = archive[assetURL.lastPathComponent]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddZeroSizeCompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "txt")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL, compressionMethod: .deflate)
        } catch {
            XCTFail("Failed to add zero-size compressed entry to archive with error : \(error)")
        }
        let entry = archive[assetURL.lastPathComponent]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddLargeUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let size = 1024*1024*20
        let data = Data.makeRandomData(size: size)
        let entryName = ProcessInfo.processInfo.globallyUniqueString
        do {
            try archive.addEntry(with: entryName, type: .file,
                                 uncompressedSize: Int64(size), provider: { (position, bufferSize) -> Data in
                let upperBound = Swift.min(size, Int(position) + bufferSize)
                let range = Range(uncheckedBounds: (lower: Int(position), upper: upperBound))
                return data.subdata(in: range)
            })
        } catch {
            XCTFail("Failed to add large entry to uncompressed archive with error : \(error)")
        }
        guard let entry = archive[entryName] else {
            XCTFail("Failed to add large entry to uncompressed archive")
            return
        }
        XCTAssert(entry.checksum == data.crc32(checksum: 0))
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddLargeCompressedEntry() {
        let archive = self.archive(for: #function, mode: .create)
        let size = 1024*1024*20
        let data = Data.makeRandomData(size: size)
        let entryName = ProcessInfo.processInfo.globallyUniqueString
        do {
            try archive.addEntry(with: entryName, type: .file, uncompressedSize: Int64(size),
                                 compressionMethod: .deflate,
                                 provider: { (position, bufferSize) -> Data in
                let upperBound = Swift.min(size, Int(position) + bufferSize)
                let range = Range(uncheckedBounds: (lower: Int(position), upper: upperBound))
                return data.subdata(in: range)
            })
        } catch {
            XCTFail("Failed to add large entry to compressed archive with error : \(error)")
        }
        guard let entry = archive[entryName] else {
            XCTFail("Failed to add large entry to compressed archive")
            return
        }
        let dataCRC32 = data.crc32(checksum: 0)
        XCTAssert(entry.checksum == dataCRC32)
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveUncompressedEntry() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove in uncompressed folder"); return
        }
        do {
            try archive.remove(entryToRemove)
        } catch {
            XCTFail("Failed to remove entry from uncompressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveCompressedEntry() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove in compressed folder archive"); return
        }
        do {
            try archive.remove(entryToRemove)
        } catch {
            XCTFail("Failed to remove entry from compressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveDataDescriptorCompressedEntry() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["second.txt"] else {
            XCTFail("Failed to find entry to remove in compressed folder archive")
            return
        }
        do {
            try archive.remove(entryToRemove)
        } catch {
            XCTFail("Failed to remove entry to compressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testRemoveEntryErrorConditions() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove in uncompressed folder")
            return
        }
        // We don't have access to the temp archive file that Archive.remove
        // uses. To exercise the error code path, we temporarily limit the number of open files for
        // the test process to exercise the error code path here.
        XCTAssertNoThrow(try self.runWithFileDescriptorLimit(0) {
            XCTAssertCocoaError(try archive.remove(entryToRemove), throwsErrorWithCode: .fileWriteUnknown)
        })
        let readonlyArchive = self.archive(for: #function, mode: .read)
        XCTAssertSwiftError(try readonlyArchive.remove(entryToRemove), throws: Archive.ArchiveError.unwritableArchive)
    }

    func testRemoveMultipleEntriesWithTruncation() {
        let archive = self.archive(for: #function, mode: .update)
        // Get entries that should be at the end of the archive for truncation optimization
        let allEntries = Array(archive)
        let sortedEntries = allEntries.sorted { $0.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader < $1.centralDirectoryStructure.effectiveRelativeOffsetOfLocalHeader }
        
        // Take the last 2 entries for truncation test
        let entriesToRemove = Array(sortedEntries.suffix(2))
        XCTAssertTrue(entriesToRemove.count == 2, "Should have 2 entries to remove for truncation test")
        
        let initialEntryCount = allEntries.count
        let entryPaths = entriesToRemove.map { $0.path }
        
        do {
            try archive.remove(entriesToRemove)
        } catch {
            XCTFail("Failed to remove multiple entries with truncation with error: \(error)")
        }
        
        XCTAssert(archive.checkIntegrity())
        XCTAssertEqual(Array(archive).count, initialEntryCount - 2, "Should have removed exactly 2 entries")
        
        // Verify removed entries are no longer accessible
        for path in entryPaths {
            XCTAssertNil(archive[path], "Entry \(path) should be removed from archive")
        }
    }

    func testRemoveMultipleEntriesWithRewrite() {
        let archive = self.archive(for: #function, mode: .update)
        
        // Get non-consecutive entries that will require the rewrite method
        guard let firstEntry = archive["test/data.random"],
              let secondEntry = archive["test/empty/"] else {
            XCTFail("Failed to find test entries for non-consecutive removal")
            return
        }
        
        let entriesToRemove = [firstEntry, secondEntry]
        let initialEntryCount = Array(archive).count
        let entryPaths = entriesToRemove.map { $0.path }
        
        do {
            try archive.remove(entriesToRemove)
        } catch {
            XCTFail("Failed to remove multiple non-consecutive entries with error: \(error)")
        }
        
        XCTAssert(archive.checkIntegrity())
        XCTAssertEqual(Array(archive).count, initialEntryCount - 2, "Should have removed exactly 2 entries")
        
        // Verify removed entries are no longer accessible
        for path in entryPaths {
            XCTAssertNil(archive[path], "Entry \(path) should be removed from archive")
        }
    }

    func testRemoveMultipleEntriesEmptyArray() {
        let archive = self.archive(for: #function, mode: .update)
        let initialEntryCount = Array(archive).count
        
        do {
            try archive.remove([])
        } catch {
            XCTFail("Failed to handle empty array removal with error: \(error)")
        }
        
        XCTAssert(archive.checkIntegrity())
        XCTAssertEqual(Array(archive).count, initialEntryCount, "Should not remove any entries when given empty array")
    }

    func testRemoveMultipleEntriesSingleEntry() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove")
            return
        }
        
        let initialEntryCount = Array(archive).count
        let entryPath = entryToRemove.path
        
        do {
            try archive.remove([entryToRemove])
        } catch {
            XCTFail("Failed to remove single entry via batch API with error: \(error)")
        }
        
        XCTAssert(archive.checkIntegrity())
        XCTAssertEqual(Array(archive).count, initialEntryCount - 1, "Should have removed exactly 1 entry")
        XCTAssertNil(archive[entryPath], "Entry should be removed from archive")
    }

    func testRemoveMultipleEntriesErrorConditions() {
        let readonlyArchive = self.archive(for: #function, mode: .read)
        let allEntries = Array(readonlyArchive)
        guard let entry = allEntries.first else {
            XCTFail("Failed to find entry in readonly archive")
            return
        }
        
        XCTAssertSwiftError(try readonlyArchive.remove([entry]), 
                           throws: Archive.ArchiveError.unwritableArchive)
    }

    func testRemoveMultipleEntriesProgress() {
        let archive = self.archive(for: #function, mode: .update)
        let allEntries = Array(archive)
        
        // Take first 3 entries for progress testing
        let entriesToRemove = Array(allEntries.prefix(3))
        XCTAssertTrue(entriesToRemove.count >= 2, "Should have at least 2 entries for progress test")
        
        let progress = Progress(totalUnitCount: 0)
        var initialCompletedCount: Int64 = 0
        
        do {
            initialCompletedCount = progress.completedUnitCount
            try archive.remove(entriesToRemove, progress: progress)
        } catch {
            XCTFail("Failed to remove entries with progress tracking with error: \(error)")
        }
        
        XCTAssert(archive.checkIntegrity())
        XCTAssertGreaterThan(progress.totalUnitCount, 0, "Progress should have been updated with total work")
        XCTAssertGreaterThan(progress.completedUnitCount, initialCompletedCount, "Progress should have been updated with completed work")
    }

    func testArchiveCreateErrorConditions() {
        let existantURL = ZIPFoundationTests.tempZipDirectoryURL
        XCTAssertCocoaError(try Archive(url: existantURL, accessMode: .create),
                            throwsErrorWithCode: .fileWriteFileExists)
        let processInfo = ProcessInfo.processInfo
        var noEndOfCentralDirectoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        noEndOfCentralDirectoryArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
        let fullPermissionAttributes = [FileAttributeKey.posixPermissions: NSNumber(value: defaultFilePermissions)]
        let fileManager = FileManager()
        let result = fileManager.createFile(atPath: noEndOfCentralDirectoryArchiveURL.path, contents: nil,
                                            attributes: fullPermissionAttributes)
        XCTAssert(result == true)
        XCTAssertSwiftError(try Archive(url: noEndOfCentralDirectoryArchiveURL, accessMode: .update),
                            throws: Archive.ArchiveError.missingEndOfCentralDirectoryRecord)
    }

    func testArchiveUpdateErrorConditions() {
        self.runWithUnprivilegedGroup {
            var nonUpdatableArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
            let processInfo = ProcessInfo.processInfo
            nonUpdatableArchiveURL.appendPathComponent(processInfo.globallyUniqueString)
            let noPermissionAttributes = [FileAttributeKey.posixPermissions: NSNumber(value: Int16(0o000))]
            let fileManager = FileManager()
            let result = fileManager.createFile(atPath: nonUpdatableArchiveURL.path, contents: nil,
                                                attributes: noPermissionAttributes)
            XCTAssert(result == true)
            XCTAssertPOSIXError(try Archive(url: nonUpdatableArchiveURL, accessMode: .update),
                                throwsErrorWithCode: .EACCES)
        }
    }

    func testReplaceCurrentArchiveWithArchiveCrossLink() {
#if os(macOS)
        let createVolumeExpectation = expectation(description: "Creation of temporary additional volume")
        let unmountVolumeExpectation = expectation(description: "Unmount temporary additional volume")
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            let volName = "Test_\(UUID().uuidString)"
            let task = try NSUserScriptTask.makeVolumeCreationTask(at: tempDir, volumeName: volName)
            task.execute { (error) in
                guard error == nil else {
                    XCTFail("\(String(describing: error))")
                    return
                }
                let vol2URL = URL(fileURLWithPath: "/Volumes/\(volName)")
                defer {
                    let options: FileManager.UnmountOptions = [.allPartitionsAndEjectDisk, .withoutUI]
                    FileManager.default.unmountVolume(at: vol2URL, options:
                                                        options, completionHandler: { (error) in
                        guard error == nil else {
                            XCTFail("\(String(describing: error))")
                            return
                        }
                        unmountVolumeExpectation.fulfill()
                    })
                }
                let vol1ArchiveURL = tempDir.appendingPathComponent("vol1Archive")
                let vol2ArchiveURL = vol2URL.appendingPathComponent("vol2Archive")
                do {
                    let vol1Archive = try Archive(url: vol1ArchiveURL, accessMode: .create)
                    let vol2Archive = try Archive(url: vol2ArchiveURL, accessMode: .create)
                    try vol1Archive.replaceCurrentArchive(with: vol2Archive)
                } catch {
                    type(of: self).tearDown()
                    XCTFail("\(String(describing: error))")
                    return
                }
                createVolumeExpectation.fulfill()
            }
        } catch {
            XCTFail("\(error)")
            return
        }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        waitForExpectations(timeout: 30.0)
#endif
    }
}
