//
//  ZIPFoundationDataSerializationTests.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import XCTest
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
        let file: UnsafeMutablePointer<FILE> = fopen(fileSystemRepresentation, "rb")
        // Close the file to exercise the error path during readStructure that deals with
        // unreadable file data.
        fclose(file)
        let centralDirectoryStructure: Entry.CentralDirectoryStructure? = Data.readStruct(from: file, at: 0)
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
        let file: UnsafeMutablePointer<FILE> = fopen(fileSystemRepresentation, "rb")
        // Close the file to exercise the error path during readChunk that deals with
        // unreadable file data.
        fclose(file)
        do {
            _ = try Data.readChunk(of: 10, from: file)
        } catch let error as Data.DataError {
            XCTAssert(error == .unreadableFile)
        } catch {
            XCTFail("Unexpected error while testing to read from a closed file.")
        }
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
        let file: UnsafeMutablePointer<FILE> = fopen(fileSystemRepresentation, "rb")
        // Close the file to exercise the error path during writeChunk that deals with
        // unwritable files.
        fclose(file)
        do {
            let dataWritten = try Data.write(chunk: Data(count: 10), to: file)
            XCTAssert(dataWritten == 0)
        } catch let error as Data.DataError {
            XCTAssert(error == .unwritableFile)
        } catch {
            XCTFail("Unexpected error while testing to write into a closed file.")
        }
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
        let file: UnsafeMutablePointer<FILE> = fopen(fileSystemRepresentation, "rb+")
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
        let file: UnsafeMutablePointer<FILE> = fopen(fileSystemRepresentation, "rb")
        let data = Data.makeRandomData(size: 1024)
        // Close the file to exercise the error path during writeChunk that deals with
        // unwritable files.
        fclose(file)
        do {
            let dataWritten = try Data.writeLargeChunk(data, size: 1024, bufferSize: 256, to: file)
            XCTAssert(dataWritten == 0)
        } catch let error as Data.DataError {
            XCTAssert(error == .unwritableFile)
        } catch {
            XCTFail("Unexpected error while testing to write into a closed file.")
        }
    }
}
