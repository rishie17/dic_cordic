import csv  # read CSV files made by the Verilog testbench
import math  # calculate atan table values for the Python model
from pathlib import Path  # build paths that work from any folder

N = 32  # fixed-point word width
FRAC = 28  # fixed-point fractional bits
ITER = 16  # number of CORDIC iterations
SCALE = 1 << FRAC  # value of 1.0 in Q3.28
MASK = (1 << N) - 1  # mask for wrapping to N bits
ROOT = Path(__file__).resolve().parents[1]  # repository root folder
ATAN = [round(math.atan(2 ** -i) * SCALE) for i in range(ITER)]  # same atan table as RTL


def wrap_n(value):  # force a Python int to signed N-bit range
    value &= MASK  # keep only N bits
    if value & (1 << (N - 1)):  # check sign bit
        value -= 1 << N  # convert from unsigned to signed
    return value  # return signed wrapped value


def to_fixed(value):  # convert real number to fixed point
    return int(value * SCALE)  # scale and truncate like the testbench


def to_float(value):  # convert fixed point back to real
    return value / SCALE  # divide by fixed-point scale


def gain_fix(value):  # same shift-add K correction as Verilog
    return (value >> 1) + (value >> 3) - (value >> 6) - (value >> 9) - (value >> 12) + (value >> 14) + (value >> 15)


def cordic_rotation(x_real, y_real, angle_real):  # Python model for rotation mode
    x_val = gain_fix(to_fixed(x_real))  # convert x and apply K correction
    y_val = gain_fix(to_fixed(y_real))  # convert y and apply K correction
    z_val = to_fixed(angle_real)  # convert input angle

    for i in range(ITER):  # do 16 CORDIC rotations
        x_old = x_val  # save old x before update
        y_old = y_val  # save old y before update
        if z_val >= 0:  # rotate one direction for positive z
            x_val = x_old - (y_old >> i)  # update x with shifted y
            y_val = y_old + (x_old >> i)  # update y with shifted x
            z_val = z_val - ATAN[i]  # subtract angle table value
        else:  # rotate opposite direction for negative z
            x_val = x_old + (y_old >> i)  # update x with shifted y
            y_val = y_old - (x_old >> i)  # update y with shifted x
            z_val = z_val + ATAN[i]  # add angle table value

    return wrap_n(x_val), wrap_n(y_val), wrap_n(z_val)  # match RTL output width


def cordic_vectoring(x_real, y_real):  # Python model for vectoring mode
    x_val = to_fixed(x_real)  # convert x input
    y_val = to_fixed(y_real)  # convert y input
    z_val = 0  # accumulated angle starts at zero

    for i in range(ITER):  # do 16 vectoring steps
        x_old = x_val  # save old x before update
        y_old = y_val  # save old y before update
        if y_val >= 0:  # rotate to reduce positive y
            x_val = x_old + (y_old >> i)  # update x
            y_val = y_old - (x_old >> i)  # move y toward zero
            z_val = z_val + ATAN[i]  # accumulate positive angle
        else:  # rotate to reduce negative y
            x_val = x_old - (y_old >> i)  # update x
            y_val = y_old + (x_old >> i)  # move y toward zero
            z_val = z_val - ATAN[i]  # accumulate negative angle

    return wrap_n(gain_fix(x_val)), wrap_n(z_val), wrap_n(y_val)  # return mag, angle, leftover y


def error(got, ref):  # calculate absolute and relative error
    abs_err = abs(got - ref)  # absolute difference
    rel_err = abs_err / max(abs(ref), 1e-12)  # avoid divide by zero
    return abs_err, rel_err  # return both error values


def check_rotation():  # compare rotation CSV with Python model
    path = ROOT / "results" / "rotation_results.csv"  # rotation result file
    if not path.exists():  # check file exists
        print("rotation_results.csv not found. Run the Verilog testbench first.")  # helpful message
        return  # stop this check

    print("\nRotation mode check")  # section header
    print("case | verilog_x python_x abs_err rel_err | verilog_y python_y abs_err rel_err")  # table header
    with path.open() as file_obj:  # open CSV file
        for idx, row in enumerate(csv.DictReader(file_obj)):  # loop over CSV rows
            x_in = float(row["x_in"])  # read x input
            y_in = float(row["y_in"])  # read y input
            angle_in = float(row["angle_in"])  # read angle input
            verilog_x = int(row["x_out"])  # read Verilog x output
            verilog_y = int(row["y_out"])  # read Verilog y output
            python_x, python_y, _ = cordic_rotation(x_in, y_in, angle_in)  # get Python result
            abs_x, rel_x = error(to_float(verilog_x), to_float(python_x))  # x error
            abs_y, rel_y = error(to_float(verilog_y), to_float(python_y))  # y error
            print(f"{idx:4d} | {to_float(verilog_x): .8f} {to_float(python_x): .8f} {abs_x:.3e} {rel_x:.3e} | "
                  f"{to_float(verilog_y): .8f} {to_float(python_y): .8f} {abs_y:.3e} {rel_y:.3e}")  # print row


def check_vectoring():  # compare vectoring CSV with Python model
    path = ROOT / "results" / "vectoring_results.csv"  # vectoring result file
    if not path.exists():  # check file exists
        print("vectoring_results.csv not found. Run the Verilog testbench first.")  # helpful message
        return  # stop this check

    print("\nVectoring mode check")  # section header
    print("case | verilog_mag python_mag abs_err rel_err | verilog_ang python_ang abs_err rel_err")  # table header
    with path.open() as file_obj:  # open CSV file
        for idx, row in enumerate(csv.DictReader(file_obj)):  # loop over CSV rows
            x_in = float(row["x_in"])  # read x input
            y_in = float(row["y_in"])  # read y input
            verilog_mag = int(row["mag_out"])  # read Verilog magnitude
            verilog_angle = int(row["angle_out"])  # read Verilog angle
            python_mag, python_angle, _ = cordic_vectoring(x_in, y_in)  # get Python result
            abs_mag, rel_mag = error(to_float(verilog_mag), to_float(python_mag))  # magnitude error
            abs_angle, rel_angle = error(to_float(verilog_angle), to_float(python_angle))  # angle error
            print(f"{idx:4d} | {to_float(verilog_mag): .8f} {to_float(python_mag): .8f} {abs_mag:.3e} {rel_mag:.3e} | "
                  f"{to_float(verilog_angle): .8f} {to_float(python_angle): .8f} {abs_angle:.3e} {rel_angle:.3e}")  # print row


if __name__ == "__main__":  # run checks when file is executed
    check_rotation()  # run rotation verification
    check_vectoring()  # run vectoring verification
