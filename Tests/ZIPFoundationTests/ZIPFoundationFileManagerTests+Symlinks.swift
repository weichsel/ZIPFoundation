//
//  ZIPFoundationFileManagerTests+Symlinks.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
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
        XCTAssert(fileManager.itemExists(at: destinationURL.appendingPathComponent("dangling")))
    }

    // MARK: - Helpers

    private func addEntry(with path: String, type: Entry.EntryType, content: String = "",
                          to archive: Archive) throws {
        let data = Data(content.utf8)
        try archive.addEntry(with: path, type: type, uncompressedSize: Int64(data.count),
                             provider: { (position, size) -> Data in
            return data.subdata(in: Int(position)..<Int(position) + size)
        })
    }
}
