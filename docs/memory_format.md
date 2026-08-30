# Memory File Format

The FFT repository uses hexadecimal memory initialization files compatible with Verilog/SystemVerilog `$readmemh`.

## Twiddle Factor File

File:

```text
twiddle_factors.mem
```

For a 2048-point FFT, the file contains 1024 entries.

Each line contains one 32-bit hexadecimal value:

```text
[31:16] = Real
[15:0]  = Imaginary
```

Both fields use signed Q1.15 representation.

Example format:

```text
7FFF0000
7FFDC648
7FF5C8F9
...
```

The values are generated using:

```text
angle = -2πk/N

Real = cos(angle)
Imag = sin(angle)
```

The resulting values are quantized to signed 16-bit Q1.15 integers and encoded using two's complement.

## Window File

File:

```text
window_2048.mem
```

Each line contains one 16-bit hexadecimal coefficient.

The coefficients are unsigned because the window values are within:

```text
0.0 ≤ w[n] ≤ 1.0
```

The Q1.15 conversion is:

```text
coefficient = round(w[n] × 32767)
```

Therefore:

```text
0.0       → 0x0000
1.0       → 0x7FFF
```

## Generation

The memory files are generated using the Python utilities under:

```text
scripts/
```

The twiddle-factor generator uses NumPy.

The window generator uses NumPy and SciPy.

The generated files are intended to be consumed directly by Vivado simulation and synthesis flows through `$readmemh`.

## Runtime Twiddle Loading

The top-level FFT module does not hard-code the twiddle coefficients into the RTL.

Instead, software or a testbench can load the coefficients through the AXI4-Lite mapped memory region beginning at:

```text
0x1000
```

This allows the coefficient memory contents to be updated without modifying the FFT RTL.