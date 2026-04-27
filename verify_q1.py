import csv  # import CSV parsing support for reading simulation output files
import math  # import math functions for computing arctangent values
from pathlib import Path  # import Path for filesystem path handling

N = 32  # total bit width used for fixed-point wraparound and two's complement conversion
FRAC = 28  # number of fractional bits in the fixed-point representation
ITER = 16  # number of CORDIC iterations to execute for the algorithm
SCALE = 1 << FRAC  # scaling factor for fixed-point values (2^FRAC)
MASK = (1 << N) - 1  # mask to keep values within N-bit range after wrapping

ATAN = [round(math.atan(2 ** -i) * SCALE) for i in range(ITER)]  # precompute scaled arctangent values for each iteration


def wrap_n(v):
    v &= MASK  # mask the value to N bits, simulating fixed-width integer wraparound
    if v & (1 << (N - 1)):
        v -= 1 << N  # if the top bit is set, interpret the value as a negative two's complement number
    return v  # return the wrapped signed integer value


def to_fixed(v):
    return int(v * SCALE)  # convert a floating-point value to fixed-point by scaling and truncating


def to_float(v):
    return v / SCALE  # convert a fixed-point integer back to floating-point by dividing by the scale factor


def scale_by_k(v):
    return (v >> 1) + (v >> 3) - (v >> 6) - (v >> 9) - (v >> 12) + (v >> 14) + (v >> 15)
    # approximate the CORDIC gain compensation constant K using bit shifts only


def cordic_rotation_fixed(x_real, y_real, ang_real):
    x = scale_by_k(to_fixed(x_real))  # convert x input to fixed-point and apply scaling compensation
    y = scale_by_k(to_fixed(y_real))  # convert y input to fixed-point and apply scaling compensation
    z = to_fixed(ang_real)  # convert angle input to fixed-point

    for i in range(ITER):
        if z >= 0:
            x, y, z = x - (y >> i), y + (x >> i), z - ATAN[i]
            # rotate by -atan(2^-i) when the remaining angle is non-negative
        else:
            x, y, z = x + (y >> i), y - (x >> i), z + ATAN[i]
            # rotate by +atan(2^-i) when the remaining angle is negative
    return wrap_n(x), wrap_n(y), wrap_n(z)  # wrap outputs back to N-bit signed range


def cordic_vectoring_fixed(x_real, y_real):
    x = to_fixed(x_real)  # convert x input to fixed-point without gain compensation initially
    y = to_fixed(y_real)  # convert y input to fixed-point
    z = 0  # start the accumulated angle at zero

    for i in range(ITER):
        if y >= 0:
            x, y, z = x + (y >> i), y - (x >> i), z + ATAN[i]
            # rotate toward the x-axis and accumulate angle when y is non-negative
        else:
            x, y, z = x - (y >> i), y + (x >> i), z - ATAN[i]
            # rotate opposite direction when y is negative
    return wrap_n(scale_by_k(x)), wrap_n(z), wrap_n(y)
    # apply gain compensation to the final magnitude, wrap the angle, and wrap the final y value


def err(got, ref):
    abs_err = abs(got - ref)  # compute the absolute error between values
    rel_err = abs_err / max(abs(ref), 1e-12)  # compute relative error while avoiding division by zero
    return abs_err, rel_err  # return both absolute and relative errors


def check_rotation():
    path = Path("rotation_results.csv")  # path to the rotation test results CSV file
    if not path.exists():
        print("rotation_results.csv not found. Run the Verilog testbench first.")
        return  # stop if the expected file does not exist

    print("\nRotation mode check")  # header message for rotation mode output
    print("case | verilog_x python_x abs_err rel_err | verilog_y python_y abs_err rel_err")
    # print column labels for the comparison table
    with path.open() as f:
        rows = csv.DictReader(f)  # parse the CSV file into dictionaries keyed by column names
        for idx, row in enumerate(rows):
            x_in = float(row["x_in"])  # read the input x value from the CSV and convert to float
            y_in = float(row["y_in"])  # read the input y value from the CSV and convert to float
            a_in = float(row["angle_in"])  # read the input angle value from the CSV and convert to float
            vx = int(row["x_out"])  # read the Verilog output x as an integer
            vy = int(row["y_out"])  # read the Verilog output y as an integer
            px, py, _ = cordic_rotation_fixed(x_in, y_in, a_in)
            # compute the expected rotated x and y values using the Python fixed-point CORDIC model
            ax, rx = err(to_float(vx), to_float(px))  # compare Verilog x and Python x outputs
            ay, ry = err(to_float(vy), to_float(py))  # compare Verilog y and Python y outputs
            print(f"{idx:4d} | {to_float(vx): .8f} {to_float(px): .8f} {ax:.3e} {rx:.3e} | "
                  f"{to_float(vy): .8f} {to_float(py): .8f} {ay:.3e} {ry:.3e}")
            # print the case number, Verilog and Python outputs, and error metrics


def check_vectoring():
    path = Path("vectoring_results.csv")  # path to the vectoring test results CSV file
    if not path.exists():
        print("vectoring_results.csv not found. Run the Verilog testbench first.")
        return  # stop if the expected file does not exist

    print("\nVectoring mode check")  # header message for vectoring mode output
    print("case | verilog_mag python_mag abs_err rel_err | verilog_ang python_ang abs_err rel_err")
    # print column labels for the comparison table
    with path.open() as f:
        rows = csv.DictReader(f)  # parse the CSV file into dictionaries keyed by column names
        for idx, row in enumerate(rows):
            x_in = float(row["x_in"])  # read the input x value from the CSV and convert to float
            y_in = float(row["y_in"])  # read the input y value from the CSV and convert to float
            vm = int(row["mag_out"])  # read the Verilog magnitude output as an integer
            va = int(row["angle_out"])  # read the Verilog angle output as an integer
            pm, pa, _ = cordic_vectoring_fixed(x_in, y_in)
            # compute the expected magnitude and angle using the Python fixed-point CORDIC vectoring model
            am, rm = err(to_float(vm), to_float(pm))  # compare Verilog and Python magnitude outputs
            aa, ra = err(to_float(va), to_float(pa))  # compare Verilog and Python angle outputs
            print(f"{idx:4d} | {to_float(vm): .8f} {to_float(pm): .8f} {am:.3e} {rm:.3e} | "
                  f"{to_float(va): .8f} {to_float(pa): .8f} {aa:.3e} {ra:.3e}")
            # print the case number, Verilog and Python outputs, and error metrics


if __name__ == "__main__":
    check_rotation()  # run the rotation mode verification when executed as a script
    check_vectoring()  # run the vectoring mode verification when executed as a script
