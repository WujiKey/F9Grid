//
//  F9GridBatchTests.swift
//  F9GridTests
//
//  Batch test data validation for F9Grid coordinate system
//  Reads test cases from f9grid_test.toml and validates index, k, and positionCode
//

import XCTest
@testable import F9Grid

class F9GridBatchTests: XCTestCase {

    // MARK: - Test Data Validation

    func testAllTestData() throws {
        let testCases = try loadTestCases()

        XCTAssertGreaterThan(testCases.count, 0, "Test file should contain test cases")

        var failedLines: [Int] = []
        var failedDetails: [String] = []
        var passedCount = 0

        for testCase in testCases {
            var lineHasError = false

            // Test cell lookup
            guard let cell = F9Grid.cell(lat: testCase.lat, lng: testCase.lng) else {
                failedDetails.append("Line \(testCase.line): cell(lat: \(testCase.lat), lng: \(testCase.lng)) returned nil")
                failedLines.append(testCase.line)
                continue
            }

            // Verify index
            if cell.index != testCase.expectedIndex {
                failedDetails.append("Line \(testCase.line): Index mismatch for (\(testCase.lat), \(testCase.lng)): expected \(testCase.expectedIndex), got \(cell.index)")
                lineHasError = true
            }

            // Verify k value
            if cell.k != testCase.expectedK {
                failedDetails.append("Line \(testCase.line): K mismatch for (\(testCase.lat), \(testCase.lng)): expected \(testCase.expectedK), got \(cell.k)")
                lineHasError = true
            }

            // Verify position code
            let actualPositionCode = cell.positionCode(lat: testCase.latDecimal, lng: testCase.lngDecimal)
            if actualPositionCode != testCase.expectedPositionCode {
                failedDetails.append("Line \(testCase.line): PositionCode mismatch for (\(testCase.lat), \(testCase.lng)): expected \(testCase.expectedPositionCode), got \(actualPositionCode)")
                lineHasError = true
            }

            if lineHasError {
                failedLines.append(testCase.line)
            } else {
                passedCount += 1
            }
        }

        // Print summary
        let failedCount = failedLines.count
        let uniqueFailedLines = Array(Set(failedLines)).sorted()

        print("\n========== Test Data Summary ==========")
        print("Total coordinates tested: \(testCases.count)")
        print("Passed: \(passedCount)")
        print("Failed: \(failedCount)")

        if !uniqueFailedLines.isEmpty {
            print("Failed lines: \(uniqueFailedLines.map(String.init).joined(separator: ", "))")
            print("\nFailure details:")
            for detail in failedDetails {
                print("  - \(detail)")
            }
        }
        print("========================================\n")

        // Report failures
        if !failedDetails.isEmpty {
            let summary = """
            Test data validation failed:
            - Total: \(testCases.count), Passed: \(passedCount), Failed: \(failedCount)
            - Failed lines: \(uniqueFailedLines.map(String.init).joined(separator: ", "))

            Details:
            \(failedDetails.joined(separator: "\n"))
            """
            XCTFail(summary)
        }
    }

    // MARK: - Individual Field Tests

    func testIndexValues() throws {
        let testCases = try loadTestCases()

        var passedCount = 0
        var failedLines: [Int] = []

        for testCase in testCases {
            guard let cell = F9Grid.cell(lat: testCase.lat, lng: testCase.lng) else {
                failedLines.append(testCase.line)
                continue
            }

            if cell.index == testCase.expectedIndex {
                passedCount += 1
            } else {
                failedLines.append(testCase.line)
            }
        }

        print("\n[Index Test] Total: \(testCases.count), Passed: \(passedCount), Failed: \(failedLines.count)")
        if !failedLines.isEmpty {
            print("[Index Test] Failed lines: \(failedLines.sorted().map(String.init).joined(separator: ", "))")
        }

        XCTAssertEqual(failedLines.count, 0,
            "Index validation failed for \(failedLines.count) lines: \(failedLines.sorted())")
    }

    func testKValues() throws {
        let testCases = try loadTestCases()

        var passedCount = 0
        var failedLines: [Int] = []

        for testCase in testCases {
            guard let cell = F9Grid.cell(lat: testCase.lat, lng: testCase.lng) else {
                failedLines.append(testCase.line)
                continue
            }

            if cell.k == testCase.expectedK {
                passedCount += 1
            } else {
                failedLines.append(testCase.line)
            }
        }

        print("\n[K Value Test] Total: \(testCases.count), Passed: \(passedCount), Failed: \(failedLines.count)")
        if !failedLines.isEmpty {
            print("[K Value Test] Failed lines: \(failedLines.sorted().map(String.init).joined(separator: ", "))")
        }

        XCTAssertEqual(failedLines.count, 0,
            "K value validation failed for \(failedLines.count) lines: \(failedLines.sorted())")
    }

