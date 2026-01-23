# F9Grid Specification

**Version 1.0**

A GPS Drift-Resistant Geographic Grid System

---

## Quick Overview

**What is F9Grid?**

F9Grid divides Earth's surface into ~300 billion rectangular cells (~41m × 41m each). Every cell has a unique 39-bit integer index. Given any GPS coordinate, you can compute its cell index; given any index, you can compute the cell's boundaries.

**The Core Idea in 3 Points:**

1. **Latitude**: Divide into 480,000 uniform rows, each 0.000375° tall (~41.5m)
2. **Longitude**: Each row has cells of width `k × 0.000125°`, where k varies by latitude to keep cell areas roughly equal
3. **Position Code**: Each cell is subdivided into a 3×3 grid (codes 1-9) for GPS drift correction

**Why k varies?** At higher latitudes, longitude degrees represent shorter distances. To maintain similar cell areas globally, cells at high latitudes span more longitude degrees (larger k). This is why cells near the equator have k=3 (narrow) while cells near poles have k up to 288,000 (wide).

**Simple Example:**
- Input: (31.2304°, 121.4737°) Shanghai
- Output: Cell index, boundaries, k value, position code
- Reverse: Index → Cell center coordinates

---

## Abstract

F9Grid is a geographic grid coordinate system based on PlusCode 10-digit grids. It adaptively merges cells at high latitudes to maintain approximately equal cell areas globally, and introduces a 9-position code mechanism for recovering original cell positions after GPS drift.

This document defines F9Grid using mathematical formulas and algorithms for implementation in any programming language.

---

## Table of Contents

