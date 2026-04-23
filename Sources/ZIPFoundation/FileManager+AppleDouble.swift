//
//  FileManager+AppleDouble.swift
//  ZIPFoundation
//
//  Copyright © 2017-2026 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

/// AppleDouble (`__MACOSX/._<name>`) helpers.
///
/// Apple-produced ZIP archives (Archive Utility, `ditto --sequesterRsrc`) preserve macOS-specific
/// file metadata — extended attributes, resource forks, and Finder info — by storing a parallel
/// `__MACOSX/.../._<name>` entry alongside each real entry. Each companion entry is an AppleDouble
/// (v2) container embedding the metadata.
///
/// On Darwin, we round-trip this metadata via the `com.apple.FinderInfo`, `com.apple.ResourceFork`,
/// and user-namespace extended attributes (`listxattr`/`setxattr`).
extension FileManager {

    static let macOSXDirectoryName = "__MACOSX"
    static let appleDoubleFilePrefix = "._"

    /// Returns the `__MACOSX/.../._<name>` companion path for the given entry path,
    /// or `nil` if no companion is meaningful (e.g. empty path, or a path already inside `__MACOSX/`).
    static func appleDoubleCompanionPath(forEntryPath path: String) -> String? {
        guard !path.isEmpty else { return nil }
        // Strip trailing slash for directory entries — the companion is always a file.
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != macOSXDirectoryName,
              !trimmed.hasPrefix(macOSXDirectoryName + "/") else { return nil }
        if let idx = trimmed.lastIndex(of: "/") {
            let parent = String(trimmed[..<idx])
            let name = String(trimmed[trimmed.index(after: idx)...])
            guard !name.isEmpty else { return nil }
            return "\(macOSXDirectoryName)/\(parent)/\(appleDoubleFilePrefix)\(name)"
        } else {
            return "\(macOSXDirectoryName)/\(appleDoubleFilePrefix)\(trimmed)"
        }
    }

    /// Returns the real entry path that the given companion path refers to, or `nil` if `path`
    /// is not a recognizable `__MACOSX/.../._<name>` companion.
    static func realEntryPath(fromAppleDoubleCompanionPath path: String) -> String? {
        let prefix = macOSXDirectoryName + "/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = String(path.dropFirst(prefix.count))
        guard !rest.isEmpty, !rest.hasSuffix("/") else { return nil }
        if let idx = rest.lastIndex(of: "/") {
            let parent = String(rest[..<idx])
            let basename = String(rest[rest.index(after: idx)...])
            guard basename.hasPrefix(appleDoubleFilePrefix) else { return nil }
            let realBasename = String(basename.dropFirst(appleDoubleFilePrefix.count))
            guard !realBasename.isEmpty else { return nil }
            return parent.isEmpty ? realBasename : parent + "/" + realBasename
        } else {
            guard rest.hasPrefix(appleDoubleFilePrefix) else { return nil }
            let realBasename = String(rest.dropFirst(appleDoubleFilePrefix.count))
            guard !realBasename.isEmpty else { return nil }
            return realBasename
        }
    }
}

// MARK: - AppleDouble v2 format

enum AppleDouble {

    static let magic: UInt32 = 0x00051607
    static let version: UInt32 = 0x00020000
    static let headerSize = 26 // 4 (magic) + 4 (version) + 16 (filler) + 2 (numEntries)
    static let entryDescriptorSize = 12 // 4 (type) + 4 (offset) + 4 (length)

    enum EntryID: UInt32 {
        case dataFork = 1
        case resourceFork = 2
        case finderInfo = 9
    }

    // Apple's extended attribute section in the AppleDouble FinderInfo entry.
    // See xnu's bsd/vfs/vfs_xattr.c.
    static let attrMagic: UInt32 = 0x41545452 // 'ATTR'
    static let attrHeaderBaseSize = 36 // everything after the apple_double_header
    static let finderInfoSize = 32
    static let finderInfoPadSize = 2
    static let maxAttrNameLength = 128
}