    func testPositionCodes() throws {
        let testCases = try loadTestCases()

        var passedCount = 0
        var failedLines: [Int] = []

        for testCase in testCases {
            guard let cell = F9Grid.cell(lat: testCase.lat, lng: testCase.lng) else {
                failedLines.append(testCase.line)
                continue
            }

            let actualPositionCode = cell.positionCode(lat: testCase.latDecimal, lng: testCase.lngDecimal)
            if actualPositionCode == testCase.expectedPositionCode {
                passedCount += 1
            } else {
                failedLines.append(testCase.line)
            }
        }

        print("\n[PositionCode Test] Total: \(testCases.count), Passed: \(passedCount), Failed: \(failedLines.count)")
        if !failedLines.isEmpty {
            print("[PositionCode Test] Failed lines: \(failedLines.sorted().map(String.init).joined(separator: ", "))")
        }

        XCTAssertEqual(failedLines.count, 0,
            "PositionCode validation failed for \(failedLines.count) lines: \(failedLines.sorted())")
    }

    // MARK: - Helper Types

    private struct TestCase {
        let line: Int
        let lat: String
        let lng: String
        let latDecimal: Decimal
        let lngDecimal: Decimal
        let expectedIndex: Int64
        let expectedK: Int
        let expectedPositionCode: Int
    }

    // MARK: - File Loading

    private func loadTestCases() throws -> [TestCase] {
        let content = try loadFile(name: "f9grid_test", ext: "toml")
        return try parseTestTOML(content)
    }

    private func loadFile(name: String, ext: String) throws -> String {
        // Path 1: Bundle resource
        let testBundle = Bundle(for: type(of: self))
        if let path = testBundle.path(forResource: name, ofType: ext) {
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                return content
            }
        }

        // Path 2: Relative to test file location (for SPM test execution)
        let currentFile = #file
        if let testDir = currentFile.components(separatedBy: "/").dropLast().joined(separator: "/") as String? {
            let filePath = testDir + "/Fixtures/\(name).\(ext)"
            if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
                return content
            }
        }

        // Path 3: Direct path
        if let content = try? String(contentsOfFile: "\(name).\(ext)", encoding: .utf8) {
            return content
        }

        throw TestFileError.fileNotFound
    }

    // MARK: - Minimal TOML Parser (no external dependencies)
    //
    // Supports the specific subset used by f9grid_test.toml:
    //   test = [
    //       ["str", "str", int, int, int],  # optional inline comment
    //       # full-line comment
    //   ]

    private func parseTestTOML(_ content: String) throws -> [TestCase] {
        let lines = content.components(separatedBy: .newlines)
        var testCases: [TestCase] = []
        var insideArray = false

        for (lineIndex, rawLine) in lines.enumerated() {
            let lineNumber = lineIndex + 1

            // Strip inline comment: find first '#' that is not inside a quoted string
            let stripped = stripTOMLComment(rawLine).trimmingCharacters(in: .whitespaces)

            if stripped.isEmpty { continue }

            if !insideArray {
                // Detect start of the test array
                if stripped.hasPrefix("test") && stripped.contains("[") {
                    insideArray = true
                }
                continue
            }

            // Detect end of the test array
            if stripped == "]" { break }

            // Skip lines that don't start a data row
            guard stripped.hasPrefix("[") else { continue }

            // Parse ["lat", "lng", index, k, positionCode]
            // Remove surrounding brackets and optional trailing comma
            var inner = stripped
            if inner.hasSuffix(",") { inner.removeLast() }
            guard inner.hasPrefix("[") && inner.hasSuffix("]") else {
                throw TestFileError.parseError(line: lineNumber)
            }
            inner = String(inner.dropFirst().dropLast())

            // Split on commas, respecting quoted strings
            let parts = splitTOMLRow(inner)
            guard parts.count == 5 else {
                throw TestFileError.parseError(line: lineNumber)
            }

            let lat = parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let lng = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let indexStr = parts[2].trimmingCharacters(in: .whitespaces)
            let kStr    = parts[3].trimmingCharacters(in: .whitespaces)
            let posStr  = parts[4].trimmingCharacters(in: .whitespaces)

            guard let expectedIndex = Int64(indexStr),
                  let expectedK = Int64(kStr),
                  let expectedPositionCode = Int64(posStr),
                  let latDecimal = Decimal(string: lat),
                  let lngDecimal = Decimal(string: lng) else {
                throw TestFileError.parseError(line: lineNumber)
            }

            testCases.append(TestCase(
                line: lineNumber,
                lat: lat,
                lng: lng,
                latDecimal: latDecimal,
                lngDecimal: lngDecimal,
                expectedIndex: expectedIndex,
                expectedK: Int(expectedK),
                expectedPositionCode: Int(expectedPositionCode)
            ))
        }

        return testCases
    }

    /// Strips a TOML comment (everything from the first '#' not inside a quoted string).
    private func stripTOMLComment(_ line: String) -> String {
        var inString = false
        for (idx, ch) in line.enumerated() {
            if ch == "\"" { inString.toggle() }
            if ch == "#" && !inString {
                return String(line.prefix(idx))
            }
        }
        return line
    }

    /// Splits a TOML inline array row on commas, ignoring commas inside quoted strings.
    private func splitTOMLRow(_ s: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inString = false
        for ch in s {
            if ch == "\"" { inString.toggle() }
            if ch == "," && !inString {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts
    }

    // MARK: - Errors

    private enum TestFileError: Error, CustomStringConvertible {
        case fileNotFound
        case parseError(line: Int)

        var description: String {
            switch self {
            case .fileNotFound:
                return "Could not load test file f9grid_test.toml"
            case .parseError(let line):
                return "Failed to parse test data at row \(line)"
            }
        }
    }
}
