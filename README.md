# F9Grid

A truly GPS drift-resistant geographic grid system — with drift ≤11.8m, repeated measurements at grid edges always yield the same grid ID.

300 billion cells, 39-bit high entropy, stable and reliable, a natural geographic key.

[中文文档](README_zh.md)

<p align="center">
  <img src="Assets/F9Grid.jpg" width="600" alt="F9Grid Overview"/>
</p>

<p align="center"><em>Near-square cells with identical shape at each latitude. Each cell divided into 9 position codes for GPS drift correction.</em></p>

## Overview

F9Grid is a grid system developed and extended based on PlusCode's 10-digit code grid. It extends PlusCode by appropriately merging high-latitude grids along the longitude direction while keeping cells at the same latitude the same size, aiming to make the cell area close to the standard cell area.

Since all existing grid systems have various issues - either irregular shapes, significant area differences, or obvious distortion in some regions - it's impossible to have both regular shapes and GPS drift resistance. F9Grid solves this problem.

## Features

- **Regular Shape**: All cells are rectangular (except poles)
- **GPS Drift Resistance**: Uses position codes to correct GPS drift up to ~11.8 meters
- **PlusCode Compatible**: Grid lines always align with 10-digit PlusCode lines
- **Equal Area**: All cells aim for ~1730.963 m² (±14.2857%)
- **High Precision**: Uses Decimal internally to avoid floating-point errors

## Requirements

- Swift 5.0+
- iOS 12.0+ / macOS 10.13+ / tvOS 12.0+ / watchOS 4.0+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Forgetless/F9Grid.git", from: "1.0.0")
]
```

Or in Xcode: File → Add Package Dependencies → Enter the repository URL.

## Quick Start

```swift
import F9Grid

// Convert coordinates to F9Grid cell
let cell = F9Grid.cell(lat: "31.239696", lng: "121.499809")
print(cell?.index)  // Cell index

// Convert index back to cell
let cellFromIndex = F9Grid.cell(index: 12345678)
print(cellFromIndex?.centerLat, cellFromIndex?.centerLng)

// Get position code for GPS drift correction
let positionCode = cell?.positionCode(lat: Decimal(string: "31.239696")!,
                                       lng: Decimal(string: "121.499809")!)

// Find original cell after GPS drift
let originalIndex = F9Grid.findOriginalCell(lat: "31.239700", lng: "121.499812",
                                             originalPositionCode: positionCode!)
