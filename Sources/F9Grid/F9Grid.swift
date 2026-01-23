import Foundation

/// F9Grid - F9 Grid coordinate system
/// Based on PlusCode 10-digit grid with latitude-dependent longitude step
/// Uses WGS-84 ellipsoid for area calculations
/// Poles are circular regions with radius = 0.000375° (3/8000)
///
/// Internal Coordinate System:
/// To avoid floating-point precision errors that could cause grid offset,
/// all internal calculations use grid coordinates (integers).
/// Grid coordinates use base unit = 0.000125° (1/8000 degree), same as PlusCode 10-digit.
/// Conversion: gridLat = lat × 8000, gridLng = lng × 8000
///
/// Naming Convention:
/// - `base*` = PlusCode 10-digit base unit constants (base90, base360)
/// - `grid*` = F9Grid coordinates and concepts (gridLat, gridLatStep, gridNorthPoleBoundary, etc.)
///
/// Boundary Convention: All ranges use [lower, upper) - lower boundary included, upper boundary excluded
/// - Latitude: [south, north) - south boundary included, north boundary excluded
/// - Longitude: [west, east) - west boundary included, east boundary excluded
/// - North pole: [89.999625°, 90°] (special case: max latitude is included)
/// - South pole: [-90°, -89.999625°) (upper boundary excluded per convention)
public struct F9Grid {

    // MARK: - Public Constants

    /// Scale factor: multiply degrees by this to get base coordinates (1/8000 degree)
    public static let scale: Int = 8000

    /// North pole index (circular region at lat >= 89.999625)
    public static let northPoleIndex: Int64 = 0

    /// South pole index (circular region at lat < -89.999625)
    public static let southPoleIndex: Int64 = 300_626_092_559

    /// Total number of grids including both poles (0 to 300626092559)
    public static let totalGrids: Int64 = southPoleIndex + 1

    // MARK: - Internal Constants

    /// 90 degrees in base units (90 × 8000 = 720000)
    internal static let base90: Int = 720_000

    /// 360 degrees in base units (360 × 8000 = 2880000)
    internal static let base360: Int = 2_880_000

    /// F9Grid latitude step in base units (0.000375° × 8000 = 3)
    internal static let gridLatStep: Int = 3

    /// North pole boundary in grid units (89.999625° × 8000 = 719997)
    internal static let gridNorthPoleBoundary: Int = base90 - gridLatStep

    /// South pole boundary in grid units (-89.999625° × 8000 = -719997)
    internal static let gridSouthPoleBoundary: Int = -base90 + gridLatStep

    /// Total latitude steps including poles (1 to 480000)
    internal static let totalLatitudeSteps: Int = base90 * 2 / gridLatStep

    // MARK: - Data Structures

    /// Expanded band data with derived fields
    public struct Band {
        public let k: Int              // Longitude step multiplier
        public let stepStart: Int      // Start step number
        public let stepEnd: Int        // End step number
        public let indexStart: Int64   // Start index
        public let indexEnd: Int64     // End index

        /// Number of cells in this latitude row (= base360 / k)
        public var cellsInRow: Int64 {
            return Int64(F9Grid.base360 / k)
        }
        /// Get the index range for the row containing the given index
        /// - Parameter index: A cell index within this band
        /// - Returns: (startIndex, endIndex) for the row, or nil if index is not in this band
        public func rowIndexRange(containing index: Int64) -> (start: Int64, end: Int64)? {
            guard index >= indexStart, index <= indexEnd else { return nil }
            let lngIdxInRow = (index - indexStart) % cellsInRow
            let rowStart = index - lngIdxInRow
            let rowEnd = rowStart + cellsInRow - 1
            return (rowStart, rowEnd)
        }
    }

    /// Unified cell data structure
    /// All ranges use [lower, upper) convention: lower boundary included, upper boundary excluded
    public struct F9Cell: Equatable, Hashable {
        public let index: Int64
        public let k: Int
        public let step: Int

        /// Latitude range [south, north) as Decimal for precision
        public let latRangeDecimal: (south: Decimal, north: Decimal)
        /// Longitude range [west, east) as Decimal for precision
        public let lngRangeDecimal: (west: Decimal, east: Decimal)

        /// Initialize with Decimal ranges (internal use)
        init(index: Int64, latRange: (south: Decimal, north: Decimal), lngRange: (west: Decimal, east: Decimal), k: Int, step: Int) {
            self.index = index
            self.k = k
            self.step = step
            self.latRangeDecimal = latRange
            self.lngRangeDecimal = lngRange
        }

        /// Latitude range [south, north) as Double
        public var latRange: (south: Double, north: Double) {
            return (NSDecimalNumber(decimal: latRangeDecimal.south).doubleValue,
                    NSDecimalNumber(decimal: latRangeDecimal.north).doubleValue)
        }

        /// Longitude range [west, east) as Double
        public var lngRange: (west: Double, east: Double) {
            return (NSDecimalNumber(decimal: lngRangeDecimal.west).doubleValue,
                    NSDecimalNumber(decimal: lngRangeDecimal.east).doubleValue)
        }

        /// Center latitude
        public var centerLat: Double {
            let center = (latRangeDecimal.south + latRangeDecimal.north) / 2
            return NSDecimalNumber(decimal: center).doubleValue
        }

        /// Center longitude (normalized to [-180, 180))
        /// Note: For pole cells, this returns 0 as the center longitude is undefined
        public var centerLng: Double {
            if isPole { return 0 }
            // Normal cells have lngRange in [0, 360), center is in [0, 360)
            // Convert to [-180, 180) by subtracting 360 if >= 180
            let center = (lngRangeDecimal.west + lngRangeDecimal.east) / 2
            let result = NSDecimalNumber(decimal: center).doubleValue
            return result >= 180 ? result - 360 : result
        }

        /// Whether this cell is a pole (north or south)
        public var isPole: Bool {
            return index == F9Grid.northPoleIndex || index == F9Grid.southPoleIndex
        }

        /// Cell index as 8-byte big-endian binary data
        public var indexData: Data {
            return withUnsafeBytes(of: UInt64(index).bigEndian) { Data($0) }
        }

        // MARK: - Equatable & Hashable

        /// Two cells are equal if they have the same index (index uniquely identifies a cell)
        public static func == (lhs: F9Cell, rhs: F9Cell) -> Bool {
            return lhs.index == rhs.index
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(index)
        }

        // MARK: - Direction Enum