struct AppleDoublePayload {
    /// Standard Finder info (32 bytes). Empty `Data` or `nil` indicates no finder info.
    var finderInfo: Data?
    /// Resource fork contents.
    var resourceFork: Data?
    /// Other extended attributes, keyed by name, preserved in insertion order.
    var extendedAttributes: [(name: String, data: Data)]

    init(finderInfo: Data? = nil, resourceFork: Data? = nil,
         extendedAttributes: [(name: String, data: Data)] = []) {
        self.finderInfo = finderInfo
        self.resourceFork = resourceFork
        self.extendedAttributes = extendedAttributes
    }

    var isEmpty: Bool {
        (finderInfo?.isEmpty ?? true) && (resourceFork?.isEmpty ?? true) && extendedAttributes.isEmpty
    }
}

// MARK: - Serialization

extension AppleDoublePayload {

    /// Encodes the payload as an AppleDouble v2 container.
    func encode() -> Data {
        var output = Data()

        let hasFinderInfo = (finderInfo?.isEmpty == false) || !extendedAttributes.isEmpty
        let hasResourceFork = (resourceFork?.isEmpty == false)
        var numEntries: UInt16 = 0
        if hasFinderInfo { numEntries += 1 }
        if hasResourceFork { numEntries += 1 }

        // Build the FinderInfo + optional xattr section in memory first so we know its size.
        var finderInfoSection = Data()
        if hasFinderInfo {
            var finderInfoBytes = Data(count: AppleDouble.finderInfoSize)
            if let fi = finderInfo {
                let copyLen = min(fi.count, AppleDouble.finderInfoSize)
                finderInfoBytes.replaceSubrange(0..<copyLen, with: fi.prefix(copyLen))
            }
            finderInfoSection.append(finderInfoBytes)
        }

        let headerPlusEntriesSize = AppleDouble.headerSize + Int(numEntries) * AppleDouble.entryDescriptorSize
        let finderInfoOffset = headerPlusEntriesSize

        if !extendedAttributes.isEmpty {
            // Two pad bytes between finder info and ATTR section (for 4-byte alignment).
            finderInfoSection.append(Data(count: AppleDouble.finderInfoPadSize))

            // Layout: header (36 bytes) + entry descriptors (variable) + attribute data blobs.
            // Offsets are absolute from the start of the AppleDouble file.
            let attrHeaderStart = finderInfoOffset + AppleDouble.finderInfoSize + AppleDouble.finderInfoPadSize
            var entriesSize = 0
            for (name, _) in extendedAttributes {
                // attr_entry_t: offset(4) + length(4) + flags(2) + namelen(1) + name(namelen, NUL-terminated)
                let nameBytes = Data(name.utf8) + Data([0])
                let rawEntrySize = 11 + nameBytes.count
                let padded = (rawEntrySize + 3) & ~3 // round up to 4 bytes
                entriesSize += padded
            }
            let dataStart = attrHeaderStart + AppleDouble.attrHeaderBaseSize + entriesSize
            var dataLength = 0
            var attrOffsets: [Int] = []
            for (_, value) in extendedAttributes {
                attrOffsets.append(dataStart + dataLength)
                dataLength += value.count
            }
            let totalSize = AppleDouble.attrHeaderBaseSize + entriesSize + dataLength

            // Attr header
            var attrSection = Data()
            attrSection.appendBE32(AppleDouble.attrMagic)
            attrSection.appendBE32(0) // debug_tag
            attrSection.appendBE32(UInt32(totalSize))
            attrSection.appendBE32(UInt32(dataStart))
            attrSection.appendBE32(UInt32(dataLength))
            // reserved[3]
            attrSection.appendBE32(0)
            attrSection.appendBE32(0)
            attrSection.appendBE32(0)
            attrSection.appendBE16(0) // flags
            attrSection.appendBE16(UInt16(extendedAttributes.count))

            // Attr entries
            for (idx, (name, value)) in extendedAttributes.enumerated() {
                attrSection.appendBE32(UInt32(attrOffsets[idx]))
                attrSection.appendBE32(UInt32(value.count))
                attrSection.appendBE16(0) // flags
                let nameBytes = Data(name.utf8) + Data([0])
                attrSection.append(UInt8(nameBytes.count)) // namelen (incl. trailing NUL)
                attrSection.append(nameBytes)
                // Pad to 4-byte boundary.
                let rawEntrySize = 11 + nameBytes.count
                let padded = (rawEntrySize + 3) & ~3
                if padded > rawEntrySize {
                    attrSection.append(Data(count: padded - rawEntrySize))
                }
            }

            // Attribute value blobs
            for (_, value) in extendedAttributes {
                attrSection.append(value)
            }

            finderInfoSection.append(attrSection)
        }

        let finderInfoLength = finderInfoSection.count
        let resourceForkOffset = finderInfoOffset + finderInfoLength
        let resourceForkLength = resourceFork?.count ?? 0

        // Apple Double header
        output.appendBE32(AppleDouble.magic)
        output.appendBE32(AppleDouble.version)
        // 16-byte filler — Apple writes "Mac OS X        " (ASCII). Zeros also accepted by all parsers we care about.
        let filler = "Mac OS X        ".data(using: .ascii) ?? Data(count: 16)
        output.append(filler.prefix(16))
        if filler.count < 16 { output.append(Data(count: 16 - filler.count)) }
        output.appendBE16(numEntries)

        // Entry descriptors — FinderInfo first if present, then ResourceFork.
        if hasFinderInfo {
            output.appendBE32(AppleDouble.EntryID.finderInfo.rawValue)
            output.appendBE32(UInt32(finderInfoOffset))
            output.appendBE32(UInt32(finderInfoLength))
        }
        if hasResourceFork {
            output.appendBE32(AppleDouble.EntryID.resourceFork.rawValue)
            output.appendBE32(UInt32(resourceForkOffset))
            output.appendBE32(UInt32(resourceForkLength))
        }

        // Payload sections.
        output.append(finderInfoSection)
        if hasResourceFork, let rf = resourceFork { output.append(rf) }

        return output
    }

