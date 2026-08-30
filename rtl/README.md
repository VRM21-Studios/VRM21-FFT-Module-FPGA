# RTL

This directory contains the synthesizable RTL implementation of the VRM21 FFT module.

The current implementation consists of an AXI-connected FFT top-level wrapper and an iterative FFT processing engine.

---

## RTL Components

### `vrm_fft_iterative_axi.v`

Top-level FFT processing module providing:

- AXI4-Lite control and configuration interface
- AXI4-Stream input interface
- AXI4-Stream output interface
- Windowing pre-processing
- Configurable FFT/IFFT operation
- Configurable FFT length
- Twiddle-factor memory interface
- Internal FFT data memory
- FFT processing control FSM
- Output streaming

The module acts as the system-level integration layer between the processor/interconnect and the iterative FFT engine.

---

### `fft_stage_iterative.v`

Iterative radix-2 FFT processing engine.

The module performs the FFT computation using:

- In-place butterfly processing
- Iterative stage/j/k traversal
- BRAM-based data storage
- BRAM-based twiddle-factor storage
- Sequential complex multiplication
- Fixed-point Q15 arithmetic
- Per-stage scaling
- In-place bit-reversal reordering
- FFT/IFFT mode support

The engine is designed to minimize dedicated arithmetic resources by reusing a small number of sequential multipliers across FFT butterflies.

---

## External RAM Dependency

The FFT data buffer and twiddle-factor memory are implemented using:

`vrm_ram_core`

from the separate:

**VRM21-RTL-Utilities**

repository.

The FFT repository intentionally does not duplicate the RAM implementation.

The RAM core is instantiated as:

```verilog
vrm_ram_core
