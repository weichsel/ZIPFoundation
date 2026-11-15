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

    /// Checks if the destination of a symlink, that is about to be created in `directoryURL`,
    /// is contained in `parentDirectoryURL`.
    ///
    /// `directoryURL` doesn't have to exist yet. The caller is expected to create missing directories
    /// (as regular directories) before creating the symlink.
    static func isSymlinkDestination(_ destinationPath: String, ofSymlinkIn directoryURL: URL,
                                     containedIn parentDirectoryURL: URL) -> Bool {
        guard let parentComponents = URL.resolvedPathComponents(ofPath: parentDirectoryURL.path)
        else { return false }
        // Callers can opt out of the restriction by passing the root of the file system (`URL.rootFS`).
        // In that case, every destination is valid, even if it can't be resolved reliably.
        guard parentComponents.isEmpty == false else { return true }
        guard let directoryComponents = URL.resolvedPathComponents(ofPath: directoryURL.path),
              let components = URL.resolvedPathComponents(ofPath: destinationPath, relativeTo: directoryComponents)
        else { return false }

        return components.starts(with: parentComponents)
    }

    /// Resolves a path, component by component, in the same way the file system does:
    /// Symlinks are followed (including a symlink in the last component) and `..` is applied
    /// to the resolved location.
    ///
    /// Trailing components that don't exist (yet) are kept as-is. A `..` that follows a non-existent component
    /// of `path` can't be resolved reliably, because subsequent archive entries could replace the missing
    /// component with a symlink.
    ///
    /// - Parameters:
    ///   - path: The path to resolve.
    ///   - baseComponents: The already resolved components of the directory a relative `path` starts at.
    ///                     Ignored if `path` is absolute.
    /// - Returns: The resolved path components or `nil` if the path can't be resolved reliably.
    static func resolvedPathComponents(ofPath path: String, relativeTo baseComponents: [String] = []) -> [String]? {
        func components(of path: String) -> [String] {
            return path.split(separator: "/").map(String.init).filter { $0 != "." }
        }

        let fileManager = FileManager()
        let maximumSymlinkCount = 64
        var symlinkCount = 0
        var hasMissingComponent = false
        var resolved = (path as NSString).isAbsolutePath ? [] : baseComponents
        var pending = Array(components(of: path).reversed())
        while let component = pending.popLast() {
            if component == ".." {
                guard hasMissingComponent == false else { return nil }

                _ = resolved.popLast()
                continue
            }
            let candidatePath = "/" + (resolved + [component]).joined(separator: "/")
            guard hasMissingComponent == false,
                  let isSymbolicLink = URL.isSymbolicLink(atPath: candidatePath, fileManager: fileManager) else {
                hasMissingComponent = true
                resolved.append(component)
                continue
            }
            guard isSymbolicLink else {
                resolved.append(component)
                continue
            }

            symlinkCount += 1
            guard symlinkCount <= maximumSymlinkCount,
                  let destination = try? fileManager.destinationOfSymbolicLink(atPath: candidatePath)
            else { return nil }

            if (destination as NSString).isAbsolutePath { resolved.removeAll() }
            pending.append(contentsOf: components(of: destination).reversed())
        }
        return resolved
    }

    /// Checks if the item at `path` is a symlink, without traversing it.
    ///
    /// - Returns: `nil` if there is no item at `path`.
    private static func isSymbolicLink(atPath path: String, fileManager: FileManager) -> Bool? {
#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS) || os(Linux)
        var fileStat = stat()
        guard lstat(fileManager.fileSystemRepresentation(withPath: path), &fileStat) == 0 else { return nil }

        return (fileStat.st_mode & S_IFMT) == S_IFLNK
#else
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return nil }

        return attributes[.type] as? FileAttributeType == .typeSymbolicLink
#endif
    }
}
