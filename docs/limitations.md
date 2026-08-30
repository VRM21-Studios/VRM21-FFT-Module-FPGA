# Limitations

This document describes the current limitations and implementation constraints of the VRM FFT module.

## 1. Maximum FFT Size

The current implementation supports FFT sizes up to **2048 points**, controlled by the `FFT_MAX_PTS` parameter.

Supported FFT lengths currently used and verified by the design are:

* 256 points
* 512 points
* 1024 points
* 2048 points

Larger transform sizes require corresponding changes to the internal memory architecture, address widths, twiddle-factor storage, and control logic.

## 2. Fixed-Point Arithmetic

The FFT datapath uses fixed-point arithmetic rather than floating-point arithmetic.

Complex samples and twiddle factors are represented using **16-bit signed components**, with twiddle coefficients stored in Q1.15 format. Consequently, numerical precision and dynamic range are limited compared with floating-point implementations.

Scaling and quantization effects should therefore be considered when interpreting FFT magnitude results.

## 3. Twiddle-Factor Memory

Twiddle factors are stored in block RAM and must be initialized before performing an FFT or IFFT operation.

The current test and FPGA workflow uploads the twiddle-factor table through the AXI4-Lite interface. For a 2048-point transform, **1024 complex twiddle factors** are required.

The hardware does not currently provide an internal mathematical twiddle-factor generator.

## 4. Windowing

The standalone `vrm_windowing_core` uses a ROM-based window coefficient table.

The current supplied coefficient memory is based on a **2048-point sine/WOLA window** derived from the square root of a Hann window. Smaller supported FFT sizes reuse this table through coefficient-address stepping in the integrated FFT path.

Changing the window function or adding additional window types requires generating and supplying a corresponding coefficient table.

## 5. AXI4-Lite Interface

The current AXI4-Lite control interface implements a lightweight register-access mechanism intended for the associated FPGA system.

The implementation assumes that address and data for write transactions are presented together. It is therefore not intended to be a fully general-purpose AXI4-Lite slave implementation covering every possible independent-channel transaction pattern.

## 6. AXI4-Stream Framing

Input data is expected to be provided as a complete FFT frame, with `TLAST` marking the final sample.

The integrated FFT block uses this frame boundary to automatically start the transform after the final input sample has passed through the windowing pipeline.

Incorrect frame lengths or missing `TLAST` signaling may result in unexpected operation.

## 7. Throughput

The FFT engine uses an **iterative architecture** rather than a fully parallel FFT architecture.

This significantly reduces FPGA resource usage, particularly for larger FFT sizes, but results in a longer transform latency compared with highly parallel or deeply pipelined FFT architectures.

The design is therefore intended primarily as a reusable FPGA FFT accelerator rather than a maximum-throughput streaming FFT implementation.

## 8. Output Scaling

The IFFT datapath introduces fixed-point scaling associated with the iterative transform implementation.

Applications using the IFFT output may require additional software-side or hardware-side scaling depending on the desired signal amplitude convention.

The included IFFT verification testbench applies compensating scaling when analyzing the generated time-domain waveform.

## 9. Memory Initialization

Simulation and FPGA builds require the associated `.mem` files to be available to the synthesis/simulation environment.

The primary files include:

* `twiddle_factors.mem`
* `window_2048.mem`

Their locations must be correctly configured in the Vivado project or equivalent build environment.

## 10. Verification Scope

The module has been verified through RTL simulation and has also been **validated on FPGA hardware using a PYNQ-based test environment**.

The current verification focuses on representative FFT/IFFT operation, AXI interfaces, windowing, twiddle-factor loading, and end-to-end signal processing.

The verification suite does not constitute exhaustive coverage of all possible AXI transaction sequences, FFT lengths, backpressure patterns, numerical corner cases, or malformed input frames.

## 11. Current Development Status

The implementation should be considered a functional FPGA-oriented FFT accelerator rather than a fully standardized commercial FFT IP core.

Future revisions may improve:

* AXI4-Lite protocol robustness
* Streaming throughput
* Numerical scaling and precision
* Window-function configurability
* Automatic twiddle-factor generation
* Verification coverage
* Support for additional FFT sizes
