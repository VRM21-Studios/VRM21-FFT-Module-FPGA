# VRM21 FFT Module FPGA

A parameterized FPGA FFT processing core developed as part of the **VRM21 RTL Series**.

The design implements an iterative radix-2 FFT/IFFT datapath with AXI4-Lite control, AXI4-Stream data interfaces, programmable twiddle-factor memory, and optional hardware windowing. The core is designed for FPGA-based DSP applications where deterministic fixed-point processing and reusable RTL infrastructure are required.

The current implementation supports FFT sizes up to **2048 points** and has been verified through RTL simulation and validated on FPGA hardware using a PYNQ-based test environment.

---

## Features

- Parameterized iterative FFT/IFFT engine
- Up to 2048-point transforms
- Forward FFT and inverse FFT operation
- Fixed-point complex data path
- Q1.15 input/output representation
- AXI4-Lite control and status interface
- AXI4-Stream input and output interfaces
- Programmable twiddle-factor BRAM
- Optional hardware windowing
- Block RAM inference for FFT data and twiddle memories
- Configurable FFT length
- Frame-based processing using AXI4-Stream `TLAST`
- Simulation result export to CSV
- FPGA hardware validation through PYNQ

---

## Architecture

The processing chain consists of several functional blocks:

```text
                AXI4-Lite
                    │
                    ▼
        ┌──────────────────────┐
        │ Control / Status     │
        │ Registers            │
        └──────────┬───────────┘
                   │
                   ▼
AXI4-Stream   ┌───────────────┐
Input ───────►│ Windowing     │
              │ Preprocessor  │
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │ FFT Data RAM  │
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │ Iterative     │
              │ FFT / IFFT    │
              │ Engine        │
              └───────┬───────┘
                      │
          ┌───────────┴───────────┐
          │                       │
          ▼                       ▼
   Twiddle-Factor RAM       FFT Data RAM
          │                       │
          └───────────┬───────────┘
                      │
                      ▼
              AXI4-Stream
                  Output
```

### Processing Flow

For FFT operation:

```text
Input Samples
     │
     ▼
Optional Windowing
     │
     ▼
FFT Data Buffer
     │
     ▼
Iterative FFT
     │
     ▼
Frequency-Domain Output
```

For IFFT operation:

```text
Frequency-Domain Input
     │
     ▼
FFT Data Buffer
     │
     ▼
Iterative IFFT
     │
     ▼
Time-Domain Output
```

---

## Hardware Interface

### AXI4-Lite

The AXI4-Lite interface provides software access to configuration, status, and twiddle-factor memory.

| Address | Register | Description |
|---:|---|---|
| `0x00` | Control | Windowing, FFT/IFFT mode, start |
| `0x04` | Status | Busy and done status |
| `0x08` | FFT Length | Active transform size |
| `0x1000+` | Twiddle RAM | Programmable twiddle factors |

### Control Register

```text
Bit 2 : Windowing Enable
        0 = Bypass
        1 = Enable

Bit 1 : Transform Mode
        0 = FFT
        1 = IFFT

Bit 0 : Start
        0 = Idle / Auto-start mode
        1 = Start operation
```

For streamed frame processing, the FFT can automatically start after the final sample is received through `TLAST`.

### Status Register

```text
Bit 1 : Busy
Bit 0 : Done
```

---

## AXI4-Stream Data Format

Complex samples are packed into a 32-bit AXI4-Stream word.

```text
31                         16 15                          0
┌────────────────────────────┬────────────────────────────┐
│        Real / Imag*        │        Imag / Real*        │
└────────────────────────────┴────────────────────────────┘
```

The exact field ordering depends on the processing interface:

- `vrm_fft_iterative_axi` input/output uses the packed complex representation implemented by the RTL.
- The accompanying testbenches explicitly decode the corresponding real and imaginary fields.
- The PYNQ software uses the same 32-bit packed representation when transferring samples through DMA.

`TLAST` marks the final sample of each transform frame.

---

## Windowing

The top-level FFT wrapper includes an optional hardware windowing stage.

The window coefficients are stored in a ROM initialized through:

```text
window_2048.mem
```

The current coefficient-generation flow uses a square-root Hann window:

```text
Sine Window = sqrt(Hann Window)
```

This is suitable for weighted overlap-add style processing when complementary analysis/synthesis windows are used.

The windowing block is also available as a standalone AXI4-Stream module:

```text
vrm_windowing_core
```

Supported transform lengths currently include:

- 256 points
- 512 points
- 1024 points
- 2048 points

The 2048-point coefficient table is reused for smaller transform sizes by applying the corresponding address step.

---

## Twiddle Factors

Twiddle factors are represented using signed Q1.15 fixed-point values.

For an N-point transform:

```text
W_N^k = exp(-j 2πk/N)
```

The stored format is:

```text
[31:16] = Real
[15:0]  = Imaginary
```

For a 2048-point transform, the design requires:

```text
2048 / 2 = 1024
```

twiddle factors.

The twiddle memory can be initialized externally and uploaded to the FPGA through the AXI4-Lite interface.

---

## Verification

The RTL has been verified using dedicated simulation testbenches covering the main processing paths.

### Windowing Test

`tb_vrm_windowing_core`

The testbench sends a 2048-sample constant signal through the AXI4-Stream interface and verifies the windowing datapath and frame termination.

### FFT Test

`tb_vrm_fft_axi_sinus`

The testbench generates three sinusoidal components:

