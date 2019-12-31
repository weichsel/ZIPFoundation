//
//  ZIPFoundationMemoryTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2020 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

import XCTest
@testable import ZIPFoundation

#if swift(>=5.0)

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

    func testMemoryArchiveErrorConditions() {
        let data = Data.makeRandomData(size: 1024)
        let invalidArchive = Archive(data: data, accessMode: .read)
        XCTAssertNil(invalidArchive)
        // Trigger the code path that is taken if funopen() fails
        // We can only do this on Apple platforms
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let systemAllocator = CFAllocatorGetDefault().takeUnretainedValue()
        CFAllocatorSetDefault(kCFAllocatorNull)
        let unallocatableArchive = Archive(data: data, accessMode: .read)
        CFAllocatorSetDefault(systemAllocator)
        XCTAssertNil(unallocatableArchive)
        #endif
    }

    func testReadOnlyFile() {
        let file = MemoryFile(data: "ABCDEabcde".data(using: .utf8)!).open(mode: "r")
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

    func testReadOnlySlicedFile() {
        let originalData = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".data(using: .utf8)!
        let slice = originalData[10..<originalData.count]
        let file = MemoryFile(data: slice).open(mode: "r")
        var chars: [UInt8] = [0, 0, 0]
        XCTAssertEqual(fread(&chars, 1, 2, file), 2)
        XCTAssertEqual(String(Unicode.Scalar(chars[0])), "A")
        XCTAssertEqual(String(Unicode.Scalar(chars[1])), "B")
    }

    func testWriteOnlyFile() {
        let mem  = MemoryFile()
        let file = mem.open(mode: "w")
        XCTAssertEqual(fwrite("01234", 1, 5, file), 5)
        XCTAssertEqual(fseek(file, -2, SEEK_END), 0)
        XCTAssertEqual(fwrite("5678", 1, 4, file), 4)
        XCTAssertEqual(fwrite("9", 1, 1, file), 1)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, "01256789".data(using: .utf8))
    }

    func testReadWriteFile() {
        let mem  = MemoryFile(data: "witch".data(using: .utf8)!)
        let file = mem.open(mode: "r+")
        XCTAssertEqual(fseek(file, 1, SEEK_CUR), 0)
        XCTAssertEqual(fwrite("a", 1, 1, file), 1)
        XCTAssertEqual(fseek(file, 0, SEEK_END), 0)
        XCTAssertEqual(fwrite("face", 1, 4, file), 4)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, "watchface".data(using: .utf8))
    }

    func testAppendFile() {
        let mem  = MemoryFile(data: "anti".data(using: .utf8)!)
        let file = mem.open(mode: "a+")
        XCTAssertEqual(fwrite("cipation", 1, 8, file), 8)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, "anticipation".data(using: .utf8))
    }
}

// MARK: - Helpers

extension ZIPFoundationTests {
    func memoryArchive(for testFunction: String, mode: Archive.AccessMode,
                       preferredEncoding: String.Encoding? = nil) -> Archive {
        var sourceArchiveURL = ZIPFoundationTests.resourceDirectoryURL
        sourceArchiveURL.appendPathComponent(testFunction.replacingOccurrences(of: "()", with: ""))
        sourceArchiveURL.appendPathExtension("zip")
        do {
            let data = mode == .create ? Data() : try Data(contentsOf: sourceArchiveURL)
            guard let archive = Archive(data: data, accessMode: mode,
                                        preferredEncoding: preferredEncoding) else {
                                            throw Archive.ArchiveError.unreadableArchive
            }
            return archive
        } catch {
            XCTFail("Failed to open memory archive for '\(sourceArchiveURL.lastPathComponent)'")
            type(of: self).tearDown()
            preconditionFailure()
        }
    }
}

#endif
