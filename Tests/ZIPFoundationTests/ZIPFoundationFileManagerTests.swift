//
//  ZIPFoundationFileManagerTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2023 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
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

    // On Darwin platforms, we want the same behavior as the system-provided ZIP utilities.
    // On the Mac, this includes the graphical Archive Utility as well as the `ditto`
    // command line tool.
    func testConsistentBehaviorWithSystemZIPUtilities() {
#if os(macOS)
        // We use a macOS framework bundle here because it covers a lot of file system edge cases like
        // double-symlinked directories etc.
        let testBundleURL = URL(fileURLWithPath: "/System/Library/Frameworks/Foundation.framework/", isDirectory: true)
        let fileManager = FileManager()
        let builtInZIPURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        try? fileManager.zipItem(at: testBundleURL, to: builtInZIPURL)

        func shellZIP(directoryAtURL url: URL) -> URL {
            let zipTask = Process()
            zipTask.launchPath = "/usr/bin/ditto"
            let tempZIPURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("zip")
            zipTask.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", url.path, tempZIPURL.path]
            let pipe = Pipe()
            zipTask.standardOutput = pipe
            zipTask.standardError = pipe
            zipTask.launch()
            zipTask.waitUntilExit()
            return tempZIPURL
        }

        let shellZIPURL = shellZIP(directoryAtURL: testBundleURL)
        let shellZIPInfos = Set(ZIPInfo.makeZIPInfos(forArchiveAtURL: shellZIPURL, mode: .shellParsing))
        let builtInZIPInfos = Set(ZIPInfo.makeZIPInfos(forArchiveAtURL: builtInZIPURL, mode: .directoryIteration))
        let diff = builtInZIPInfos.symmetricDifference(shellZIPInfos)
        XCTAssert(diff.count == 0)
#endif
    }
}

// MARK: - Private

#if os(macOS)
private struct ZIPInfo: Hashable {

    enum Mode {
        case directoryIteration
        case shellParsing
    }

    let size: size_t
    let modificationDate: Date
    let path: String

    init(size: size_t, modificationDate: Date, path: String) {
        self.size = size
        self.modificationDate = modificationDate
        self.path = path
    }

    init(logLine: String) {
        // We are parsing the output of `unzip -ZT` here.
        // The following assumptions must be met:
        // - 8 columns
        // - size field at index 3
        // - date/time field at index 6
        // - path field at index 7
        let fields = logLine
            .split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            .map { String($0) }
        self.size = size_t(fields[3]) ?? 0
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd.HHmmss"
        let date = dateFormatter.date(from: fields[6])
        self.modificationDate = date ?? Date()
        self.path = fields[7].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func makeZIPInfos(forArchiveAtURL url: URL, mode: Mode) -> [ZIPInfo] {

        func directoryZIPInfos(forArchiveAtURL url: URL) -> [ZIPInfo] {
            let fileManager = FileManager()
            let tempDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .standardizedFileURL
                .appendingPathComponent(UUID().uuidString)
            let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .isDirectoryKey, .pathKey]
            try? fileManager.unzipItem(at: url, to: tempDirectoryURL)
            guard let enumerator = fileManager.enumerator(at: tempDirectoryURL, includingPropertiesForKeys: keys)
            else { return [] }

            var zipInfos = [ZIPInfo]()
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: Set(keys)),
                      let path = resourceValues.path,
                      let isDirectory = resourceValues.isDirectory else { continue }

                let size = resourceValues.fileSize ?? 0
                let date = resourceValues.creationDate ?? Date()
                let tempPath = tempDirectoryURL.path
                let relPath = URL.makeRelativePath(fromPath: path, relativeToPath: tempPath, isDirectory: isDirectory)
                zipInfos.append(.init(size: size, modificationDate: date, path: String(relPath)))
            }
            return zipInfos
        }

        func shellZIPInfos(forArchiveAtURL url: URL) -> [ZIPInfo] {
            let unzipTask = Process()
            unzipTask.launchPath = "/usr/bin/unzip"
            unzipTask.arguments = ["-ZT", url.path]
            let pipe = Pipe()
            unzipTask.standardOutput = pipe
            unzipTask.standardError = pipe
            unzipTask.launch()
            let unzipOutputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let unzipOutput = String(data: unzipOutputData, encoding: .utf8)!
            unzipTask.waitUntilExit()
            return unzipOutput.split(whereSeparator: \.isNewline)
                .dropFirst(2)
                .dropLast()
                .map { ZIPInfo(logLine: String($0) ) }
        }

        switch mode {
        case .directoryIteration:
            return directoryZIPInfos(forArchiveAtURL: url)
        case .shellParsing:
            return shellZIPInfos(forArchiveAtURL: url)
        }
    }
}

private extension URL {

    static func makeRelativePath(fromPath path: String, relativeToPath basePath: String, isDirectory: Bool) -> String {
        let prefixRange = path.startIndex..<path.index(path.startIndex, offsetBy: 1)
        return URL(fileURLWithPath: path, isDirectory: isDirectory)
            .standardizedFileURL
            .path
            .replacingOccurrences(of: basePath, with: "")
            .replacingOccurrences(of: "/private", with: "")
            .replacingOccurrences(of: "/", with: "", range: prefixRange)
            .appending(isDirectory ? "/" : "")
    }
}
#endif
