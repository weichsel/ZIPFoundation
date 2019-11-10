//
//  ZIPFoundationMemoryFileTests.swift
//  ZIPFoundation
//
//  Created by Matthias Neeracher on 28.10.19.
//

import Foundation

import XCTest
@testable import ZIPFoundation

extension ZIPFoundationTests {
    func testReadOnlyFile() {
        let file = MemoryFile(data: "ABCDEabcde".data(using: .utf8)!).open(mode: "r")
        var ch : [UInt8] = [0, 0, 0]
        XCTAssertEqual(fread(&ch, 1, 2, file), 2)
        XCTAssertEqual(String(Unicode.Scalar(ch[0])), "A")
        XCTAssertEqual(String(Unicode.Scalar(ch[1])), "B")
        XCTAssertNotEqual(fwrite("x", 1, 1, file), 1)
        XCTAssertEqual(fseek(file, 3, SEEK_CUR), 0)
        XCTAssertEqual(fread(&ch, 1, 2, file), 2)
        XCTAssertEqual(String(Unicode.Scalar(ch[0])), "a")
        XCTAssertEqual(String(Unicode.Scalar(ch[1])), "b")
        XCTAssertEqual(fseek(file, 9, SEEK_SET), 0)
        XCTAssertEqual(fread(&ch, 1, 2, file), 1)
        XCTAssertEqual(String(Unicode.Scalar(ch[0])), "e")
        XCTAssertEqual(String(Unicode.Scalar(ch[1])), "b")
        XCTAssertEqual(fclose(file), 0)
    }

    func testReadOnlySlicedFile() {
        let originalData = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".data(using: .utf8)!
        let slice        = originalData[10..<originalData.count]
        let file = MemoryFile(data: slice).open(mode: "r")
        var ch : [UInt8] = [0, 0, 0]
        XCTAssertEqual(fread(&ch, 1, 2, file), 2)
        XCTAssertEqual(String(Unicode.Scalar(ch[0])), "A")
        XCTAssertEqual(String(Unicode.Scalar(ch[1])), "B")
    }

    func testWriteOnlyFile() {
        let mem  = MemoryFile()
        let file = mem.open(mode: "w")
        XCTAssertEqual(fwrite("01234", 1, 5, file), 5)
        XCTAssertEqual(fseek(file, -2, SEEK_END), 0)
        XCTAssertEqual(fwrite("5678", 1, 4, file), 4)
        XCTAssertEqual(fwrite("9", 1, 1, file), 1)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, "01256789".data(using: .utf8))
    }

    func testReadWriteFile() {
        let mem  = MemoryFile(data: "witch".data(using: .utf8)!)
        let file = mem.open(mode: "r+")
        XCTAssertEqual(fseek(file, 1, SEEK_CUR), 0)
        XCTAssertEqual(fwrite("a", 1, 1, file), 1)
        XCTAssertEqual(fseek(file, 0, SEEK_END), 0)
        XCTAssertEqual(fwrite("face", 1, 4, file), 4)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, "watchface".data(using: .utf8))
    }

    func testAppendFile() {
        let mem  = MemoryFile(data: "anti".data(using: .utf8)!)
        let file = mem.open(mode: "a+")
        XCTAssertEqual(fwrite("cipation", 1, 8, file), 8)
        XCTAssertEqual(fflush(file), 0)
        XCTAssertEqual(mem.data, "anticipation".data(using: .utf8))
    }
}
