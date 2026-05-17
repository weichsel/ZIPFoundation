//
//  Error+ZIP.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension POSIXError {

    init(_ code: Int32, path: String) {
        let errorCode = POSIXError.Code(rawValue: code) ?? .EPERM
        self = .init(errorCode, userInfo: [NSFilePathErrorKey: path])
    }
}

extension CocoaError {

#if swift(>=4.2)
#else

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
#else

    // The swift-corelibs-foundation version of NSError.swift was missing a convenience method to create
    // error objects from error codes. (https://github.com/apple/swift-corelibs-foundation/pull/1420)
    // We have to provide an implementation for non-Darwin platforms using Swift versions < 4.2.

    public static func error(_ code: CocoaError.Code, userInfo: [AnyHashable: Any]? = nil, url: URL? = nil) -> Error {
        var info: [String: Any] = userInfo as? [String: Any] ?? [:]
        if let url = url {
            info[NSURLErrorKey] = url
        }
        return NSError(domain: NSCocoaErrorDomain, code: code.rawValue, userInfo: info)
    }

#endif
#endif
}
