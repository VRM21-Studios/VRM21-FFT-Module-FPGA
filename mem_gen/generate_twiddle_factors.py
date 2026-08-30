import numpy as np


# =============================================================================
# Configuration
# =============================================================================

FFT_PTS = 2048
NUM_TWIDDLES = FFT_PTS // 2

OUTPUT_FILE = (
    r"path\2\this_file\twiddle_factors.mem"
)


# =============================================================================
# Twiddle Factor Generation
# =============================================================================
#
# Generates the first N/2 twiddle factors for an N-point FFT.
#
# Twiddle factor definition:
#
#     W_N^k = exp(-j * 2 * pi * k / N)
#
# Each complex coefficient is stored as:
#
#     [31:16] = Real component
#     [15:0]  = Imaginary component
#
# Both components use signed Q1.15 fixed-point representation.
# =============================================================================

with open(OUTPUT_FILE, "w") as f:
    for i in range(NUM_TWIDDLES):

        # Calculate the twiddle-factor phase angle.
        angle = -2.0 * np.pi * i / FFT_PTS

        # Convert the real and imaginary components to signed Q1.15.
        real_part = int(round(np.cos(angle) * 32767))
        imag_part = int(round(np.sin(angle) * 32767))

        # Saturate to the valid signed 16-bit Q1.15 range.
        if real_part > 32767:
            real_part = 32767
        if real_part < -32768:
            real_part = -32768

        if imag_part > 32767:
            imag_part = 32767
        if imag_part < -32768:
            imag_part = -32768

        # Convert signed values to 16-bit two's-complement representation.
        real_hex = real_part & 0xFFFF
        imag_hex = imag_part & 0xFFFF

        # Pack the complex coefficient into a 32-bit word:
        #     [Real(16) | Imaginary(16)]
        twiddle_32 = (real_hex << 16) | imag_hex

        # Write one 32-bit hexadecimal word per line.
        f.write(f"{twiddle_32:08X}\n")


print(
    f"Successfully generated {NUM_TWIDDLES} twiddle factors "
    f"for a {FFT_PTS}-point FFT."
)
