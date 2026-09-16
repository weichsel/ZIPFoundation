//
//  ZIPFoundationMemoryTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

import XCTest
@testable import ZIPFoundation

#if swift(>=5.0) && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || os(Linux))

extension ZIPFoundationTests {

    func testExtractUncompressedFolderEntriesFromMemory() {
        let archive = self.memoryArchive(for: #function, mode: .read)
        for entry in archive {
            do {
                // Test extracting to memory
                var checksum = try archive.extract(entry, bufferSize: 32, consumer: { _ in })
                XCTAssert(entry.checksum == checksum)
                // Test extracting to file
                var fileURL = self.createDirectory(for: #function)
                fileURL.appendPathComponent(entry.path)
                checksum = try archive.extract(entry, to: fileURL)
                XCTAssert(entry.checksum == checksum)
                let fileManager = FileManager()
                XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
                if entry.type == .file {
                    let fileData = try Data(contentsOf: fileURL)
                    let checksum = fileData.crc32(checksum: 0)
                    XCTAssert(checksum == entry.checksum)
                }
            } catch {
                XCTFail("Failed to unzip uncompressed folder entries")
            }
        }
        XCTAssert(archive.data != nil)
    }

    func testExtractCompressedFolderEntriesFromMemory() {
        let archive = self.memoryArchive(for: #function, mode: .read)
        for entry in archive {
            do {
                // Test extracting to memory
                var checksum = try archive.extract(entry, bufferSize: 128, consumer: { _ in })
                XCTAssert(entry.checksum == checksum)
                // Test extracting to file
                var fileURL = self.createDirectory(for: #function)
                fileURL.appendPathComponent(entry.path)
                checksum = try archive.extract(entry, to: fileURL)
                XCTAssert(entry.checksum == checksum)
                let fileManager = FileManager()
                XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
                if entry.type != .directory {
                    let fileData = try Data(contentsOf: fileURL)
                    let checksum = fileData.crc32(checksum: 0)
                    XCTAssert(checksum == entry.checksum)
                }
            } catch {
                XCTFail("Failed to unzip compressed folder entries")
            }
        }
    }

    func testCreateArchiveAddUncompressedEntryToMemory() {
        let archive = self.memoryArchive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL)
        } catch {
            XCTFail("Failed to add entry to uncompressed folder archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testCreateArchiveAddCompressedEntryToMemory() {
        let archive = self.memoryArchive(for: #function, mode: .create)
        let assetURL = self.resourceURL(for: #function, pathExtension: "png")
        do {
            let relativePath = assetURL.lastPathComponent
            let baseURL = assetURL.deletingLastPathComponent()
            try archive.addEntry(with: relativePath, relativeTo: baseURL, compressionMethod: .deflate)
        } catch {
            XCTFail("Failed to add entry to compressed folder archive with error : \(error)")
        }
        let entry = archive[assetURL.lastPathComponent]
        XCTAssertNotNil(entry)
        XCTAssert(archive.checkIntegrity())
    }

    func testUpdateArchiveRemoveUncompressedEntryFromMemory() throws {
        let archive = self.memoryArchive(for: #function, mode: .update)
        XCTAssert(archive.checkIntegrity())
        guard let entryToRemove = archive["original"] else {
            XCTFail("Failed to find entry to remove from memory archive"); return
        }
        do {
            try archive.remove(entryToRemove)
        } catch {
            XCTFail("Failed to remove entry from memory archive with error : \(error)")
        }
        XCTAssert(archive.checkIntegrity())
    }

    func testMemoryArchiveErrorConditions() throws {
        let data = Data.makeRandomData(size: 1024)
        XCTAssertSwiftError(try Archive(data: data, accessMode: .read),
                            throws: Archive.ArchiveError.missingEndOfCentralDirectoryRecord)
        let archive = self.memoryArchive(for: #function, mode: .create)
        let replacementArchive = self.memoryArchive(for: #function, mode: .read)
        replacementArchive.memoryFile = nil
        XCTAssertSwiftError(
            try archive.replaceCurrentArchive(with: replacementArchive),
            throws: Archive.ArchiveError.unwritableArchive
        )

        var noEndOfCentralDirectoryArchiveURL = ZIPFoundationTests.tempZipDirectoryURL
        noEndOfCentralDirectoryArchiveURL.appendPathComponent(ProcessInfo.processInfo.globallyUniqueString)
        let fullPermissionAttributes = [FileAttributeKey.posixPermissions: NSNumber(value: defaultFilePermissions)]
        FileManager().createFile(atPath: noEndOfCentralDirectoryArchiveURL.path, contents: nil,
                                 attributes: fullPermissionAttributes)
        let noEOCDArchiveData = try Data(contentsOf: noEndOfCentralDirectoryArchiveURL)
        XCTAssertSwiftError(try Archive(data: noEOCDArchiveData, accessMode: .update),
                            throws: Archive.ArchiveError.missingEndOfCentralDirectoryRecord)
    }

    func testReadOnlyFile() throws {
        let file = try Archive.MemoryFile(data: Data("ABCDEabcde".utf8)).open(mode: .read)
        var chars: [UInt8] = [0, 0, 0]
        XCTAssertEqual(fread(&chars, 1, 2, file), 2)
        XCTAssertEqual(String(Unicode.Scalar(chars[0])), "A")
        XCTAssertEqual(String(Unicode.Scalar(chars[1])), "B")
        XCTAssertNotEqual(fwrite("x", 1, 1, file), 1)
        XCTAssertEqual(fseek(file, 3, SEEK_CUR), 0)
        XCTAssertEqual(fread(&chars, 1, 2, file), 2)
        XCTAssertEqual(String(Unicode.Scalar(chars[0])), "a")
        XCTAssertEqual(String(Unicode.Scalar(chars[1])), "b")
        XCTAssertEqual(fseek(file, 9, SEEK_SET), 0)
        XCTAssertEqual(fread(&chars, 1, 2, file), 1)
        XCTAssertEqual(String(Unicode.Scalar(chars[0])), "e")
        XCTAssertEqual(String(Unicode.Scalar(chars[1])), "b")
        XCTAssertEqual(fclose(file), 0)
    }

    func testReadOnlySlicedFile() throws {
        let originalData = Data("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)
        let slice = originalData[10..<originalData.count]
        let file = try Archive.MemoryFile(data: slice).open(mode: .read)
        var chars: [UInt8] = [0, 0, 0]
        XCTAssertEqual(fread(&chars, 1, 2, file), 2)
        XCTAssertEqual(String(Unicode.Scalar(chars[0])), "A")
        XCTAssertEqual(String(Unicode.Scalar(chars[1])), "B")
    }

    func testReadPastEndOfMemoryFile() throws {
        let originalData = Data("01234ABCDE".utf8)
        let inputs = [Data(), Data("ABCDE".utf8), originalData[5..<originalData.count]]
        for data in inputs {
            let file = try Archive.MemoryFile(data: data).open(mode: .read)
            defer { fclose(file) }
            var buffer = [UInt8](repeating: 0, count: 3)
            for offset in [data.count, data.count + 1, Int(Int32.max)] {
                XCTAssertEqual(fseek(file, offset, SEEK_SET), 0)
                XCTAssertEqual(fread(&buffer, 1, buffer.count, file), 0)
                XCTAssertNotEqual(feof(file), 0)
                XCTAssertEqual(ferror(file), 0)
                XCTAssertEqual(ftell(file), offset)
            }
            // Reading past EOF must not prevent seeking back to valid data.
            XCTAssertEqual(fseek(file, 0, SEEK_SET), 0)
            XCTAssertEqual(feof(file), 0)
            let count = fread(&buffer, 1, buffer.count, file)
            XCTAssertEqual(count, min(data.count, buffer.count))
            XCTAssertEqual(Array(buffer.prefix(count)), Array(data.prefix(buffer.count)))
        }
    }

    func testMemoryArchiveWithLocalHeaderBeyondEOF() throws {
        let archive = try Archive(accessMode: .create)
        let contents = Data("test".utf8)
        try archive.addEntry(with: "test.txt", type: .file,
                             uncompressedSize: Int64(contents.count)) { position, size in
            contents.subdata(in: Int(position)..<(Int(position) + size))
        }
        var data = try XCTUnwrap(archive.data)
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        let directoryOffset = try XCTUnwrap(data.range(of: signature)?.lowerBound)
        // Point the local file header beyond the end of the archive.
        data.replaceSubrange((directoryOffset + 42)..<(directoryOffset + 46),
                             with: [0xff, 0xff, 0xff, 0x7f])
        let reader = try Archive(data: data, accessMode: .read)
        XCTAssertNil(reader.makeIterator().next())
    }

    func testWriteOnlyFile() throws {
        let mem = Archive.MemoryFile()
        let file = try mem.open(mode: .create)
        XCTAssertEqual(fwrite("01234", 1, 5, file), 5)
        XCTAssertEqual(fseek(file, -2, SEEK_END), 0)
        XCTAssertEqual(fwrite("5678", 1, 4, file), 4)
        XCTAssertEqual(fwrite("9", 1, 1, file), 1)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, Data("01256789".utf8))
    }

    func testReadWriteFile() throws {
        let mem = Archive.MemoryFile(data: Data("witch".utf8))
        let file = try mem.open(mode: .update)
        XCTAssertEqual(fseek(file, 1, SEEK_CUR), 0)
        XCTAssertEqual(fwrite("a", 1, 1, file), 1)
        XCTAssertEqual(fseek(file, 0, SEEK_END), 0)
        XCTAssertEqual(fwrite("face", 1, 4, file), 4)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, Data("watchface".utf8))
        // Also exercise the codepath where we explicitly seek beyond `data.count`
        XCTAssertEqual(fseek(file, 10, SEEK_SET), 0)
        XCTAssertEqual(fwrite("x", 1, 1, file), 1)
        XCTAssertEqual(fseek(file, 2, SEEK_SET), 0)
        XCTAssertEqual(fwrite("watchfaces", 10, 1, file), 1)
        XCTAssertEqual(fseek(file, 2, SEEK_SET), 0)
        XCTAssertEqual(fclose(file), 0)
    }
}

// MARK: - Helpers

extension ZIPFoundationTests {

    func memoryArchive(for testFunction: String, mode: Archive.AccessMode,
                       pathEncoding: String.Encoding? = nil) -> Archive {
        var sourceArchiveURL = ZIPFoundationTests.resourceDirectoryURL
        sourceArchiveURL.appendPathComponent(testFunction.replacingOccurrences(of: "()", with: ""))
        sourceArchiveURL.appendPathExtension("zip")
        do {
            let data = mode == .create ? Data() : try Data(contentsOf: sourceArchiveURL)
            return try Archive(data: data, accessMode: mode,
                               pathEncoding: pathEncoding)
        } catch {
            XCTFail("Failed to open memory archive for '\(sourceArchiveURL.lastPathComponent)'")
            type(of: self).tearDown()
            preconditionFailure()
        }
    }
}

#endif
