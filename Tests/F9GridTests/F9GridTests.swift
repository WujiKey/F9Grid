//
//  F9GridTests.swift
//  F9GridTests
//
//  Comprehensive tests for F9Grid coordinate system
//

import XCTest
@testable import F9Grid

class F9GridTests: XCTestCase {

    // MARK: - Constants Tests

    func testConstants() {
        XCTAssertEqual(F9Grid.scale, 8000)
        XCTAssertEqual(F9Grid.base90, 720_000)
        XCTAssertEqual(F9Grid.base360, 2_880_000)
        XCTAssertEqual(F9Grid.gridLatStep, 3)
        XCTAssertEqual(F9Grid.gridNorthPoleBoundary, 719997)
        XCTAssertEqual(F9Grid.gridSouthPoleBoundary, -719997)
        XCTAssertEqual(F9Grid.northPoleIndex, 0)
        XCTAssertEqual(F9Grid.southPoleIndex, 300_626_092_559)
        XCTAssertEqual(F9Grid.totalGrids, 300_626_092_560)
        XCTAssertEqual(F9Grid.totalLatitudeSteps, 480_000)
    }

    // MARK: - North Pole Tests

    func testNorthPoleExact() {
        let cell = F9Grid.cell(lat: "90", lng: "0")
        XCTAssertNotNil(cell)

        if let cell = cell {
            XCTAssertEqual(cell.index, F9Grid.northPoleIndex)
            XCTAssertEqual(cell.k, F9Grid.base360)
            XCTAssertEqual(cell.step, 1)
            XCTAssertTrue(cell.isPole)

            let positionCode = cell.positionCode(lat: Decimal(90), lng: Decimal(0))
            XCTAssertEqual(positionCode, F9Grid.northPolePositionCode)
        }
    }

    func testNorthPoleWithVariousLongitudes() {
        let longitudes = ["0", "90", "180", "-180", "-90", "45.5", "-123.456"]

        for lng in longitudes {
            let cell = F9Grid.cell(lat: "90", lng: lng)
            XCTAssertNotNil(cell)
            XCTAssertEqual(cell?.index, F9Grid.northPoleIndex)
        }
    }