```

## Grid System

- **Standard**: WGS-84 ellipsoid
- **Base Unit**: 0.000125° (same as PlusCode 10-digit)
- **Latitude Step**: 0.000375° (3 base units)
- **Longitude Step**: 0.000125° × k (varies by latitude)
- **Total Cells**: 300,626,092,560
- **Index Range**: 0 (north pole) to 300,626,092,559 (south pole)
- **Boundary Rule**: All ranges use `[low, up)` half-open intervals
  - Latitude: `[south, north)` — south boundary included, north boundary excluded
  - Longitude: `[west, east)` — west boundary included, east boundary excluded
  - North pole: `[89.999625°, 90°]` — special case, includes maximum latitude
  - South pole: `[-90°, -89.999625°)` — follows half-open rule

### Position Codes

```
4(NW) 9(N)  2(NE)
3(W)  5(C)  7(E)
8(SW) 1(S)  6(SE)
```

Position codes enable drift correction - the original cell can be recovered from drifted coordinates plus the original position code.

### Cell Dimensions

| Direction | Size | Notes |
|-----------|------|-------|
| North-South | ~41.5 m | Fixed 0.000375°, consistent globally |
| East-West | ~41.7 m (k=3) | Standard cell at equator |
| East-West | Varies by latitude | Merged at high latitudes to maintain area |

### Drift Resistance

F9Grid achieves precise GPS drift correction through its 3×3 position code system:

| Metric | Value | Notes |
|--------|-------|-------|
| Minimum correction | ~11.9 m | Guaranteed recovery threshold (1/3 of smallest cell width) |
| Maximum correction | ~42.1 m | Maximum diagonal drift recoverable |
| Max latitude correction | ~27.6 m | North-South direction (2/3 cell height, fixed) |
| Max longitude correction | ~31.8 m | East-West direction (2/3 of largest cell width) |

**Correction ranges by direction:**

| Direction | Min Tolerance | Max Tolerance | Notes |
|-----------|---------------|---------------|-------|
| North-South | ~13.8 m | ~27.6 m | 1/3 to 2/3 cell height (fixed globally) |
| East-West | ~11.9 m | ~31.8 m | Varies with k-value (±14.2857% area variance) |

As long as GPS drift stays within the minimum range (~11.9 m), the original cell is guaranteed to be precisely recovered using the original position code (except at poles). Recovery is possible up to the maximum ranges depending on drift direction.

## Comparison with Other Grid Systems

| Feature | F9Grid | S2 | H3 | HEALPix | PlusCode |
|---------|---------|----|----|---------|----------|
| **Cell Shape** | Rectangle (near-square) ✓ | Quadrilateral (irregular) | Hexagon | Rhombus/Triangle (irregular) | Rectangle (extremely narrow at high lat) |
| **Same-Latitude Consistency** | Identical shape & area ✓ | Inconsistent | Inconsistent | Equal area only | Same shape, different area |
| **Area Variance** | ±14.2857% | 110% | 99% | Equal area | Extreme distortion at high lat |
| **High Latitude** | Auto-merge maintains area | Severe distortion | Relatively uniform | Uniform | Severely narrowed |
| **GPS Drift Correction** | ✓ Position codes | ✗ | ✗ | ✗ | ✗ |
| **Coordinate Conversion** | Simple integer math | Complex | Complex | Complex | Simple |
| **Adjacency** | Simple (N/S/E/W) ✓ | Complex | Complex | Complex (irregular 8-neighbors) | Simple |
| **Pole Handling** | Circular pole cells | Singularity issues | Pentagons | Special handling | Distorted |

### Why Choose F9Grid?

1. **Regular Shape**: Conforms to WGS-84 ellipsoid surface with near-square cells. All cells at the same latitude have identical shape and area. Maximum area variance between latitudes is only ±14.2857%, far better than PlusCode (extreme distortion at high latitudes), S2 (110%), and H3 (99%)
2. **Simple Adjacency**: N/S/E/W neighbor relationships are straightforward, superior to HEALPix and H3
3. **Drift Resistance**: Unique position code mechanism corrects GPS drift within ~11.9 m (min) to ~42.1 m (max) for precise recovery
4. **High-Latitude Friendly**: Automatic merging prevents PlusCode's severe narrowing, with minimal high-latitude error occurring only at latitudes 31° and 64°
5. **Simple & Efficient**: Based on integer arithmetic, no complex spherical geometry required, clear boundaries

## API Reference

### `F9Grid.cell(lat:lng:) -> F9Cell?`

Convert latitude/longitude to F9Grid cell.

- **Parameters**: `lat`, `lng` as String or Decimal
- **Returns**: `F9Cell` with index, position code, center coordinates, and grid info

### `F9Grid.cell(index:) -> F9Cell?`

Convert F9Grid index to cell.

- **Parameters**: `index` as Int64 (0 = north pole, 300626092559 = south pole)
- **Returns**: `F9Cell` with center coordinates and grid info

### `F9Grid.findOriginalCell(lat:lng:originalPositionCode:) -> Int64?`

Find the original cell index based on current coordinates and original position code.

- **Parameters**: Current `lat`, `lng` and the `originalPositionCode` (1-9)
- **Returns**: Original cell index

### `F9Cell` Properties

| Property | Type | Description |
|----------|------|-------------|
| `index` | `Int64` | Global cell index |
| `k` | `Int` | Longitude step multiplier |
| `step` | `Int` | Latitude step number |
| `latRange` | `(south: Double, north: Double)` | Latitude boundaries [south, north) |
| `lngRange` | `(west: Double, east: Double)` | Longitude boundaries [west, east) |
| `centerLat` | `Double` | Center latitude |
| `centerLng` | `Double` | Center longitude (normalized to [-180, 180)) |
| `isPole` | `Bool` | Whether this cell is a pole |

### `F9Cell` Protocols

- **Equatable**: Two cells are equal if they have the same index
- **Hashable**: Can be used in Set or as Dictionary keys

## PlusCode Integration

F9Grid also supports creating cells from PlusCode:

```swift
// Create cell from 10-digit PlusCode
let cell = F9Grid.cell(plusCode: "85HRJX6P+JX")

// PlusCode with + sign or spaces
let cell2 = F9Grid.cell(plusCode: "85HR JX6P+JX")
```

## Technical Specification

For implementing F9Grid in other programming languages, see the complete technical specification:

- [F9Grid Specification](Spec/F9Grid_Specification.md)
- [F9Grid 技术规范 (中文)](Spec/F9Grid_Specification_zh.md)
