//
//  URL+ZIP.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/main/LICENSE for license information.
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

    /// Checks if the receiver is contained in `directoryURL`, based on the locations
    /// the file system would actually access.
    ///
    /// A lexical check (e.g. via `URL.standardized`) is not sufficient here, because it doesn't
    /// replicate the path resolution of lower level API like POSIX `fopen`:
    /// - An entry path like `/../secret.txt` appended to `/tmp/` results in `/tmp//../secret.txt`.
    ///   `URL.standardized` expands this to `/tmp/secret.txt`, while the file system resolves it to `/secret.txt`.
    ///   More details: https://github.com/weichsel/ZIPFoundation/issues/281
    /// - A path like `link/../file` is lexically contained in its parent directory. If `link` is a symlink,
    ///   the file system resolves the link first and applies `..` to the link destination afterwards.
    ///   Entries of a maliciously crafted archive can use symlinks created by preceding entries
    ///   to escape the destination directory that way.
    ///
    /// - Parameters:
    ///   - directoryURL: The directory that should contain the receiver.
    ///   - directoryComponents: The resolved path components of `directoryURL`. They are passed in,
    ///                          so that callers that check many URLs only have to resolve the directory once.
    func isContained(in directoryURL: URL, resolvedTo directoryComponents: [String]) -> Bool {
        let path = self.path
        let directoryPath = directoryURL.path
        // If the receiver was built by appending to `directoryURL`, only the appended part has to be resolved.
        // Missing components of the appended part are created as regular directories before the receiver
        // is written. A `..` that follows them can therefore be resolved.
        // The path of the root directory already ends with a path delimiter.
        let directoryPrefix = directoryPath.unicodeScalars.last == "/" ? directoryPath : directoryPath + "/"
        // A slash is a path delimiter even when a following combining mark forms one Character with it.
        let components: [String]?
        if path.unicodeScalars.starts(with: directoryPrefix.unicodeScalars) {
            let suffix = path.unicodeScalars.dropFirst(directoryPrefix.unicodeScalars.count)
            components = URL.resolvedPathComponents(ofPath: "./" + String(suffix), relativeTo: directoryComponents,
                                                    missingComponentsAreDirectories: true)
        } else {
            components = URL.resolvedPathComponents(ofPath: path)
        }
        guard let components = components else { return false }

        return URL.pathComponents(components, startWith: directoryComponents)
    }

    /// Checks if the destination of a symlink, that is about to be created in `directoryURL`,
    /// is contained in `parentDirectoryURL`.
    ///
    /// `directoryURL` doesn't have to exist yet. The caller is expected to create missing directories
    /// (as regular directories) before creating the symlink. The same applies to `parentDirectoryURL`,
    /// which is provided by the caller of the extraction. A `..` that follows a missing directory can
    /// therefore be resolved for both of them. The destination of the symlink is always resolved strictly.
    static func isSymlinkDestination(_ destinationPath: String, ofSymlinkIn directoryURL: URL,
                                     containedIn parentDirectoryURL: URL) -> Bool {
        guard let parentComponents = URL.resolvedPathComponents(ofPath: parentDirectoryURL.path,
                                                                missingComponentsAreDirectories: true)
        else { return false }
        // Callers can opt out of the restriction by passing the root of the file system (`URL.rootFS`).
        // In that case, every destination is valid, even if it can't be resolved reliably.
        guard parentComponents.isEmpty == false else { return true }
        // An empty destination doesn't refer to a location.
        guard destinationPath.isEmpty == false else { return false }
        guard let directoryComponents = URL.resolvedPathComponents(ofPath: directoryURL.path,
                                                                   missingComponentsAreDirectories: true),
              let components = URL.resolvedPathComponents(ofPath: destinationPath, relativeTo: directoryComponents)
        else { return false }

        return URL.pathComponents(components, startWith: parentComponents)
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
    ///   - missingComponentsAreDirectories: Pass `true` if the caller creates the missing components of `path`
    ///                                      as regular directories before it accesses the path. This is the
    ///                                      case for entry paths and for the destination of an extraction,
    ///                                      which is provided by the caller of the extraction. A `..` then
    ///                                      removes the missing component that precedes it. Missing components
    ///                                      that are not located within `baseComponents` can't be resolved,
    ///                                      because they would be created outside of that directory.
    /// - Returns: The resolved path components or `nil` if the path can't be resolved reliably.
    static func resolvedPathComponents(ofPath path: String, relativeTo baseComponents: [String] = [],
                                       missingComponentsAreDirectories: Bool = false) -> [String]? {
        func components(of path: String) -> [String] {
            return path.unicodeScalars.split(separator: "/").map(String.init).filter { $0 != "." }
        }

        let fileManager = FileManager()
        let maximumSymlinkCount = 64
        var symlinkCount = 0
        // The number of components at the end of `resolved` that don't exist.
        var missingComponentCount = 0
        var resolved = URL.isAbsolutePath(path) ? [] : baseComponents
        var pending = Array(components(of: path).reversed())
        while let component = pending.popLast() {
            if component == ".." {
                if missingComponentCount > 0 {
                    guard missingComponentsAreDirectories else { return nil }

                    missingComponentCount -= 1
                }
                _ = resolved.popLast()
                continue
            }
            let candidatePath = "/" + (resolved + [component]).joined(separator: "/")
            guard missingComponentCount == 0,
                  let isSymbolicLink = URL.isSymbolicLink(atPath: candidatePath, fileManager: fileManager) else {
                // The missing directory would be created at the location that has been resolved so far.
                if missingComponentsAreDirectories, URL.pathComponents(resolved, startWith: baseComponents) == false {
                    return nil
                }

                missingComponentCount += 1
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

            if URL.isAbsolutePath(destination) { resolved.removeAll() }
            pending.append(contentsOf: components(of: destination).reversed())
        }
        return resolved
    }

    /// Checks if `path` is absolute in the way the file system interprets it.
    ///
    /// On POSIX systems, only a leading slash marks an absolute path. `NSString.isAbsolutePath` also
    /// treats paths that start with a tilde (e.g. `~`, `~/dir` or `~name`) as absolute on Darwin,
    /// while the file system resolves them relative to the current directory (or the symlink's parent).
    /// The first byte is compared, so that a combining mark after the slash doesn't affect the check.
    static func isAbsolutePath(_ path: String) -> Bool {
#if os(Windows)
        return (path as NSString).isAbsolutePath
#else
        return path.utf8.first == UInt8(ascii: "/")
#endif
    }

    /// Compares exact spellings, allowing different spellings on Darwin if they identify the same directory.
    static func pathComponents(_ components: [String], startWith prefix: [String]) -> Bool {
        guard components.count >= prefix.count else { return false }
        for index in prefix.indices {
            if components[index].unicodeScalars.elementsEqual(prefix[index].unicodeScalars) { continue }
#if canImport(Darwin)
            let candidatePath = "/" + components[...index].joined(separator: "/")
            let directoryPath = "/" + prefix[...index].joined(separator: "/")
            var candidate = stat()
            var directory = stat()
            // Pass the original spellings to lstat so Foundation cannot normalize them before lookup.
            guard lstat(candidatePath, &candidate) == 0, lstat(directoryPath, &directory) == 0,
                  (candidate.st_mode & S_IFMT) == S_IFDIR, (directory.st_mode & S_IFMT) == S_IFDIR,
                  candidate.st_dev == directory.st_dev, candidate.st_ino == directory.st_ino else { return false }
#else
            return false
#endif
        }
        return true
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
