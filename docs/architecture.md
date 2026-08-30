# Architecture

## Overview

The VRM21 FFT system consists of an AXI4-Lite control plane, an AXI4-Stream processing path, dedicated windowing logic, block-RAM-based storage, and an iterative FFT/IFFT engine.

The architecture is optimized for FPGA implementation where hardware resource efficiency is more important than achieving the minimum possible transform latency.

## Top-Level Data Flow

```text
AXI4-Stream Input
       │
       ▼
┌─────────────────┐
│ Windowing Stage │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   FFT Data RAM  │
└────────┬────────┘
         │
         ▼
┌────────────────────┐
│ Iterative FFT/IFFT │
│      Engine        │
└─────────┬──────────┘
          │
          ▼
┌─────────────────┐
│   FFT Data RAM  │
└────────┬────────┘
         │
         ▼
AXI4-Stream Output
```

The FFT engine and top-level controller share the FFT data RAM. During input collection, the RAM stores incoming samples. During FFT processing, the iterative engine uses the same RAM for intermediate butterfly results.

## Control Plane

The control plane uses AXI4-Lite.

Software can:

1. Configure the transform length.
2. Select FFT or IFFT mode.
3. Enable or bypass windowing.
4. Load twiddle factors.
5. Start a transform.
6. Monitor the busy and done status.

## Input Stage

Input samples are received through AXI4-Stream.

A complete frame is identified using `TLAST`. The top-level controller stores the processed samples sequentially in FFT RAM.

The input counter is reset when:

- `TLAST` is received, or
- the configured transform length is reached.

## Windowing Stage

The windowing stage consists of two pipeline stages:

```text
AXI Input
   │
   ▼
Stage 1
ROM Fetch + Sample Capture
   │
   ▼
Stage 2
Fixed-Point Multiplication
   │
   ▼
FFT RAM
```

Windowing can be bypassed through the control register.

## FFT Processing

Once the complete input frame has been stored, the controller generates a start pulse for the iterative FFT engine.

The engine operates directly on the FFT data RAM and repeatedly performs butterfly operations using the configured twiddle factors.

The top-level controller waits for the engine's `done` indication before transitioning to the output stage.

## Output Stage

After FFT processing completes, the controller primes the synchronous RAM read path and begins streaming the processed samples through AXI4-Stream.

The output stream remains valid while the module is in the output state.

`TLAST` is asserted for the final configured sample.

## Memory Resources

Two main memories are used:

### FFT Data RAM

Stores:

- Input samples
- Intermediate butterfly results
- Final FFT/IFFT results

### Twiddle RAM

Stores complex Q1.15 twiddle factors.

Both memories are instantiated through `vrm_ram_core` and configured for block RAM inference.

## Resource-Oriented Design

The iterative architecture intentionally reuses arithmetic and memory resources across FFT stages.

Compared with a fully parallel FFT architecture, this approach generally provides:

- Lower arithmetic resource usage
- Lower memory bandwidth requirements
- Simpler FPGA integration

The trade-off is increased processing latency because the transform is computed over multiple iterative cycles.