//
//  Data+Serialization.swift
//  ZIPFoundation
//
//  Copyright © 2017 Thomas Zoechling, https://www.peakstep.com and the ZIP Foundation project authors.
//  Released under the MIT License.
//
//  See https://github.com/weichsel/ZIPFoundation/LICENSE for license information.
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
        return self.subdata(in: start..<start+MemoryLayout<T>.size).withUnsafeBytes { $0.pointee }
    }

    static func readStructure<T>(from file:UnsafeMutablePointer<FILE>, at offset: Int) -> T? where T: DataSerializable {
        fseek(file, offset, SEEK_SET)
        guard let data = try? self.readChunk(from: file, size: T.size) else {
            return nil
        }
        let structure = T(data: data, additionalDataProvider: { (additionalDataSize) -> Data in
            return try self.readChunk(from: file, size: additionalDataSize)
        })
        return structure
    }

    static func readChunk(from file: UnsafeMutablePointer<FILE>, size: Int) throws -> Data {
        let bytes = UnsafeMutableRawPointer.allocate(bytes: size, alignedTo: 1)
        let bytesRead = fread(bytes, 1, size, file)
        let error = ferror(file)
        if error > 0 {
            throw DataError.unreadableFile
        }
        return Data(bytesNoCopy: bytes, count: bytesRead, deallocator: Data.Deallocator.free)
    }

    static func consumePart(of file: UnsafeMutablePointer<FILE>,
                            size: Int, chunkSize: Int, skipCRC32: Bool = false,
                            consumer: Consumer) throws -> CRC32 {
        let readInOneChunk = (size < chunkSize)
        var chunkSize = readInOneChunk ? size : chunkSize
        var checksum = CRC32(0)
        var bytesRead = 0
        while bytesRead < size {
            let remainingSize = size - bytesRead
            chunkSize = remainingSize < chunkSize ? remainingSize : chunkSize
            let data = try Data.readChunk(from: file, size: Int(chunkSize))
            try consumer(data)
            if !skipCRC32 {
                checksum = data.crc32(checksum: checksum)
            }
            bytesRead += chunkSize
        }
        return checksum
    }

    static func write(chunk: Data, to file: UnsafeMutablePointer<FILE>) throws -> Int {
        var sizeWritten = 0
        chunk.withUnsafeBytes { sizeWritten = fwrite($0, 1, chunk.count, file) }
        let error = ferror(file)
        if error > 0 {
            throw DataError.unwritableFile
        }
        return sizeWritten
    }
}
