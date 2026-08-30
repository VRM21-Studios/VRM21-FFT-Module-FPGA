# Interface Specification

## Clock and Reset

| Signal | Direction | Description |
|---|---|---|
| `aclk` | Input | System clock |
| `aresetn` | Input | Active-low reset |

The design uses a synchronous active-low reset for sequential logic.

## AXI4-Lite Interface

The top-level FFT core exposes a standard AXI4-Lite slave interface for configuration and status access.

### Write Interface

| Signal | Description |
|---|---|
| `s_axi_awaddr` | Write address |
| `s_axi_awvalid` | Write address valid |
| `s_axi_awready` | Write address ready |
| `s_axi_wdata` | Write data |
| `s_axi_wstrb` | Write byte strobes |
| `s_axi_wvalid` | Write data valid |
| `s_axi_wready` | Write data ready |
| `s_axi_bresp` | Write response |
| `s_axi_bvalid` | Write response valid |
| `s_axi_bready` | Write response ready |

### Read Interface

| Signal | Description |
|---|---|
| `s_axi_araddr` | Read address |
| `s_axi_arvalid` | Read address valid |
| `s_axi_arready` | Read address ready |
| `s_axi_rdata` | Read data |
| `s_axi_rresp` | Read response |
| `s_axi_rvalid` | Read data valid |
| `s_axi_rready` | Read data ready |

## AXI4-Stream Input

| Signal | Description |
|---|---|
| `s_axis_tdata` | Packed complex input sample |
| `s_axis_tvalid` | Input data valid |
| `s_axis_tready` | Input ready |
| `s_axis_tlast` | End-of-frame indicator |

The input sample format is:

```text
[31:16] = Real
[15:0]  = Imaginary
```

## AXI4-Stream Output

| Signal | Description |
|---|---|
| `m_axis_tdata` | Packed complex output sample |
| `m_axis_tvalid` | Output data valid |
| `m_axis_tready` | Downstream ready |
| `m_axis_tlast` | End-of-frame indicator |

The output sample format is:

```text
[31:16] = Real
[15:0]  = Imaginary
```

## Handshake

A transfer occurs when:

```text
VALID && READY
```

For input:

```text
s_axis_tvalid && s_axis_tready
```

For output:

```text
m_axis_tvalid && m_axis_tready
```

The testbenches drive AXI-Stream input on the falling clock edge to provide stable signals before the following rising-edge transfer.

## Frame Handling

A transform frame is terminated by `TLAST`.

For a configured 2048-point transform:

```text
Sample 0
Sample 1
...
Sample 2046
Sample 2047 + TLAST
```

The same mechanism is used for FFT and IFFT operation.

## Windowing Core Interface

`vrm_windowing_core` provides an independent AXI4-Stream processing block.

It accepts the same 32-bit complex sample representation and applies the configured ROM coefficient to both components.

The block propagates `TLAST` through its pipeline.