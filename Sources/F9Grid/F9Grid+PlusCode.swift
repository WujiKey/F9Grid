//
//  F9Grid+PlusCode.swift
//  F9Grid
//
//  PlusCode encoding/decoding extension for F9Grid
//

import Foundation

extension F9Grid {

    /// PlusCode character set (20 characters)
    private static let plusCodeChars = "23456789CFGHJMPQRVWX"

    /// Convert 10-digit PlusCode to F9Cell
    /// - Parameter plusCode: 10-digit PlusCode (e.g., "8PFRXG2G+22" or "8PFRXG2G22")
    /// - Returns: F9Cell with index and position code, or nil if invalid
    /// - Note: Uses pure integer arithmetic for PlusCode decoding
    public static func cell(plusCode: String) -> F9Cell? {
        // Remove + and spaces, uppercase
        let code = plusCode.replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        guard code.count >= 10 else { return nil }
        let chars = Array(code.prefix(10))

        // Validate and get indices
        var indices = [Int]()
        for c in chars {
            guard let idx = plusCodeChars.firstIndex(of: c) else { return nil }
            indices.append(plusCodeChars.distance(from: plusCodeChars.startIndex, to: idx))
        }

        // PlusCode decoding using pure integer arithmetic (base coordinates)
        // Base weights: 20° × 8000 = 160000, 1° × 8000 = 8000, 0.05° × 8000 = 400,
        //               0.0025° × 8000 = 20, 1/8000° × 8000 = 1
        // -90° × 8000 = -720000, -180° × 8000 = -1440000
        let gridLat = indices[0] * 160000 + indices[2] * 8000 + indices[4] * 400
                    + indices[6] * 20 + indices[8] - base90
        let gridLng = indices[1] * 160000 + indices[3] * 8000 + indices[5] * 400
                    + indices[7] * 20 + indices[9] - base360 / 2

        // Check for pole regions
        if gridLat >= gridNorthPoleBoundary {
            return northPoleCell
        }
        if gridLat < gridSouthPoleBoundary {
            return southPoleCell
        }

        // Convert to Decimal for position code calculation
        // For PlusCode, use the grid coordinates as Decimal (center of the 10-digit cell)
        let lat = Decimal(gridLat) / Decimal(scale)
        let lng = Decimal(gridLng) / Decimal(scale)

        return cell(lat: lat, lng: lng)
    }
}
