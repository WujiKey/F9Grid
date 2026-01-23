import math
import pandas as pd
import sys

# ===== WGS-84 Ellipsoid Parameters =====
a = 6378137.0           # Semi-major axis (equatorial radius)
b = 6356752.314245      # Semi-minor axis (polar radius)
e2 = 1 - (b * b) / (a * a)  # First eccentricity squared

# ===== F9Grid Parameters =====
STD_AREA = 1730.963     # Standard cell area (square meters)
LAT_STEP = 0.000375     # Latitude step (degrees)
BASE_LON_UNIT = 0.000125  # Base longitude unit (degrees)
MAX_ERR = 0.142857      # Maximum error ±14.2857%
DIVISOR = 2880000       # k must be a divisor of this value

def all_valid_k():
    """Get all valid k values (divisors of 2880000)"""
    return [k for k in range(1, DIVISOR + 1) if DIVISOR % k == 0]

VALID_K = all_valid_k()

def wgs84_cell_area(lat_north_deg: float, k: int) -> float:
    """
    Calculate single cell area on WGS-84 ellipsoid

    Args:
        lat_north_deg: North boundary latitude of this row (degrees)
        k: Longitude step multiplier

    Returns:
        Cell area (square meters)
    """
    lat1 = math.radians(lat_north_deg)
    lat2 = math.radians(lat_north_deg - LAT_STEP)
    phi_mid = 0.5 * (lat1 + lat2)
    dphi = abs(lat2 - lat1)
    dlon = math.radians(BASE_LON_UNIT * k)

    sinp = math.sin(phi_mid)
    val = 1 - e2 * sinp * sinp
    if val < 0:
        val = 0.0
    W = math.sqrt(val)
    if W == 0.0:
        W = 1e-12

    # M: Meridional radius of curvature
    M = a * (1 - e2) / (W ** 3)
    # N: Prime vertical radius of curvature
    N = a / W

    return M * N * math.cos(phi_mid) * dphi * dlon


def wgs84_polar_cap_area(lat_boundary_deg: float) -> float:
    """
    Calculate polar cap area on WGS-84 ellipsoid

    Args:
        lat_boundary_deg: Boundary latitude
            - Positive (e.g., 89.999625): Calculate north polar cap (from 90° to this latitude)
            - Negative (e.g., -89.999625): Calculate south polar cap (from -90° to this latitude)

    Returns:
        Polar cap area (square meters)
    """
    if lat_boundary_deg >= 0:
        lat_start = 90.0
        lat_end = lat_boundary_deg
    else:
        lat_start = lat_boundary_deg
        lat_end = -90.0

    # Numerical integration (trapezoidal rule)
    n_steps = 1000
    dlat = abs(lat_start - lat_end) / n_steps
    total_area = 0.0

    for i in range(n_steps):
        if lat_boundary_deg >= 0:
            lat1 = lat_start - i * dlat
            lat2 = lat1 - dlat
        else:
            lat1 = lat_start - i * dlat
            lat2 = lat1 - dlat

        phi_mid = math.radians((lat1 + lat2) / 2)
        dphi = math.radians(abs(lat2 - lat1))
        dlon = math.radians(360.0)

        sinp = math.sin(phi_mid)
        val = 1 - e2 * sinp * sinp
        if val < 0:
            val = 0.0
        W = math.sqrt(val)
        if W == 0.0:
            W = 1e-12

        M = a * (1 - e2) / (W ** 3)
        N = a / W

        strip_area = M * N * abs(math.cos(phi_mid)) * dphi * dlon
        total_area += strip_area

    return total_area


def select_best_k_wgs84(lat1: float, lat2: float) -> tuple:
    """
    Select best k value using WGS-84 ellipsoid area calculation
    """
    best_k = None
    best_err = 1e9
    best_area = None

    for k in VALID_K:
        area = wgs84_cell_area(lat1, k)
        err = (area - STD_AREA) / STD_AREA

        if abs(err) <= MAX_ERR and abs(err) < abs(best_err):
            best_k = k
            best_area = area
            best_err = err

    return best_k, best_area, best_err