        /// Direction for neighbor lookup
        public enum Direction: CaseIterable {
            case n, s, e, w, ne, nw, se, sw
        }

        // MARK: - Neighbor Methods

        /// Get neighbor cell in the specified direction
        /// - Parameter direction: The direction to look for neighbor
        /// - Returns: The neighbor F9Cell, or nil if at pole boundary
        public func neighbor(_ direction: Direction) -> F9Cell? {
            // Poles have no neighbors in traditional sense
            if isPole { return nil }

            switch direction {
            case .e:
                return F9Grid.cell(index: F9Grid.getEastNeighbor(index: index))
            case .w:
                return F9Grid.cell(index: F9Grid.getWestNeighbor(index: index))
            case .n:
                return F9Grid.findNorthNeighbor(for: self)
            case .s:
                return F9Grid.findSouthNeighbor(for: self)
            case .ne:
                guard let north = neighbor(.n) else { return nil }
                return north.neighbor(.e)
            case .nw:
                guard let north = neighbor(.n) else { return nil }
                return north.neighbor(.w)
            case .se:
                guard let south = neighbor(.s) else { return nil }
                return south.neighbor(.e)
            case .sw:
                guard let south = neighbor(.s) else { return nil }
                return south.neighbor(.w)
            }
        }

        /// Get all 8 neighbors (N, NE, E, SE, S, SW, W, NW)
        /// - Returns: Dictionary of direction to neighbor cell (excludes nil neighbors at poles)
        public func neighbors() -> [Direction: F9Cell] {
            var result: [Direction: F9Cell] = [:]
            for direction in Direction.allCases {
                if let neighbor = neighbor(direction) {
                    result[direction] = neighbor
                }
            }
            return result
        }

        // MARK: - Sub-cell Bounds

        /// Get the geographic bounds for a sub-cell (9-grid position)
        /// - Parameter positionCode: Position code (1-9)
        /// - Returns: Tuple with latitude and longitude ranges, or nil for poles or invalid code
        public func subCellBounds(positionCode: Int) -> (latRange: (south: Double, north: Double), lngRange: (west: Double, east: Double))? {
            guard (1...9).contains(positionCode), !isPole else { return nil }

            // Find row and col from position code
            // positionCodeInCell[row][col] = code
            var positionRow = 0
            var positionCol = 0
            outer: for row in 0..<3 {
                for col in 0..<3 {
                    if F9Grid.positionCodeInCell[row][col] == positionCode {
                        positionRow = row
                        positionCol = col
                        break outer
                    }
                }
            }

            let scale = Decimal(F9Grid.scale)
            let baseUnit = Decimal(1) / scale  // 0.000125°

            // Latitude: each cell is 3 base units high, divided into 3 rows
            let latSouth = latRangeDecimal.south + Decimal(positionRow) * baseUnit
            let latNorth = latSouth + baseUnit

            // Longitude: each cell is k base units wide, divided into 3 columns
            let kDecimal = Decimal(k)
            let cellWidth = kDecimal / scale
            let colWidth = cellWidth / Decimal(3)
            let lngWest = lngRangeDecimal.west + Decimal(positionCol) * colWidth
            let lngEast = lngWest + colWidth

            return (
                latRange: (NSDecimalNumber(decimal: latSouth).doubleValue,
                          NSDecimalNumber(decimal: latNorth).doubleValue),
                lngRange: (NSDecimalNumber(decimal: lngWest).doubleValue,
                          NSDecimalNumber(decimal: lngEast).doubleValue)
            )
        }

        /// Calculate position code for given coordinates within this cell
        /// - Parameters:
        ///   - lat: Latitude as Decimal
        ///   - lng: Longitude as Decimal
        /// - Returns: Position code (1-9)
        /// - Note: North pole returns 1 (all directions point south), south pole returns 9 (all directions point north)
        ///
        /// Position boundaries use addition instead of division to avoid Decimal precision issues.
        /// Each cell is divided into 3x3 sub-cells, and the boundaries are calculated as:
        /// - lat1_3 = latSouth + baseUnit (1/3 boundary)
        /// - lat2_3 = latSouth + baseUnit * 2 (2/3 boundary)
        /// This works because latStep = 3 * baseUnit, so 1/3 and 2/3 can be computed exactly.
        public func positionCode(lat: Decimal, lng: Decimal) -> Int {
            // Handle poles specially
            if index == F9Grid.northPoleIndex {
                return F9Grid.northPolePositionCode
            }
            if index == F9Grid.southPoleIndex {
                return F9Grid.southPolePositionCode
            }

            // Latitude: cell height = 3 base units (0.000375°), boundaries at 1 and 2 units
            // Longitude: cell width = k base units, boundaries at k/3 and 2k/3 units
            //   Use offset * 3 < k to avoid division (k may not be divisible by 3)

            let scale = Decimal(F9Grid.scale)  // 8000

            // Latitude position: boundaries at offset 1 and 2 (fixed, no division needed)
            let latOffset = (lat - latRangeDecimal.south) * scale  // 0 to 3
            let positionRow = latOffset < 1 ? 0 : (latOffset < 2 ? 1 : 2)

            // Normalize longitude for comparison
            let lngStep = lngRangeDecimal.east - lngRangeDecimal.west
            var normalizedLng = lng
            if lngStep > 0 {
                if normalizedLng < lngRangeDecimal.west - 180 { normalizedLng += 360 }
                if normalizedLng > lngRangeDecimal.west + 180 { normalizedLng -= 360 }
            }

            // Longitude position: use offset * 3 < k to avoid k/3 division
            let lngOffset = (normalizedLng - lngRangeDecimal.west) * scale  // 0 to k
            let lngOffset3 = lngOffset * 3  // 0 to 3k
            let kDecimal = Decimal(k)
            let positionCol = lngOffset3 < kDecimal ? 0 : (lngOffset3 < kDecimal * 2 ? 1 : 2)

            return F9Grid.positionCodeInCell[positionRow][positionCol]
        }
    }

    // MARK: - Static Data

    /// 9-grid position layout (indexed by [positionRow][positionCol])
    /// positionRow: 0=south, 1=middle, 2=north
    /// positionCol: 0=west, 1=middle, 2=east
    /// Layout:
    ///   4(NW) 9(N)  2(NE)
    ///   3(W)  5(C)  7(E)
    ///   8(SW) 1(S)  6(SE)
    public static let positionCodeInCell: [[Int]] = [
        [8, 1, 6],  // row 0 (south): SW, S, SE
        [3, 5, 7],  // row 1 (middle): W, C, E
        [4, 9, 2],  // row 2 (north): NW, N, NE
    ]

