//
//  ZIPFoundationErrorConditionTests.swift
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
}
