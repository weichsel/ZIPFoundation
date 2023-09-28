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

    func testTemporaryReplacementDirectoryURL() throws {
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
        let memoryArchive = try Archive(data: Data(), accessMode: .create)
        let memoryTempURL = URL.temporaryReplacementDirectoryURL(for: memoryArchive)
        XCTAssertNotNil(memoryTempURL, "Temporary URL creation for in-memory archive failed.")
#endif
    }
}

extension XCTestCase {

    func XCTAssertSwiftError<T, E: Error & Equatable>(_ expression: @autoclosure () throws -> T,
                                                      throws error: E,
                                                      in file: StaticString = #file,
                                                      line: UInt = #line) {
        var thrownError: Error?
        XCTAssertThrowsError(try expression(), file: file, line: line) { thrownError = $0}
        XCTAssertTrue(thrownError is E, "Unexpected error type: \(type(of: thrownError))", file: file, line: line)
        XCTAssertEqual(thrownError as? E, error, file: file, line: line)
    }

    func XCTAssertPOSIXError<T>(_ expression: @autoclosure () throws -> T,
                                throwsErrorWithCode code: POSIXError.Code,
                                in file: StaticString = #file,
                                line: UInt = #line) {
        var thrownError: POSIXError?
        XCTAssertThrowsError(try expression(), file: file, line: line) { thrownError = $0 as? POSIXError }
        XCTAssertNotNil(thrownError, file: file, line: line)
        XCTAssertTrue(thrownError?.code == code, file: file, line: line)
    }

    func XCTAssertCocoaError<T>(_ expression: @autoclosure () throws -> T,
                                throwsErrorWithCode code: CocoaError.Code,
                                in file: StaticString = #file,
                                line: UInt = #line) {
        var thrownError: CocoaError?
        #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        XCTAssertThrowsError(try expression(), file: file, line: line) { thrownError = $0 as? CocoaError}
        #else
        XCTAssertThrowsError(try expression(), file: file, line: line) {
            // For unknown reasons, some errors in the `NSCocoaErrorDomain` can't be cast to `CocoaError` on Linux.
            // We manually re-create them here as `CocoaError` to work around this.
            thrownError = CocoaError(.init(rawValue: ($0 as NSError).code))
        }
        #endif
        XCTAssertNotNil(thrownError, file: file, line: line)
        XCTAssertTrue(thrownError?.code == code, file: file, line: line)
    }
}
