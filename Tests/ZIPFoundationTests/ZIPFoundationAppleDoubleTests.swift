//
//  ZIPFoundationAppleDoubleTests.swift
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

    func testAppleDoubleCompanionPathDerivation() {
        XCTAssertEqual(FileManager.appleDoubleCompanionPath(forEntryPath: "foo.txt"),
                       "__MACOSX/._foo.txt")
        XCTAssertEqual(FileManager.appleDoubleCompanionPath(forEntryPath: "dir/foo.txt"),
                       "__MACOSX/dir/._foo.txt")
        XCTAssertEqual(FileManager.appleDoubleCompanionPath(forEntryPath: "dir/sub/foo.txt"),
                       "__MACOSX/dir/sub/._foo.txt")
        // Trailing slash (directory entries) is stripped so the companion itself is a file.
        XCTAssertEqual(FileManager.appleDoubleCompanionPath(forEntryPath: "dir/"),
                       "__MACOSX/._dir")
        XCTAssertEqual(FileManager.appleDoubleCompanionPath(forEntryPath: "dir/sub/"),
                       "__MACOSX/dir/._sub")
        // Companions never nest.
        XCTAssertNil(FileManager.appleDoubleCompanionPath(forEntryPath: "__MACOSX/._foo"))
        XCTAssertNil(FileManager.appleDoubleCompanionPath(forEntryPath: "__MACOSX"))
        XCTAssertNil(FileManager.appleDoubleCompanionPath(forEntryPath: ""))
        XCTAssertNil(FileManager.appleDoubleCompanionPath(forEntryPath: "/"))
    }

    func testRealEntryPathFromCompanion() {
        XCTAssertEqual(FileManager.realEntryPath(fromAppleDoubleCompanionPath: "__MACOSX/._foo.txt"),
                       "foo.txt")
        XCTAssertEqual(FileManager.realEntryPath(fromAppleDoubleCompanionPath: "__MACOSX/dir/._foo.txt"),
                       "dir/foo.txt")
        XCTAssertEqual(FileManager.realEntryPath(fromAppleDoubleCompanionPath: "__MACOSX/dir/sub/._foo.txt"),
                       "dir/sub/foo.txt")
        XCTAssertNil(FileManager.realEntryPath(fromAppleDoubleCompanionPath: "foo.txt"))
        XCTAssertNil(FileManager.realEntryPath(fromAppleDoubleCompanionPath: "__MACOSX/foo.txt"))
        XCTAssertNil(FileManager.realEntryPath(fromAppleDoubleCompanionPath: "__MACOSX/"))
        XCTAssertNil(FileManager.realEntryPath(fromAppleDoubleCompanionPath: "__MACOSX/._"))
    }

    func testAppleDoubleEncodingRoundTrip() {
        let finderInfo = Data([0x54, 0x45, 0x58, 0x54, 0x21, 0x52, 0x63, 0x68] + [UInt8](repeating: 0, count: 24))
        let resourceFork = Data("fake-resource-fork-bytes".utf8)
        let xattrs: [(name: String, data: Data)] = [
            ("com.example.single", Data("abc".utf8)),
            ("com.example.multi", Data([0x00, 0xFF, 0x42, 0x01, 0x02, 0x03, 0x04]))
        ]
        let payload = AppleDoublePayload(finderInfo: finderInfo,
                                         resourceFork: resourceFork,
                                         extendedAttributes: xattrs)
        let encoded = payload.encode()
        let decoded = AppleDoublePayload.decode(encoded)
        XCTAssertNotNil(decoded)
        guard let decoded else { return }
        XCTAssertEqual(decoded.finderInfo, finderInfo)
        XCTAssertEqual(decoded.resourceFork, resourceFork)
        XCTAssertEqual(decoded.extendedAttributes.count, xattrs.count)
        for (actual, expected) in zip(decoded.extendedAttributes, xattrs) {
            XCTAssertEqual(actual.name, expected.name)
            XCTAssertEqual(actual.data, expected.data)
        }
    }

    func testAppleDoubleEncodingEmptyFinderInfoIgnored() {
        // Zero-filled FinderInfo round-trips as "no finder info" — it carries no information and
        // matches what Apple-produced AppleDouble files typically encode.
        let xattrs: [(name: String, data: Data)] = [("com.example.only", Data([0xAB, 0xCD]))]
        let payload = AppleDoublePayload(finderInfo: nil, resourceFork: nil, extendedAttributes: xattrs)
        let encoded = payload.encode()
        let decoded = AppleDoublePayload.decode(encoded)
        XCTAssertNil(decoded?.finderInfo)
        XCTAssertEqual(decoded?.extendedAttributes.count, 1)
        XCTAssertEqual(decoded?.extendedAttributes.first?.name, "com.example.only")
        XCTAssertEqual(decoded?.extendedAttributes.first?.data, Data([0xAB, 0xCD]))
    }

    func testAppleDoubleDecodeRejectsBadMagic() {
        var data = AppleDoublePayload(resourceFork: Data([0x01])).encode()
        data[0] = 0x00 // Corrupt magic
        data[1] = 0x00
        data[2] = 0x00
        data[3] = 0x00
        XCTAssertNil(AppleDoublePayload.decode(data))
    }

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)

    func testZipItemPreservesXattrsOnDarwin() throws {
        let fileManager = FileManager()
        let sandbox = self.createDirectory(for: #function)
        let sourceDir = sandbox.appendingPathComponent("source", isDirectory: true)
        let extractDir = sandbox.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true, attributes: nil)

        let fileURL = sourceDir.appendingPathComponent("tagged.txt")
        try Data("hello".utf8).write(to: fileURL)

        let xattrValue = Data("annotation".utf8)
        try self.setXattr(name: "com.example.note", value: xattrValue, at: fileURL)

        let archiveURL = sandbox.appendingPathComponent("archive.zip")
        try fileManager.zipItem(at: sourceDir, to: archiveURL, shouldKeepParent: false)

        // Archive must include the AppleDouble companion.
        let archive = try Archive(url: archiveURL, accessMode: .read)
        XCTAssertNotNil(archive["__MACOSX/._tagged.txt"], "Expected AppleDouble companion in archive")

        // Extract and verify xattr round-trips.
        try fileManager.unzipItem(at: archiveURL, to: extractDir)
        let extractedFile = extractDir.appendingPathComponent("tagged.txt")
        XCTAssertTrue(fileManager.itemExists(at: extractedFile))
        // `__MACOSX` entries should not land on disk.
        XCTAssertFalse(fileManager.itemExists(at: extractDir.appendingPathComponent("__MACOSX")))

        let restored = self.getXattr(name: "com.example.note", at: extractedFile)
        XCTAssertEqual(restored, xattrValue)
    }

    func testZipItemPreservesResourceForkOnDarwin() throws {
        let fileManager = FileManager()
        let sandbox = self.createDirectory(for: #function)
        let sourceDir = sandbox.appendingPathComponent("source", isDirectory: true)
        let extractDir = sandbox.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: sourceDir, withIntermediateDirectories: true, attributes: nil)

        let fileURL = sourceDir.appendingPathComponent("resourced.bin")
        try Data("main-data".utf8).write(to: fileURL)

        // Write a resource fork by setting the special xattr.
        let rfBytes = Data([0x00, 0x00, 0x01, 0x00] + Array("RESOURCE-FORK-PAYLOAD".utf8))
        try self.setXattr(name: "com.apple.ResourceFork", value: rfBytes, at: fileURL)

        let archiveURL = sandbox.appendingPathComponent("archive.zip")
        try fileManager.zipItem(at: sourceDir, to: archiveURL, shouldKeepParent: false)

        try fileManager.unzipItem(at: archiveURL, to: extractDir)
        let extractedFile = extractDir.appendingPathComponent("resourced.bin")
        let restored = self.getXattr(name: "com.apple.ResourceFork", at: extractedFile)
        XCTAssertEqual(restored, rfBytes)
    }

    func testUnzipItemWithPreservesAppleMetadataFalse() throws {
        // Opting out of AppleDouble handling should fall back to the original behavior where
        // `__MACOSX` entries land on disk verbatim.
        let fileManager = FileManager()
        let archiveURL = self.resourceURL(for: "testUnzipItem", pathExtension: "zip")
        let destination = self.createDirectory(for: #function)
        try fileManager.unzipItem(at: archiveURL, to: destination, preservesAppleMetadata: false)
        XCTAssertTrue(fileManager.itemExists(at: destination.appendingPathComponent("__MACOSX")))
    }

    func testArchiveAddEntryAddsCompanionOnDarwin() throws {
        let fileManager = FileManager()
        let sandbox = self.createDirectory(for: #function)
        let fileURL = sandbox.appendingPathComponent("note.txt")
        try Data("payload".utf8).write(to: fileURL)
        let xattrValue = Data("user-annotation".utf8)
        try self.setXattr(name: "com.example.tag", value: xattrValue, at: fileURL)

        let archiveURL = sandbox.appendingPathComponent("archive.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "note.txt", relativeTo: sandbox)

        // Primary entry plus AppleDouble companion.
        XCTAssertNotNil(archive["note.txt"])
        XCTAssertNotNil(archive["__MACOSX/._note.txt"])
    }

    func testArchiveAddEntryRespectsPreservesAppleMetadataFalse() throws {
        let fileManager = FileManager()
        let sandbox = self.createDirectory(for: #function)
        let fileURL = sandbox.appendingPathComponent("plain.txt")
        try Data("payload".utf8).write(to: fileURL)
        try self.setXattr(name: "com.example.tag", value: Data("tag".utf8), at: fileURL)

        let archiveURL = sandbox.appendingPathComponent("archive.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "plain.txt", relativeTo: sandbox, preservesAppleMetadata: false)

        XCTAssertNotNil(archive["plain.txt"])
        XCTAssertNil(archive["__MACOSX/._plain.txt"])
    }

    func testArchiveExtractAppliesCompanion() throws {
        let fileManager = FileManager()
        let sandbox = self.createDirectory(for: #function)
        let sourceFile = sandbox.appendingPathComponent("doc.txt")
        try Data("content".utf8).write(to: sourceFile)
        let tag = Data("meta".utf8)
        try self.setXattr(name: "com.example.tag", value: tag, at: sourceFile)

        let archiveURL = sandbox.appendingPathComponent("archive.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "doc.txt", relativeTo: sandbox)

        // Extract only the real entry via the low-level API and verify xattr is applied.
        let destination = sandbox.appendingPathComponent("extracted/doc.txt")
        guard let realEntry = archive["doc.txt"] else {
            XCTFail("Missing real entry"); return
        }
        _ = try archive.extract(realEntry, to: destination)
        XCTAssertEqual(self.getXattr(name: "com.example.tag", at: destination), tag)
    }

    func testArchiveExtractWithoutPreservesAppleMetadataSkipsCompanion() throws {
        let fileManager = FileManager()
        let sandbox = self.createDirectory(for: #function)
        let sourceFile = sandbox.appendingPathComponent("doc.txt")
        try Data("content".utf8).write(to: sourceFile)
        try self.setXattr(name: "com.example.tag", value: Data("meta".utf8), at: sourceFile)

        let archiveURL = sandbox.appendingPathComponent("archive.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "doc.txt", relativeTo: sandbox)

        let destination = sandbox.appendingPathComponent("extracted/doc.txt")
        guard let realEntry = archive["doc.txt"] else { XCTFail("Missing real entry"); return }
        _ = try archive.extract(realEntry, to: destination, preservesAppleMetadata: false)
        XCTAssertNil(self.getXattr(name: "com.example.tag", at: destination))
    }

    func testArchiveExtractCompanionEntryItselfIsNotReinterpreted() throws {
        // Extracting the `__MACOSX/._name` entry itself should write it verbatim as an AppleDouble
        // file (the caller asked for that specific entry).
        let fileManager = FileManager()
        let sandbox = self.createDirectory(for: #function)
        let sourceFile = sandbox.appendingPathComponent("doc.txt")
        try Data("content".utf8).write(to: sourceFile)
        try self.setXattr(name: "com.example.tag", value: Data("meta".utf8), at: sourceFile)

        let archiveURL = sandbox.appendingPathComponent("archive.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "doc.txt", relativeTo: sandbox)

        guard let companion = archive["__MACOSX/._doc.txt"] else {
            XCTFail("Missing companion entry"); return
        }
        let outURL = sandbox.appendingPathComponent("raw-companion")
        _ = try archive.extract(companion, to: outURL)
        let rawData = try Data(contentsOf: outURL)
        XCTAssertNotNil(AppleDoublePayload.decode(rawData))
    }

    // MARK: - Helpers

    private func setXattr(name: String, value: Data, at url: URL) throws {
        let fsRep = FileManager().fileSystemRepresentation(withPath: url.path)
        let bytes = [UInt8](value)
        let result = bytes.withUnsafeBufferPointer { ptr -> Int32 in
            setxattr(fsRep, name, ptr.baseAddress, bytes.count, 0, XATTR_NOFOLLOW)
        }
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "setxattr failed for \(name)"])
        }
    }

    private func getXattr(name: String, at url: URL) -> Data? {
        let fsRep = FileManager().fileSystemRepresentation(withPath: url.path)
        let size = getxattr(fsRep, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size >= 0 else { return nil }
        if size == 0 { return Data() }
        var bytes = [UInt8](repeating: 0, count: size)
        let got = bytes.withUnsafeMutableBufferPointer { ptr -> ssize_t in
            guard let base = ptr.baseAddress else { return -1 }
            return getxattr(fsRep, name, base, ptr.count, 0, XATTR_NOFOLLOW)
        }
        guard got >= 0 else { return nil }
        if got < size { bytes.removeSubrange(Int(got)..<size) }
        return Data(bytes)
    }

#endif
}
