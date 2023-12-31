//
//  ZIPFoundationErrorConditionTests+ZIP64.swift
//  ZIPFoundation
//
//  Copyright © 2017-2024 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {

    func testWriteEOCDWithTooLargeSizeOfCentralDirectory() {
        let archive = self.archive(for: #function, mode: .create)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: .max,
                                                                                numberOfEntries: 0)
        XCTAssertSwiftError(
            try archive.writeEndOfCentralDirectory(centralDirectoryStructure: makeMockCentralDirectory()!,
                                                                   startOfCentralDirectory: 0,
                                                                   startOfEndOfCentralDirectory: 0,
                                                                   operation: .add),
                            throws: Archive.ArchiveError.invalidCentralDirectorySize)
    }

    func testWriteEOCDWithTooLargeCentralDirectoryOffset() {
        let archive = self.archive(for: #function, mode: .create)
        archive.zip64EndOfCentralDirectory = makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: 0,
                                                                                numberOfEntries: .max)
        XCTAssertSwiftError(
            try archive.writeEndOfCentralDirectory(centralDirectoryStructure: makeMockCentralDirectory()!,
                                                                   startOfCentralDirectory: 0,
                                                                   startOfEndOfCentralDirectory: 0,
                                                                   operation: .add),
                            throws: Archive.ArchiveError.invalidCentralDirectoryEntryCount)
    }

    // MARK: - Helper

    private func makeMockZIP64EndOfCentralDirectory(sizeOfCentralDirectory: UInt64, numberOfEntries: UInt64)
    -> Archive.ZIP64EndOfCentralDirectory {
        let record = Archive.ZIP64EndOfCentralDirectoryRecord(sizeOfZIP64EndOfCentralDirectoryRecord: UInt64(44),
                                                              versionMadeBy: UInt16(789),
                                                              versionNeededToExtract: Archive.Version.v45.rawValue,
                                                              numberOfDisk: 0, numberOfDiskStart: 0,
                                                              totalNumberOfEntriesOnDisk: 0,
                                                              totalNumberOfEntriesInCentralDirectory: numberOfEntries,
                                                              sizeOfCentralDirectory: sizeOfCentralDirectory,
                                                              offsetToStartOfCentralDirectory: 0,
                                                              zip64ExtensibleDataSector: Data())
        let locator = Archive.ZIP64EndOfCentralDirectoryLocator(numberOfDiskWithZIP64EOCDRecordStart: 0,
                                                                relativeOffsetOfZIP64EOCDRecord: 0,
                                                                totalNumberOfDisk: 1)
        return Archive.ZIP64EndOfCentralDirectory(record: record, locator: locator)
    }

    private func makeMockCentralDirectory() -> Entry.CentralDirectoryStructure? {
        let cdsBytes: [UInt8] = [0x50, 0x4b, 0x01, 0x02, 0x1e, 0x15, 0x14, 0x00,
                                 0x08, 0x08, 0x08, 0x00, 0xab, 0x85, 0x77, 0x47,
                                 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                                 0xb0, 0x11, 0x00, 0x00, 0x00, 0x00]
        guard let cds = Entry.CentralDirectoryStructure(data: Data(cdsBytes),
                                                        additionalDataProvider: { count -> Data in
                                                            guard let pathData = "/".data(using: .utf8) else {
                                                                throw AdditionalDataError.encodingError
                                                            }
                                                            XCTAssert(count == pathData.count)
                                                            return pathData
                                                        }) else {
            XCTFail("Failed to read central directory structure.")
            return nil
        }
        return cds
    }
}
