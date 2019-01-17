//
//  ZIPFoundationProgressTests.swift
//  ZIPFoundation
//
//  Created by Thomas Zoechling on 17.01.19.
//

import XCTest
@testable import ZIPFoundation

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
extension ZIPFoundationTests {
    func testArchiveAddUncompressedEntryProgress() {
        let archive = self.archive(for: #function, mode: .update)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let progress = archive.makeProgressForAddingItem(at: assetURL)
        let handler: XCTKVOExpectation.Handler = { (_, _) -> Bool in
            if progress.fractionCompleted > 0.5 {
                progress.cancel()
                return true
            }
            return false
        }
        let cancel = self.keyValueObservingExpectation(for: progress, keyPath: #keyPath(Progress.fractionCompleted),
                                                       handler: handler)
        let zipQueue = DispatchQueue.init(label: "ZIPFoundationTests")
        zipQueue.async {
            do {
                let relativePath = assetURL.lastPathComponent
                let baseURL = assetURL.deletingLastPathComponent()
                try archive.addEntry(with: relativePath, relativeTo: baseURL, bufferSize: 1, progress: progress)
            } catch let error as Archive.ArchiveError {
                XCTAssert(error == Archive.ArchiveError.cancelledOperation)
            } catch {
                XCTFail("Failed to add entry to uncompressed folder archive with error : \(error)")
            }
        }
        self.wait(for: [cancel], timeout: 20.0)
        zipQueue.sync {
            XCTAssert(progress.fractionCompleted > 0.5)
            XCTAssert(archive.checkIntegrity())
        }
    }

    func testArchiveAddCompressedEntryProgress() {
        let archive = self.archive(for: #function, mode: .update)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        let progress = archive.makeProgressForAddingItem(at: assetURL)
        let handler: XCTKVOExpectation.Handler = { (_, _) -> Bool in
            if progress.fractionCompleted > 0.5 {
                progress.cancel()
                return true
            }
            return false
        }
        let cancel = self.keyValueObservingExpectation(for: progress, keyPath: #keyPath(Progress.fractionCompleted),
                                                       handler: handler)
        let zipQueue = DispatchQueue.init(label: "ZIPFoundationTests")
        zipQueue.async {
            do {
                let relativePath = assetURL.lastPathComponent
                let baseURL = assetURL.deletingLastPathComponent()
                try archive.addEntry(with: relativePath, relativeTo: baseURL,
                                     compressionMethod: .deflate, bufferSize: 1, progress: progress)
            } catch let error as Archive.ArchiveError {
                XCTAssert(error == Archive.ArchiveError.cancelledOperation)
            } catch {
                XCTFail("Failed to add entry to uncompressed folder archive with error : \(error)")
            }
        }
        self.wait(for: [cancel], timeout: 20.0)
        zipQueue.sync {
            XCTAssert(progress.fractionCompleted > 0.5)
            XCTAssert(archive.checkIntegrity())
        }
    }

    func testRemoveEntryProgress() {
        let archive = self.archive(for: #function, mode: .update)
        guard let entryToRemove = archive["test/data.random"] else {
            XCTFail("Failed to find entry to remove in uncompressed folder")
            return
        }
        let progress = archive.makeProgressForRemoving(entryToRemove)
        let handler: XCTKVOExpectation.Handler = { (_, _) -> Bool in
            if progress.fractionCompleted > 0.5 {
                progress.cancel()
                return true
            }
            return false
        }
        let cancel = self.keyValueObservingExpectation(for: progress, keyPath: #keyPath(Progress.fractionCompleted),
                                                       handler: handler)
        DispatchQueue.global().async {
            do {
                try archive.remove(entryToRemove, progress: progress)
            } catch let error as Archive.ArchiveError {
                XCTAssert(error == Archive.ArchiveError.cancelledOperation)
            } catch {
                XCTFail("Failed to remove entry from uncompressed folder archive with error : \(error)")
            }
        }
        self.wait(for: [cancel], timeout: 20.0)
        XCTAssert(progress.fractionCompleted > 0.5)
        XCTAssert(archive.checkIntegrity())
    }

    func testZipItemProgress() {
        let fileManager = FileManager()
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        var fileArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        fileArchiveURL.appendPathComponent(self.archiveName(for: #function))
        let fileProgress = Progress()
        let fileExpectation = self.keyValueObservingExpectation(for: fileProgress,
                                                                keyPath: #keyPath(Progress.fractionCompleted),
                                                                expectedValue: 1.0)
        DispatchQueue.global().async {
            do {
                try fileManager.zipItem(at: assetURL, to: fileArchiveURL, progress: fileProgress)
            } catch { XCTFail("Failed to zip item at URL:\(assetURL)") }
            guard let archive = Archive(url: fileArchiveURL, accessMode: .read) else {
                XCTFail("Failed to read archive.") ; return
            }
            XCTAssert(archive.checkIntegrity())
        }
        var directoryURL = ZIPFoundationTests.tempZipDirectoryURL
        directoryURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        var directoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        directoryArchiveURL.appendPathComponent(self.archiveName(for: #function, suffix: "Directory"))
        let newAssetURL = directoryURL.appendingPathComponent(assetURL.lastPathComponent)
        let directoryProgress = Progress()
        let directoryExpectation = self.keyValueObservingExpectation(for: directoryProgress,
                                                                     keyPath: #keyPath(Progress.fractionCompleted),
                                                                     expectedValue: 1.0)
        DispatchQueue.global().async {
            do {
                try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                try fileManager.createDirectory(at: directoryURL.appendingPathComponent("nested"),
                                                withIntermediateDirectories: true, attributes: nil)
                try fileManager.copyItem(at: assetURL, to: newAssetURL)
                try fileManager.createSymbolicLink(at: directoryURL.appendingPathComponent("link"),
                                                   withDestinationURL: newAssetURL)
                try fileManager.zipItem(at: directoryURL, to: directoryArchiveURL, progress: directoryProgress)
            } catch { XCTFail("Unexpected error while trying to zip via fileManager.") }
            guard let directoryArchive = Archive(url: directoryArchiveURL, accessMode: .read) else {
                XCTFail("Failed to read archive."); return
            }
            XCTAssert(directoryArchive.checkIntegrity())
        }
        self.wait(for: [fileExpectation, directoryExpectation], timeout: 20.0)
    }

    func testUnzipItemProgress() {
        let fileManager = FileManager()
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        let progress = Progress()
        let expectation = self.keyValueObservingExpectation(for: progress,
                                                            keyPath: #keyPath(Progress.fractionCompleted),
                                                            expectedValue: 1.0)
        DispatchQueue.global().async {
            do {
                try fileManager.unzipItem(at: archive.url, to: destinationURL, progress: progress)
            } catch {
                XCTFail("Failed to extract item."); return
            }
            var itemsExist = false
            for entry in archive {
                let directoryURL = destinationURL.appendingPathComponent(entry.path)
                itemsExist = fileManager.fileExists(atPath: directoryURL.path)
                if !itemsExist { break }
            }
            XCTAssert(itemsExist)
        }
        self.wait(for: [expectation], timeout: 10.0)
    }
}
#endif
