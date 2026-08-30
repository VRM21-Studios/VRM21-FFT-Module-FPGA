# Testbench Results

This document summarizes the simulation results for the VRM FFT processing chain.

The verification environment currently covers:

* AXI-Stream windowing
* 2048-point FFT processing
* 2048-point IFFT processing
* AXI4-Lite control and twiddle-factor loading
* AXI4-Stream input/output handling
* CSV result generation

FPGA validation is not included in this document yet and will be documented separately after the hardware validation results are finalized.

---

## 1. Windowing Core

### Testbench

`tb_vrm_windowing_core`

### Configuration

| Parameter       |                    Value |
| --------------- | -----------------------: |
| Maximum points  |                     2048 |
| Input format    |            Q1.15 complex |
| Window ROM      |        `window_2048.mem` |
| Clock           |                  100 MHz |
| Input samples   |                     2048 |
| Input signal    |              Constant DC |
| Input amplitude |                    10000 |
| AXI-Stream      |                  Enabled |
| TLAST           | Asserted on final sample |

The testbench injects a constant complex-valued input frame:

```text
Real = 10000
Imag = 10000
```

The windowing core applies the coefficients stored in `window_2048.mem`. Since the input is constant, the output envelope follows the programmed window coefficients.

The testbench also verifies AXI-Stream frame termination through `TLAST`.

### Simulation Log

```text
[200000] Starting injection of 2048 samples...
Out L:      0 | R:      0 | TLAST: 0
Out L:      0 | R:      0 | TLAST: 0
// Output truncated for brevity
Out L:      0 | R:      0 | TLAST: 0
[41150000] Input transmission completed. Waiting for pipeline flush...
Out L:      0 | R:      0 | TLAST: 1
[41350000] Simulation completed.
```

The complete console output is intentionally omitted from this document because the testbench produces one output line per sample.

---

## 2. FFT Test

### Testbench

`tb_vrm_fft_axi_sinus`

### Configuration

| Parameter         |                  Value |
| ----------------- | ---------------------: |
| FFT size          |                   2048 |
| Sample rate       |                 48 kHz |
| Input frequencies | 100 Hz, 300 Hz, 500 Hz |
| Windowing         |                Enabled |
| Transform mode    |                    FFT |
| Input format      |          Q1.15 complex |
| Twiddle factors   |  `twiddle_factors.mem` |
| Clock             |                100 MHz |
| Output format     |                Complex |
| Result file       |       `fft_result.csv` |

The testbench generates three sinusoidal components at:

```text
100 Hz
300 Hz
500 Hz
```

with a sampling frequency of 48 kHz.

The three tones are combined into a single real-valued input signal and processed using the 2048-point FFT. Windowing is enabled to reduce spectral leakage.

The twiddle-factor memory is loaded through the AXI4-Lite interface before the FFT operation begins.

### Simulation Log

```text
Loading twiddle ROM via AXI-Lite...
Twiddle loaded.
Configuring FFT...
Sending input samples at Fs = 48 kHz...
Input sent.
Waiting for FFT to complete...
FFT done.
Capturing output...
Writing CSV...
CSV written to fft_result.csv
```

The resulting FFT data is stored in:

```text
result/fft_result.csv
```

The CSV contains the FFT bin index, corresponding frequency, and complex output components:

```text
index,freq_hz,real,imag
```

---

## 3. IFFT Test

### Testbench

`tb_vrm_ifft_axi_impulse`

### Configuration

| Parameter       |                 Value |
| --------------- | --------------------: |
| IFFT size       |                  2048 |
| Transform mode  |                  IFFT |
| Windowing       |              Disabled |
| Input spectrum  | Frequency-domain bins |
| Active bins     |           10 and 2038 |
| Input amplitude |                 16000 |
| Twiddle factors | `twiddle_factors.mem` |
| Clock           |               100 MHz |
| Result file     |     `ifft_result.csv` |

The testbench injects a conjugate-symmetric frequency-domain spectrum.

The non-zero bins are:

```text
Bin 10   = 16000 + j0
Bin 2038 = 16000 + j0
```

Since bin 2038 corresponds to the negative-frequency counterpart of bin 10 for a 2048-point transform, the resulting time-domain signal is expected to be predominantly real-valued and sinusoidal.

Windowing is disabled for this test so that the IFFT operates directly on the injected frequency-domain spectrum.

### Simulation Log

```text
Loading twiddle ROM via AXI-Lite...
Configuring hardware for IFFT Mode...
Sending frequency bins...
Frequency bins sent.
Waiting for IFFT to synthesize time-domain signal...
IFFT done.
Capturing time-domain output...
Writing CSV...
CSV written to ifft_result.csv
```

The resulting IFFT data is stored in:

```text
result/ifft_result.csv
```

The CSV contains the reconstructed time-domain sample index and complex output:

```text
sample_n,real,imag
```

---

## 4. Generated Test Results

The current simulation flow generates the following result files:

```text
result/
├── fft_result.csv
└── ifft_result.csv
```

These files provide numerical output from the FFT and IFFT testbenches and can be used for further analysis or plotting.

---

## 5. Verification Summary

| Testbench                 | Function             | Points | Result    |
| ------------------------- | -------------------- | -----: | --------- |
| `tb_vrm_windowing_core`   | AXI-Stream windowing |   2048 | Completed |
| `tb_vrm_fft_axi_sinus`    | Forward FFT          |   2048 | Completed |
| `tb_vrm_ifft_axi_impulse` | Inverse FFT          |   2048 | Completed |

The simulation environment successfully executes the complete control and data-transfer flow for the tested configurations, including:

* AXI4-Lite register access
* Twiddle-factor loading
* AXI4-Stream frame injection
* Windowing pre-processing
* FFT/IFFT execution
* Output streaming
* `TLAST` frame termination
* CSV result generation

---

## 6. FPGA Validation

The FFT processing chain has also been validated on FPGA hardware.

Detailed FPGA validation results, including the PYNQ control script, hardware output logs, and corresponding measurements, will be added to this document in a future update.

**Status:** FPGA validation completed; detailed results pending documentation.
