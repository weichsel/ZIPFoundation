//
//  ZIPFoundationFileManagerTests+Symlinks.swift
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

    func testUnzipChainedSymlinkTraversal() throws {
        // Each link target is lexically contained in the destination directory.
        // Resolved through the file system, `link01` points to the parent of the destination though.
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        let escapedURL = destinationURL.deletingLastPathComponent().appendingPathComponent("chained-escaped.txt")
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link00", type: .symlink, content: ".", to: archive)
        try self.addEntry(with: "link01", type: .symlink, content: "link00/..", to: archive)
        try self.addEntry(with: "link01/chained-escaped.txt", type: .file, content: "escaped", to: archive)
        XCTAssertSwiftError(try fileManager.unzipItem(at: archive.url, to: destinationURL),
                            throws: Archive.ArchiveError.uncontainedSymlink)
        XCTAssertFalse(fileManager.itemExists(at: escapedURL))
        XCTAssertFalse(fileManager.itemExists(at: destinationURL.appendingPathComponent("link01")))
        // A rejected link must not leave its parent directory behind.
        let nestedArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "new/link01", type: .symlink, content: "../link00/..", to: nestedArchive)
        XCTAssertSwiftError(try fileManager.unzipItem(at: nestedArchive.url, to: destinationURL),
                            throws: Archive.ArchiveError.uncontainedSymlink)
        XCTAssertFalse(fileManager.itemExists(at: destinationURL.appendingPathComponent("new")))
    }

    func testUnzipDeferredSymlinkTraversal() throws {
        // `link` is dangling when it gets created. The entries that follow would turn it into
        // a link to the parent of the destination directory.
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        let escapedURL = destinationURL.deletingLastPathComponent().appendingPathComponent("deferred-escaped.txt")
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link", type: .symlink, content: "dir/self/../..", to: archive)
        try self.addEntry(with: "dir/self", type: .symlink, content: ".", to: archive)
        try self.addEntry(with: "link/deferred-escaped.txt", type: .file, content: "escaped", to: archive)
        XCTAssertSwiftError(try fileManager.unzipItem(at: archive.url, to: destinationURL),
                            throws: Archive.ArchiveError.uncontainedSymlink)
        XCTAssertFalse(fileManager.itemExists(at: escapedURL))
    }

    func testUnzipEntryPathTraversalThroughSymlink() throws {
        // `link/..` lexically resolves to the destination directory.
        // The file system resolves `link` first and therefore ends up in the parent of the destination.
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        let escapedURL = destinationURL.deletingLastPathComponent().appendingPathComponent("path-escaped.txt")
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link", type: .symlink, content: ".", to: archive)
        try self.addEntry(with: "link/../path-escaped.txt", type: .file, content: "escaped", to: archive)
        XCTAssertCocoaError(try fileManager.unzipItem(at: archive.url, to: destinationURL),
                            throwsErrorWithCode: .fileReadInvalidFileName)
        XCTAssertFalse(fileManager.itemExists(at: escapedURL))
    }

    func testUnzipEntryThroughUncontainedSymlink() throws {
        // Allowing symlinks to point outside of the destination must not allow
        // subsequent entries to be written through them.
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        let outsideURL = self.createDirectory(for: #function + "Outside")
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link", type: .symlink, content: outsideURL.path, to: archive)
        try self.addEntry(with: "link/escaped.txt", type: .file, content: "escaped", to: archive)
        XCTAssertCocoaError(try fileManager.unzipItem(at: archive.url, to: destinationURL,
                                                      symlinksValidWithin: URL.rootFS),
                            throwsErrorWithCode: .fileReadInvalidFileName)
        XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent("link")))
        XCTAssertFalse(fileManager.itemExists(at: outsideURL.appendingPathComponent("escaped.txt")))
        // Directory entries must not be able to alter attributes of the link destination either.
        let directoryArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link/", type: .directory, to: directoryArchive)
        XCTAssertCocoaError(try fileManager.unzipItem(at: directoryArchive.url, to: destinationURL,
                                                      symlinksValidWithin: URL.rootFS),
                            throwsErrorWithCode: .fileReadInvalidFileName)
    }

    func testUnzipEntryThroughContainedSymlink() throws {
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "dir/", type: .directory, to: archive)
        try self.addEntry(with: "link", type: .symlink, content: "dir", to: archive)
        try self.addEntry(with: "nested/sub/link", type: .symlink, content: "../../dir", to: archive)
        try self.addEntry(with: "dangling", type: .symlink, content: "missing/file.txt", to: archive)
        try self.addEntry(with: "dir/deep/", type: .directory, to: archive)
        try self.addEntry(with: "deep", type: .symlink, content: "dir/deep", to: archive)
        // Lexically, this destination is outside of the destination directory.
        try self.addEntry(with: "resolved", type: .symlink, content: "deep/../../dir", to: archive)
        try self.addEntry(with: "resolved/third.txt", type: .file, content: "contained", to: archive)
        try self.addEntry(with: "link/file.txt", type: .file, content: "contained", to: archive)
        try self.addEntry(with: "nested/sub/link/other.txt", type: .file, content: "contained", to: archive)
        XCTAssertNoThrow(try fileManager.unzipItem(at: archive.url, to: destinationURL))
        let directoryURL = destinationURL.appendingPathComponent("dir")
        XCTAssert(fileManager.itemExists(at: directoryURL.appendingPathComponent("file.txt")))
        XCTAssert(fileManager.itemExists(at: directoryURL.appendingPathComponent("other.txt")))
        XCTAssert(fileManager.itemExists(at: directoryURL.appendingPathComponent("third.txt")))
        let danglingURL = destinationURL.appendingPathComponent("dangling")
        XCTAssertEqual(try? fileManager.destinationOfSymbolicLink(atPath: danglingURL.path), "missing/file.txt")
    }

    func testExtractCompressedSymlinkWithSmallBufferSize() throws {
        // The link destination is longer than the buffer size, so it is decompressed in multiple chunks.
        let archive = self.archive(for: #function, mode: .read)
        let destinationURL = self.createDirectory(for: #function)
        let linkURL = destinationURL.appendingPathComponent("link")
        _ = try archive.extract(XCTUnwrap(archive["link"]), to: linkURL, bufferSize: 32)
        XCTAssertEqual(try FileManager().destinationOfSymbolicLink(atPath: linkURL.path),
                       "target-directory/with-a-rather-long-name/that-exceeds-the-buffer-size/file.txt")
    }

    func testUnzipSymlinkToNotYetExistingSymlink() throws {
        // Framework bundles contain symlinks that point through other symlinks.
        // Depending on the entry order, those don't exist yet when the link gets created.
        // More details: https://github.com/weichsel/ZIPFoundation/issues/185
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "Test.framework/Resources", type: .symlink,
                          content: "Versions/Current/Resources", to: archive)
        try self.addEntry(with: "Test.framework/Versions/A/Resources/Info.plist", type: .file,
                          content: "plist", to: archive)
        try self.addEntry(with: "Test.framework/Versions/Current", type: .symlink, content: "A", to: archive)
        XCTAssertNoThrow(try fileManager.unzipItem(at: archive.url, to: destinationURL))
        let infoURL = destinationURL.appendingPathComponent("Test.framework/Resources/Info.plist")
        XCTAssert(fileManager.fileExists(atPath: infoURL.path))
    }

    func testSymlinkContainmentWithUnresolvablePaths() throws {
        let fileManager = FileManager()
        let directoryURL = self.createDirectory(for: #function)
        let loopURL = directoryURL.appendingPathComponent("loop")
        try fileManager.createSymbolicLink(atPath: loopURL.path, withDestinationPath: "loop")
        XCTAssertNil(URL.resolvedPathComponents(ofPath: loopURL.path))
        // Reject an unresolvable containment root, link parent, or link destination.
        XCTAssertFalse(URL.isSymlinkDestination("file", ofSymlinkIn: directoryURL, containedIn: loopURL))
        XCTAssertFalse(URL.isSymlinkDestination("file", ofSymlinkIn: loopURL, containedIn: directoryURL))
        XCTAssertFalse(URL.isSymlinkDestination("loop", ofSymlinkIn: directoryURL, containedIn: directoryURL))
        XCTAssertTrue(URL.isSymlinkDestination("loop", ofSymlinkIn: directoryURL, containedIn: .rootFS))
    }

    func testUnzipIntoSymlinkLoop() throws {
        let fileManager = FileManager()
        let directoryURL = self.createDirectory(for: #function)
        let loopURL = directoryURL.appendingPathComponent("loop")
        try fileManager.createSymbolicLink(atPath: loopURL.path, withDestinationPath: "loop")
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "file.txt", type: .file, content: "contained", to: archive)
        XCTAssertCocoaError(try fileManager.unzipItem(at: archive.url, to: loopURL),
                            throwsErrorWithCode: .fileReadInvalidFileName)
        XCTAssertEqual(try fileManager.destinationOfSymbolicLink(atPath: loopURL.path), "loop")
    }

    func testContainmentOfAbsolutePaths() throws {
        let directoryURL = self.createDirectory(for: #function)
        let components = try XCTUnwrap(URL.resolvedPathComponents(ofPath: directoryURL.path))
        XCTAssertTrue(directoryURL.isContained(in: directoryURL, resolvedTo: components))
        let siblingURL = URL(fileURLWithPath: directoryURL.path + "Sibling/file.txt")
        XCTAssertFalse(siblingURL.isContained(in: directoryURL, resolvedTo: components))
        XCTAssertFalse(directoryURL.deletingLastPathComponent().isContained(in: directoryURL, resolvedTo: components))
        // The path of the root directory already ends with a path delimiter.
        let rootEntryURL = URL.rootFS.appendingPathComponent("zipfoundation-missing/../file.txt")
        XCTAssertTrue(rootEntryURL.isContained(in: .rootFS, resolvedTo: []))
    }

    func testUnzipEntryWithParentReference() throws {
        let fileManager = FileManager()
        let directoryURL = self.createDirectory(for: #function)
        let destinationURL = directoryURL.appendingPathComponent("destination")
        // The directories that precede `..` don't exist before the entries are extracted.
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "missing/../file.txt", type: .file, content: "contained", to: archive)
        try self.addEntry(with: "a/b/../../c/../other.txt", type: .file, content: "contained", to: archive)
        XCTAssertNoThrow(try fileManager.unzipItem(at: archive.url, to: destinationURL))
        XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent("file.txt")))
        XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent("other.txt")))
        let escapingArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "absent/../../escaped.txt", type: .file, content: "escaped", to: escapingArchive)
        XCTAssertCocoaError(try fileManager.unzipItem(at: escapingArchive.url, to: destinationURL),
                            throwsErrorWithCode: .fileReadInvalidFileName)
        XCTAssertFalse(fileManager.itemExists(at: directoryURL.appendingPathComponent("escaped.txt")))
        // The components that follow `..` are resolved through the file system again.
        let outsideURL = directoryURL.appendingPathComponent("outside")
        try fileManager.createDirectory(at: outsideURL, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createSymbolicLink(atPath: destinationURL.appendingPathComponent("link").path,
                                           withDestinationPath: "../outside")
        let linkArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "absent/../link/escaped.txt", type: .file, content: "escaped", to: linkArchive)
        XCTAssertCocoaError(try fileManager.unzipItem(at: linkArchive.url, to: destinationURL),
                            throwsErrorWithCode: .fileReadInvalidFileName)
        XCTAssertFalse(fileManager.itemExists(at: outsideURL.appendingPathComponent("escaped.txt")))
        // A missing directory must not be created outside of the destination, even if the path returns to it.
        let returningArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "../created-outside/../destination/escaped.txt", type: .file, content: "escaped",
                          to: returningArchive)
        XCTAssertCocoaError(try fileManager.unzipItem(at: returningArchive.url, to: destinationURL),
                            throwsErrorWithCode: .fileReadInvalidFileName)
        XCTAssertFalse(fileManager.itemExists(at: directoryURL.appendingPathComponent("created-outside")))
        XCTAssertFalse(fileManager.itemExists(at: destinationURL.appendingPathComponent("escaped.txt")))
        // A symlink entry can be located behind a missing directory as well. Its destination is contained.
        let symlinkArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "target.txt", type: .file, content: "contained", to: symlinkArchive)
        try self.addEntry(with: "vacant/../alias", type: .symlink, content: "target.txt", to: symlinkArchive)
        XCTAssertNoThrow(try fileManager.unzipItem(at: symlinkArchive.url, to: destinationURL))
        let aliasURL = destinationURL.appendingPathComponent("alias")
        XCTAssertEqual(try? fileManager.destinationOfSymbolicLink(atPath: aliasURL.path), "target.txt")
        // The destination of the caller can contain a missing directory that is followed by `..`.
        let indirectURL = directoryURL.appendingPathComponent("vacant/../indirect")
        XCTAssertNoThrow(try fileManager.unzipItem(at: symlinkArchive.url, to: indirectURL))
        let indirectAliasURL = directoryURL.appendingPathComponent("indirect/alias")
        XCTAssertEqual(try? fileManager.destinationOfSymbolicLink(atPath: indirectAliasURL.path), "target.txt")
        XCTAssert(fileManager.itemExists(at: directoryURL.appendingPathComponent("indirect/target.txt")))
    }

    func testUnzipEntryWithLeadingCombiningMark() throws {
        let fileName = "\u{0301}notes.txt"
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: fileName, type: .file, content: "notes", to: archive)
        let destinationURL = self.createDirectory(for: #function)
        try FileManager().unzipItem(at: archive.url, to: destinationURL)
        XCTAssertEqual(try Data(contentsOf: destinationURL.appendingPathComponent(fileName)), Data("notes".utf8))
        let parent = try XCTUnwrap(URL.resolvedPathComponents(ofPath: destinationURL.path))
        XCTAssertEqual(URL.resolvedPathComponents(ofPath: "nested/" + fileName, relativeTo: parent),
                       parent + ["nested", fileName])
    }

    func testUnzipEntryIntoDirectoryAlias() throws {
        try self.checkUnzipEntry(into: "cafe\u{0301}", alsoSpelled: "caf\u{00E9}")
        try self.checkUnzipEntry(into: "destination", alsoSpelled: "Destination")
    }

    private func checkUnzipEntry(into name: String, alsoSpelled siblingName: String) throws {
        let fileManager = FileManager()
        let directoryURL = self.createDirectory(for: #function)
        let destinationURL = directoryURL.appendingPathComponent(name)
        let siblingURL = directoryURL.appendingPathComponent(siblingName)
        XCTAssertFalse(URL.isSymlinkDestination("../" + siblingName, ofSymlinkIn: destinationURL,
                                                containedIn: destinationURL))
        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
        let entryArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "../" + siblingName + "/entry.txt", type: .file, content: "entry", to: entryArchive)
        let symlinkArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link", type: .symlink, content: "../" + siblingName, to: symlinkArchive)
#if canImport(Darwin)
        // Only the destination has been created, so a successful lookup means the names are aliases.
        var info = stat()
        if lstat(siblingURL.path, &info) == 0 {
            XCTAssertNoThrow(try fileManager.unzipItem(at: entryArchive.url, to: destinationURL))
            XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent("entry.txt")))
            XCTAssertNoThrow(try fileManager.unzipItem(at: symlinkArchive.url, to: destinationURL))
            return
        }
