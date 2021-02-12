//
//  Archive+EntrySorting.swift
//  ZIPFoundation
//
//  Copyright © 2017-2021 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

extension Archive {
    /// Return all `entries` in the receiver sorted in an order that ensures that contained symlinks can be
    /// restored.
    ///
    /// Directories and files are sorted in the order they are in the archive. Symlinks will be
    /// sorted in the order they need to be extracted.
    ///
    /// - Returns: The sorted entries.
    /// - Throws: An error if an entry contains malformed path information.
    public func sortedEntries() throws -> [Entry] {
        let entries = Array(self.makeIterator())
        let sortedSymlinks = try sortSymblinks(in: entries)
        let sortedFilesAndDirectories = sortFilesAndDirectories(in: entries)
        return sortedFilesAndDirectories + sortedSymlinks
    }

    // MARK: - Helpers

    private func sortSymblinks(in entries: [Entry]) throws -> [Entry] {
        return try entries
            .lazy
            .filter { entry in
                entry.type == .symlink
            }.map { entry -> (entry: Entry, destinationPath: String) in
                guard let destinationPath = try self.symlinkDestinationPath(for: entry) else {
                    throw ArchiveError.invalidSymlinkDestinationPath
                }
                return (entry, destinationPath)
            }.reduce(into: [(entry: Entry, destinationPath: String)]()) { entries, element in
                let unsortedPath = element.entry.path
                let unsortedDestinationPath = element.destinationPath

                for (index, sortedElement) in entries.enumerated() {
                    let sortedPath = sortedElement.entry.path
                    let sortedDestinationPath = sortedElement.destinationPath

                    if unsortedDestinationPath.hasPrefix(sortedDestinationPath) {
                        entries.insert(element, at: entries.index(after: index))
                        return
                    } else if sortedDestinationPath.hasPrefix(unsortedDestinationPath) {
                        entries.insert(element, at: index)
                        return
                    } else if sortedDestinationPath.hasPrefix(unsortedPath) {
                        entries.insert(element, at: index)
                        return
                    } else if unsortedDestinationPath.hasPrefix(sortedPath) {
                        entries.insert(element, at: entries.index(after: index))
                        return
                    }
                }

                entries.append(element)
            }.map { $0.entry }
    }

    private func symlinkDestinationPath(for entry: Entry) throws -> String? {
        var destinationPath: String?
        _ = try self.extract(entry, bufferSize: entry.localFileHeader.compressedSize, skipCRC32: true) { data in
            guard let linkPath = String(data: data, encoding: .utf8) else { return }

            destinationPath = entry
                .path
                .split(separator: "/")
                .dropLast()
                .joined(separator: "/")
                + "/"
                + linkPath
        }
        return destinationPath
    }

    private func sortFilesAndDirectories(in entries: [Entry]) -> [Entry] {
        return entries
            .filter { entry in
                entry.type != .symlink
            }.sorted { (left, right) -> Bool in
                switch (left.type, right.type) {
                case (.file, .directory): return false
                default: return true
                }
            }
    }
}
