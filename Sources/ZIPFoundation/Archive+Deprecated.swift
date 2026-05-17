//
//  Archive+Deprecated.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

public extension Archive {

    @available(*, deprecated, message: "Please use the throwing initializer.")
    convenience init?(url: URL, accessMode mode: AccessMode, preferredEncoding: String.Encoding? = nil) {
        try? self.init(url: url, accessMode: mode, pathEncoding: preferredEncoding)
    }

#if swift(>=5.0) && (os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || os(Linux))
    @available(*, deprecated, message: "Please use the throwing initializer.")
    convenience init?(data: Data = Data(), accessMode mode: AccessMode, preferredEncoding: String.Encoding? = nil) {
        try? self.init(data: data, accessMode: mode, pathEncoding: preferredEncoding)
    }
#endif
}
