# Register Map

## Address Map

The top-level FFT core exposes control/status registers through AXI4-Lite.

| Address | Register | Access | Description |
|---:|---|---|---|
| `0x0000` | CTRL | R/W | Control register |
| `0x0004` | STATUS | R | Status register |
| `0x0008` | FFT_N | R/W | Active FFT length |
| `0x1000+` | TWIDDLE RAM | W | Twiddle-factor memory |

## CTRL — `0x0000`

| Bit | Name | Description |
|---:|---|---|
| 2 | WINDOW_EN | Windowing enable |
| 1 | MODE | Transform mode |
| 0 | START | Start transform |

### WINDOW_EN

```text
0 = Windowing bypassed
1 = Windowing enabled
```

### MODE

```text
0 = FFT
1 = IFFT
```

### START

Writing `1` initiates an FFT/IFFT operation when no streamed frame automatically starts the transform.

The start bit is automatically cleared after the transform completes.

## STATUS — `0x0004`

| Bit | Name | Description |
|---:|---|---|
| 1 | BUSY | FFT engine active |
| 0 | DONE | Transform completion indication |

### BUSY

```text
0 = FFT engine idle
1 = FFT engine busy
```

### DONE

Indicates completion of the current transform operation.

## FFT_N — `0x0008`

The lower 16 bits specify the active FFT length.

Supported values:

```text
256
512
1024
2048
```

Example:

```text
FFT_N = 2048
```

## Twiddle RAM

Twiddle factors are mapped starting at:

```text
0x1000
```

Each twiddle factor occupies 4 bytes.

Therefore:

```text
Twiddle[0] → 0x1000
Twiddle[1] → 0x1004
Twiddle[2] → 0x1008
...
```

For a 2048-point transform, 1024 entries are used.

Twiddle RAM writes are accepted only while the FFT engine is idle.

## Example Configuration

### 2048-point FFT with Windowing

```text
Write 2048 to 0x0008
Write 0x00000004 to 0x0000
```

### 2048-point IFFT without Windowing

```text
Write 2048 to 0x0008
Write 0x00000002 to 0x0000
```