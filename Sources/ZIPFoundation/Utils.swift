//
//  Utils.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension Optional where Wrapped: UnsignedInteger {
    public var isNilOrEmpty: Bool {
        (self ?? 0) == 0
    }
}

// MARK: - Debug

extension Data {
    var hexDescription: String {
        return reduce("") {$0 + String(format: "%02x", $1)}
    }
}