    /// Parses an AppleDouble v2 container. Returns `nil` if the data is malformed.
    static func decode(_ data: Data) -> AppleDoublePayload? {
        guard data.count >= AppleDouble.headerSize else { return nil }
        guard data.readBE32(at: 0) == AppleDouble.magic else { return nil }
        // Accept anything with the 0x0002xxxx major version.
        let version = data.readBE32(at: 4)
        guard (version >> 16) == 0x0002 else { return nil }
        let numEntries = Int(data.readBE16(at: 24))
        let entriesEnd = AppleDouble.headerSize + numEntries * AppleDouble.entryDescriptorSize
        guard data.count >= entriesEnd else { return nil }

        var payload = AppleDoublePayload()
        for i in 0..<numEntries {
            let base = AppleDouble.headerSize + i * AppleDouble.entryDescriptorSize
            let type = data.readBE32(at: base)
            let offset = Int(data.readBE32(at: base + 4))
            let length = Int(data.readBE32(at: base + 8))
            guard offset >= 0, length >= 0, offset &+ length <= data.count else { return nil }
            let section = data.subdata(in: data.startIndex.advanced(by: offset)
                                            ..< data.startIndex.advanced(by: offset + length))
            switch AppleDouble.EntryID(rawValue: type) {
            case .finderInfo:
                let (finderInfo, xattrs) = parseFinderInfoSection(section, fullData: data, sectionOffset: offset)
                payload.finderInfo = finderInfo
                payload.extendedAttributes = xattrs
            case .resourceFork:
                payload.resourceFork = section
            default:
                continue
            }
        }
        return payload
    }

