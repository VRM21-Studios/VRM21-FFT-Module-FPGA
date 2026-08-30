import numpy as np
import scipy.signal as signal


# =============================================================================
# Configuration
# =============================================================================

N = 2048

OUTPUT_FILE = (
    r"path\2\this_file\window_2048.mem"
)


# =============================================================================
# Window Generation
# =============================================================================
#
# Generates a square-root Hann window, also known as a sine window:
#
#     W_sine[n] = sqrt(W_Hann[n])
#
# For a 50% overlap-add configuration:
#
#     W_sine[n] * W_sine[n + N/2] = W_Hann[n] + W_Hann[n + N/2]
#
# resulting in a constant overlap-add response under the corresponding
# normalization convention.
#
# The generated coefficients are converted to unsigned Q1.15 fixed-point
# representation and stored as hexadecimal values for use with $readmemh.
# =============================================================================

# Generate the Hann window.
hann_window = signal.windows.hann(N)

# Take the square root of the Hann window to obtain the sine/WOLA window.
sine_window = np.sqrt(hann_window)

# Convert the window coefficients to unsigned Q1.15.
q15_window = np.clip(
    sine_window * 32767,
    0,
    32767
).astype(int)


# =============================================================================
# Memory File Generation
# =============================================================================

with open(OUTPUT_FILE, "w") as f:
    for value in q15_window:
        # Write one 16-bit hexadecimal coefficient per line.
        f.write(f"{value:04X}\n")


print(
    "Successfully generated window_2048.mem "
    f"({N}-point square-root Hann / sine window)."
)