def main():
    rows = []

    print("Calculating F9Grid parameters using WGS-84 ellipsoid...")
    print(f"Standard cell area: {STD_AREA} square meters")
    print(f"Maximum error range: ±{MAX_ERR*100:.4f}%")
    print()

    # ===== North Pole Region (extended as circular cap) =====
    north_pole_lat1 = 90.0
    north_pole_lat2 = 90.0 - LAT_STEP  # 89.999625

    north_pole_wgs84_area = wgs84_polar_cap_area(north_pole_lat2)

    print(f"North Pole Region (spherical cap):")
    print(f"  Latitude range: [{north_pole_lat2}, {north_pole_lat1}]")
    print(f"  WGS84 area: {north_pole_wgs84_area:.4f} square meters")
    print(f"  Approximately {north_pole_wgs84_area/STD_AREA:.2f} standard cells")
    print()

    rows.append({
        "lat1": round(north_pole_lat1, 6),
        "lat2": round(north_pole_lat2, 6),
        "k": DIVISOR,
        "n": 1,
        "step1": 1,
        "step2": 1,
        "index_s": 0,
        "wgs84_area1": north_pole_wgs84_area,
        "wgs84_err1": (north_pole_wgs84_area - STD_AREA * 3) / (STD_AREA * 3),
        "wgs84_area2": north_pole_wgs84_area,
        "wgs84_err2": (north_pole_wgs84_area - STD_AREA * 3) / (STD_AREA * 3),
        "is_pole": True
    })

    index_counter = 1
    lat = 90.0 - LAT_STEP
    step_id = 2

    total_steps = int(180 / LAT_STEP) - 2
    current_step = 0
    current_block = None

    # Main loop
    while lat > -90 + LAT_STEP:
        lat1 = round(lat, 6)
        lat2 = round(lat - LAT_STEP, 6)

        current_step += 1
        progress = current_step / total_steps * 100
        sys.stdout.write(f"\rCalculation progress: {progress:.2f}%")
        sys.stdout.flush()

        k, wgs84_area, wgs84_err = select_best_k_wgs84(lat1, lat2)
        if k is None:
            lat -= LAT_STEP
            step_id += 1
            continue

        step_lon = BASE_LON_UNIT * k
        n = int(round(360 / step_lon))

        if current_block is None:
            current_block = {
                "lat1": lat1,
                "lat2": lat2,
                "k": k,
                "n": n,
                "step1": step_id,
                "step2": step_id,
                "index_s": index_counter,
                "wgs84_area1": wgs84_area,
                "wgs84_err1": wgs84_err,
                "wgs84_area2": wgs84_area,
                "wgs84_err2": wgs84_err,
                "is_pole": False
            }
            index_counter += n

        else:
            if k == current_block["k"]:
                # Same k value, merge: extend lat2, update step2 and area2/err2
                # Note: n is not accumulated, keep as cells per step (ensures k × n = 2880000)
                current_block["lat2"] = lat2
                current_block["step2"] = step_id
                current_block["wgs84_area2"] = wgs84_area
                current_block["wgs84_err2"] = wgs84_err
                index_counter += n
            else:
                rows.append(current_block)
                current_block = {
                    "lat1": lat1,
                    "lat2": lat2,
                    "k": k,
                    "n": n,
                    "step1": step_id,
                    "step2": step_id,
                    "index_s": index_counter,
                    "wgs84_area1": wgs84_area,
                    "wgs84_err1": wgs84_err,
                    "wgs84_area2": wgs84_area,
                    "wgs84_err2": wgs84_err,
                    "is_pole": False
                }
                index_counter += n

        lat -= LAT_STEP
        step_id += 1

    if current_block:
        rows.append(current_block)

    # ===== South Pole Region (extended as circular cap) =====
    south_pole_lat1 = -90.0 + LAT_STEP  # -89.999625
    south_pole_lat2 = -90.0

    south_pole_wgs84_area = wgs84_polar_cap_area(south_pole_lat1)

    print(f"\n\nSouth Pole Region (spherical cap):")
    print(f"  Latitude range: [{south_pole_lat2}, {south_pole_lat1}]")
    print(f"  WGS84 area: {south_pole_wgs84_area:.4f} square meters")
    print(f"  Approximately {south_pole_wgs84_area/STD_AREA:.2f} standard cells")
    print()

    rows.append({
        "lat1": round(south_pole_lat1, 6),
        "lat2": round(south_pole_lat2, 6),
        "k": DIVISOR,
        "n": 1,
        "step1": step_id,
        "step2": step_id,
        "index_s": index_counter,
        "wgs84_area1": south_pole_wgs84_area,
        "wgs84_err1": (south_pole_wgs84_area - STD_AREA * 3) / (STD_AREA * 3),
        "wgs84_area2": south_pole_wgs84_area,
        "wgs84_err2": (south_pole_wgs84_area - STD_AREA * 3) / (STD_AREA * 3),
        "is_pole": True
    })

    # Generate final output
    rows_final = []
    for blk in rows:
        # Calculate index_e: for poles, n=1; for regular regions, use steps × cells per step
        num_steps = blk["step2"] - blk["step1"] + 1
        total_cells = blk["n"] * num_steps
        index_e = blk["index_s"] + total_cells - 1

        rows_final.append([
            f"{blk['lat1']:.6f}",
            f"{blk['lat2']:.6f}",
            blk["k"],
            blk["n"],
            blk["step1"],
            blk["step2"],
            blk["index_s"],
            index_e,
            f"{blk['wgs84_area1']:.4f}",
            f"{blk['wgs84_area2']:.4f}",
            f"{blk['wgs84_err1']*100:+.4f}%",
            f"{blk['wgs84_err2']*100:+.4f}%"
        ])

    df = pd.DataFrame(rows_final, columns=[
        "lat_s", "lat_e", "k", "n", "step_s", "step_e",
        "index_s", "index_e", "area_min", "area_max", "err1", "err2"
    ])

    print("Calculation complete!")
    print()
    print("=== First 5 rows (including North Pole region) ===")
    print(df.head(5))
    print()
    print("=== Last 5 rows (including South Pole region) ===")
    print(df.tail(5))
    print()
    print(f"Total {len(rows_final)} latitude bands")
    print(f"North Pole index: 0")
    print(f"South Pole index: {rows_final[-1][7]}")

    output_file = "f9grid_wgs84.csv"
    df.to_csv(output_file, index=False, encoding="utf-8-sig")
    print(f"\nResults saved to: {output_file}")

    # Output statistics (excluding pole regions)
    print("\n=== WGS-84 Error Statistics (excluding pole regions) ===")
    wgs84_err_values = []
    for i, row in enumerate(rows_final):
        if i == 0 or i == len(rows_final) - 1:  # Skip poles
            continue
        err1 = float(row[10].replace('%', '').replace('+', ''))
        err2 = float(row[11].replace('%', '').replace('+', ''))
        wgs84_err_values.extend([err1, err2])

    if wgs84_err_values:
        print(f"Maximum positive error: {max(wgs84_err_values):+.4f}%")
        print(f"Maximum negative error: {min(wgs84_err_values):+.4f}%")
        print(f"Average absolute error: {sum(abs(e) for e in wgs84_err_values)/len(wgs84_err_values):.4f}%")


if __name__ == "__main__":
    main()
