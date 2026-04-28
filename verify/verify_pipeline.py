import csv  # read simulation CSV output
import math  # build atan lookup table
from collections import deque  # keep input samples in order
from pathlib import Path  # build paths safely

N = 32  # fixed-point word width
FRAC = 28  # fixed-point fractional bits
ITER = 16  # stages per CORDIC mode
SCALE = 1 << FRAC  # fixed-point value of 1.0
MASK = (1 << N) - 1  # mask for N-bit wrapping
ROOT = Path(__file__).resolve().parents[1]  # repository root
ATAN = [round(math.atan(2 ** -i) * SCALE) for i in range(ITER)]  # same atan table as RTL


def wrap_n(value):  # force Python integer into signed N-bit range
    value &= MASK  # keep lower N bits
    if value & (1 << (N - 1)):  # check sign bit
        value -= 1 << N  # convert from two's complement
    return value  # return signed value


def to_fixed(value):  # convert real value to fixed point
    return int(value * SCALE)  # scale and truncate


def to_float(value):  # convert fixed point to real
    return value / SCALE  # divide by scale factor


def gain_fix(value):  # same K correction used by RTL
    return (value >> 1) + (value >> 3) - (value >> 6) - (value >> 9) - (value >> 12) + (value >> 14) + (value >> 15)


def cordic_rotate(x_real, y_real, angle_real):  # fixed-point rotation model
    x_val = gain_fix(to_fixed(x_real))  # pre-scale x by K
    y_val = gain_fix(to_fixed(y_real))  # pre-scale y by K
    z_val = to_fixed(angle_real)  # convert angle to fixed point

    for i in range(ITER):  # run rotation stages
        x_old = x_val  # save old x
        y_old = y_val  # save old y
        if z_val >= 0:  # rotate one direction
            x_val = x_old - (y_old >> i)  # update x
            y_val = y_old + (x_old >> i)  # update y
            z_val = z_val - ATAN[i]  # reduce angle
        else:  # rotate opposite direction
            x_val = x_old + (y_old >> i)  # update x
            y_val = y_old - (x_old >> i)  # update y
            z_val = z_val + ATAN[i]  # reduce angle
    return wrap_n(x_val), wrap_n(y_val)  # return rotated vector


def cordic_vector(x_int, y_int):  # fixed-point vectoring model
    x_val = x_int  # start from rotated x
    y_val = y_int  # start from rotated y
    z_val = 0  # accumulated vector angle

    for i in range(ITER):  # run vectoring stages
        x_old = x_val  # save old x
        y_old = y_val  # save old y
        if y_val >= 0:  # reduce positive y
            x_val = x_old + (y_old >> i)  # update x
            y_val = y_old - (x_old >> i)  # move y toward zero
            z_val = z_val + ATAN[i]  # accumulate angle
        else:  # reduce negative y
            x_val = x_old - (y_old >> i)  # update x
            y_val = y_old + (x_old >> i)  # move y toward zero
            z_val = z_val - ATAN[i]  # accumulate angle
    return wrap_n(gain_fix(x_val)), wrap_n(z_val), x_val, y_val  # return outputs and raw vectoring values


def cordic_divide(x_int, y_int):  # fixed-point linear CORDIC model for y/x
    if x_int < 0:  # keep denominator positive like the RTL
        x_val = -x_int  # denominator = abs(x)
        y_val = -y_int  # flip numerator so y/x stays the same
    else:  # denominator already positive
        x_val = x_int  # denominator stays constant
        y_val = y_int  # numerator/residual moves toward zero
    z_val = 0  # quotient starts at zero

    for i in range(ITER):  # run linear CORDIC stages
        step = 1 << (FRAC - i)  # current quotient step
        if y_val >= 0:  # residual positive: subtract denominator shift
            y_val = y_val - (x_val >> i)  # update residual
            z_val = z_val + step  # add quotient step
        else:  # residual negative: add denominator shift
            y_val = y_val + (x_val >> i)  # update residual
            z_val = z_val - step  # subtract quotient step
    return wrap_n(z_val)  # return final quotient


def error(got, ref):  # calculate absolute and relative error
    abs_err = abs(got - ref)  # absolute difference
    rel_err = abs_err / max(abs(ref), 1e-12)  # avoid division by zero
    return abs_err, rel_err  # return both values


def print_pair(name, verilog_value, python_value):  # print one output comparison
    abs_err, rel_err = error(to_float(verilog_value), to_float(python_value))  # compute errors
    print(f"  {name:9s}: verilog={to_float(verilog_value): .8f}  "
          f"python={to_float(python_value): .8f}  abs={abs_err:.3e}  rel={rel_err:.3e}")  # show result
    return abs_err  # return abs error for pass/fail


def main():  # main verification function
    path = ROOT / "results" / "pipeline_results.csv"  # pipeline CSV file
    if not path.exists():  # check file exists
        print("pipeline_results.csv not found. Run the Verilog pipeline testbench first.")
        return

    inputs = deque()  # input sample queue
    outputs = []  # output sample list
    with path.open() as file_obj:  # open result CSV
        for row in csv.DictReader(file_obj):  # read each row
            if row["type"] == "IN":  # testbench input row
                inputs.append((float(row["x_in"]), float(row["y_in"]), float(row["angle_in"])))
            elif row["type"] == "OUT":  # testbench output row
                outputs.append((int(row["x_rot"]), int(row["y_rot"]), int(row["mag_out"]),
                                int(row["angle_out"]), int(row["quotient_out"])))

    max_abs_err = 0.0  # track worst error over all outputs

    print("\nPipelined rotation + vectoring + division check")
    for idx, values in enumerate(outputs):  # compare each output row
        if not inputs:  # guard against malformed CSV
            break
        x_real, y_real, angle_real = inputs.popleft()  # matching input
        vx, vy, vmag, vang, vquot = values  # Verilog outputs
        px, py = cordic_rotate(x_real, y_real, angle_real)  # Python rotated vector
        pmag, pang, raw_vec_x, raw_vec_y = cordic_vector(px, py)  # Python vectoring result
        pquot = cordic_divide(px, py)  # Python linear CORDIC result, quotient = y_rot / x_rot

        print(f"\ncase {idx}: input x={x_real}, y={y_real}, angle={angle_real}")  # case header
        max_abs_err = max(max_abs_err, print_pair("x_rot", vx, px))  # compare rotated x
        max_abs_err = max(max_abs_err, print_pair("y_rot", vy, py))  # compare rotated y
        max_abs_err = max(max_abs_err, print_pair("magnitude", vmag, pmag))  # compare magnitude
        max_abs_err = max(max_abs_err, print_pair("angle", vang, pang))  # compare vectoring angle
        max_abs_err = max(max_abs_err, print_pair("quotient", vquot, pquot))  # compare division output

    if max_abs_err == 0.0:  # exact fixed-point match
        print("\nPASS: Verilog pipeline matches Python fixed-point model bit-for-bit.")
    else:  # nonzero error was found
        print(f"\nCHECK: maximum absolute error = {max_abs_err:.3e}")


if __name__ == "__main__":  # run when called as a script
    main()
