import csv
from collections import deque
from pathlib import Path

N = 32
FRAC = 28
ITER = 16
SCALE = 1 << FRAC
MASK = (1 << N) - 1


def wrap_n(v):
    v &= MASK
    if v & (1 << (N - 1)):
        v -= 1 << N
    return v


def to_fixed(v):
    return int(v * SCALE)


def to_float(v):
    return v / SCALE


def cordic_divide_fixed(n_real, d_real):
    # Same linear CORDIC idea as the Verilog pipeline.
    sign = (n_real < 0) ^ (d_real < 0)
    x = abs(to_fixed(d_real))
    y = abs(to_fixed(n_real))
    z = 0

    for i in range(ITER):
        term = 1 << (FRAC - i)
        if y >= 0:
            y = y - (x >> i)
            z = z + term
        else:
            y = y + (x >> i)
            z = z - term

    if sign:
        z = -z
    return wrap_n(z)


def err(got, ref):
    abs_err = abs(got - ref)
    rel_err = abs_err / max(abs(ref), 1e-12)
    return abs_err, rel_err


def main():
    path = Path("pipeline_results.csv")
    if not path.exists():
        print("pipeline_results.csv not found. Run the Verilog pipeline testbench first.")
        return

    inputs = deque()
    outputs = []
    with path.open() as f:
        rows = csv.DictReader(f)
        for row in rows:
            if row["type"] == "IN":
                inputs.append((float(row["numerator"]), float(row["denominator"])))
            elif row["type"] == "OUT":
                outputs.append(int(row["quotient_int"]))

    print("\nDoubly pipelined division check")
    print("case | numerator denominator | verilog_q python_q math_q abs_err rel_err")
    for idx, vq in enumerate(outputs):
        if not inputs:
            break
        n_real, d_real = inputs.popleft()
        pq = cordic_divide_fixed(n_real, d_real)
        math_q = n_real / d_real
        ae, re = err(to_float(vq), to_float(pq))
        print(f"{idx:4d} | {n_real: .4f} {d_real: .4f} | "
              f"{to_float(vq): .8f} {to_float(pq): .8f} {math_q: .8f} {ae:.3e} {re:.3e}")


if __name__ == "__main__":
    main()