    /// North pole cell - circular region
    /// latRange: [89.999625, 90.0] = [gridNorthPoleBoundary/8000, 90.0]
    /// Note: positionCode for north pole is always 1 (South, all directions point south)
    public static let northPoleCell = F9Cell(
        index: northPoleIndex,
        latRange: (Decimal(string: "89.999625")!, Decimal(90)),
        lngRange: (Decimal(-180), Decimal(180)),
        k: base360, step: 1
    )

    /// North pole position code - 1 (South) represents that all directions point south
    public static let northPolePositionCode = 1

    /// South pole cell - circular region
    /// latRange: [-90.0, -89.999625) per [lower, upper) convention (upper boundary excluded)
    /// Note: positionCode for south pole is always 9 (North, all directions point north)
    public static let southPoleCell = F9Cell(
        index: southPoleIndex,
        latRange: (Decimal(-90), Decimal(string: "-89.999625")!),
        lngRange: (Decimal(-180), Decimal(180)),
        k: base360, step: totalLatitudeSteps
    )

    /// South pole position code - 9 (North) represents that all directions point north
    public static let southPolePositionCode = 9

    /// Compact band data: (k, stepStart, indexStart) - 263 bands (including poles)
    /// stepEnd and indexEnd are derived from the next band's values
    ///
    /// Poles are included as special bands:
    ///   North pole: (2880000, 1, 0), step 1, lat >= 89.999625°
    ///   South pole: (2880000, 480000, 300626092559), step 480000, lat < -89.999625°
    private static let bandData: [(k: Int, stepStart: Int, indexStart: Int64)] = [
        (2880000, 1, 0),  // North pole
        (288000, 2, 1), (180000, 3, 11), (120000, 4, 27), (96000, 5, 51), (80000, 6, 81), (72000, 7, 117),
        (60000, 8, 157), (57600, 9, 205), (48000, 10, 255), (45000, 11, 315), (40000, 12, 379), (36000, 13, 451),
        (32000, 14, 531), (28800, 16, 711), (24000, 18, 911), (23040, 20, 1151), (22500, 21, 1276), (20000, 22, 1404),
        (19200, 24, 1692), (18000, 25, 1842), (16000, 28, 2322), (15000, 30, 2682), (14400, 32, 3066), (12800, 34, 3466),
        (12000, 37, 4141), (11520, 39, 4621), (11250, 41, 5121), (10000, 44, 5889), (9600, 47, 6753), (9000, 50, 7653),
        (8000, 54, 8933), (7680, 59, 10733), (7500, 61, 11483), (7200, 63, 12251), (6400, 68, 14251), (6000, 74, 16951),
        (5760, 78, 18871), (5625, 80, 19871), (5000, 86, 22943), (4800, 93, 26975), (4608, 97, 29375), (4500, 100, 31250),
        (4000, 107, 35730), (3840, 116, 42210), (3750, 120, 45210), (3600, 124, 48282), (3200, 134, 56282), (3000, 147, 67982),
        (2880, 155, 75662), (2560, 167, 87662), (2500, 180, 102287), (2400, 186, 109199), (2304, 193, 117599), (2250, 200, 126349),
        (2000, 214, 144269), (1920, 232, 170189), (1875, 239, 180689), (1800, 247, 192977), (1600, 267, 224977), (1536, 289, 264577),
        (1500, 299, 283327), (1440, 309, 302527), (1280, 334, 352527), (1250, 359, 408777), (1200, 370, 434121), (1152, 386, 472521),
        (1125, 398, 502521), (1000, 427, 576761), (960, 462, 677561), (900, 487, 752561), (800, 533, 899761), (768, 578, 1061761),
        (750, 597, 1133011), (720, 616, 1205971), (640, 666, 1405971), (625, 716, 1630971), (600, 739, 1736955), (576, 770, 1885755),
        (512, 832, 2195755), (500, 895, 2550130), (480, 924, 2717170), (450, 974, 3017170), (400, 1065, 3599570), (384, 1155, 4247570),
        (375, 1193, 4532570), (360, 1232, 4832090), (320, 1331, 5624090), (300, 1460, 6785090), (288, 1539, 7543490), (256, 1664, 8793490),
        (250, 1789, 10199740), (240, 1847, 10867900), (225, 1946, 12055900), (200, 2129, 14398300), (192, 2308, 16975900), (180, 2433, 18850900),
        (160, 2661, 22498900), (150, 2919, 27142900), (144, 3078, 30195700), (128, 3327, 35175700), (125, 3576, 40778200), (120, 3693, 43473880),
        (100, 4113, 53553880), (96, 4617, 68069080), (90, 4865, 75509080), (80, 5323, 90165080), (75, 5838, 108705080), (72, 6156, 120916280),
        (64, 6654, 140836280), (60, 7298, 169816280), (50, 8228, 214456280), (48, 9237, 272574680), (45, 9734, 302394680), (40, 10651, 361082680),
        (36, 11915, 452090680), (32, 13321, 564570680), (30, 14614, 680940680), (25, 16481, 860172680), (24, 18509, 1093798280), (20, 20625, 1347718280),
        (18, 23909, 1820614280), (16, 26751, 2275334280), (15, 29373, 2747294280), (12, 33798, 3596894280), (10, 41669, 5485934280), (9, 48478, 7446926280),
        (8, 54439, 9354446280), (6, 66880, 13833206280), (5, 87211, 23592086280), (4, 110471, 36989846280), (3, 156411, 70066646280), (4, 323591, 230559446280),
        (5, 369531, 263636246280), (6, 392791, 277034006280), (8, 413122, 286792886280), (9, 425563, 291271646280), (10, 431524, 293179166280), (12, 438333, 295140158280),
        (15, 446204, 297029198280), (16, 450629, 297878798280), (18, 453251, 298350758280), (20, 456093, 298805478280), (24, 459377, 299278374280), (25, 461493, 299532294280),
        (30, 463521, 299765919880), (32, 465388, 299945151880), (36, 466681, 300061521880), (40, 468087, 300174001880), (45, 469351, 300265009880), (48, 470268, 300323697880),
        (50, 470765, 300353517880), (60, 471774, 300411636280), (64, 472704, 300456276280), (72, 473348, 300485256280), (75, 473846, 300505176280), (80, 474164, 300517387480),
        (90, 474679, 300535927480), (96, 475137, 300550583480), (100, 475385, 300558023480), (120, 475889, 300572538680), (125, 476309, 300582618680), (128, 476426, 300585314360),
        (144, 476675, 300590916860), (150, 476924, 300595896860), (160, 477083, 300598949660), (180, 477341, 300603593660), (192, 477569, 300607241660), (200, 477694, 300609116660),
        (225, 477873, 300611694260), (240, 478056, 300614036660), (250, 478155, 300615224660), (256, 478213, 300615892820), (288, 478338, 300617299070), (300, 478463, 300618549070),
        (320, 478542, 300619307470), (360, 478671, 300620468470), (375, 478770, 300621260470), (384, 478809, 300621559990), (400, 478847, 300621844990), (450, 478937, 300622492990),
        (480, 479028, 300623075390), (500, 479078, 300623375390), (512, 479107, 300623542430), (576, 479170, 300623896805), (600, 479232, 300624206805), (625, 479263, 300624355605),
        (640, 479286, 300624461589), (720, 479336, 300624686589), (750, 479386, 300624886589), (768, 479405, 300624959549), (800, 479424, 300625030799), (900, 479469, 300625192799),
        (960, 479515, 300625339999), (1000, 479540, 300625414999), (1125, 479575, 300625515799), (1152, 479604, 300625590039), (1200, 479616, 300625620039), (1250, 479632, 300625658439),
        (1280, 479643, 300625683783), (1440, 479668, 300625740033), (1500, 479693, 300625790033), (1536, 479703, 300625809233), (1600, 479713, 300625827983), (1800, 479735, 300625867583),
        (1875, 479755, 300625899583), (1920, 479763, 300625911871), (2000, 479770, 300625922371), (2250, 479788, 300625948291), (2304, 479802, 300625966211), (2400, 479809, 300625974961),
        (2500, 479816, 300625983361), (2560, 479822, 300625990273), (2880, 479835, 300626004898), (3000, 479847, 300626016898), (3200, 479855, 300626024578), (3600, 479868, 300626036278),
        (3750, 479878, 300626044278), (3840, 479882, 300626047350), (4000, 479886, 300626050350), (4500, 479895, 300626056830), (4608, 479902, 300626061310), (4800, 479905, 300626063185),
        (5000, 479909, 300626065585), (5625, 479916, 300626069617), (5760, 479922, 300626072689), (6000, 479924, 300626073689), (6400, 479928, 300626075609), (7200, 479934, 300626078309),
        (7500, 479939, 300626080309), (7680, 479941, 300626081077), (8000, 479943, 300626081827), (9000, 479948, 300626083627), (9600, 479952, 300626084907), (10000, 479955, 300626085807),
        (11250, 479958, 300626086671), (11520, 479961, 300626087439), (12000, 479963, 300626087939), (12800, 479965, 300626088419), (14400, 479968, 300626089094), (15000, 479970, 300626089494),
        (16000, 479972, 300626089878), (18000, 479974, 300626090238), (19200, 479977, 300626090718), (20000, 479978, 300626090868), (22500, 479980, 300626091156), (23040, 479981, 300626091284),
        (24000, 479982, 300626091409), (28800, 479984, 300626091649), (32000, 479986, 300626091849), (36000, 479988, 300626092029), (40000, 479989, 300626092109), (45000, 479990, 300626092181),
        (48000, 479991, 300626092245), (57600, 479992, 300626092305), (60000, 479993, 300626092355), (72000, 479994, 300626092403), (80000, 479995, 300626092443), (96000, 479996, 300626092479),
        (120000, 479997, 300626092509), (180000, 479998, 300626092533), (288000, 479999, 300626092549),
        (2880000, 480000, 300626092559),  // South pole
    ]

