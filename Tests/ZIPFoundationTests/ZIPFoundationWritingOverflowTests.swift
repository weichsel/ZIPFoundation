//
//  ZIPFoundationWritingTests.swift
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

    func testCreateArchiveWithTooManyEntriesOnDisk() {
        let archive = self.archive(for: #function, mode: .create)
        let fileName = ProcessInfo.processInfo.globallyUniqueString
        var didCatchExpectedError = false

        do {
            try (1...UInt16.max).forEach { _ in
                try archive.addEntry(with: fileName, type: .file, uncompressedSize: 1,
                                     provider: { (_, chunkSize) -> Data in
                    return Data(count: chunkSize)
                })
            }
        } catch {
            XCTFail("Unexpected error while trying to add an entry.")
        }
        do {
            try archive.addEntry(with: fileName, type: .file, uncompressedSize: 1,
                                 provider: { (_, chunkSize) -> Data in
                return Data(count: chunkSize)
            })
        } catch let error as Archive.ArchiveError {
            XCTAssert(error == .invalidNumberOfEntriesOnDisk)
            didCatchExpectedError = true
        } catch {
            XCTFail("Unexpected error while trying to add an entry exceeding maximum size.")
        }
        XCTAssert(didCatchExpectedError)
    }

    func testCreateArchiveWithTooManyEntriesInCD() {
        let archive = self.archive(for: #function, mode: .create)
        let fileName = ProcessInfo.processInfo.globallyUniqueString
        var didCatchExpectedError = false

        let record = Archive.EndOfCentralDirectoryRecord(record: archive.endOfCentralDirectoryRecord,
                                                         numberOfEntriesOnDisk: 0,
                                                         numberOfEntriesInCentralDirectory: UInt16.max - 1,
                                                         updatedSizeOfCentralDirectory: 0,
                                                         startOfCentralDirectory: 0)
        archive.endOfCentralDirectoryRecord = record

        do {
            try archive.addEntry(with: fileName, type: .file, uncompressedSize: 1,
                                 provider: { (_, chunkSize) -> Data in
                return Data(count: chunkSize)
            })
        } catch {
            XCTFail("Unexpected error while trying to add an entry.")
        }
        do {
            try archive.addEntry(with: fileName, type: .file, uncompressedSize: 1,
                                 provider: { (_, chunkSize) -> Data in
                return Data(count: chunkSize)
            })
        } catch let error as Archive.ArchiveError {
            XCTAssert(error == .invalidNumberOfEntriesInCentralDirectory)
            didCatchExpectedError = true
        } catch {
            XCTFail("Unexpected error while trying to add an entry exceeding maximum size.")
        }
        XCTAssert(didCatchExpectedError)
    }
}