    func testNorthPoleBoundaryExact() {
        let cell = F9Grid.cell(lat: "89.999625", lng: "0")
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.index, F9Grid.northPoleIndex)
        XCTAssertTrue(cell?.isPole ?? false)
    }

    // MARK: - South Pole Tests

    func testSouthPoleExact() {
        let cell = F9Grid.cell(lat: "-90", lng: "0")
        XCTAssertNotNil(cell)

        if let cell = cell {
            XCTAssertEqual(cell.index, F9Grid.southPoleIndex)
            XCTAssertEqual(cell.k, F9Grid.base360)
            XCTAssertTrue(cell.isPole)

            let positionCode = cell.positionCode(lat: Decimal(-90), lng: Decimal(0))
            XCTAssertEqual(positionCode, F9Grid.southPolePositionCode)
        }
    }

    func testSouthPoleBoundaryExact() {
        // -89.999625 is ABOVE the south pole boundary (inside last ring, not pole)
        // Uses [lower, upper) convention: south pole is lat < -89.999625
        let cell1 = F9Grid.cell(lat: "-89.999625", lng: "0")
        XCTAssertNotNil(cell1)
        XCTAssertNotEqual(cell1?.index, F9Grid.southPoleIndex)  // Last ring, not south pole

        // -89.99962501 should be in south pole (lat < -89.999625)
        // gridLat = -89.99962501 * 8000 = -719997.00008, truncates to -719997
        // -719997 < -719997 is false, so it's NOT south pole yet
        // Need -719998 or lower, which is -89.99975 or lower
        let cell2 = F9Grid.cell(lat: "-89.99975", lng: "0")
        XCTAssertNotNil(cell2)
        XCTAssertEqual(cell2?.index, F9Grid.southPoleIndex)
    }

    // MARK: - Equator Tests

    func testEquatorOrigin() {
        let cell = F9Grid.cell(lat: "0", lng: "0")
        XCTAssertNotNil(cell)

        if let cell = cell {
            XCTAssertFalse(cell.isPole)
            XCTAssertEqual(cell.k, 3)  // Equator has minimum k
            XCTAssertEqual(cell.step, 240000)  // Equator step
        }
    }

    func testEquatorLongitudeVariations() {
        let testCases: [(lng: String, expectedLngWest: Decimal)] = [
            ("0", Decimal(0)),
            ("45", Decimal(string: "44.999625")!),
            ("90", Decimal(string: "89.999625")!),
            ("-90", Decimal(string: "269.999625")!),
        ]

        for (lng, _) in testCases {
            let cell = F9Grid.cell(lat: "0", lng: lng)
            XCTAssertNotNil(cell)
            XCTAssertEqual(cell?.step, 240000)
        }
    }

    // MARK: - Position Code Tests

    func testPositionCodeAtCenter() {
        let cell = F9Grid.cell(lat: "0", lng: "0")
        XCTAssertNotNil(cell)

        if let cell = cell {
            // Center of cell should be position code 5
            let centerLat = (cell.latRangeDecimal.south + cell.latRangeDecimal.north) / 2
            let centerLng = (cell.lngRangeDecimal.west + cell.lngRangeDecimal.east) / 2
            let posCode = cell.positionCode(lat: centerLat, lng: centerLng)
            XCTAssertEqual(posCode, 5)
        }
    }

    func testPositionCodeAtBoundaries() {
        let cell = F9Grid.cell(lat: "0", lng: "0")
        XCTAssertNotNil(cell)

        if let cell = cell {
            // Use addition-based boundary calculation (same as implementation)
            let baseUnit = Decimal(1) / Decimal(8000)
            let lat1_3 = cell.latRangeDecimal.south + baseUnit
            let lat2_3 = cell.latRangeDecimal.south + baseUnit * 2

            let lngStep = cell.lngRangeDecimal.east - cell.lngRangeDecimal.west
            let lngSubUnit = lngStep / 3
            let lng1_3 = cell.lngRangeDecimal.west + lngSubUnit
            let lng2_3 = cell.lngRangeDecimal.west + lngSubUnit * 2

            // At 1/3 boundary
            let code13 = cell.positionCode(lat: lat1_3, lng: lng1_3)
            XCTAssertEqual(code13, 5)  // middle zone

            // At 2/3 boundary
            let code23 = cell.positionCode(lat: lat2_3, lng: lng2_3)
            XCTAssertEqual(code23, 2)  // NE zone
        }
    }

    func testAllPositionCodesInCell() {
        let cell = F9Grid.cell(lat: "0", lng: "0")
        XCTAssertNotNil(cell)

        if let cell = cell {
            let baseUnit = Decimal(1) / Decimal(8000)
            let lngStep = cell.lngRangeDecimal.east - cell.lngRangeDecimal.west

            // Test all 9 positions
            let testPoints: [(latOffset: Decimal, lngOffset: Decimal, expectedCode: Int)] = [
                // South row
                (baseUnit / 2, lngStep / 6, 8),           // SW
                (baseUnit / 2, lngStep / 2, 1),           // S
                (baseUnit / 2, lngStep * 5 / 6, 6),       // SE
                // Middle row
                (baseUnit * 3 / 2, lngStep / 6, 3),       // W
                (baseUnit * 3 / 2, lngStep / 2, 5),       // C
                (baseUnit * 3 / 2, lngStep * 5 / 6, 7),   // E
                // North row
                (baseUnit * 5 / 2, lngStep / 6, 4),       // NW
                (baseUnit * 5 / 2, lngStep / 2, 9),       // N
                (baseUnit * 5 / 2, lngStep * 5 / 6, 2),   // NE
            ]

            for (latOffset, lngOffset, expectedCode) in testPoints {
                let lat = cell.latRangeDecimal.south + latOffset
                let lng = cell.lngRangeDecimal.west + lngOffset
                let actualCode = cell.positionCode(lat: lat, lng: lng)
                XCTAssertEqual(actualCode, expectedCode, "Position (\(latOffset), \(lngOffset))")
            }
        }
    }

    // MARK: - Index Roundtrip Tests

    func testIndexToCellRoundtrip() {
        let testCoords: [(lat: String, lng: String)] = [
            ("0", "0"),
            ("31.230416", "121.473701"),
            ("39.9042", "116.4074"),
            ("-33.8688", "151.2093"),
            ("45", "90"),
            ("-45", "-90"),
        ]

        for (lat, lng) in testCoords {
            guard let cell1 = F9Grid.cell(lat: lat, lng: lng) else {
                continue
            }

            guard let cell2 = F9Grid.cell(index: cell1.index) else {
                XCTFail("Failed to get cell from index \(cell1.index)")
                continue
            }

            XCTAssertEqual(cell1.latRangeDecimal.south, cell2.latRangeDecimal.south)
            XCTAssertEqual(cell1.latRangeDecimal.north, cell2.latRangeDecimal.north)
            XCTAssertEqual(cell1.lngRangeDecimal.west, cell2.lngRangeDecimal.west)
            XCTAssertEqual(cell1.lngRangeDecimal.east, cell2.lngRangeDecimal.east)
            XCTAssertEqual(cell1.k, cell2.k)
            XCTAssertEqual(cell1.step, cell2.step)
        }
    }

    func testPoleIndexRoundtrip() {
        // North pole
        let northPole = F9Grid.cell(index: F9Grid.northPoleIndex)
        XCTAssertNotNil(northPole)
        XCTAssertEqual(northPole?.index, F9Grid.northPoleIndex)
        XCTAssertTrue(northPole?.isPole ?? false)

        // South pole
        let southPole = F9Grid.cell(index: F9Grid.southPoleIndex)
        XCTAssertNotNil(southPole)
        XCTAssertEqual(southPole?.index, F9Grid.southPoleIndex)
        XCTAssertTrue(southPole?.isPole ?? false)
    }

    // MARK: - K Band Tests

    func testHighLatitudeKValues() {
        // Near north pole, k should be large
        let cell1 = F9Grid.cell(lat: "89.99", lng: "0")
        XCTAssertNotNil(cell1)
        XCTAssertGreaterThan(cell1?.k ?? 0, 10000)

        // Near equator, k should be small
        let cell2 = F9Grid.cell(lat: "0", lng: "0")
        XCTAssertNotNil(cell2)
        XCTAssertEqual(cell2?.k, 3)
    }

    // MARK: - Longitude Wrapping Tests

    func testLongitudeWrapping() {
        let cell1 = F9Grid.cell(lat: "0", lng: "0")
        let cell2 = F9Grid.cell(lat: "0", lng: "360")
        let cell3 = F9Grid.cell(lat: "0", lng: "-360")

        XCTAssertNotNil(cell1)
        XCTAssertNotNil(cell2)
        XCTAssertNotNil(cell3)
        XCTAssertEqual(cell1?.index, cell2?.index)
        XCTAssertEqual(cell1?.index, cell3?.index)
    }

    func testDateLineCrossing() {
        let cell1 = F9Grid.cell(lat: "0", lng: "180")
        let cell2 = F9Grid.cell(lat: "0", lng: "-180")

        XCTAssertNotNil(cell1)
        XCTAssertNotNil(cell2)
        XCTAssertEqual(cell1?.index, cell2?.index)
    }

    // MARK: - findOriginalCell Tests

    func testFindOriginalCellSamePosition() {
        let testCases: [(lat: String, lng: String)] = [
            ("31.230416", "121.473701"),
            ("0", "0"),
            ("45", "90"),
        ]

        for (lat, lng) in testCases {
            guard let cell = F9Grid.cell(lat: lat, lng: lng) else {
                continue
            }

            let latDec = Decimal(string: lat)!
            let lngDec = Decimal(string: lng)!
            let posCode = cell.positionCode(lat: latDec, lng: lngDec)

            let foundIndex = F9Grid.findOriginalCell(lat: lat, lng: lng, originalPositionCode: posCode)
            XCTAssertEqual(foundIndex, cell.index)
        }
    }

    func testFindOriginalCellPoles() {
        // North pole
        let northIndex = F9Grid.findOriginalCell(lat: "90", lng: "0", originalPositionCode: F9Grid.northPolePositionCode)
        XCTAssertEqual(northIndex, F9Grid.northPoleIndex)

        // South pole
        let southIndex = F9Grid.findOriginalCell(lat: "-90", lng: "0", originalPositionCode: F9Grid.southPolePositionCode)
        XCTAssertEqual(southIndex, F9Grid.southPoleIndex)
    }

    // MARK: - Invalid Input Tests

    func testInvalidCoordinates() {
        let cell1 = F9Grid.cell(lat: "invalid", lng: "0")
        XCTAssertNil(cell1)

        let cell2 = F9Grid.cell(lat: "0", lng: "invalid")
        XCTAssertNil(cell2)
    }

    // MARK: - Index Data Tests

    func testIndexDataBigEndian() {
        // Test with a known index value
        let cell = F9Grid.cell(lat: "0", lng: "0")
        XCTAssertNotNil(cell)

        if let cell = cell {
            let data = cell.indexData
            XCTAssertEqual(data.count, 8)

            // Verify big-endian format: reconstruct the value
            let reconstructed = data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
            XCTAssertEqual(reconstructed, UInt64(cell.index))
        }
    }

    func testIndexDataPoles() {
        // North pole (index = 0)
        let northPole = F9Grid.cell(index: F9Grid.northPoleIndex)!
        let northData = northPole.indexData
        XCTAssertEqual(northData, Data([0, 0, 0, 0, 0, 0, 0, 0]))

        // South pole (index = 300_626_092_559)
        let southPole = F9Grid.cell(index: F9Grid.southPoleIndex)!
        let southData = southPole.indexData
        // 300_626_092_559 = 0x45FEB6220F in hex
        let expectedSouthData = Data([0x00, 0x00, 0x00, 0x45, 0xFE, 0xB6, 0x22, 0x0F])
        XCTAssertEqual(southData, expectedSouthData)
    }
}
