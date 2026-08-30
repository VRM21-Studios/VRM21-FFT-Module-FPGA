`timescale 1ns / 1ps

// ============================================================================
// Module      : vrm_windowing_core
// Description : AXI4-Stream Windowing Core
//
// Applies a window function coefficient to streaming complex Q1.15 samples.
// Window coefficients are stored in a ROM initialized from an external memory
// file. The core provides a two-stage pipeline consisting of coefficient
// fetch and fixed-point multiplication.
//
// Input/output sample format:
//   [31:16] = Real component
//   [15:0]  = Imaginary component
//
// The window coefficient is represented as an unsigned Q1.15 value. Both real
// and imaginary components are multiplied by the same coefficient and the
// result is converted back to Q1.15 format.
//
// Supported window functions depend on the contents of the ROM initialization
// file. The default configuration uses a 2048-point coefficient table.
//
// Interface:
//   - AXI4-Stream input  : Complex Q1.15 samples
//   - AXI4-Stream output : Windowed complex Q1.15 samples
//
// Notes:
//   - The datapath advances only when the downstream AXI4-Stream interface
//     asserts TREADY.
//   - TLAST resets the internal sample counter for the next frame.
//   - The ROM is intended to be inferred as Block RAM on supported FPGA
//     targets.
//
// Author      : VRM21-Studios
// License     : MIT
// ============================================================================

module vrm_windowing_core #(
    parameter integer C_AXIS_TDATA_WIDTH = 32,
    parameter integer MAX_PTS            = 2048,
    parameter ROM_FILE                   = "window_2048.mem"
)(
    input wire aclk,
    input wire aresetn,

    // ------------------------------------------------------------------------
    // AXI4-Stream Slave Interface
    //
    // Packed complex input sample:
    //   [31:16] = Real
    //   [15:0]  = Imaginary
    // ------------------------------------------------------------------------
    input  wire [C_AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input  wire                           s_axis_tlast,
    input  wire                           s_axis_tvalid,
    output wire                           s_axis_tready,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master Interface
    //
    // Packed complex output sample:
    //   [31:16] = Real
    //   [15:0]  = Imaginary
    // ------------------------------------------------------------------------
    output wire [C_AXIS_TDATA_WIDTH-1:0] m_axis_tdata,
    output wire                           m_axis_tlast,
    output wire                           m_axis_tvalid,
    input  wire                           m_axis_tready
);

    localparam ADDR_W = $clog2(MAX_PTS);

    // =========================================================================
    // 1. WINDOW COEFFICIENT ROM
    // =========================================================================
    //
    // The ROM stores unsigned Q1.15 window coefficients.
    //
    // The coefficient memory is initialized using an external hexadecimal
    // memory file. The ROM style attribute encourages FPGA synthesis tools to
    // implement the coefficient table using Block RAM.
    //
    // ROM_FILE can be overridden to select a different window coefficient
    // table.
    // =========================================================================

    (* rom_style = "block" *)
    reg [15:0] window_rom [0:MAX_PTS-1];

    initial begin
        $readmemh(ROM_FILE, window_rom);
    end

    // =========================================================================
    // 2. SAMPLE COUNTER AND PIPELINE CONTROL
    // =========================================================================
    //
    // The datapath uses a simplified AXI4-Stream backpressure scheme.
    // Processing advances only when the downstream interface is ready.
    //
    // This keeps the input and output pipeline stages aligned without
    // introducing additional buffering.
    // =========================================================================

    wire pipe_en = m_axis_tready;

    assign s_axis_tready = pipe_en;

    reg [ADDR_W-1:0] sample_idx;

    always @(posedge aclk) begin
        if (!aresetn) begin
            sample_idx <= 0;
        end else if (s_axis_tvalid && pipe_en) begin

            // Start a new frame after TLAST or after reaching the maximum
            // configured frame length.
            if (s_axis_tlast || sample_idx == MAX_PTS - 1) begin
                sample_idx <= 0;
            end else begin
                sample_idx <= sample_idx + 1;
            end
        end
    end

    // =========================================================================
    // 3. PIPELINE STAGE 1: SAMPLE CAPTURE AND ROM FETCH
    // =========================================================================
    //
    // Captures the incoming complex sample and associates it with the
    // corresponding window coefficient.
    //
    // The sample index and coefficient are advanced together so that the
    // coefficient remains aligned with the corresponding input sample.
    // =========================================================================

    reg signed [15:0] s1_data_l;
    reg signed [15:0] s1_data_r;
    reg        [15:0] s1_coeff;
    reg                s1_valid;
    reg                s1_last;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s1_data_l <= 0;
            s1_data_r <= 0;
            s1_coeff  <= 0;
            s1_valid  <= 0;
            s1_last   <= 0;
        end else if (pipe_en) begin
            s1_valid <= s_axis_tvalid;
            s1_last  <= s_axis_tlast;

            if (s_axis_tvalid) begin
                s1_data_l <= s_axis_tdata[15:0];
                s1_data_r <= s_axis_tdata[31:16];

                // Fetch the window coefficient associated with this sample.
                s1_coeff <= window_rom[sample_idx];
            end
        end
    end

    // =========================================================================
    // 4. PIPELINE STAGE 2: FIXED-POINT MULTIPLICATION
    // =========================================================================
    //
    // Multiplies both complex components by the same Q1.15 window
    // coefficient.
    //
    // The coefficient is explicitly extended with a leading zero before
    // conversion to signed representation. This keeps the Q1.15 coefficient
    // positive during the signed multiplication.
    //
    // Product format:
    //   Q1.15 × Q1.15 -> Q2.30
    //
    // Bits [30:15] are selected to return the result to Q1.15 format.
    // =========================================================================

    reg signed [15:0] s2_out_l;
    reg signed [15:0] s2_out_r;
    reg                s2_valid;
    reg                s2_last;

    wire signed [31:0] mult_l =
        s1_data_l * $signed({1'b0, s1_coeff});

    wire signed [31:0] mult_r =
        s1_data_r * $signed({1'b0, s1_coeff});

    always @(posedge aclk) begin
        if (!aresetn) begin
            s2_out_l <= 0;
            s2_out_r <= 0;
            s2_valid <= 0;
            s2_last  <= 0;
        end else if (pipe_en) begin
            s2_valid <= s1_valid;
            s2_last  <= s1_last;

            // Convert the Q2.30 multiplication result back to Q1.15.
            s2_out_l <= mult_l[30:15];
            s2_out_r <= mult_r[30:15];
        end
    end

    // =========================================================================
    // 5. AXI4-STREAM OUTPUT
    // =========================================================================
    //
    // Preserve the complex sample packing used by the input interface.
    // TLAST and TVALID are propagated through the two pipeline stages.
    // =========================================================================

    assign m_axis_tdata  = {s2_out_r, s2_out_l};
    assign m_axis_tlast  = s2_last;
    assign m_axis_tvalid = s2_valid;

endmodule