    private static func parseFinderInfoSection(_ section: Data, fullData: Data, sectionOffset: Int)
        -> (finderInfo: Data?, xattrs: [(name: String, data: Data)]) {
        var finderInfo: Data?
        if section.count >= AppleDouble.finderInfoSize {
            finderInfo = section.prefix(AppleDouble.finderInfoSize)
            // Treat all-zero Finder Info as "no finder info" — matches what apps like ditto emit
            // when only xattrs are present. We still preserve it if non-zero.
            if finderInfo?.allSatisfy({ $0 == 0 }) == true { finderInfo = nil }
        }
        guard section.count > AppleDouble.finderInfoSize + AppleDouble.finderInfoPadSize else {
            return (finderInfo, [])
        }
        // The ATTR section follows the 32 Finder Info bytes + 2 padding bytes. Its internal
        // offsets are absolute from the start of the AppleDouble file.
        let attrMagicOffset = sectionOffset + AppleDouble.finderInfoSize + AppleDouble.finderInfoPadSize
        guard attrMagicOffset + AppleDouble.attrHeaderBaseSize <= fullData.count else {
            return (finderInfo, [])
        }
        guard fullData.readBE32(at: attrMagicOffset) == AppleDouble.attrMagic else {
            return (finderInfo, [])
        }
        let totalSize = Int(fullData.readBE32(at: attrMagicOffset + 8))
        let dataStart = Int(fullData.readBE32(at: attrMagicOffset + 12))
        let numAttrs = Int(fullData.readBE16(at: attrMagicOffset + 34))
        guard attrMagicOffset + totalSize <= fullData.count else { return (finderInfo, []) }
        guard dataStart <= fullData.count else { return (finderInfo, []) }
        var entryCursor = attrMagicOffset + AppleDouble.attrHeaderBaseSize
        var results: [(name: String, data: Data)] = []
        for _ in 0..<numAttrs {
            guard entryCursor + 11 <= fullData.count else { break }
            let valueOffset = Int(fullData.readBE32(at: entryCursor))
            let valueLength = Int(fullData.readBE32(at: entryCursor + 4))
            let nameLen = Int(fullData[fullData.startIndex.advanced(by: entryCursor + 10)])
            guard nameLen > 0, entryCursor + 11 + nameLen <= fullData.count else { break }
            let nameRange = (entryCursor + 11)..<(entryCursor + 11 + nameLen - 1) // strip trailing NUL
            let nameData = fullData.subdata(in: fullData.startIndex.advanced(by: nameRange.lowerBound)
                                                ..< fullData.startIndex.advanced(by: nameRange.upperBound))
            guard let name = String(data: nameData, encoding: .utf8), !name.isEmpty else { break }
            guard valueOffset >= 0, valueLength >= 0,
                  valueOffset + valueLength <= fullData.count else { break }
            let valueData = fullData.subdata(in: fullData.startIndex.advanced(by: valueOffset)
                                                  ..< fullData.startIndex.advanced(by: valueOffset + valueLength))
            results.append((name: name, data: valueData))
            let rawEntrySize = 11 + nameLen
            let padded = (rawEntrySize + 3) & ~3
            entryCursor += padded
        }
        return (finderInfo, results)
    }
}

// MARK: - Big-endian helpers

