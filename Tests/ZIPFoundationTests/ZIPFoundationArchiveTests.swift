//
//  ZIPFoundationErrorConditionTests.swift
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

    func testArchiveInvalidEOCDRecordConditions() {
        let emptyECDR = Archive.EndOfCentralDirectoryRecord(data: Data(),
                                                            additionalDataProvider: {_ -> Data in
            return Data() })
        XCTAssertNil(emptyECDR)
        let invalidECDRData = Data(count: 22)
        let invalidECDR = Archive.EndOfCentralDirectoryRecord(data: invalidECDRData,
                                                              additionalDataProvider: {_ -> Data in
            return Data() })
        XCTAssertNil(invalidECDR)
    }

    func testDirectoryCreationHelperMethods() {
        let processInfo = ProcessInfo.processInfo
        var nestedURL = ZIPFoundationTests.tempZipDirectoryURL
        nestedURL.appendPathComponent(processInfo.globallyUniqueString)
        nestedURL.appendPathComponent(processInfo.globallyUniqueString)
        do {
            try FileManager().createParentDirectoryStructure(for: nestedURL)
        } catch { XCTFail("Failed to create parent directory.") }
    }

    func testTemporaryReplacementDirectoryURL() {
        let archive = self.archive(for: #function, mode: .create)
        var tempURLs = Set<URL>()
        defer { for url in tempURLs { try? FileManager.default.removeItem(at: url) } }
        // We choose 2000 temp directories to test workaround for http://openradar.appspot.com/50553219
        for _ in 1...2000 {
            let tempDir = URL.temporaryReplacementDirectoryURL(for: archive)
            XCTAssertFalse(tempURLs.contains(tempDir), "Temp directory URL should be unique. \(tempDir)")
            tempURLs.insert(tempDir)
        }

#if swift(>=5.0)
        // Also cover the fallback codepath in the helper method to generate a unique temp URL.
        // In-memory archives have no filesystem representation and therefore don't need a per-volume
        // temp URL.
        guard let memoryArchive = Archive(data: Data(), accessMode: .create) else {
            XCTFail("Temporary memory archive creation failed.")
            return
        }

        let memoryTempURL = URL.temporaryReplacementDirectoryURL(for: memoryArchive)
        XCTAssertNotNil(memoryTempURL, "Temporary URL creation for in-memory archive failed.")
#endif
    }
}