```text
100 Hz
300 Hz
500 Hz
```

at:

```text
Fs = 48 kHz
N  = 2048
```

Windowing is enabled and the resulting FFT spectrum is exported to:

```text
result/fft_result.csv
```

### IFFT Test

`tb_vrm_ifft_axi_impulse`

The testbench injects a conjugate-symmetric spectrum at:

```text
Bin 10
Bin 2038
```

and performs a 2048-point IFFT to reconstruct the corresponding time-domain signal.

The output is exported to:

```text
result/ifft_result.csv
```

Detailed simulation logs and verification information are available in:

```text
docs/tb_result.md
```

---

## FPGA Validation

The FFT processing chain has been validated on FPGA hardware using a PYNQ-based host environment.

The hardware validation flow consists of:

```text
PYNQ Python Application
        │
        ▼
   AXI DMA Engine
        │
        ▼
vrm_fft_iterative_axi
        │
        ├── AXI4-Lite Configuration
        │
        ├── Twiddle-Factor BRAM
        │
        ├── Hardware Windowing
        │
        └── Iterative FFT Engine
        │
        ▼
   AXI DMA Output
        │
        ▼
   Python Analysis
```

The PYNQ application configures the transform length, generates and uploads the Q1.15 twiddle factors, enables hardware windowing, and transfers input/output samples through AXI DMA.

The software analysis flow can process CSV/TXT datasets and generate time-domain and frequency-domain plots from the FPGA output.

The current hardware configuration uses:

```text
FFT Size       : 2048 points
Sample Format  : 32-bit packed complex
Windowing      : Hardware enabled
Transform      : Forward FFT
Interface      : AXI4-Lite + AXI4-Stream
Data Transfer  : AXI DMA
Host Platform  : PYNQ
```

FPGA validation confirms that the RTL can operate as an integrated hardware accelerator rather than only as an RTL simulation model.

Detailed hardware measurements and PYNQ execution logs can be added to the verification documentation as the hardware validation record is expanded.

---

## Software Support

A Python/PYNQ utility is provided for hardware-assisted FFT processing and result visualization.

The software performs:

1. FPGA bitstream loading
2. FFT IP discovery
3. AXI DMA buffer allocation
4. Twiddle-factor generation
5. Twiddle-factor upload
6. FFT configuration
7. Input sample packing
8. DMA-based data transfer
9. FPGA output decoding
10. Magnitude calculation
11. Frequency-domain plotting

For datasets containing multiple FFT frames, the software can process individual frames and average their magnitude spectra.

---

## Repository Structure

```text
.
├── rtl/
│   ├── vrm_fft_iterative_axi.v
│   ├── vrm_windowing_core.v
│   └── ...
│
├── tb/
│   ├── tb_vrm_fft_axi_sinus.v
│   ├── tb_vrm_ifft_axi_impulse.v
│   ├── tb_vrm_windowing_core.v
│   └── ...
│
├── mem/
│   ├── twiddle_factors.mem
│   └── window_2048.mem
│
├── scripts/
│   ├── generate_twiddle_factors.py
│   └── generate_window.py
│
├── result/
│   ├── fft_result.csv
│   └── ifft_result.csv
│
├── docs/
│   ├── architecture.md
│   ├── interface.md
│   ├── tb_result.md
│   └── limitations.md
│
└── README.md
```

The exact directory names may vary depending on the Vivado project organization.

---

## Fixed-Point Representation

The main datapath uses fixed-point arithmetic to reduce FPGA resource usage and provide deterministic hardware behavior.

The external complex sample format is based on signed 16-bit Q1.15 components.

```text
Q1.15

Sign
 │
 ▼
┌─┬───────────────────────────────┐
│S│          Fraction             │
└─┴───────────────────────────────┘
  15 fractional bits
```

Twiddle factors and window coefficients are also represented using 16-bit fixed-point values.

Internal FFT arithmetic may use wider intermediate representations depending on the processing stage.

---

## Current Limitations

The current implementation has several practical limitations:

- Maximum configured transform size is 2048 points.
- Supported transform lengths are currently limited to the implemented power-of-two configurations.
- The current coefficient memory is based on a 2048-point window table.
- Fixed-point quantization introduces numerical error compared with floating-point FFT implementations.
- Twiddle factors must be loaded or initialized before FFT processing.
- The current AXI4-Lite implementation expects the address and data write channels to be presented together.
- The current verification environment focuses primarily on functional correctness rather than exhaustive numerical error characterization.
- FPGA resource utilization and maximum operating frequency depend on the target FPGA device and synthesis configuration.

Additional implementation-specific limitations are documented in:

```text
docs/limitations.md
```

---

## Status

| Component | Status |
|---|---|
| Iterative FFT engine | Implemented |
| IFFT mode | Implemented |
| AXI4-Lite control | Implemented |
| AXI4-Stream interface | Implemented |
| Twiddle-factor BRAM | Implemented |
| Hardware windowing | Implemented |
| Windowing standalone core | Implemented |
| RTL simulation | Verified |
| FFT simulation | Verified |
| IFFT simulation | Verified |
| CSV result generation | Verified |
| FPGA validation | Completed |
| Extended numerical characterization | Ongoing |

---

## License

Licensed under the MIT License.
Provided as-is, without warranty.

---

## VRM21 RTL Series

This FFT core is part of the **VRM21 RTL Series**, a collection of reusable FPGA/RTL building blocks developed for DSP, processor, memory, and hardware acceleration applications.
