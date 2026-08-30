# VRM21 FFT Core

A parameterized, fixed-point FFT/IFFT processing core designed for FPGA-based digital signal processing applications.

The core provides an AXI4-Lite control interface and AXI4-Stream data interfaces, with support for configurable transform length, optional windowing, externally loaded twiddle factors, and iterative in-place FFT processing.

The design is intended to serve as a reusable FFT building block within the VRM21 RTL/DSP ecosystem.

## Features

- Iterative radix-2 FFT/IFFT architecture
- Maximum transform size of 2048 points
- Supported transform sizes:
  - 256 points
  - 512 points
  - 1024 points
  - 2048 points
- Configurable FFT/IFFT operation
- Optional input windowing
- Dedicated AXI4-Stream windowing core
- External twiddle-factor RAM loading
- Fixed-point Q1.15 arithmetic
- Complex 16-bit real + 16-bit imaginary sample format
- AXI4-Lite control and status interface
- AXI4-Stream input and output interfaces
- Block RAM inference for FFT data and twiddle storage
- Parameterized RTL suitable for FPGA synthesis
- Compatible with Vivado-based FPGA development flows

## Architecture

The top-level processing path is organized as:

```text
                    AXI4-Lite
                        │
                        ▼
              ┌──────────────────┐
              │ Control / Status │
              │    Registers     │
              └────────┬─────────┘
                       │
AXI4-Stream Input      │
      │                │
      ▼                │
┌───────────────┐      │
│   Windowing   │      │
│     Core      │      │
└───────┬───────┘      │
        │              │
        ▼              │
┌──────────────────┐   │
│   FFT Data RAM   │◄──┘
└────────┬─────────┘
         │
         ▼
┌──────────────────────┐
│ Iterative FFT Engine │
│      FFT / IFFT      │
└──────────┬───────────┘
           │
           ▼
┌──────────────────┐
│   FFT Data RAM   │
└────────┬─────────┘
         │
         ▼
   AXI4-Stream Output
```

The FFT engine operates iteratively using shared memory rather than requiring a fully parallel FFT datapath. This reduces hardware resource usage at the expense of increased processing latency.

## Data Format

The AXI4-Stream interface uses a 32-bit packed complex sample:

```text
31                    16 15                     0
+-----------------------+-----------------------+
|     Real / Channel R  |    Imag / Channel L   |
+-----------------------+-----------------------+
```

For the FFT core, the packed format is interpreted as:

```text
[31:16] = Real
[15:0]  = Imaginary
```

The dedicated windowing core uses the same 32-bit packed representation.

All sample and coefficient arithmetic is based on signed fixed-point Q1.15 representation unless otherwise specified.

## Control

The FFT core is controlled through AXI4-Lite registers.

The main control register provides:

```text
Bit 2 : Windowing Enable
Bit 1 : Transform Mode
       0 = FFT
       1 = IFFT

Bit 0 : Start
```

The status register provides:

```text
Bit 1 : Busy
Bit 0 : Done
```

See [`docs/register_map.md`](docs/register_map.md) for the complete register map.

## Windowing

The top-level FFT design supports optional input windowing.

A dedicated [`vrm_windowing_core`](rtl/vrm_windowing_core.v) is also provided for applications that require windowing as an independent AXI4-Stream processing block.

The current coefficient-generation flow uses a square-root Hann window, commonly referred to as a sine window:

```text
Hann[n] = 0.5 * (1 - cos(2πn / (N-1)))

Window[n] = sqrt(Hann[n])
```

The coefficients are quantized to unsigned Q1.15 and stored in a memory initialization file.

## Twiddle Factors

Twiddle factors are generated externally and loaded into the FFT core through the AXI4-Lite interface.

For an N-point transform:

```text
W_N^k = exp(-j 2πk/N)
```

Each coefficient is stored as:

```text
[31:16] = Real Q1.15
[15:0]  = Imaginary Q1.15
```

The default configuration provides 1024 twiddle factors for a 2048-point transform.

See [`docs/memory_format.md`](docs/memory_format.md).

## Verification

The repository includes simulation testbenches covering:

- AXI4-Stream windowing operation
- 2048-point FFT processing
- Multi-tone sinusoidal input
- 2048-point IFFT processing
- Frequency-domain to time-domain reconstruction
- Twiddle-factor loading through AXI4-Lite
- Windowing configuration
- AXI4-Stream frame handling and TLAST propagation

The provided simulation results are stored under:

```text
result/
├── fft_result.csv
└── ifft_result.csv
```

A detailed result analysis will be added separately after the simulation logs and FPGA validation data have been consolidated.

## FPGA Validation

The FFT design has also been validated on FPGA hardware.

The hardware validation confirms that the RTL can be integrated into an FPGA processing system and operated through the corresponding software-controlled interface.

Detailed FPGA validation methodology, PYNQ control code, and hardware logs will be documented separately.

## Repository Structure

```text
.
├── rtl/
│   ├── vrm_fft_iterative_axi.v
│   ├── vrm_windowing_core.v
│   └── fft_stage_iterative.v
│
├── mem/
│   ├── twiddle_factors.mem
│   └── window_2048.mem
│
├── scripts/
│   ├── generate_twiddle_factors.py
│   └── generate_window.py
│
├── tb/
│   ├── tb_vrm_fft_axi_sinus.v
│   ├── tb_vrm_ifft_axi_impulse.v
│   └── tb_vrm_windowing_core.v
│
├── result/
│   ├── fft_result.csv
│   └── ifft_result.csv
│
├── docs/
│   ├── architecture.md
│   ├── interface.md
│   ├── register_map.md
│   ├── algorithm.md
│   ├── memory_format.md
│   └── simulation.md
│
└── README.md
```

## Status

| Component | Status |
|---|---|
| FFT RTL | Implemented |
| IFFT RTL | Implemented |
| Iterative FFT Engine | Implemented |
| AXI4-Lite Control | Implemented |
| AXI4-Stream Data Path | Implemented |
| Windowing Core | Implemented |
| Twiddle RAM | Implemented |
| Window ROM | Implemented |
| Simulation Testbench | Available |
| FFT Simulation | Completed |
| IFFT Simulation | Completed |
| FPGA Validation | Completed |
| Detailed Validation Report | Pending |

## Dependencies

The top-level design uses the following VRM21 RTL infrastructure:

- `vrm_ram_core` from the VRM21 RTL utilities
- Vivado FPGA synthesis and simulation environment

The Python scripts require:

- Python 3.x
- NumPy
- SciPy

## License

See the repository license file for licensing terms.

## Documentation

Additional technical documentation:

- [`docs/architecture.md`](docs/architecture.md)
- [`docs/interface.md`](docs/interface.md)
- [`docs/register_map.md`](docs/register_map.md)
- [`docs/algorithm.md`](docs/algorithm.md)
- [`docs/memory_format.md`](docs/memory_format.md)
- [`docs/simulation.md`](docs/simulation.md)