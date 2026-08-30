# Algorithm and Fixed-Point Representation

## FFT Transform

The FFT computes the discrete Fourier transform using an iterative butterfly architecture.

The forward transform follows:

```text
X[k] = Σ x[n] · e^(-j2πkn/N)
```

The inverse transform uses:

```text
x[n] = Σ X[k] · e^(+j2πkn/N)
```

The implementation uses a shared memory architecture and performs the transform iteratively across multiple processing cycles.

## Twiddle Factors

The twiddle factor is defined as:

```text
W_N^k = e^(-j2πk/N)
```

or:

```text
W_N^k = cos(2πk/N) - j sin(2πk/N)
```

For a 2048-point transform, the required coefficient table contains:

```text
2048 / 2 = 1024
```

entries.

## Fixed-Point Format

Sample and coefficient values use Q1.15 representation.

The nominal representation is:

```text
value = integer / 2^15
```

For example:

```text
32767 ≈ +0.99997
16384 ≈ +0.50000
0     = 0.00000
-32768 = -1.00000
```

Complex values are represented using two signed 16-bit components.

## Complex Multiplication

For:

```text
A = Ar + jAi
B = Br + jBi
```

the complex product is:

```text
A × B =
(ArBr - AiBi)
+
j(ArBi + AiBr)
```

The intermediate multiplication requires additional precision before being shifted back into the target fixed-point format.

## Windowing

The windowing stage multiplies each input sample by a coefficient:

```text
x_windowed[n] = x[n] × w[n]
```

For Q1.15 multiplication, the product is shifted by 15 bits to return to the original fixed-point scale.

## Sine / WOLA Window

The provided Python generator creates a square-root Hann window:

```text
w[n] = sqrt(Hann[n])
```

where:

```text
Hann[n] = 0.5 × (1 - cos(2πn/(N-1)))
```

The square-root form is useful for overlap-add processing because applying the same window in both analysis and synthesis gives:

```text
sqrt(Hann) × sqrt(Hann) = Hann
```

For 50% overlap, the resulting overlap relationship can provide a constant reconstruction envelope under the corresponding WOLA conditions.

## FFT Length Scaling

The same 2048-point window coefficient table can be reused for smaller supported FFT sizes by selecting coefficients at a larger index step.

The current mapping is:

| FFT Size | Window ROM Step |
|---:|---:|
| 256 | 8 |
| 512 | 4 |
| 1024 | 2 |
| 2048 | 1 |

## IFFT Scaling

The fixed-point iterative IFFT implementation introduces transform-dependent scaling.

Simulation analysis may therefore apply additional digital scaling when reconstructing or visualizing the resulting time-domain waveform.

Such post-processing is performed by the testbench and is not part of the AXI4-Stream interface specification.