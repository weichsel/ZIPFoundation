//
//  MemoryFile.swift
//  ZIPFoundation
//
//  Copyright © 2017-2019 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

class MemoryFile {
    public private(set) var data:   Data
    private var offset  = 0

    init(data: Data = Data()) {
        self.data = data
    }

    func open(mode: String) -> UnsafeMutablePointer<FILE>? {
        let cookie   = Unmanaged.passRetained(self)
        let writable = mode.count > 0 && (mode.first! != "r" || mode.last! == "+")
        let append   = mode.count > 0 && mode.first! == "a"
        #if os(macOS) || os(iOS) || os(tvOS)
        let result = writable
            ? funopen(cookie.toOpaque(), readStub, writeStub, seekStub, closeStub)
            : funopen(cookie.toOpaque(), readStub, nil, seekStub, closeStub)
        #endif
        if append {
            fseek(result, 0, SEEK_END)
        }
        return result
    }

    fileprivate func readData(buffer: UnsafeMutableRawBufferPointer) -> Int {
        let sz = min(buffer.count, data.count-offset)
        data.copyBytes(to: buffer, from: offset..<offset+sz)
        offset += sz
        return sz
    }

    fileprivate func writeData(buffer: UnsafeRawBufferPointer) -> Int {
        if offset < data.count && offset+buffer.count > data.count {
            data.removeSubrange(offset..<data.count)
        } else if offset > data.count {
            data.append(Data(count: offset-data.count))
        }
        if offset == data.count {
            data.append(buffer.bindMemory(to: UInt8.self))
        } else {
            data.replaceSubrange(offset..<offset+buffer.count, with: buffer.bindMemory(to: UInt8.self))
        }
        offset += buffer.count
        return buffer.count
    }

    fileprivate func seek(offset: Int, whence: Int32) -> Int {
        switch whence {
        case SEEK_SET:
            self.offset = offset
        case SEEK_CUR:
            self.offset += offset
        case SEEK_END:
            self.offset = data.count+offset
        default:
            assertionFailure("Unknown seek whence \(whence)")
        }
        return self.offset
    }

}

fileprivate func fileFromCookie(cookie: UnsafeRawPointer) -> MemoryFile {
    return Unmanaged<MemoryFile>.fromOpaque(cookie).takeUnretainedValue()
}

fileprivate func closeStub(_ cookie: UnsafeMutableRawPointer?) -> Int32 {
    if let cookie = cookie {
        Unmanaged<MemoryFile>.fromOpaque(cookie).release()
    }
    return 0
}

#if os(macOS) || os(iOS) || os(tvOS)
fileprivate func readStub(_ cookie: UnsafeMutableRawPointer?, _ bytePtr: UnsafeMutablePointer<Int8>?, _ count: Int32) -> Int32 {
    guard let cookie = cookie, let bytePtr = bytePtr else { return 0 }
    return Int32(fileFromCookie(cookie: cookie).readData(
        buffer: UnsafeMutableRawBufferPointer(start: bytePtr, count: Int(count))))
}

fileprivate func writeStub(_ cookie: UnsafeMutableRawPointer?, _ bytePtr: UnsafePointer<Int8>?, _ count: Int32) -> Int32 {
    guard let cookie = cookie, let bytePtr = bytePtr else { return 0 }
    return Int32(fileFromCookie(cookie: cookie).writeData(
        buffer: UnsafeRawBufferPointer(start: bytePtr, count: Int(count))))
}

fileprivate func seekStub(_ cookie: UnsafeMutableRawPointer?, _ offset: fpos_t, _ whence: Int32) -> fpos_t {
    guard let cookie = cookie else { return 0 }
    return fpos_t(fileFromCookie(cookie: cookie).seek(offset: Int(offset), whence: whence))
}
#endif
