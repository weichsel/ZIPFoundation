//
//  URL+ZIP.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

extension URL {

    /// A file URL representing the root of the local filesystem (`/`).
    /// Can be used to indicate that symlinks may point anywhere on the filesystem during extraction.
    public static var rootFS: URL { URL(fileURLWithPath: "/") }

    static func temporaryReplacementDirectoryURL(for archive: Archive) -> URL {
        #if swift(>=5.0) || os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        if archive.url.isFileURL,
           let tempDir = try? FileManager().url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                appropriateFor: archive.url, create: true) {
            return tempDir
        }
        #endif

        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            ProcessInfo.processInfo.globallyUniqueString)
    }

    func isContained(in parentDirectoryURL: URL) -> Bool {
        // Ensure this URL is contained in the passed in URL
        let parentDirectoryURL = URL(fileURLWithPath: parentDirectoryURL.path, isDirectory: true).standardized
        // Maliciously crafted ZIP files can contain entries using a prepended path delimiter `/` in combination
        // with the parent directory shorthand `..` to bypass our containment check.
        // When a malicious entry path like e.g. `/../secret.txt` gets appended to the destination
        // directory URL (e.g. `file:///tmp/`), the resulting URL `file:///tmp//../secret.txt` gets expanded
        // to `file:///tmp/secret` when using `URL.standardized`. This URL would pass the check performed
        // in `isContained(in:)`.
        // Lower level API like POSIX `fopen` - which is used at a later point during extraction - expands
        // `/tmp//../secret.txt` to `/secret.txt` though. This would lead to an escape to the parent directory.
        // To avoid that, we replicate the behavior of `fopen`s path expansion and replace all double delimiters
        // with single delimiters.
        // More details: https://github.com/weichsel/ZIPFoundation/issues/281
        let sanitizedEntryPathURL: URL = {
            let sanitizedPath = self.path.replacingOccurrences(of: "//", with: "/")
            return URL(fileURLWithPath: sanitizedPath)
        }()
        return sanitizedEntryPathURL.standardized.absoluteString.hasPrefix(parentDirectoryURL.absoluteString)
    }
}