    /// Expanded bands array (lazily computed from compact data)
    private static let bands: [Band] = {
        var result: [Band] = []
        result.reserveCapacity(bandData.count)

        for i in 0..<bandData.count {
            let data = bandData[i]
            let stepEnd: Int
            let indexEnd: Int64

            if i < bandData.count - 1 {
                // Derive stepEnd/indexEnd from next band's start values
                // This works for all bands including north pole (step=1, index=0)
                stepEnd = bandData[i + 1].stepStart - 1
                indexEnd = bandData[i + 1].indexStart - 1
            } else {
                // South pole is the last band, it's a single cell
                // stepEnd=stepStart, indexEnd=indexStart
                stepEnd = data.stepStart
                indexEnd = data.indexStart
            }

            result.append(Band(k: data.k, stepStart: data.stepStart, stepEnd: stepEnd, indexStart: data.indexStart, indexEnd: indexEnd))
        }

        return result
    }()

    // Band lookup

    /// Find band by step number (binary search)
    /// - Parameter step: Step number (1 = north pole, 480000 = south pole)
    /// - Returns: Band containing the step, or nil if out of range
    private static func getBandByStep(_ step: Int) -> Band? {
        guard step >= 1, step <= totalLatitudeSteps else { return nil }

        var left = 0
        var right = bands.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let band = bands[mid]

            if step < band.stepStart {
                right = mid - 1
            } else if step > band.stepEnd {
                left = mid + 1
            } else {
                return band
            }
        }
        return nil
    }

    /// Find band containing index (binary search)
    /// - Parameter index: Cell index (0 = north pole, southPoleIndex = south pole)
    /// - Returns: Band containing the index, or nil if out of range
    private static func getBandByIndex(_ index: Int64) -> Band? {
        guard index >= 0, index <= southPoleIndex else { return nil }

        var left = 0
        var right = bands.count - 1

        while left <= right {
            let mid = (left + right) / 2
            let band = bands[mid]

            if index < band.indexStart {
                right = mid - 1
            } else if index > band.indexEnd {
                left = mid + 1
            } else {
                return band
            }
        }
        return nil
    }

    // MARK: - Public API

    /// Convert latitude/longitude (String) to F9Grid cell
    /// - Parameters:
    ///   - lat: Latitude as string (e.g., "31.230416")
    ///   - lng: Longitude as string (e.g., "121.473701")
    /// - Returns: F9Cell with index, position code, center coordinates, and grid info
    ///           Returns nil if coordinate is in restricted pole area (poles + first/last rings)
    ///           or if coordinates are invalid
    /// - Note: Uses Decimal internally for precise grid and position code calculation
    public static func cell(lat: String, lng: String) -> F9Cell? {
        guard let latDecimal = Decimal(string: lat),
              let lngDecimal = Decimal(string: lng) else {
            return nil
        }
        return cell(lat: latDecimal, lng: lngDecimal)
    }

    /// Convert F9Grid index to F9Cell (grid center)
    /// - Parameter index: F9Grid global index (0 = north pole, 1-300626092558 = regular grids, 300626092559 = south pole)
    /// - Returns: F9Cell with center lat/lng and grid info, or nil if index is out of range
    /// - Note: Internally uses grid coordinates for integer precision
    public static func cell(index: Int64) -> F9Cell? {
        guard let band = getBandByIndex(index) else { return nil }

        // Handle poles (k == base360 means only 1 cell in row)
        if band.k == base360 {
            return index == northPoleIndex ? northPoleCell : southPoleCell
        }

        let k = band.k
        let cellsInRow = band.cellsInRow

        // Calculate offset within band
        let offset = index - band.indexStart
        let stepOffset = Int(offset / cellsInRow)
        let lngIdx = offset % cellsInRow

        let step = band.stepStart + stepOffset

        // Calculate coordinates using grid units (cells start from lng=0 as per F9Grid.md)
        let (gridLatNorth, gridLatSouth) = stepToGridLatRange(step)
        let gridLngWest = Int(lngIdx) * k
        let gridLngEast = gridLngWest + k

        // Convert to Decimal (÷8000)
        let scaleDecimal = Decimal(scale)
        return F9Cell(
            index: index,
            latRange: (Decimal(gridLatSouth) / scaleDecimal, Decimal(gridLatNorth) / scaleDecimal),
            lngRange: (Decimal(gridLngWest) / scaleDecimal, Decimal(gridLngEast) / scaleDecimal),
            k: k,
            step: step
        )
    }

    /// Find the original CellIndex based on current coordinates and the original position code
    /// - Parameters:
    ///   - lat: Current measured latitude as string
    ///   - lng: Current measured longitude as string
    ///   - originalPositionCode: The position code recorded the first time (1-9)
    /// - Returns: The unique original CellIndex, or nil if invalid
    /// - Note: Uses Decimal internally for precise grid and position code calculation
    public static func findOriginalCell(lat: String, lng: String, originalPositionCode: Int) -> Int64? {
        guard let latDecimal = Decimal(string: lat),
              let lngDecimal = Decimal(string: lng) else {
            return nil
        }
        return findOriginalCell(lat: latDecimal, lng: lngDecimal, originalPositionCode: originalPositionCode)
    }

    // MARK: - Private Implementation

    // Grid coordinate conversion

    /// Convert Decimal coordinate to grid coordinate using floor behavior
    /// - Parameter decimal: Coordinate as Decimal (e.g., 31.230416)
    /// - Returns: coordinate in grid units (× 8000), floored to handle [west, east) convention
    /// - Note: Uses floor (towards negative infinity) to ensure correct boundary handling
    ///         for the [lower, upper) interval convention. This is critical for negative values:
    ///         -36.00000001 * 8000 = -288000.00008 should become -288001, not -288000.
    private static func decimalToGrid(_ decimal: Decimal) -> Int {
        let grid = decimal * Decimal(scale)
        let doubleValue = NSDecimalNumber(decimal: grid).doubleValue
        return Int(floor(doubleValue))
    }

    /// Convert latitude to step number using pure integer arithmetic
    /// Uses [south, north) convention: south boundary is included, north boundary is excluded
    /// Example: step 240000 covers [0.0, 0.000375), step 240001 covers [-0.000375, 0.0)
    /// - Parameter gridLat: latitude in grid units (lat × 8000)
    private static func latToStep(_ gridLat: Int) -> Int {
        // step = ceil((720000 - gridLat) / 3)
        // Integer ceil formula: (a + b - 1) / b for positive a
        let numerator = base90 - gridLat  // Always positive for valid lat
        let step = (numerator + gridLatStep - 1) / gridLatStep
        return max(1, min(step, totalLatitudeSteps))
    }

    /// Convert step number to latitude range in grid units
    /// Returns [south, north) interval in grid coordinates
    private static func stepToGridLatRange(_ step: Int) -> (north: Int, south: Int) {
        // Equator is at step 240000 (= totalLatitudeSteps / 2)
        // delta = step - equatorStep, positive for southern hemisphere
        // south = -delta * 3 (grid units)
        // north = -(delta - 1) * 3 (grid units)
        let equatorStep = totalLatitudeSteps / 2  // 240000
        let delta = step - equatorStep
        let south = -delta * gridLatStep
        let north = -(delta - 1) * gridLatStep
        return (north, south)
    }

    // Cell calculation

    /// Convert latitude/longitude (Decimal) to F9Grid cell
    /// - Parameters:
    ///   - lat: Latitude as Decimal
    ///   - lng: Longitude as Decimal
    /// - Returns: F9Cell or nil if in restricted area or pole region
    public static func cell(lat: Decimal, lng: Decimal) -> F9Cell? {
        let gridLat = decimalToGrid(lat)
        let gridLng = decimalToGrid(lng)

        // Check for pole regions using [lower, upper) convention
        // North pole: gridLat >= gridNorthPoleBoundary (89.999625°)
        // South pole: gridLat < gridSouthPoleBoundary (-89.999625°)
        if gridLat >= gridNorthPoleBoundary {
            return northPoleCell
        }
        if gridLat < gridSouthPoleBoundary {
            return southPoleCell
        }

        // Get step and band using pure integer arithmetic
        let step = latToStep(gridLat)

        guard let band = getBandByStep(step) else { return nil }

        let k = band.k
        let cellsInRow = band.cellsInRow

        // Normalize gridLng to [0, base360) for index calculation
        var normalizedGridLng = gridLng % base360
        if normalizedGridLng < 0 { normalizedGridLng += base360 }

        // Calculate longitude index (integer division)
        var lngIdx = Int64(normalizedGridLng / k) % cellsInRow
        if lngIdx < 0 { lngIdx += cellsInRow }

        // Calculate global index
        let index = band.indexStart + Int64(step - band.stepStart) * cellsInRow + lngIdx

        // Calculate grid boundaries as Decimal
        let (gridLatNorth, gridLatSouth) = stepToGridLatRange(step)
        let gridLngWest = Int(lngIdx) * k
        let gridLngEast = gridLngWest + k

        let scaleDecimal = Decimal(scale)
        return F9Cell(
            index: index,
            latRange: (Decimal(gridLatSouth) / scaleDecimal, Decimal(gridLatNorth) / scaleDecimal),
            lngRange: (Decimal(gridLngWest) / scaleDecimal, Decimal(gridLngEast) / scaleDecimal),
            k: k,
            step: step
        )
    }

    // MARK: - Band Info

    /// Band information for a specific latitude
    public struct BandInfo {
        public let k: Int
        public let northBoundary: Double
        public let southBoundary: Double
        public let cellsInRow: Int64
    }

    /// Get band information for a given latitude
    /// - Parameter lat: Latitude as Decimal
    /// - Returns: BandInfo containing k value and latitude boundaries, or nil for poles
    public static func bandInfo(forLatitude lat: Decimal) -> BandInfo? {
        let gridLat = decimalToGrid(lat)

        // Check for pole regions
        if gridLat >= gridNorthPoleBoundary || gridLat < gridSouthPoleBoundary {
            return nil  // Poles don't have standard band info
        }

        let step = latToStep(gridLat)
        guard let band = getBandByStep(step) else { return nil }

        let (gridLatNorth, gridLatSouth) = stepToGridLatRange(step)
        let scaleDouble = Double(scale)

        return BandInfo(
            k: band.k,
            northBoundary: Double(gridLatNorth) / scaleDouble,
            southBoundary: Double(gridLatSouth) / scaleDouble,
            cellsInRow: band.cellsInRow
        )
    }

    /// Get band information for a given latitude (Double convenience)
    public static func bandInfo(forLatitude lat: Double) -> BandInfo? {
        return bandInfo(forLatitude: Decimal(lat))
    }

    // MARK: - Cells in Rectangle

    /// Find all cells within a geographic rectangle
    /// - Parameters:
    ///   - minLat: Minimum latitude (south boundary)
    ///   - maxLat: Maximum latitude (north boundary)
    ///   - minLng: Minimum longitude (west boundary)
    ///   - maxLng: Maximum longitude (east boundary)
    /// - Returns: Array of F9Cell within the rectangle
    /// - Note: Includes cells that intersect with the rectangle boundaries
    public static func cellsInRect(minLat: Decimal, maxLat: Decimal,
                                   minLng: Decimal, maxLng: Decimal) -> [F9Cell] {
        var result: [F9Cell] = []

        // Clamp latitude to valid range
        let clampedMinLat = max(minLat, Decimal(-90))
        let clampedMaxLat = min(maxLat, Decimal(90))

        guard clampedMinLat <= clampedMaxLat else { return result }

        // Check for pole inclusion
        let gridMinLat = decimalToGrid(clampedMinLat)
        let gridMaxLat = decimalToGrid(clampedMaxLat)

        // Include north pole if maxLat reaches it
        if gridMaxLat >= gridNorthPoleBoundary {
            result.append(northPoleCell)
        }

        // Include south pole if minLat reaches it
        if gridMinLat < gridSouthPoleBoundary {
            result.append(southPoleCell)
        }

        // Get step range for non-pole cells
        let effectiveMinLat = max(gridMinLat, gridSouthPoleBoundary)
        let effectiveMaxLat = min(gridMaxLat, gridNorthPoleBoundary - 1)

        guard effectiveMinLat <= effectiveMaxLat else { return result }

        // Calculate step range (note: higher lat = lower step number)
        let minStep = latToStep(effectiveMaxLat)  // north boundary -> lower step
        let maxStep = latToStep(effectiveMinLat)  // south boundary -> higher step

        // Check if covering full longitude range (360° or more)
        let lngSpan = maxLng - minLng
        let fullLngCoverage = lngSpan >= 360

        // Normalize longitude to [0, 360) for calculations
        var normMinLng = minLng
        var normMaxLng = maxLng
        while normMinLng < 0 { normMinLng += 360 }
        while normMinLng >= 360 { normMinLng -= 360 }
        while normMaxLng < 0 { normMaxLng += 360 }
        while normMaxLng >= 360 { normMaxLng -= 360 }

        // Handle longitude wrap-around
        let lngWraps = !fullLngCoverage && normMaxLng < normMinLng

        // Iterate through each step (latitude row)
        for step in minStep...maxStep {
            guard let band = getBandByStep(step) else { continue }

            let k = band.k
            let cellsInRow = band.cellsInRow
            let scaleDecimal = Decimal(scale)
            let kDecimal = Decimal(k)
            let cellWidth = kDecimal / scaleDecimal

            // Calculate longitude index range
            let gridMinLngIdx = Int64(floor(NSDecimalNumber(decimal: normMinLng / cellWidth).doubleValue))
            let gridMaxLngIdx = Int64(floor(NSDecimalNumber(decimal: normMaxLng / cellWidth).doubleValue))

            // Get the row's starting index
            let rowStartIndex = band.indexStart + Int64(step - band.stepStart) * cellsInRow

            if fullLngCoverage {
                // Full longitude coverage: include all cells in this row
                for lngIdx in Int64(0)..<cellsInRow {
                    let cellIndex = rowStartIndex + lngIdx
                    if let c = cell(index: cellIndex) {
                        result.append(c)
                    }
                }
            } else if lngWraps {
                // Longitude wraps around: include [normMinLng, 360) and [0, normMaxLng]
                // From normMinLng to end of row
                for lngIdx in gridMinLngIdx..<cellsInRow {
                    let cellIndex = rowStartIndex + lngIdx
                    if let c = cell(index: cellIndex) {
                        result.append(c)
                    }
                }
                // From start of row to normMaxLng
                for lngIdx in Int64(0)...gridMaxLngIdx {
                    let cellIndex = rowStartIndex + lngIdx
                    if let c = cell(index: cellIndex) {
                        result.append(c)
                    }
                }
            } else {
                // Normal case: include [normMinLng, normMaxLng]
                for lngIdx in gridMinLngIdx...gridMaxLngIdx {
                    let wrappedLngIdx = ((lngIdx % cellsInRow) + cellsInRow) % cellsInRow
                    let cellIndex = rowStartIndex + wrappedLngIdx
                    if let c = cell(index: cellIndex) {
                        result.append(c)
                    }
                }
            }
        }

        return result
    }

    /// Find all cells within a geographic rectangle (Double convenience)
    public static func cellsInRect(minLat: Double, maxLat: Double,
                                   minLng: Double, maxLng: Double) -> [F9Cell] {
        return cellsInRect(minLat: Decimal(minLat), maxLat: Decimal(maxLat),
                          minLng: Decimal(minLng), maxLng: Decimal(maxLng))
    }

    // MARK: - Neighbor Helpers (Internal)

    /// Find north neighbor cell
    internal static func findNorthNeighbor(for currentCell: F9Cell) -> F9Cell? {
        // Move to north cell using center longitude
        let northLat = currentCell.latRangeDecimal.north + oneGridUnit
        let gridNorthLat = decimalToGrid(northLat)

        // Check if entering north pole
        if gridNorthLat >= gridNorthPoleBoundary {
            return northPoleCell
        }

        // Use center longitude to find north neighbor
        let centerLng = (currentCell.lngRangeDecimal.west + currentCell.lngRangeDecimal.east) / 2
        return cell(lat: northLat, lng: centerLng)
    }

    /// Find south neighbor cell
    internal static func findSouthNeighbor(for currentCell: F9Cell) -> F9Cell? {
        // Move to south cell using center longitude
        let southLat = currentCell.latRangeDecimal.south - oneGridUnit
        let gridSouthLat = decimalToGrid(southLat)

        // Check if entering south pole
        if gridSouthLat < gridSouthPoleBoundary {
            return southPoleCell
        }

        // Use center longitude to find south neighbor
        let centerLng = (currentCell.lngRangeDecimal.west + currentCell.lngRangeDecimal.east) / 2
        return cell(lat: southLat, lng: centerLng)
    }

    // MARK: - Drift Correction (findOriginalCell implementation)

    /// Internal implementation using Decimal coordinates for precise boundary comparisons
    ///
    /// Use case: The first time a location was recorded, only the position code was saved.
    /// Later, when verifying the location, we have new GPS coordinates and need to find
    /// which CellIndex was originally used.
    ///
    /// Position grid layout:
    /// ```
    /// 4(NW) 9(N)  2(NE)
    /// 3(W)  5(C)  7(E)
    /// 8(SW) 1(S)  6(SE)
    /// ```
    ///
    /// Key insight: Due to non-overlapping position code regions across cells,
    /// the combination of (lat, lng, originalPositionCode) uniquely determines
    /// the original cell - only one cell is possible.
    public static func findOriginalCell(lat: Decimal, lng: Decimal, originalPositionCode: Int) -> Int64? {
        // Validate position code
        guard (1...9).contains(originalPositionCode) else {
            return nil
        }

        let gridLat = decimalToGrid(lat)

        // Check pole and restricted ring regions first
        let poleCheck = checkPoleRegions(gridLat: gridLat, originalPositionCode: originalPositionCode)
        if poleCheck.isInPoleRegion {
            return poleCheck.index
        }

        // Get current cell info using Decimal coordinates
        guard let currentCell = cell(lat: lat, lng: lng) else {
            return nil
        }

        // Calculate current position code
        let currentCode = currentCell.positionCode(lat: lat, lng: lng)

        // Apply matching rules using table-driven approach
        return matchPositionCode(
            originalCode: originalPositionCode,
            currentCode: currentCode,
            currentIndex: currentCell.index,
            lat: lat,
            lng: lng
        )
    }

    // Pole region check

    /// Check if coordinates are in pole regions (including first/last rings)
    /// Returns (isInPoleRegion, poleIndex) where poleIndex is nil if position code doesn't match
    ///
    /// Pole regions are extended by one grid unit (1/8000°) to include first/last rings:
    /// - North pole: gridLat >= gridNorthPoleBoundary - 1 (includes first ring)
    /// - South pole: gridLat < gridSouthPoleBoundary + 1 (includes last ring)
    ///
    /// This works because:
    /// - First ring position codes are 4/9/2 (north row), which can be corrected back to north pole
    /// - Last ring position codes are 8/1/6 (south row), which can be corrected back to south pole
    ///
    /// If originalPositionCode matches the pole's code (1 for north, 9 for south),
    /// the original position was at the pole; otherwise it's invalid (GPS cannot drift this far).
    private static func checkPoleRegions(gridLat: Int, originalPositionCode: Int) -> (isInPoleRegion: Bool, index: Int64?) {
        // North pole + first ring: gridLat >= gridNorthPoleBoundary - 1
        if gridLat >= gridNorthPoleBoundary - 1 {
            let index = originalPositionCode == northPolePositionCode ? northPoleIndex : nil
            return (true, index)
        }

        // South pole + last ring: gridLat < gridSouthPoleBoundary + 1
        if gridLat < gridSouthPoleBoundary + 1 {
            let index = originalPositionCode == southPolePositionCode ? southPoleIndex : nil
            return (true, index)
        }

        return (false, nil)
    }

    // Position code matching (table-driven)

    /// Matching action to take based on position codes
    private enum MatchAction {
        case sameCell           // Return current cell index
        case eastNeighbor       // Return east neighbor (index + 1 with wrap)
        case westNeighbor       // Return west neighbor (index - 1 with wrap)
        case findNorth          // Search north cell
        case findSouth          // Search south cell
    }

    /// Matching rules table: [originalCode][currentCode] -> action
    ///
    /// GPS drift principle:
    /// - GPS may drift to adjacent position within the same cell (e.g., 4→9, 9→2)
    /// - GPS may drift across cell boundary to adjacent position in neighbor cell
    /// - Position code never jumps over one position (e.g., 4 cannot directly become 6)
    ///
    /// Therefore, given original position code and current position code,
    /// we can uniquely determine which cell the original position was in.
    ///
    /// Ordered by position grid layout:
    ///   4(NW)  9(N)  2(NE)
    ///   3(W)   5(C)  7(E)
    ///   8(SW)  1(S)  6(SE)
    private static let matchingRules: [Int: [Int: MatchAction]] = [
        // North row: 4(NW), 9(N), 2(NE)
        4: [4: .sameCell,     9: .sameCell,  2: .eastNeighbor,
            3: .sameCell,     5: .sameCell,  7: .eastNeighbor,
            8: .findSouth,    1: .findSouth, 6: .findSouth],
        9: [4: .sameCell,     9: .sameCell,  2: .sameCell,
            3: .sameCell,     5: .sameCell,  7: .sameCell,
            8: .findSouth,    1: .findSouth, 6: .findSouth],
        2: [4: .westNeighbor, 9: .sameCell,  2: .sameCell,
            3: .westNeighbor, 5: .sameCell,  7: .sameCell,
            8: .findSouth,    1: .findSouth, 6: .findSouth],
        // Middle row: 3(W), 5(C), 7(E)
        3: [4: .sameCell,     9: .sameCell,  2: .eastNeighbor,
            3: .sameCell,     5: .sameCell,  7: .eastNeighbor,
            8: .sameCell,     1: .sameCell,  6: .eastNeighbor],
        5: [4: .sameCell,     9: .sameCell,  2: .sameCell,
            3: .sameCell,     5: .sameCell,  7: .sameCell,
            8: .sameCell,     1: .sameCell,  6: .sameCell],
        7: [4: .westNeighbor, 9: .sameCell,  2: .sameCell,
            3: .westNeighbor, 5: .sameCell,  7: .sameCell,
            8: .westNeighbor, 1: .sameCell,  6: .sameCell],
        // South row: 8(SW), 1(S), 6(SE)
        8: [4: .findNorth,    9: .findNorth, 2: .findNorth,
            3: .sameCell,     5: .sameCell,  7: .eastNeighbor,
            8: .sameCell,     1: .sameCell,  6: .eastNeighbor],
        1: [4: .findNorth,    9: .findNorth, 2: .findNorth,
            3: .sameCell,     5: .sameCell,  7: .sameCell,
            8: .sameCell,     1: .sameCell,  6: .sameCell],
        6: [4: .findNorth,    9: .findNorth, 2: .findNorth,
            3: .westNeighbor, 5: .sameCell,  7: .sameCell,
            8: .westNeighbor, 1: .sameCell,  6: .sameCell],
    ]

    /// Apply matching rules to find original cell
    private static func matchPositionCode(
        originalCode: Int,
        currentCode: Int,
        currentIndex: Int64,
        lat: Decimal,
        lng: Decimal
    ) -> Int64? {
        guard let rules = matchingRules[originalCode],
              let action = rules[currentCode] else {
            return nil
        }

        switch action {
        case .sameCell:
            return currentIndex
        case .eastNeighbor:
            return getEastNeighbor(index: currentIndex)
        case .westNeighbor:
            return getWestNeighbor(index: currentIndex)
        case .findNorth:
            return findNorthCell(lat: lat, lng: lng, originalPositionCode: originalCode)
        case .findSouth:
            return findSouthCell(lat: lat, lng: lng, originalPositionCode: originalCode)
        }
    }

    // Neighbor lookup

    /// Get east neighbor index (wraps around at row end)
    internal static func getEastNeighbor(index: Int64) -> Int64 {
        guard let band = getBandByIndex(index),
              let range = band.rowIndexRange(containing: index) else {
            return index + 1
        }
        return index == range.end ? range.start : index + 1
    }

    /// Get west neighbor index (wraps around at row start)
    internal static func getWestNeighbor(index: Int64) -> Int64 {
        guard let band = getBandByIndex(index),
              let range = band.rowIndexRange(containing: index) else {
            return index - 1
        }
        return index == range.start ? range.end : index - 1
    }

    // North/South cell search

    /// Sub-rules for north cell search: [originalCode][northCellCode] -> action
    /// Original codes from south row (8,1,6), north cell codes also from south row (8,1,6)
    private static let northCellSubRules: [Int: [Int: MatchAction]] = [
        8: [8: .sameCell,     1: .sameCell, 6: .eastNeighbor],
        1: [8: .sameCell,     1: .sameCell, 6: .sameCell],
        6: [8: .westNeighbor, 1: .sameCell, 6: .sameCell],
    ]

    /// Sub-rules for south cell search: [originalCode][southCellCode] -> action
    /// Original codes from north row (4,9,2), south cell codes also from north row (4,9,2)
    private static let southCellSubRules: [Int: [Int: MatchAction]] = [
        4: [4: .sameCell,     9: .sameCell, 2: .eastNeighbor],
        9: [4: .sameCell,     9: .sameCell, 2: .sameCell],
        2: [4: .westNeighbor, 9: .sameCell, 2: .sameCell],
    ]

    /// One grid unit as Decimal (1/8000)
    private static let oneGridUnit = Decimal(1) / Decimal(scale)

    /// Find the unique north cell when current position is in south part [8,1,6]
    /// and original position was in north part [4,9,2]
    private static func findNorthCell(lat: Decimal, lng: Decimal, originalPositionCode: Int) -> Int64? {
        // Move by one grid unit to reach south edge of north cell
        let northLat = lat + oneGridUnit
        let northGridLat = decimalToGrid(northLat)

        // If northLat enters pole region, return north pole
        if northGridLat >= gridNorthPoleBoundary {
            return northPoleIndex
        }

        guard let northCell = cell(lat: northLat, lng: lng) else {
            // northLat is in first ring (restricted), original must be north pole
            return northPoleIndex
        }

        // Calculate position code for north cell
        let northCellPositionCode = northCell.positionCode(lat: northLat, lng: lng)

        // Apply sub-rules
        guard let rules = northCellSubRules[originalPositionCode],
              let action = rules[northCellPositionCode] else {
            return nil
        }

        switch action {
        case .sameCell: return northCell.index
        case .eastNeighbor: return getEastNeighbor(index: northCell.index)
        case .westNeighbor: return getWestNeighbor(index: northCell.index)
        case .findNorth, .findSouth: return nil  // Should not happen in sub-rules
        }
    }

    /// Find the unique south cell when current position is in north part [4,9,2]
    /// and original position was in south part [8,1,6]
    private static func findSouthCell(lat: Decimal, lng: Decimal, originalPositionCode: Int) -> Int64? {
        // Move by one grid unit to reach north edge of south cell
        let southLat = lat - oneGridUnit
        let southGridLat = decimalToGrid(southLat)

        // If southLat enters pole region, return south pole
        if southGridLat < gridSouthPoleBoundary {
            return southPoleIndex
        }

        guard let southCell = cell(lat: southLat, lng: lng) else {
            // southLat is in last ring (restricted), original must be south pole
            return southPoleIndex
        }

        // Calculate position code for south cell
        let southCellPositionCode = southCell.positionCode(lat: southLat, lng: lng)

        // Apply sub-rules
        guard let rules = southCellSubRules[originalPositionCode],
              let action = rules[southCellPositionCode] else {
            return nil
        }

        switch action {
        case .sameCell: return southCell.index
        case .eastNeighbor: return getEastNeighbor(index: southCell.index)
        case .westNeighbor: return getWestNeighbor(index: southCell.index)
        case .findNorth, .findSouth: return nil  // Should not happen in sub-rules
        }
    }

}
