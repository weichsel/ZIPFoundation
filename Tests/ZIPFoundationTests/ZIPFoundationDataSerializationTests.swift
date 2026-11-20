//
//  ZIPFoundationDataSerializationTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
//

import XCTest
#if canImport(Android)
import Android
#endif
@testable import ZIPFoundation

extension ZIPFoundationTests {

    func testReadStructureErrorConditions() {
        let processInfo = ProcessInfo.processInfo
        let fileManager = FileManager()
        var fileURL = ZIPFoundationTests.tempZipDirectoryURL
        fileURL.appendPathComponent(processInfo.globallyUniqueString)
        let result = fileManager.createFile(atPath: fileURL.path, contents: Data(),
                                            attributes: nil)
        XCTAssert(result == true)
        let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
        let file: FILEPointer = fopen(fileSystemRepresentation, "rb")
        let unreachableStructure: Entry.CentralDirectoryStructure? = Data.readStruct(from: file, at: .max)
        XCTAssertNil(unreachableStructure)
        fclose(file)
        // Use a write-only file to exercise the error path during readStructure that deals with
        // unreadable file data.
        let writeOnlyFile: FILEPointer = fopen(fileSystemRepresentation, "wb")
        defer { fclose(writeOnlyFile) }
        let centralDirectoryStructure: Entry.CentralDirectoryStructure? = Data.readStruct(from: writeOnlyFile, at: 0)
        XCTAssertNil(centralDirectoryStructure)
    }

    func testReadChunkErrorConditions() {
        let processInfo = ProcessInfo.processInfo
        let fileManager = FileManager()
        var fileURL = ZIPFoundationTests.tempZipDirectoryURL
        fileURL.appendPathComponent(processInfo.globallyUniqueString)
        let result = fileManager.createFile(atPath: fileURL.path, contents: Data(),
                                            attributes: nil)
        XCTAssert(result == true)
        let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
        // Use a write-only file to exercise the error path during readChunk that deals with
        // unreadable file data.
        let file: FILEPointer = fopen(fileSystemRepresentation, "wb")
        defer { fclose(file) }
        XCTAssertSwiftError(try Data.readChunk(of: 10, from: file),
                            throws: Data.DataError.unreadableFile)
    }

    func testWriteChunkErrorConditions() {
        let processInfo = ProcessInfo.processInfo
        let fileManager = FileManager()
        var fileURL = ZIPFoundationTests.tempZipDirectoryURL
        fileURL.appendPathComponent(processInfo.globallyUniqueString)
        let result = fileManager.createFile(atPath: fileURL.path, contents: Data(),
                                            attributes: nil)
        XCTAssert(result == true)
        let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
        // Use a read-only file to exercise the error path during writeChunk that deals with
        // unwritable files.
        let file: FILEPointer = fopen(fileSystemRepresentation, "rb")
        defer { fclose(file) }
        XCTAssertSwiftError(try Data.write(chunk: Data(count: 10), to: file),
                            throws: Data.DataError.unwritableFile)
    }

    func testCRC32Calculation() {
        let dataURL = self.resourceURL(for: #function, pathExtension: "data")
        let data = (try? Data.init(contentsOf: dataURL)) ?? Data()
        XCTAssertEqual(data.crc32(checksum: 0), 1400077496)
        #if canImport(zlib)
        XCTAssertEqual(data.crc32(checksum: 0), data.builtInCRC32(checksum: 0))
        #endif
    }

    func testWriteLargeChunk() {
        let processInfo = ProcessInfo.processInfo
        let fileManager = FileManager()
        var fileURL = ZIPFoundationTests.tempZipDirectoryURL
        fileURL.appendPathComponent(processInfo.globallyUniqueString)
        let result = fileManager.createFile(atPath: fileURL.path, contents: Data(),
                                            attributes: nil)
        XCTAssert(result == true)
        let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
        let file: FILEPointer = fopen(fileSystemRepresentation, "rb+")
        let data = Data.makeRandomData(size: 1024)
        do {
            let writtenSize = try Data.writeLargeChunk(data, size: 1024, bufferSize: 256, to: file)
            XCTAssertEqual(writtenSize, 1024)
            fseeko(file, 0, SEEK_SET)
            let writtenData = try Data.readChunk(of: Int(writtenSize), from: file)
            XCTAssertEqual(writtenData, data)
        } catch {
            XCTFail("Unexpected error while testing to write into a closed file.")
        }
    }

    func testWriteLargeChunkErrorConditions() {
        let processInfo = ProcessInfo.processInfo
        let fileManager = FileManager()
        var fileURL = ZIPFoundationTests.tempZipDirectoryURL
        fileURL.appendPathComponent(processInfo.globallyUniqueString)
        let result = fileManager.createFile(atPath: fileURL.path, contents: Data(),
                                            attributes: nil)
        XCTAssert(result == true)
        let fileSystemRepresentation = fileManager.fileSystemRepresentation(withPath: fileURL.path)
        // Use a read-only file to exercise the error path during writeChunk that deals with
        // unwritable files.
        let file: FILEPointer = fopen(fileSystemRepresentation, "rb")
        defer { fclose(file) }
        let data = Data.makeRandomData(size: 1024)
        XCTAssertSwiftError(try Data.writeLargeChunk(data, size: 1024, bufferSize: 256, to: file),
                            throws: Data.DataError.unwritableFile)
    }

    /// Consumers can keep the data they receive. A chunk must not change when the next chunk is processed.
    func testConsumersCanKeepProcessedData() throws {
        let bufferSize = 1024
        let data = Data.makeRandomData(size: bufferSize * 16)
        let provider: (Data) -> Provider = { source in
            return { position, size in
                let lowerBound = Int(position)
                let upperBound = Swift.min(source.count, lowerBound + size)
                return source.subdata(in: lowerBound..<upperBound)
            }
        }
        func process(_ source: Data, with operation: (Provider, Consumer) throws -> CRC32) throws -> Data {
            var chunks = [Data]()
            var copies = [Data]()
            var keptChunksChanged = false
            _ = try operation(provider(source), { chunk in
                keptChunksChanged = keptChunksChanged || chunks != copies
                chunks.append(chunk)
                copies.append(Data([UInt8](chunk)))
            })
            XCTAssertGreaterThan(chunks.count, 1)
            XCTAssertFalse(keptChunksChanged || chunks != copies, "Kept chunks changed during processing")
            return copies.reduce(Data(), +)
        }
        let compressedData = try process(data) {
            try Data.compress(size: Int64(data.count), bufferSize: bufferSize, provider: $0, consumer: $1)
        }
        let decompressedData = try process(compressedData) {
            try Data.decompress(size: Int64(compressedData.count), bufferSize: bufferSize,
                                skipCRC32: false, provider: $0, consumer: $1)
        }
        XCTAssertEqual(decompressedData, data)
    }
}

extension Data {
    static func makeRandomData(size: Int) -> Data {
        #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        let bytes = [UInt32](repeating: 0, count: size).map { _ in UInt32.random(in: 0...UInt32.max) }
        #else
        let bytes = [UInt32](repeating: 0, count: size).map { _ in random() }
        #endif
        return Data(bytes: bytes, count: size)
    }
}
