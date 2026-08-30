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
```
with:
```
DATA_WIDTH = 32
RAM_STYLE  = "block"
```
for both the FFT sample buffer and the twiddle-factor memory.

The architecture therefore separates generic memory infrastructure from FFT-specific processing logic.

Memory Organization

Two independent memory blocks are used.

FFT Data RAM

Stores complex FFT samples using a 32-bit packed representation:
```
31                    16 15                     0
+-----------------------+-----------------------+
|       Real [15:0]     |    Imaginary [15:0]   |
+-----------------------+-----------------------+
```
The FFT engine operates directly on this memory using in-place butterfly updates.

Twiddle RAM

Stores precomputed complex twiddle factors:
```
31                    16 15                     0
+-----------------------+-----------------------+
|       Real [15:0]     |    Imaginary [15:0]   |
+-----------------------+-----------------------+
```
The twiddle memory is writable through the AXI4-Lite interface when the FFT engine is idle.

Twiddle updates are blocked while the FFT engine is busy.

Windowing

The top-level module optionally applies a window function before FFT processing.

The current implementation uses a block ROM initialized from:
```
window_2048.mem
```
The window coefficient is represented using a 16-bit fixed-point format.

Supported FFT lengths currently include:
```
256
512
1024
2048
```
The window ROM address step is automatically adjusted according to the selected FFT length.

Processing Flow

The overall data path is:

AXI4-Stream Input
        │
        ▼
Window ROM
        │
        ▼
Window Multiply / Bypass
        │
        ▼
FFT Data RAM
        │
        ▼
Iterative FFT Engine
        │
        ├── Twiddle RAM
        │
        └── In-Place Butterfly Processing
        │
        ▼
Bit Reversal
        │
        ▼
FFT Data RAM
        │
        ▼
AXI4-Stream Output
Synthesis Considerations

The FFT implementation is intended for FPGA-oriented synthesis.

The design explicitly requests block RAM inference for:

FFT sample storage
Twiddle-factor storage
Window coefficient storage

The actual implementation result depends on the target FPGA architecture and synthesis tool.

The generic RAM infrastructure is delegated to vrm_ram_core so that memory implementation remains reusable across the broader VRM21 RTL ecosystem.