fileprivate extension Data {

    mutating func appendBE32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    mutating func appendBE16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }

    func readBE32(at offset: Int) -> UInt32 {
        withUnsafeBytes {
            UInt32(bigEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    func readBE16(at offset: Int) -> UInt16 {
        withUnsafeBytes {
            UInt16(bigEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }
}

// MARK: - File-system bridge (Darwin only)

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)

extension FileManager {

    static let finderInfoXattrName = "com.apple.FinderInfo"
    static let resourceForkXattrName = "com.apple.ResourceFork"

    /// Builds an `AppleDoublePayload` from the file at `url` by reading its extended attributes
    /// (including `com.apple.FinderInfo` and `com.apple.ResourceFork`). Returns `nil` when the file
    /// has no Apple-specific metadata.
    static func readAppleDoublePayload(at url: URL) -> AppleDoublePayload? {
        let fsRep = FileManager().fileSystemRepresentation(withPath: url.path)
        guard let names = listExtendedAttributeNames(fsRep: fsRep), !names.isEmpty else { return nil }
        var payload = AppleDoublePayload()
        for name in names {
            guard let value = getExtendedAttribute(fsRep: fsRep, name: name) else { continue }
            switch name {
            case finderInfoXattrName:
                payload.finderInfo = value
            case resourceForkXattrName:
                payload.resourceFork = value
            default:
                payload.extendedAttributes.append((name: name, data: value))
            }
        }
        return payload.isEmpty ? nil : payload
    }

    /// Applies the given `AppleDoublePayload` to the file at `url` by writing its extended attributes.
    /// Missing / unreadable attributes are ignored; failures are only thrown for hard errors.
    static func applyAppleDoublePayload(_ payload: AppleDoublePayload, to url: URL) {
        let fsRep = FileManager().fileSystemRepresentation(withPath: url.path)
        if let fi = payload.finderInfo, !fi.isEmpty {
            // Finder Info is always 32 bytes.
            let trimmed = fi.count >= AppleDouble.finderInfoSize
                ? fi.prefix(AppleDouble.finderInfoSize)
                : fi + Data(count: AppleDouble.finderInfoSize - fi.count)
            setExtendedAttribute(fsRep: fsRep, name: finderInfoXattrName, value: Data(trimmed))
        }
        if let rf = payload.resourceFork, !rf.isEmpty {
            setExtendedAttribute(fsRep: fsRep, name: resourceForkXattrName, value: rf)
        }
        for (name, value) in payload.extendedAttributes {
            setExtendedAttribute(fsRep: fsRep, name: name, value: value)
        }
    }

    private static func listExtendedAttributeNames(fsRep: UnsafePointer<CChar>) -> [String]? {
        let size = listxattr(fsRep, nil, 0, XATTR_NOFOLLOW)
        if size < 0 { return nil }
        if size == 0 { return [] }
        var buffer = [CChar](repeating: 0, count: size)
        let got = buffer.withUnsafeMutableBufferPointer { ptr -> ssize_t in
            return listxattr(fsRep, ptr.baseAddress, ptr.count, XATTR_NOFOLLOW)
        }
        guard got > 0 else { return [] }
        var names: [String] = []
        var current = [CChar]()
        for i in 0..<Int(got) {
            let c = buffer[i]
            if c == 0 {
                if !current.isEmpty {
                    current.append(0)
                    if let name = String(validatingUTF8: current) { names.append(name) }
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(c)
            }
        }
        return names
    }

    private static func getExtendedAttribute(fsRep: UnsafePointer<CChar>, name: String) -> Data? {
        let size = getxattr(fsRep, name, nil, 0, 0, XATTR_NOFOLLOW)
        if size < 0 { return nil }
        if size == 0 { return Data() }
        var data = Data(count: size)
        let got = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> ssize_t in
            guard let base = ptr.baseAddress else { return -1 }
            return getxattr(fsRep, name, base, ptr.count, 0, XATTR_NOFOLLOW)
        }
        guard got >= 0 else { return nil }
        if got < size { data.removeSubrange(Int(got)..<size) }
        return data
    }

    @discardableResult
    private static func setExtendedAttribute(fsRep: UnsafePointer<CChar>, name: String, value: Data) -> Bool {
        let result = value.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int32 in
            return setxattr(fsRep, name, ptr.baseAddress, value.count, 0, XATTR_NOFOLLOW)
        }
        return result == 0
    }
}

#endif
