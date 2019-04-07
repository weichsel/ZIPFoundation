//
//  Data+Serialization.swift
//  ZIPFoundation
//
//  Copyright © 2017-2019 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/blob/master/LICENSE for license information.
//

import Foundation

protocol DataSerializable {
    static var size: Int { get }
    init?(data: Data, additionalDataProvider: (Int) throws -> Data)
    var data: Data { get }
}

extension Data {
    enum DataError: Error {
        case unreadableFile
        case unwritableFile
    }

    func scanValue<T>(start: Int) -> T {
        let subdata = self.subdata(in: start..<start+MemoryLayout<T>.size)
        #if swift(>=5.0)
        return subdata.withUnsafeBytes { $0.load(as: T.self) }
        #else
        return subdata.withUnsafeBytes { $0.pointee }
        #endif
    }

    func withUnsafeUInt8Pointer<T>(_ body: (UnsafePointer<UInt8>) throws -> T) rethrows -> T {
        #if swift(>=5.0)
        return try self.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) -> T in
            let unsafeBufferPointer = rawBufferPointer.bindMemory(to: UInt8.self)
            guard let unsafePointer = unsafeBufferPointer.baseAddress else {
                var int: UInt8 = 0
                return try body(&int)
            }
            return try body(unsafePointer)
        }
        #else
        return try self.withUnsafeBytes(body)
        #endif
    }

    static func readStruct<T>(from file: UnsafeMutablePointer<FILE>, at offset: Int) -> T? where T: DataSerializable {
        fseek(file, offset, SEEK_SET)
        guard let data = try? self.readChunk(of: T.size, from: file) else {
            return nil
        }
        let structure = T(data: data, additionalDataProvider: { (additionalDataSize) -> Data in
            return try self.readChunk(of: additionalDataSize, from: file)
        })
        return structure
    }

    static func consumePart(of size: Int, chunkSize: Int, skipCRC32: Bool = false,
                            provider: Provider, consumer: Consumer) throws -> CRC32 {
        let readInOneChunk = (size < chunkSize)
        var chunkSize = readInOneChunk ? size : chunkSize
        var checksum = CRC32(0)
        var bytesRead = 0
        while bytesRead < size {
            let remainingSize = size - bytesRead
            chunkSize = remainingSize < chunkSize ? remainingSize : chunkSize
            let data = try provider(bytesRead, chunkSize)
            try consumer(data)
            if !skipCRC32 {
                checksum = data.crc32(checksum: checksum)
            }
            bytesRead += chunkSize
        }
        return checksum
    }

    static func readChunk(of size: Int, from file: UnsafeMutablePointer<FILE>) throws -> Data {
        #if swift(>=4.1)
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        #else
        let bytes = UnsafeMutableRawPointer.allocate(bytes: size, alignedTo: 1)
        #endif
        let bytesRead = fread(bytes, 1, size, file)
        let error = ferror(file)
        if error > 0 {
            throw DataError.unreadableFile
        }
        return Data(bytesNoCopy: bytes, count: bytesRead, deallocator: .custom({ buf, _ in buf.deallocate() }))
    }

    static func write(chunk: Data, to file: UnsafeMutablePointer<FILE>) throws -> Int {
        var sizeWritten = 0
        chunk.withUnsafeUInt8Pointer { sizeWritten = fwrite($0, 1, chunk.count, file) }
        let error = ferror(file)
        if error > 0 {
            throw DataError.unwritableFile
        }
        return sizeWritten
    }
}
