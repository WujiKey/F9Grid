//
//  F9GridPlusCodeTests.swift
//  F9GridTests
//
//  Tests for PlusCode encoding/decoding extension
//

import XCTest
@testable import F9Grid

class F9GridPlusCodeTests: XCTestCase {

    // MARK: - Basic PlusCode Decoding

    func testPlusCodeDecoding() {
        // Shanghai approximate location
        let cell = F9Grid.cell(plusCode: "8QQCJX8V+QF")
        XCTAssertNotNil(cell)
        XCTAssertFalse(cell?.isPole ?? true)
    }

    func testPlusCodeWithPlus() {
        let cell1 = F9Grid.cell(plusCode: "8QQCJX8V+QF")
        let cell2 = F9Grid.cell(plusCode: "8QQCJX8VQF")
        XCTAssertEqual(cell1?.index, cell2?.index)
    }

    func testPlusCodeWithSpaces() {
        let cell1 = F9Grid.cell(plusCode: "8QQCJX8V+QF")
        let cell2 = F9Grid.cell(plusCode: "8QQC JX8V +QF")
        XCTAssertEqual(cell1?.index, cell2?.index)
    }

    func testPlusCodeLowercase() {
        let cell1 = F9Grid.cell(plusCode: "8QQCJX8V+QF")
        let cell2 = F9Grid.cell(plusCode: "8qqcjx8v+qf")
        XCTAssertEqual(cell1?.index, cell2?.index)
    }

    // MARK: - Invalid Input Tests

    func testPlusCodeInvalidInput() {
        let cell1 = F9Grid.cell(plusCode: "invalid")
        XCTAssertNil(cell1)

        let cell2 = F9Grid.cell(plusCode: "8Q33")  // Too short
        XCTAssertNil(cell2)
    }

    func testPlusCodeInvalidCharacters() {
        // PlusCode uses specific 20 characters: 23456789CFGHJMPQRVWX
        // Characters like A, B, I, L, O, U are not valid
        let cell = F9Grid.cell(plusCode: "ABCD1234+AB")
        XCTAssertNil(cell)
    }

    // MARK: - Pole Region Tests

    func testPlusCodeNorthPole() {
        // PlusCode for north pole region
        let cell = F9Grid.cell(plusCode: "CFXXXXXX+XX")
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.index, F9Grid.northPoleIndex)
    }

    func testPlusCodeSouthPole() {
        // PlusCode for south pole region
        let cell = F9Grid.cell(plusCode: "22222222+22")
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.index, F9Grid.southPoleIndex)
    }

    // MARK: - Known Location Tests

    func testPlusCodeBeijing() {
        // Beijing approximate location
        let cell = F9Grid.cell(plusCode: "8PFRW9C9+XX")
        XCTAssertNotNil(cell)
        XCTAssertFalse(cell?.isPole ?? true)
    }

    func testPlusCodeEquator() {
        // Equator at prime meridian
        let cell = F9Grid.cell(plusCode: "6FG22222+22")
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.step, 240000)  // Equator step
    }

    // MARK: - Consistency Tests

    func testPlusCodeConsistencyWithCoordinates() {
        // Test that PlusCode method returns valid cell
        // and the cell center can be used to get the same cell back
        let plusCodeCell = F9Grid.cell(plusCode: "8QQCJX8V+22")
        XCTAssertNotNil(plusCodeCell)

        if let cell = plusCodeCell {
            // Using the cell's center coordinates should return the same cell
            let centerLat = String(cell.centerLat)
            let centerLng = String(cell.centerLng)
            let coordCell = F9Grid.cell(lat: centerLat, lng: centerLng)

            XCTAssertNotNil(coordCell)
            XCTAssertEqual(cell.index, coordCell?.index)
        }
    }
}
