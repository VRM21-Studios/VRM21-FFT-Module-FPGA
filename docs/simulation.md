# Simulation

## Overview

The repository includes simulation testbenches for the FFT, IFFT, and standalone windowing core.

The simulation environment is intended to verify functional behavior and AXI interface operation before or alongside FPGA hardware validation.

## Testbench Files

### FFT Multi-Tone Test

```text
tb_vrm_fft_axi_sinus.v
```

This testbench performs a 2048-point FFT using three sinusoidal components:

```text
100 Hz
300 Hz
500 Hz
```

with:

```text
Sample rate = 48 kHz
FFT size    = 2048
```

Windowing is enabled for this test.

The generated output is written to:

```text
result/fft_result.csv
```

The CSV contains:

```text
index,freq_hz,real,imag
```

This allows the FFT spectrum to be inspected externally using Python, MATLAB, Excel, or other numerical-analysis tools.

## IFFT Test

```text
tb_vrm_ifft_axi_impulse.v
```

The IFFT test injects a symmetric frequency-domain stimulus at:

```text
Bin 10
Bin 2038
```

The resulting output is captured as a time-domain signal.

The test uses:

```text
IFFT mode     = enabled
Windowing     = disabled
FFT size      = 2048
```

The resulting data is written to:

```text
result/ifft_result.csv
```

The CSV contains:

```text
sample_n,real,imag
```

## Windowing Test

```text
tb_vrm_windowing_core.v
```

The standalone windowing testbench sends a constant input frame through `vrm_windowing_core`.

A dummy triangular ROM is generated automatically for simulation.

Because the input is constant, the output envelope follows the coefficient profile stored in the ROM. This provides a simple way to verify:

- ROM access
- Fixed-point multiplication
- AXI4-Stream handshake
- Pipeline operation
- TLAST propagation

## Clock

The testbenches use a 100 MHz simulation clock:

```text
Period = 10 ns
```

generated using:

```verilog
always #5 clk = ~clk;
```

## AXI-Stream Stimulus

Input samples are driven on the falling clock edge.

The testbench waits for:

```text
s_axis_tready == 1
```

before completing the transfer.

This approach prevents the stimulus from changing immediately around the active rising edge.

## Twiddle Loading

The FFT and IFFT testbenches load the 1024 twiddle factors through the AXI4-Lite interface.

The first twiddle entry is written to:

```text
0x1000
```

and subsequent entries are spaced by four bytes.

## Result Files

Simulation result files are stored under:

```text
result/
```

Current result artifacts include:

```text
fft_result.csv
ifft_result.csv
```

These files provide machine-readable output for subsequent numerical analysis.

## Detailed Results

A dedicated detailed verification report will be added after the simulation logs and FPGA validation data have been consolidated.

The planned report will include:

- Simulator configuration
- Waveform observations
- FFT peak locations
- Frequency-bin analysis
- IFFT reconstruction analysis
- Numerical error measurements
- FPGA hardware validation results
- PYNQ control procedure
- Known limitations