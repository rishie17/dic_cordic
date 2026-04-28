import csv  # read simulation CSV output
from collections import deque  # keep input samples in order
from pathlib import Path  # build paths safely

N = 32  # fixed-point word width
FRAC = 28  # fixed-point fractional bits
ITER = 16  # number of divider stages
SCALE = 1 << FRAC  # value of 1.0 in fixed point
MASK = (1 << N) - 1  # mask for N-bit wrapping
ROOT = Path(__file__).resolve().parents[1]  # repository root


def wrap_n(value):  # force Python int into signed N-bit range
    value &= MASK  # keep only N bits
    if value & (1 << (N - 1)):  # check sign bit
        value -= 1 << N  # convert two's complement to signed int
    return value  # return wrapped value


def to_fixed(value):  # convert real number to fixed point
    return int(value * SCALE)  # scale and truncate


def to_float(value):  # convert fixed point to real number
    return value / SCALE  # divide by fixed-point scale


def cordic_divide(num_real, den_real):  # Python model for linear CORDIC division
    result_negative = (num_real < 0) ^ (den_real < 0)  # quotient sign
    x_val = abs(to_fixed(den_real))  # x is absolute denominator
    y_val = abs(to_fixed(num_real))  # y is absolute numerator
    z_val = 0  # z builds the quotient

    for i in range(ITER):  # do 16 division steps
        step = 1 << (FRAC - i)  # current quotient bit weight
        if y_val >= 0:  # residual is positive
            y_val = y_val - (x_val >> i)  # subtract shifted denominator
            z_val = z_val + step  # add quotient step
        else:  # residual is negative
            y_val = y_val + (x_val >> i)  # add shifted denominator back
            z_val = z_val - step  # subtract quotient step

    if result_negative:  # restore sign at the end
        z_val = -z_val  # make quotient negative
    return wrap_n(z_val)  # match RTL output width


def error(got, ref):  # calculate absolute and relative error
    abs_err = abs(got - ref)  # absolute difference
    rel_err = abs_err / max(abs(ref), 1e-12)  # relative error with zero guard
    return abs_err, rel_err  # return both values


def main():  # main verification function
    path = ROOT / "results" / "pipeline_results.csv"  # pipeline result file
    if not path.exists():  # check file exists
        print("pipeline_results.csv not found. Run the Verilog pipeline testbench first.")  # helpful message
        return  # stop if there is no CSV

    inputs = deque()  # queue of input test cases
    outputs = []  # list of Verilog output integers
    with path.open() as file_obj:  # open CSV file
        for row in csv.DictReader(file_obj):  # read each row
            if row["type"] == "IN":  # input row from testbench
                inputs.append((float(row["numerator"]), float(row["denominator"])))  # save input pair
            elif row["type"] == "OUT":  # output row from testbench
                outputs.append(int(row["quotient_int"]))  # save Verilog quotient

    print("\nPipelined division check")  # section header
    print("case | numerator denominator | verilog_q python_q math_q abs_err rel_err")  # table header
    for idx, verilog_q in enumerate(outputs):  # compare each output
        if not inputs:  # guard in case CSV is mismatched
            break  # stop if no matching input exists
        num_real, den_real = inputs.popleft()  # get matching input pair
        python_q = cordic_divide(num_real, den_real)  # compute Python model
        math_q = num_real / den_real  # compute ideal floating result
        abs_err, rel_err = error(to_float(verilog_q), to_float(python_q))  # compare RTL and Python
        print(f"{idx:4d} | {num_real: .4f} {den_real: .4f} | "
              f"{to_float(verilog_q): .8f} {to_float(python_q): .8f} {math_q: .8f} {abs_err:.3e} {rel_err:.3e}")  # print row


if __name__ == "__main__":  # run only when executed as a script
    main()  # run pipeline verification
