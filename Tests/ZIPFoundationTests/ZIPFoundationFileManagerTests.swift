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

    func testZipItem() throws {
        let fileManager = FileManager()
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        var fileArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        fileArchiveURL.appendPathComponent(self.archiveName(for: #function))
        do {
            try fileManager.zipItem(at: assetURL, to: fileArchiveURL)
        } catch { XCTFail("Failed to zip item at URL:\(assetURL)") }
        let archive = try Archive(url: fileArchiveURL, accessMode: .read)
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
        let directoryArchive = try Archive(url: directoryArchiveURL, accessMode: .read)
        XCTAssert(directoryArchive.checkIntegrity())
        let parentDirectoryArchive = try Archive(url: parentDirectoryArchiveURL, accessMode: .read)
        XCTAssert(parentDirectoryArchive.checkIntegrity())
    }

    func testZipItemErrorConditions() {
        let fileManager = FileManager()
        let nonExistingURL1 = URL(fileURLWithPath: "/nothing")
        let nonExistingURL2 = URL(fileURLWithPath: "/nowhere")
        XCTAssertCocoaError(try fileManager.zipItem(at: nonExistingURL1, to: nonExistingURL2),
                            throwsErrorWithCode: .fileReadNoSuchFile)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertCocoaError(try fileManager.zipItem(at: tempURL, to: tempURL),
                            throwsErrorWithCode: .fileWriteFileExists)
        let unwritableURL = URL(fileURLWithPath: "/test.zip")
        XCTAssertCocoaError(try fileManager.zipItem(at: tempURL, to: tempURL),
                            throwsErrorWithCode: .fileWriteFileExists)
        XCTAssertCocoaError(try fileManager.zipItem(at: tempURL, to: unwritableURL),
                            throwsErrorWithCode: .fileWriteVolumeReadOnly)
        var directoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        let pathComponent = self.pathComponent(for: #function) + "Directory"
        directoryArchiveURL.appendPathComponent(pathComponent)
        directoryArchiveURL.appendPathExtension("zip")
        var unreadableFileURL = ZIPFoundationTests.tempZipDirectoryURL
        unreadableFileURL.appendPathComponent(pathComponent)
        unreadableFileURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        try? fileManager.createParentDirectoryStructure(for: unreadableFileURL)
        let noPermissionAttributes = [FileAttributeKey.posixPermissions: Int16(0o000)]
        let result = fileManager.createFile(atPath: unreadableFileURL.path, contents: nil,
                                            attributes: noPermissionAttributes)
        XCTAssert(result == true)
        let directoryURL = unreadableFileURL.deletingLastPathComponent()
        XCTAssertCocoaError(try fileManager.zipItem(at: directoryURL, to: directoryArchiveURL),
                            throwsErrorWithCode: .fileReadNoPermission)
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
            try fileManager.unzipItem(at: archive.url, to: destinationURL, pathEncoding: encoding)
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
        XCTAssertCocoaError(try fileManager.unzipItem(at: nonexistantArchiveURL,
                                                      to: ZIPFoundationTests.tempZipDirectoryURL),
                            throwsErrorWithCode: .fileReadNoSuchFile)
        try? fileManager.createParentDirectoryStructure(for: existingURL)
        fileManager.createFile(atPath: existingURL.path, contents: Data(), attributes: nil)
        XCTAssertCocoaError(try fileManager.unzipItem(at: existingArchiveURL, to: destinationURL),
                            throwsErrorWithCode: .fileWriteFileExists)
        let nonZipArchiveURL = self.resourceURL(for: #function, pathExtension: "png")
        XCTAssertSwiftError(try fileManager.unzipItem(at: nonZipArchiveURL, to: destinationURL),
                            throws: Archive.ArchiveError.missingEndOfCentralDirectoryRecord)
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
        let shellZIPInfos = ZIPInfo.makeZIPInfos(forArchiveAtURL: shellZIPURL, mode: .shellParsing)
            .sorted { $0.path < $1.path }
        let builtInZIPInfos = ZIPInfo.makeZIPInfos(forArchiveAtURL: builtInZIPURL, mode: .directoryIteration)
            .sorted { $0.path < $1.path }
        XCTAssert(shellZIPInfos == builtInZIPInfos)
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

extension ZIPInfo: Equatable {

    static func == (lhs: Self, rhs: Self) -> Bool {
        let hasSamePath = lhs.path == rhs.path
        let hasSameSize = lhs.size == rhs.size
        // ZIP date/timesstamps have very low resolution. We have to compare with some leeway.
        let startDate = lhs.modificationDate.addingTimeInterval(-2)
        let endDate = lhs.modificationDate.addingTimeInterval(+2)
        let dateRange = startDate...endDate
        let hasSameDate = dateRange.contains(rhs.modificationDate)
        return hasSamePath &&
               hasSameSize &&
               hasSameDate
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