1. [Constants](#1-constants)
2. [Coordinate System](#2-coordinate-system)
3. [Grid Division](#3-grid-division)
4. [Band System](#4-band-system)
5. [Index Calculation](#5-index-calculation)
6. [Position Code System](#6-position-code-system)
7. [Drift Correction Algorithm](#7-drift-correction-algorithm)
8. [PlusCode Conversion](#8-pluscode-conversion)
9. [Appendix: Band Data Table](#appendix-band-data-table)

---

## 1. Constants

### 1.1 Fundamental Constants

$$
\begin{aligned}
S &= 8000 & \text{(scale factor)} \\
U &= \frac{1}{S} = 0.000125° & \text{(base unit)} \\
B_{90} &= 90 \times S = 720000 & \text{(90° in grid coordinates)} \\
B_{360} &= 360 \times S = 2880000 & \text{(360° in grid coordinates)}
\end{aligned}
$$

### 1.2 Grid Step Size

$$
\begin{aligned}
\Delta_{lat} &= 3U = 0.000375° & \text{(latitude step, fixed)} \\
\Delta_{lng} &= k \cdot U = k \times 0.000125° & \text{(longitude step, varies with latitude)}
\end{aligned}
$$

### 1.3 System Bounds

$$
\begin{aligned}
N_{steps} &= \frac{180°}{\Delta_{lat}} = \frac{2 \times B_{90}}{3} = 480000 & \text{(total latitude steps)} \\
I_{north} &= 0 & \text{(north pole index)} \\
I_{south} &= 300626092559 & \text{(south pole index)} \\
N_{total} &= 300626092560 & \text{(total cells)}
\end{aligned}
$$

### 1.4 Pole Boundaries (Grid Coordinates)

$$
\begin{aligned}
G_{north} &= B_{90} - 3 = 719997 & \text{(north pole boundary: } 89.999625°) \\
G_{south} &= -B_{90} + 3 = -719997 & \text{(south pole boundary: } -89.999625°)
\end{aligned}
$$

---

## 2. Coordinate System

### 2.1 Coordinate Conversion

**Degrees → Grid Coordinates** (use floor for correct half-open interval handling):

$$
G = \lfloor D \times S \rfloor
$$

where $D$ is degrees, $G$ is grid coordinate, $\lfloor \cdot \rfloor$ is floor (toward negative infinity).

**Grid Coordinates → Degrees**:

$$
D = \frac{G}{S}
$$

### 2.2 Boundary Convention

All ranges use **half-open intervals** $[lower, upper)$:

| Dimension | Interval | Description |
|-----------|----------|-------------|
| Latitude | $[lat_{south}, lat_{north})$ | South included, north excluded |
| Longitude | $[lng_{west}, lng_{east})$ | West included, east excluded |
| North Pole | $[89.999625°, 90°]$ | Special case: includes maximum |
| South Pole | $[-90°, -89.999625°)$ | Follows half-open rule |

---

## 3. Grid Division

### 3.1 Latitude Division

Latitude is uniformly divided into $N_{steps} = 480000$ steps:

$$
step = \left\lceil \frac{B_{90} - G_{lat}}{3} \right\rceil = \left\lfloor \frac{B_{90} - G_{lat} + 2}{3} \right\rfloor
$$

where $G_{lat}$ is latitude in grid coordinates, $step \in [1, 480000]$.

**Special values**:
- $step = 1$: North pole
- $step = 240000$: Equator ($lat \in [0°, 0.000375°)$)
- $step = 480000$: South pole

### 3.2 Step to Latitude Range

Given $step$, compute latitude bounds (in grid coordinates):

$$
\begin{aligned}
\delta &= step - 240000 \\
G_{south} &= -\delta \times 3 \\
G_{north} &= -(\delta - 1) \times 3
\end{aligned}
$$

Convert to degrees: $lat = G / S$

### 3.3 Longitude Division

Number of cells per latitude row:

$$
N_{lng} = \frac{B_{360}}{k} = \frac{2880000}{k}
$$

Longitude index (starting from prime meridian):

$$
idx_{lng} = \left\lfloor \frac{G_{lng} \mod B_{360}}{k} \right\rfloor
$$

where $G_{lng} \mod B_{360}$ normalizes longitude to $[0, B_{360})$.

### 3.4 k-Value Constraint

$k$ must satisfy:

$$
k \mid 2880000 = 2^9 \times 3^2 \times 5^4
$$

i.e., $k$ is a divisor of 2880000, ensuring grid lines align with PlusCode.

---

## 4. Band System

### 4.1 Band Concept

**Why do we need bands?**

At different latitudes, the physical length of 1° longitude varies significantly:
- At equator: 1° longitude ≈ 111 km
- At 60° latitude: 1° longitude ≈ 55 km
- At 89° latitude: 1° longitude ≈ 2 km

If we used a fixed longitude step everywhere, cells near poles would be extremely narrow. Bands solve this by grouping latitude rows that share the same k-multiplier.

**How the band data was derived:**

1. **Step 1 - Calculate optimal k for each latitude**: Using WGS84 ellipsoid formulas, compute the actual cell area for each latitude row and each valid k value. Select the k that makes the area closest to the target (~1731 m²).

2. **Step 2 - Allow bounded fluctuation**: To avoid extreme outliers, allow area to fluctuate within a tolerance. After testing all valid k values (divisors of 2,880,000), the minimum achievable error is **±14.2857%**, which corresponds to adjacent k values having a ratio of at most 8:7, i.e., $(8-7)/7 = 14.2857\%$.

3. **Step 3 - Merge into bands**: Adjacent latitude rows sharing the same k value are merged into a single band. This pre-computation eliminates the need for WGS84 calculations at runtime.

**Key Principles:**

1. **Same latitude = Same k**: All cells in the same latitude row have identical width and shape
2. **k changes only when necessary**: k only increases when the area would otherwise exceed the tolerance
3. **Maximum area variance = ±14.2857%**: The minimum achievable error given k must divide 2,880,000
4. **Target cell area ≈ 1731 m²**: Approximately 41.5m × 41.7m at the equator
5. **Runtime efficiency**: Band lookup via binary search, no WGS84 calculations needed

### 4.2 Band Definition

A band is a contiguous range of latitude steps sharing the same $k$ value. The system contains **263 bands**.

Each band is defined by a 5-tuple:

$$
Band = (k, step_{start}, step_{end}, idx_{start}, idx_{end})
$$

### 4.3 Band Lookup

**By Step** (for coordinate → index):

$$
\text{find } Band_i \text{ where } step_{start}^{(i)} \leq step \leq step_{end}^{(i)}
$$

**By Index** (for index → coordinate):

$$
\text{find } Band_i \text{ where } idx_{start}^{(i)} \leq index \leq idx_{end}^{(i)}
$$

Both use **binary search**, complexity $O(\log 263)$.

### 4.4 Band Data Derivation

Store compact 3-tuples $(k, step_{start}, idx_{start})$, derive end values:

$$
\begin{aligned}
step_{end}^{(i)} &= step_{start}^{(i+1)} - 1 \\
idx_{end}^{(i)} &= idx_{start}^{(i+1)} - 1
\end{aligned}
$$

South pole (last band): $step_{end} = step_{start}$, $idx_{end} = idx_{start}$

---

## 5. Index Calculation

### 5.1 Coordinate → Index

Given latitude/longitude $(lat, lng)$:

**Algorithm**:

$$
\begin{aligned}
&\textbf{Input: } lat, lng \text{ (degrees)} \\
&\textbf{Output: } index, k, step, bounds \\[1em]
&G_{lat} \gets \lfloor lat \times S \rfloor \\
&G_{lng} \gets \lfloor lng \times S \rfloor \\[0.5em]
&\textbf{if } G_{lat} \geq G_{north}: \textbf{ return } \text{NorthPole} \\
&\textbf{if } G_{lat} < G_{south}: \textbf{ return } \text{SouthPole} \\[0.5em]
&step \gets \left\lfloor \frac{B_{90} - G_{lat} + 2}{3} \right\rfloor \\
&band \gets \text{getBandByStep}(step) \\
&k \gets band.k \\
&N_{lng} \gets B_{360} / k \\[0.5em]
&G'_{lng} \gets G_{lng} \mod B_{360} \\
&\textbf{if } G'_{lng} < 0: G'_{lng} \gets G'_{lng} + B_{360} \\
&idx_{lng} \gets (G'_{lng} / k) \mod N_{lng} \\[0.5em]
&index \gets band.idx_{start} + (step - band.step_{start}) \times N_{lng} + idx_{lng}
\end{aligned}
$$

### 5.2 Index → Coordinate

Given $index$:

**Algorithm**:

$$
\begin{aligned}
&\textbf{Input: } index \\
&\textbf{Output: } lat_{range}, lng_{range}, k, step \\[1em]
&\textbf{if } index = I_{north}: \textbf{ return } \text{NorthPole} \\
&\textbf{if } index = I_{south}: \textbf{ return } \text{SouthPole} \\[0.5em]
&band \gets \text{getBandByIndex}(index) \\
&k \gets band.k \\
&N_{lng} \gets B_{360} / k \\[0.5em]
&offset \gets index - band.idx_{start} \\
&step_{offset} \gets \lfloor offset / N_{lng} \rfloor \\
&idx_{lng} \gets offset \mod N_{lng} \\
&step \gets band.step_{start} + step_{offset} \\[0.5em]
&(G_{north}, G_{south}) \gets \text{stepToLatRange}(step) \\
&G_{west} \gets idx_{lng} \times k \\
&G_{east} \gets G_{west} + k
\end{aligned}
$$

### 5.3 Formula Summary

**Global index formula**:

$$
index = idx_{band\_start} + (step - step_{band\_start}) \times \frac{B_{360}}{k} + idx_{lng}
$$

**Inverse decomposition**:

$$
\begin{aligned}
offset &= index - idx_{band\_start} \\
step &= step_{band\_start} + \lfloor offset \times k / B_{360} \rfloor \\
idx_{lng} &= offset \mod (B_{360} / k)
\end{aligned}
$$

---

## 6. Position Code System

### 6.1 Nine-Grid Definition

Each cell is divided into a $3 \times 3$ sub-grid, position code $P \in \{1, 2, ..., 9\}$:

```
┌─────┬─────┬─────┐
│  4  │  9  │  2  │  North row (row=2)
│ NW  │  N  │ NE  │
├─────┼─────┼─────┤
│  3  │  5  │  7  │  Middle row (row=1)
│  W  │  C  │  E  │
├─────┼─────┼─────┤
│  8  │  1  │  6  │  South row (row=0)
│ SW  │  S  │ SE  │
└─────┴─────┴─────┘
 West   Mid   East
 col=0 col=1 col=2
```

**Mapping matrix**:

$$
P_{matrix} = \begin{bmatrix}
8 & 1 & 6 \\
3 & 5 & 7 \\
4 & 9 & 2
\end{bmatrix}
$$

where $P = P_{matrix}[row][col]$.

### 6.2 Position Code Calculation

Given cell $Cell$ and coordinates $(lat, lng)$:

**Latitude direction** (fixed boundaries):

$$
\begin{aligned}
\epsilon_{lat} &= (lat - lat_{south}) \times S \in [0, 3) \\
row &= \begin{cases}
0 & \epsilon_{lat} < 1 \\
1 & 1 \leq \epsilon_{lat} < 2 \\
2 & \epsilon_{lat} \geq 2
\end{cases}
\end{aligned}
$$

**Longitude direction** (use multiplication to avoid division precision issues):

$$
\begin{aligned}
\epsilon_{lng} &= (lng - lng_{west}) \times S \in [0, k) \\
col &= \begin{cases}
0 & 3 \times \epsilon_{lng} < k \\
1 & k \leq 3 \times \epsilon_{lng} < 2k \\
2 & 3 \times \epsilon_{lng} \geq 2k
\end{cases}
\end{aligned}
$$

**Position code**:

$$
P = P_{matrix}[row][col]
$$

### 6.3 Pole Position Codes

$$
\begin{aligned}
P_{north} &= 1 & \text{(north pole: all directions point south)} \\
P_{south} &= 9 & \text{(south pole: all directions point north)}
\end{aligned}
$$

---

## 7. Drift Correction Algorithm

### 7.1 Principle

GPS drift typically stays within tens of meters. The position code system leverages:

1. Within a cell, positions can only drift to **adjacent** sub-regions
2. If current position code differs significantly from original, cell boundary was crossed
3. $(current\ coordinates, original\ position\ code)$ **uniquely determines** the original cell

### 7.2 Drift Tolerance

| Direction | Minimum | Maximum | Formula |
|-----------|---------|---------|---------|
| N-S | ~13.8m | ~27.6m | $\frac{1}{3}\Delta_{lat}$ to $\frac{2}{3}\Delta_{lat}$ |
| E-W | ~11.9m | ~31.8m | $\frac{1}{3}\Delta_{lng}^{min}$ to $\frac{2}{3}\Delta_{lng}^{max}$ |

### 7.3 Matching Rules Matrix

Define action set $A = \{S, E, W, \uparrow N, \downarrow S\}$:
- $S$: Return current cell
- $E$: Return east neighbor
- $W$: Return west neighbor
- $\uparrow N$: Search north cell
- $\downarrow S$: Search south cell

**Matching matrix** $M[P_{orig}][P_{curr}] \to A$:

$$
M = \begin{array}{c|ccccccccc}
 & 4 & 9 & 2 & 3 & 5 & 7 & 8 & 1 & 6 \\
\hline
4 & S & S & E & S & S & E & \downarrow & \downarrow & \downarrow \\
9 & S & S & S & S & S & S & \downarrow & \downarrow & \downarrow \\
2 & W & S & S & W & S & S & \downarrow & \downarrow & \downarrow \\
3 & S & S & E & S & S & E & S & S & E \\
5 & S & S & S & S & S & S & S & S & S \\
7 & W & S & S & W & S & S & W & S & S \\
8 & \uparrow & \uparrow & \uparrow & S & S & E & S & S & E \\
1 & \uparrow & \uparrow & \uparrow & S & S & S & S & S & S \\
6 & \uparrow & \uparrow & \uparrow & W & S & S & W & S & S \\
\end{array}
$$

### 7.4 Main Algorithm

$$
\begin{aligned}
&\textbf{function } \text{findOriginalCell}(lat, lng, P_{orig}): \\
&\quad \textbf{if } P_{orig} \notin [1, 9]: \textbf{ return } \text{null} \\[0.5em]
&\quad G_{lat} \gets \lfloor lat \times S \rfloor \\[0.5em]
&\quad \text{// Pole region check} \\
&\quad \textbf{if } G_{lat} \geq G_{north} - 1: \\
&\quad\quad \textbf{return } (P_{orig} = 1) \text{ ? } I_{north} : \text{null} \\
&\quad \textbf{if } G_{lat} < G_{south} + 1: \\
&\quad\quad \textbf{return } (P_{orig} = 9) \text{ ? } I_{south} : \text{null} \\[0.5em]
&\quad Cell_{curr} \gets \text{coordToCell}(lat, lng) \\
&\quad P_{curr} \gets \text{positionCode}(Cell_{curr}, lat, lng) \\[0.5em]
&\quad action \gets M[P_{orig}][P_{curr}] \\
&\quad \textbf{return } \text{applyAction}(action, Cell_{curr}, lat, lng, P_{orig})
\end{aligned}
$$

### 7.5 Neighbor Calculation

**East neighbor** (with wrap):

$$
idx_{east} = \begin{cases}
idx_{row\_start} & \text{if } idx = idx_{row\_end} \\
idx + 1 & \text{otherwise}
\end{cases}
$$

where:
$$
\begin{aligned}
idx_{row\_start} &= idx_{band\_start} + \lfloor (idx - idx_{band\_start}) / N_{lng} \rfloor \times N_{lng} \\
idx_{row\_end} &= idx_{row\_start} + N_{lng} - 1
\end{aligned}
$$

**West neighbor** (with wrap):

$$
idx_{west} = \begin{cases}
idx_{row\_end} & \text{if } idx = idx_{row\_start} \\
idx - 1 & \text{otherwise}
\end{cases}
$$

### 7.6 North/South Search

**Search north cell** (when original position code is 8/1/6):

$$
\begin{aligned}
&lat' \gets lat + U \\
&\textbf{if } \lfloor lat' \times S \rfloor \geq G_{north}: \textbf{ return } I_{north} \\
&Cell_{north} \gets \text{coordToCell}(lat', lng) \\
&P_{north} \gets \text{positionCode}(Cell_{north}, lat', lng) \\
&\textbf{return } \text{applySubRule}_{north}(P_{orig}, P_{north}, Cell_{north})
\end{aligned}
$$

**North sub-rule matrix**:

$$
M_{north}[P_{orig}][P_{north}] = \begin{array}{c|ccc}
 & 8 & 1 & 6 \\
\hline
8 & S & S & E \\
1 & S & S & S \\
6 & W & S & S \\
\end{array}
$$

**Search south cell** (when original position code is 4/9/2):

$$
\begin{aligned}
&lat' \gets lat - U \\
&\textbf{if } \lfloor lat' \times S \rfloor < G_{south}: \textbf{ return } I_{south} \\
&Cell_{south} \gets \text{coordToCell}(lat', lng) \\
&P_{south} \gets \text{positionCode}(Cell_{south}, lat', lng) \\
&\textbf{return } \text{applySubRule}_{south}(P_{orig}, P_{south}, Cell_{south})
\end{aligned}
$$

**South sub-rule matrix**:

$$
M_{south}[P_{orig}][P_{south}] = \begin{array}{c|ccc}
 & 4 & 9 & 2 \\
\hline
4 & S & S & E \\
9 & S & S & S \\
2 & W & S & S \\
\end{array}
$$

---

## 8. PlusCode Conversion

### 8.1 Character Set

$$
\Sigma = \text{"23456789CFGHJMPQRVWX"} \quad (|\Sigma| = 20)
$$

Character index: $\text{idx}(c) = \Sigma.\text{indexOf}(c)$

### 8.2 Decoding Formula

Given 10-digit PlusCode $c_0 c_1 c_2 c_3 c_4 c_5 c_6 c_7 c_8 c_9$:

$$
\begin{aligned}
G_{lat} &= \text{idx}(c_0) \times 160000 + \text{idx}(c_2) \times 8000 + \text{idx}(c_4) \times 400 \\
&\quad + \text{idx}(c_6) \times 20 + \text{idx}(c_8) - B_{90} \\[0.5em]
G_{lng} &= \text{idx}(c_1) \times 160000 + \text{idx}(c_3) \times 8000 + \text{idx}(c_5) \times 400 \\
&\quad + \text{idx}(c_7) \times 20 + \text{idx}(c_9) - \frac{B_{360}}{2}
\end{aligned}
$$

**Weight explanation**:
- $20° \times 8000 = 160000$
- $1° \times 8000 = 8000$
- $0.05° \times 8000 = 400$
- $0.0025° \times 8000 = 20$
- $0.000125° \times 8000 = 1$

---

## 9. Implementation Notes

### 9.1 Data Types

| Concept | Recommended Type | Range |
|---------|------------------|-------|
| Cell Index | int64 | $[0, 300626092559]$ |
| Grid Coordinate | int32 | $[-2880000, 2880000]$ |
| Lat/Lng | Decimal/fixed-point | Avoid floating-point errors |
| k value | int32 | $[3, 2880000]$ |
| Step | int32 | $[1, 480000]$ |
| Position Code | int8 | $[1, 9]$ |

### 9.2 Precision Requirements

1. **Use fixed-point arithmetic**: Floating-point may cause boundary errors
2. **Floor function**: Must round toward negative infinity, not truncate
3. **Integer arithmetic**: Use integers for core calculations
4. **Boundary testing**: Thoroughly test coordinates at cell boundaries

### 9.3 Key Test Cases

| Location | Latitude | Longitude | Expected |
|----------|----------|-----------|----------|
| North Pole | 90 | any | $index=0$ |
| South Pole | -90 | any | $index=300626092559$ |
| Equator Origin | 0 | 0 | $k=3, step=240000$ |
| Date Line | 0 | 180/-180 | Same cell |
| High Latitude | 89.99 | 0 | $k > 10000$ |

---

## Appendix: Band Data Table

263 records in format $(k, step_{start}, idx_{start})$:

```
(2880000, 1, 0)           // North Pole
(288000, 2, 1)
(180000, 3, 11)
(120000, 4, 27)
(96000, 5, 51)
(80000, 6, 81)
(72000, 7, 117)
(60000, 8, 157)
(57600, 9, 205)
(48000, 10, 255)
(45000, 11, 315)
(40000, 12, 379)
(36000, 13, 451)
(32000, 14, 531)
(28800, 16, 711)
(24000, 18, 911)
(23040, 20, 1151)
(22500, 21, 1276)
(20000, 22, 1404)
(19200, 24, 1692)
(18000, 25, 1842)
(16000, 28, 2322)
(15000, 30, 2682)
(14400, 32, 3066)
(12800, 34, 3466)
(12000, 37, 4141)
(11520, 39, 4621)
(11250, 41, 5121)
(10000, 44, 5889)
(9600, 47, 6753)
(9000, 50, 7653)
(8000, 54, 8933)
(7680, 59, 10733)
(7500, 61, 11483)
(7200, 63, 12251)
(6400, 68, 14251)
(6000, 74, 16951)
(5760, 78, 18871)
(5625, 80, 19871)
(5000, 86, 22943)
(4800, 93, 26975)
(4608, 97, 29375)
(4500, 100, 31250)
(4000, 107, 35730)
(3840, 116, 42210)
(3750, 120, 45210)
(3600, 124, 48282)
(3200, 134, 56282)
(3000, 147, 67982)
(2880, 155, 75662)
(2560, 167, 87662)
(2500, 180, 102287)
(2400, 186, 109199)
(2304, 193, 117599)
(2250, 200, 126349)
(2000, 214, 144269)
(1920, 232, 170189)
(1875, 239, 180689)
(1800, 247, 192977)
(1600, 267, 224977)
(1536, 289, 264577)
(1500, 299, 283327)
(1440, 309, 302527)
(1280, 334, 352527)
(1250, 359, 408777)
(1200, 370, 434121)
(1152, 386, 472521)
(1125, 398, 502521)
(1000, 427, 576761)
(960, 462, 677561)
(900, 487, 752561)
(800, 533, 899761)
(768, 578, 1061761)
(750, 597, 1133011)
(720, 616, 1205971)
(640, 666, 1405971)
(625, 716, 1630971)
(600, 739, 1736955)
(576, 770, 1885755)
(512, 832, 2195755)
(500, 895, 2550130)
(480, 924, 2717170)
(450, 974, 3017170)
(400, 1065, 3599570)
(384, 1155, 4247570)
(375, 1193, 4532570)
(360, 1232, 4832090)
(320, 1331, 5624090)
(300, 1460, 6785090)
(288, 1539, 7543490)
(256, 1664, 8793490)
(250, 1789, 10199740)
(240, 1847, 10867900)
(225, 1946, 12055900)
(200, 2129, 14398300)
(192, 2308, 16975900)
(180, 2433, 18850900)
(160, 2661, 22498900)
(150, 2919, 27142900)
(144, 3078, 30195700)
(128, 3327, 35175700)
(125, 3576, 40778200)
(120, 3693, 43473880)
(100, 4113, 53553880)
(96, 4617, 68069080)
(90, 4865, 75509080)
(80, 5323, 90165080)
(75, 5838, 108705080)
(72, 6156, 120916280)
(64, 6654, 140836280)
(60, 7298, 169816280)
(50, 8228, 214456280)
(48, 9237, 272574680)
(45, 9734, 302394680)
(40, 10651, 361082680)
(36, 11915, 452090680)
(32, 13321, 564570680)
(30, 14614, 680940680)
(25, 16481, 860172680)
(24, 18509, 1093798280)
(20, 20625, 1347718280)
(18, 23909, 1820614280)
(16, 26751, 2275334280)
(15, 29373, 2747294280)
(12, 33798, 3596894280)
(10, 41669, 5485934280)
(9, 48478, 7446926280)
(8, 54439, 9354446280)
(6, 66880, 13833206280)
(5, 87211, 23592086280)
(4, 110471, 36989846280)
(3, 156411, 70066646280)          // Equator region k=3
(4, 323591, 230559446280)
(5, 369531, 263636246280)
(6, 392791, 277034006280)
(8, 413122, 286792886280)
(9, 425563, 291271646280)
(10, 431524, 293179166280)
(12, 438333, 295140158280)
(15, 446204, 297029198280)
(16, 450629, 297878798280)
(18, 453251, 298350758280)
(20, 456093, 298805478280)
(24, 459377, 299278374280)
(25, 461493, 299532294280)
(30, 463521, 299765919880)
(32, 465388, 299945151880)
(36, 466681, 300061521880)
(40, 468087, 300174001880)
(45, 469351, 300265009880)
(48, 470268, 300323697880)
(50, 470765, 300353517880)
(60, 471774, 300411636280)
(64, 472704, 300456276280)
(72, 473348, 300485256280)
(75, 473846, 300505176280)
(80, 474164, 300517387480)
(90, 474679, 300535927480)
(96, 475137, 300550583480)
(100, 475385, 300558023480)
(120, 475889, 300572538680)
(125, 476309, 300582618680)
(128, 476426, 300585314360)
(144, 476675, 300590916860)
(150, 476924, 300595896860)
(160, 477083, 300598949660)
(180, 477341, 300603593660)
(192, 477569, 300607241660)
(200, 477694, 300609116660)
(225, 477873, 300611694260)
(240, 478056, 300614036660)
(250, 478155, 300615224660)
(256, 478213, 300615892820)
(288, 478338, 300617299070)
(300, 478463, 300618549070)
(320, 478542, 300619307470)
(360, 478671, 300620468470)
(375, 478770, 300621260470)
(384, 478809, 300621559990)
(400, 478847, 300621844990)
(450, 478937, 300622492990)
(480, 479028, 300623075390)
(500, 479078, 300623375390)
(512, 479107, 300623542430)
(576, 479170, 300623896805)
(600, 479232, 300624206805)
(625, 479263, 300624355605)
(640, 479286, 300624461589)
(720, 479336, 300624686589)
(750, 479386, 300624886589)
(768, 479405, 300624959549)
(800, 479424, 300625030799)
(900, 479469, 300625192799)
(960, 479515, 300625339999)
(1000, 479540, 300625414999)
(1125, 479575, 300625515799)
(1152, 479604, 300625590039)
(1200, 479616, 300625620039)
(1250, 479632, 300625658439)
(1280, 479643, 300625683783)
(1440, 479668, 300625740033)
(1500, 479693, 300625790033)
(1536, 479703, 300625809233)
(1600, 479713, 300625827983)
(1800, 479735, 300625867583)
(1875, 479755, 300625899583)
(1920, 479763, 300625911871)
(2000, 479770, 300625922371)
(2250, 479788, 300625948291)
(2304, 479802, 300625966211)
(2400, 479809, 300625974961)
(2500, 479816, 300625983361)
(2560, 479822, 300625990273)
(2880, 479835, 300626004898)
(3000, 479847, 300626016898)
(3200, 479855, 300626024578)
(3600, 479868, 300626036278)
(3750, 479878, 300626044278)
(3840, 479882, 300626047350)
(4000, 479886, 300626050350)
(4500, 479895, 300626056830)
(4608, 479902, 300626061310)
(4800, 479905, 300626063185)
(5000, 479909, 300626065585)
(5625, 479916, 300626069617)
(5760, 479922, 300626072689)
(6000, 479924, 300626073689)
(6400, 479928, 300626075609)
(7200, 479934, 300626078309)
(7500, 479939, 300626080309)
(7680, 479941, 300626081077)
(8000, 479943, 300626081827)
(9000, 479948, 300626083627)
(9600, 479952, 300626084907)
(10000, 479955, 300626085807)
(11250, 479958, 300626086671)
(11520, 479961, 300626087439)
(12000, 479963, 300626087939)
(12800, 479965, 300626088419)
(14400, 479968, 300626089094)
(15000, 479970, 300626089494)
(16000, 479972, 300626089878)
(18000, 479974, 300626090238)
(19200, 479977, 300626090718)
(20000, 479978, 300626090868)
(22500, 479980, 300626091156)
(23040, 479981, 300626091284)
(24000, 479982, 300626091409)
(28800, 479984, 300626091649)
(32000, 479986, 300626091849)
(36000, 479988, 300626092029)
(40000, 479989, 300626092109)
(45000, 479990, 300626092181)
(48000, 479991, 300626092245)
(57600, 479992, 300626092305)
(60000, 479993, 300626092355)
(72000, 479994, 300626092403)
(80000, 479995, 300626092443)
(96000, 479996, 300626092479)
(120000, 479997, 300626092509)
(180000, 479998, 300626092533)
(288000, 479999, 300626092549)
(2880000, 480000, 300626092559)  // South Pole
```

**Derivation formula**:

$$
\begin{aligned}
step_{end}^{(i)} &= step_{start}^{(i+1)} - 1 \\
idx_{end}^{(i)} &= idx_{start}^{(i+1)} - 1
\end{aligned}
$$

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2025 | Initial release |