#endif
        try fileManager.createDirectory(at: siblingURL, withIntermediateDirectories: true, attributes: nil)
        XCTAssertCocoaError(try fileManager.unzipItem(at: entryArchive.url, to: destinationURL),
                            throwsErrorWithCode: .fileReadInvalidFileName)
        XCTAssertFalse(fileManager.itemExists(at: siblingURL.appendingPathComponent("entry.txt")))
        XCTAssertSwiftError(try fileManager.unzipItem(at: symlinkArchive.url, to: destinationURL),
                            throws: Archive.ArchiveError.uncontainedSymlink)
        XCTAssertFalse(fileManager.itemExists(at: destinationURL.appendingPathComponent("link")))
    }

    func testUnzipEntryWithoutName() throws {
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function).appendingPathComponent("destination")
        // An entry without a name would refer to the destination directory itself.
        for (path, type) in [("", Entry.EntryType.file), ("/", .directory)] {
            let archive = self.archive(for: #function, mode: .create)
            try self.addEntry(with: path, type: type, content: type == .file ? "file" : "", to: archive)
            XCTAssertCocoaError(try fileManager.unzipItem(at: archive.url, to: destinationURL),
                                throwsErrorWithCode: .fileReadInvalidFileName)
            XCTAssertFalse(fileManager.itemExists(at: destinationURL))
        }
    }

    func testUnzipSymlinkWithInvalidDestination() throws {
        let fileManager = FileManager()
        let destinationURL = self.createDirectory(for: #function)
        let linkURL = destinationURL.appendingPathComponent("link")
        let emptyArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link", type: .symlink, content: "", to: emptyArchive)
        XCTAssertSwiftError(try fileManager.unzipItem(at: emptyArchive.url, to: destinationURL),
                            throws: Archive.ArchiveError.uncontainedSymlink)
        XCTAssertFalse(fileManager.itemExists(at: linkURL))
        // A destination with a NUL byte can't be represented as a file system path.
        let nulArchive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link", type: .symlink, content: "tar\0get", to: nulArchive)
        XCTAssertSwiftError(try fileManager.unzipItem(at: nulArchive.url, to: destinationURL),
                            throws: Archive.ArchiveError.invalidEntryPath)
        XCTAssertFalse(fileManager.itemExists(at: linkURL))
        // A destination that exceeds the size limit is rejected before it is read.
        let longArchive = self.archive(for: #function, mode: .create)
        let longDestination = String(repeating: "a", count: maxSymbolicLinkDestinationSize + 1)
        try self.addEntry(with: "link", type: .symlink, content: longDestination, to: longArchive)
        XCTAssertSwiftError(try fileManager.unzipItem(at: longArchive.url, to: destinationURL),
                            throws: Archive.ArchiveError.invalidEntryPath)
        // The compressed symlink of the test archive states a small size, but expands to a long destination.
        let compressedArchive = self.archive(for: #function, mode: .update)
        let entry = try XCTUnwrap(compressedArchive["link"])
        XCTAssertGreaterThan(entry.uncompressedSize, UInt64(maxSymbolicLinkDestinationSize))
        let smallEntry = try XCTUnwrap(self.entry(entry, withUncompressedSize: 8))
        XCTAssertSwiftError(try compressedArchive.extract(smallEntry, to: linkURL),
                            throws: Archive.ArchiveError.invalidEntryPath)
        XCTAssertFalse(fileManager.itemExists(at: linkURL))
    }

    func testExtractStoredSymlinkWithOversizedLocalHeader() throws {
        // The local file header states a size of 4 GiB. The central directory states the actual size.
        let archive = self.archive(for: #function, mode: .read)
        let entry = try XCTUnwrap(archive["link"])
        XCTAssertEqual(entry.localFileHeader.compressedSize, UInt32.max)
        var data = Data()
        let checksum = try archive.extract(entry, bufferSize: 2) { chunk in
            XCTAssertLessThanOrEqual(chunk.count, 2)
            data.append(chunk)
        }
        XCTAssertEqual(data, Data("target".utf8))
        XCTAssertEqual(checksum, entry.checksum)
        let linkURL = self.createDirectory(for: #function).appendingPathComponent("link")
        _ = try archive.extract(entry, to: linkURL)
        XCTAssertEqual(try FileManager().destinationOfSymbolicLink(atPath: linkURL.path), "target")
    }

    func testExtractStoredZIP64Symlink() throws {
        // The central directory states the sizes in ZIP64 extended information.
        let archive = self.archive(for: #function, mode: .read)
        let entry = try XCTUnwrap(archive["link"])
        XCTAssertEqual(entry.centralDirectoryStructure.compressedSize, UInt32.max)
        XCTAssertEqual(entry.zip64ExtendedInformation?.compressedSize, 6)
        var data = Data()
        let checksum = try archive.extract(entry) { data.append($0) }
        XCTAssertEqual(data, Data("target".utf8))
        XCTAssertEqual(checksum, entry.checksum)
    }

    func testExtractStoredSymlinkWithWrongUncompressedSize() throws {
        // Some writers stored a wrong uncompressed size for symlinks. The compressed size is used instead.
        let archive = self.archive(for: #function, mode: .create)
        try self.addEntry(with: "link", type: .symlink, content: "target", to: archive)
        let reportedSize = UInt32(maxSymbolicLinkDestinationSize + 1)
        let entry = try XCTUnwrap(self.entry(XCTUnwrap(archive["link"]), withUncompressedSize: reportedSize))
        let progress = archive.makeProgressForReading(entry)
        var data = Data()
        _ = try archive.extract(entry, bufferSize: 2, progress: progress) { data.append($0) }
        XCTAssertEqual(data, Data("target".utf8))
        XCTAssertEqual(progress.completedUnitCount, 6)
        XCTAssertEqual(progress.totalUnitCount, 6)
        let linkURL = self.createDirectory(for: #function).appendingPathComponent("link")
        _ = try archive.extract(entry, to: linkURL)
        XCTAssertEqual(try FileManager().destinationOfSymbolicLink(atPath: linkURL.path), "target")
    }

    func testDeprecatedContainmentCheck() {
        let directoryURL = self.createDirectory(for: #function)
        XCTAssertTrue(directoryURL.appendingPathComponent("file.txt").isContained(in: directoryURL))
        XCTAssertFalse(directoryURL.appendingPathComponent("../file.txt").isContained(in: directoryURL))
        // The containing directory can't be resolved, because `..` follows a component that doesn't exist.
        let unresolvableURL = directoryURL.appendingPathComponent("missing/../directory")
        XCTAssertFalse(unresolvableURL.appendingPathComponent("file.txt").isContained(in: unresolvableURL))
    }

    // MARK: - Helpers

    /// Returns a copy of `entry` whose central directory structure states a different uncompressed size.
    private func entry(_ entry: Entry, withUncompressedSize size: UInt32) -> Entry? {
        var data = entry.centralDirectoryStructure.data
        withUnsafeBytes(of: size.littleEndian) { data.replaceSubrange(24..<28, with: $0) }
        let structureSize = Entry.CentralDirectoryStructure.size
        let structure = Entry.CentralDirectoryStructure(data: data.prefix(structureSize)) { _ in
            return Data(data.dropFirst(structureSize))
        }
        return structure.flatMap { Entry(centralDirectoryStructure: $0, localFileHeader: entry.localFileHeader) }
    }

    func addEntry(with path: String, type: Entry.EntryType, content: String = "",
                  to archive: Archive) throws {
        let data = Data(content.utf8)
        try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count),
                             provider: { (position, size) -> Data in
            return data.subdata(in: Int(position)..<Int(position) + size)
        })
    }
}
