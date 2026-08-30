`timescale 1ns / 1ps

// ============================================================================
// VRM21 FFT Iterative AXI Interface
// ----------------------------------------------------------------------------
// Module      : vrm_fft_iterative_axi
// Description : AXI4-Lite controlled iterative FFT/IFFT processing module
//               with AXI4-Stream input/output interfaces.
//
// Function:
//   - Accepts complex input samples through AXI4-Stream.
//   - Optionally applies a configurable window function before FFT processing.
//   - Stores input samples in an internal block RAM.
//   - Performs iterative radix-2 FFT/IFFT processing.
//   - Supports configurable transform lengths up to FFT_MAX_PTS.
//   - Streams transformed complex samples through AXI4-Stream.
//   - Provides AXI4-Lite control and status registers.
//   - Provides software-accessible twiddle-factor memory.
//
// Data Format:
//   AXI4-Stream input/output:
//     [31:16] = Real component
//     [15:0]  = Imaginary component
//
// Supported FFT Lengths:
//   - 256 points
//   - 512 points
//   - 1024 points
//   - 2048 points
//
// Numeric Format:
//   - Complex samples : Signed Q15
//   - Window factors  : Signed/unsigned Q15-compatible coefficients
//   - Twiddle factors : Signed Q15
//
// Memory:
//   - FFT data memory uses vrm_ram_core from VRM21-RTL-Utilities.
//   - Twiddle-factor memory uses vrm_ram_core from VRM21-RTL-Utilities.
//   - Window coefficients are provided through an external memory image.
//
// Interfaces:
//   - AXI4-Lite  : Control, status, FFT configuration, and twiddle loading.
//   - AXI4-Stream: Complex sample input and transformed sample output.
//
// Control Features:
//   - FFT / IFFT mode selection.
//   - Optional windowing.
//   - Software-controlled FFT start.
//   - FFT length configuration.
//   - Busy and done status reporting.
//   - Software-accessible twiddle-factor memory.
//
// Architecture:
//   AXI4-Lite
//       │
//       ├── Control / Status
//       └── Twiddle RAM
//              │
//              ▼
//       Windowing Pipeline
//              │
//              ▼
//          FFT Data RAM
//              │
//              ▼
//     Iterative FFT Engine
//              │
//              ▼
//       AXI4-Stream Output
//
// Dependencies:
//   - vrm_ram_core
//   - fft_stage_iterative
//   - window_2048.mem
//
// Implementation Notes:
//   - The FFT engine operates in-place using the internal data RAM.
//   - The top-level datapath separates input collection, FFT execution,
//     RAM prefetch, and output streaming into independent scheduler states.
//   - Twiddle-factor memory writes are blocked while the FFT engine is busy.
//   - The implementation is intended for FPGA-oriented synthesis and
//     integration with AXI-based SoC systems.
//
// Author      : VRM21 Studios
// Project     : VRM21 RTL / FFT Module Series
// License     : MIT
// ============================================================================

module vrm_fft_iterative_axi #(
    parameter C_S_AXI_DATA_WIDTH  = 32,
    parameter C_S_AXI_ADDR_WIDTH  = 13,
    parameter C_AXIS_TDATA_WIDTH  = 32,
    parameter FFT_MAX_PTS         = 2048
) (
    input wire aclk,
    input wire aresetn,

    // ------------------------------------------------------------------------
    // AXI4-Lite Slave Interface
    // ------------------------------------------------------------------------
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire                           s_axi_awvalid,
    output wire                           s_axi_awready,

    input  wire [C_S_AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [3:0]                     s_axi_wstrb,
    input  wire                           s_axi_wvalid,
    output wire                           s_axi_wready,

    output wire [1:0]                     s_axi_bresp,
    output wire                           s_axi_bvalid,
    input  wire                           s_axi_bready,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire                           s_axi_arvalid,
    output wire                           s_axi_arready,

    output wire [C_S_AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]                     s_axi_rresp,
    output wire                           s_axi_rvalid,
    input  wire                           s_axi_rready,

    // ------------------------------------------------------------------------
    // AXI4-Stream Slave Interface
    // ------------------------------------------------------------------------
    // Packed complex input sample:
    //   [31:16] = Real
    //   [15:0]  = Imaginary
    input  wire [C_AXIS_TDATA_WIDTH-1:0] s_axis_tdata,
    input  wire                           s_axis_tvalid,
    input  wire                           s_axis_tlast,
    output wire                           s_axis_tready,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master Interface
    // ------------------------------------------------------------------------
    // Packed complex output sample:
    //   [31:16] = Real
    //   [15:0]  = Imaginary
    output wire [C_AXIS_TDATA_WIDTH-1:0] m_axis_tdata,
    output wire                           m_axis_tvalid,
    output wire                           m_axis_tlast,
    input  wire                           m_axis_tready
);

    localparam ADDR_DATA = $clog2(FFT_MAX_PTS);
    localparam ADDR_TWID = $clog2(FFT_MAX_PTS / 2);

    // =========================================================================
    // 1. AXI4-LITE CONTROL AND STATUS REGISTERS
    // =========================================================================
    //
    // Control register:
    //   [2] = Windowing enable
    //         1: Apply window function
    //         0: Bypass window function
    //
    //   [1] = Transform mode
    //         0: FFT
    //         1: IFFT
    //
    //   [0] = Start
    //
    // Status register:
    //   [1] = Busy
    //   [0] = Done
    //
    // FFT length register:
    //   [15:0] = Active FFT length
    //
    reg [31:0] reg_ctrl   = 32'h0;
    reg [31:0] reg_status = 32'h0;
    reg [15:0] reg_fft_n  = 16'd2048;

    // Twiddle-factor memory is mapped to the upper AXI address region.
    wire is_twid_addr = (s_axi_awaddr >= 16'h1000);

    wire fft_done;

    reg        axi_awready;
    reg        axi_wready;
    reg        axi_bvalid;

    reg        axi_arready;
    reg        axi_rvalid;
    reg [31:0] axi_rdata;

    assign s_axi_awready = axi_awready;
    assign s_axi_wready  = axi_wready;
    assign s_axi_bvalid  = axi_bvalid;
    assign s_axi_bresp   = 2'b00;

    assign s_axi_arready = axi_arready;
    assign s_axi_rvalid  = axi_rvalid;
    assign s_axi_rdata   = axi_rdata;
    assign s_axi_rresp   = 2'b00;

    // Twiddle RAM write interface.
    reg                    twid_we;
    reg [ADDR_TWID-1:0]    twid_wr_addr;
    reg [31:0]             twid_wr_data;

    // -------------------------------------------------------------------------
    // AXI4-Lite Write Channel
    //
    // The implementation accepts an address/data pair when both AWVALID and
    // WVALID are asserted together. Twiddle-factor writes are rejected while
    // the FFT engine is busy.
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;

            reg_ctrl    <= 32'h0;
            reg_fft_n   <= 16'd2048;

            twid_we     <= 1'b0;
        end else begin
            twid_we <= 1'b0;

            if (!axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                axi_awready <= 1'b1;
                axi_wready  <= 1'b1;
            end else begin
                axi_awready <= 1'b0;
                axi_wready  <= 1'b0;
            end

            if (axi_awready &&
                s_axi_awvalid &&
                axi_wready &&
                s_axi_wvalid) begin

                axi_bvalid <= 1'b1;

                if (!is_twid_addr) begin
                    case (s_axi_awaddr[7:0])
                        8'h00: reg_ctrl  <= s_axi_wdata;
                        8'h08: reg_fft_n <= s_axi_wdata[15:0];
                        default: begin
                        end
                    endcase
                end else if (!reg_status[1]) begin
                    // Twiddle memory may only be modified while idle.
                    twid_we      <= 1'b1;
                    twid_wr_addr <= s_axi_awaddr[ADDR_TWID+1:2];
                    twid_wr_data <= s_axi_wdata;
                end
            end else if (s_axi_bready && axi_bvalid) begin
                axi_bvalid <= 1'b0;
            end

            // Start is automatically cleared when the FFT operation completes.
            if (fft_done)
                reg_ctrl[0] <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // AXI4-Lite Read Channel
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rdata   <= 32'h0;
        end else begin
            if (!axi_arready && s_axi_arvalid) begin
                axi_arready <= 1'b1;
                axi_rvalid  <= 1'b1;

                case (s_axi_araddr[7:0])
                    8'h00: axi_rdata <= reg_ctrl;
                    8'h04: axi_rdata <= reg_status;
                    8'h08: axi_rdata <= {16'b0, reg_fft_n};
                    default: axi_rdata <= 32'h0;
                endcase
            end else if (s_axi_rready && axi_rvalid) begin
                axi_rvalid  <= 1'b0;
                axi_arready <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 2. WINDOWING PRE-PROCESSOR
    // =========================================================================

    // Window coefficient ROM.
    // Coefficients are loaded from the simulation/synthesis memory image.
    (* rom_style = "block" *)
    reg [15:0] window_rom [0:FFT_MAX_PTS-1];

    initial begin
        $readmemh("window_2048.mem", window_rom);
    end

    // Window ROM address increment based on the active FFT length.
    //
    // The 2048-point coefficient table is reused for smaller FFT sizes:
    //
    //   256  -> step 8
    //   512  -> step 4
    //   1024 -> step 2
    //   2048 -> step 1
    //
    reg [ADDR_DATA-1:0] win_step;

    always @(*) begin
        case (reg_fft_n)
            16'd256:  win_step = 8;
            16'd512:  win_step = 4;
            16'd1024: win_step = 2;
            16'd2048: win_step = 1;
            default:  win_step = 1;
        endcase
    end

    // Data-path scheduler states.
    localparam S_IDLE     = 0;
    localparam S_FFT_RUN  = 1;
    localparam S_PREFETCH = 2;
    localparam S_OUTPUT   = 3;

    reg [1:0] state = S_IDLE;

    // Input is accepted only while the top-level data path is idle.
    wire fsm_ready = (state == S_IDLE) && aresetn;

    assign s_axis_tready = fsm_ready;

    reg [ADDR_DATA-1:0] win_cnt  = 0;
    reg [ADDR_DATA-1:0] win_addr = 0;

    // -------------------------------------------------------------------------
    // Windowing Pipeline - Stage 1
    //
    // Captures the incoming complex sample and reads the corresponding window
    // coefficient from ROM.
    // -------------------------------------------------------------------------
    reg signed [15:0] stg1_l;
    reg signed [15:0] stg1_r;
    reg                stg1_valid;
    reg                stg1_last;
    reg [15:0]         stg1_coeff;

    always @(posedge aclk) begin
        if (!aresetn) begin
            win_cnt    <= 0;
            win_addr   <= 0;
            stg1_valid <= 1'b0;
            stg1_last  <= 1'b0;
        end else if (fsm_ready) begin
            stg1_valid <= s_axis_tvalid;
            stg1_last  <= s_axis_tlast;

            if (s_axis_tvalid) begin
                stg1_l     <= s_axis_tdata[15:0];
                stg1_r     <= s_axis_tdata[31:16];
                stg1_coeff <= window_rom[win_addr];

                if (s_axis_tlast || win_cnt == reg_fft_n - 1) begin
                    win_cnt  <= 0;
                    win_addr <= 0;
                end else begin
                    win_cnt  <= win_cnt + 1;
                    win_addr <= win_addr + win_step;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Windowing Pipeline - Stage 2
    //
    // Applies the window coefficient to both real and imaginary components,
    // or forwards the original sample when windowing is disabled.
    // -------------------------------------------------------------------------
    reg signed [15:0] stg2_l;
    reg signed [15:0] stg2_r;
    reg                stg2_valid;
    reg                stg2_last;

    wire signed [31:0] mult_l =
        stg1_l * $signed({1'b0, stg1_coeff});

    wire signed [31:0] mult_r =
        stg1_r * $signed({1'b0, stg1_coeff});

    always @(posedge aclk) begin
        if (!aresetn) begin
            stg2_valid <= 1'b0;
            stg2_last  <= 1'b0;
            stg2_l     <= 0;
            stg2_r     <= 0;
        end else if (fsm_ready) begin
            stg2_valid <= stg1_valid;
            stg2_last  <= stg1_last;

            if (reg_ctrl[2]) begin
                stg2_l <= mult_l[30:15];
                stg2_r <= mult_r[30:15];
            end else begin
                stg2_l <= stg1_l;
                stg2_r <= stg1_r;
            end
        end
    end

    wire [31:0] win_tdata  = {stg2_r, stg2_l};
    wire        win_tvalid = stg2_valid;
    wire        win_tlast  = stg2_last;

    // =========================================================================
    // 3. FFT CORE AND MEMORY INSTANTIATION
    // =========================================================================

    wire fft_mode = reg_ctrl[1];
    wire [15:0] fft_n = reg_fft_n;

    // FFT data RAM interface.
    wire                  ram_we;
    wire                  ram_re;
    wire [ADDR_DATA-1:0]  ram_wr_addr;
    wire [ADDR_DATA-1:0]  ram_rd_addr;
    wire [31:0]           ram_wr_data;
    wire [31:0]           ram_rd_data;

    // Generic RAM infrastructure provided by VRM21-RTL-Utilities.
    vrm_ram_core #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(ADDR_DATA),
        .RAM_STYLE("block")
    ) u_data_ram (
        .clk     (aclk),
        .rstn    (aresetn),
        .we      (ram_we),
        .wr_addr (ram_wr_addr),
        .wr_data (ram_wr_data),
        .re      (ram_re),
        .rd_addr (ram_rd_addr),
        .rd_data (ram_rd_data)
    );

    // Twiddle-factor RAM interface.
    wire [31:0]          twid_rd_data;
    wire                 fft_twid_re;
    wire [ADDR_TWID-1:0] fft_twid_addr;

    vrm_ram_core #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(ADDR_TWID),
        .RAM_STYLE("block")
    ) u_twid_ram (
        .clk     (aclk),
        .rstn    (aresetn),
        .we      (twid_we),
        .wr_addr (twid_wr_addr),
        .wr_data (twid_wr_data),
        .re      (fft_twid_re),
        .rd_addr (fft_twid_addr),
        .rd_data (twid_rd_data)
    );

    // FFT engine interface.
    wire        fft_busy;
    wire        fft_ram_we;
    wire [ADDR_DATA-1:0] fft_ram_addr;
    wire [31:0] fft_ram_wdata;

    reg fft_start_pulse = 1'b0;

    fft_stage_iterative #(
        .MAX_N(FFT_MAX_PTS)
    ) u_fft (
        .clk           (aclk),
        .rstn          (aresetn),
        .start         (fft_start_pulse),
        .mode          (fft_mode),
        .fft_n         (fft_n),

        .ram_data_we   (fft_ram_we),
        .ram_data_addr (fft_ram_addr),
        .ram_data_wdata(fft_ram_wdata),
        .ram_data_rdata(ram_rd_data),

        .ram_twid_re   (fft_twid_re),
        .ram_twid_addr (fft_twid_addr),
        .ram_twid_rdata(twid_rd_data),

        .done          (fft_done),
        .busy          (fft_busy)
    );

    // =========================================================================
    // 4. DATA-PATH FSM
    // =========================================================================
    //
    // Controls:
    //
    //   S_IDLE
    //       Accept input samples and populate the FFT RAM.
    //
    //   S_FFT_RUN
    //       Wait for the iterative FFT engine to complete.
    //
    //   S_PREFETCH
    //       Prime the synchronous RAM output path before streaming.
    //
    //   S_OUTPUT
    //       Stream processed FFT samples through AXI4-Stream.
    //
    reg [ADDR_DATA-1:0] input_cnt;
    reg [ADDR_DATA-1:0] output_cnt;
    reg [ADDR_DATA-1:0] rd_addr_ptr;
    reg                  start_reg_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state          <= S_IDLE;
            input_cnt      <= 0;
            output_cnt     <= 0;
            rd_addr_ptr    <= 0;
            start_reg_r    <= 1'b0;
            fft_start_pulse <= 1'b0;
        end else begin
            start_reg_r     <= reg_ctrl[0];
            fft_start_pulse <= 1'b0;

            case (state)

                S_IDLE: begin
                    output_cnt  <= 0;
                    rd_addr_ptr <= 0;

                    // Start FFT after the final input sample has passed through
                    // the windowing pipeline.
                    if (win_tvalid && fsm_ready) begin
                        input_cnt <= input_cnt + 1;

                        if (win_tlast) begin
                            fft_start_pulse <= 1'b1;
                            state            <= S_FFT_RUN;
                            input_cnt        <= 0;
                        end

                    // Alternatively, allow software to start an FFT directly
                    // when no streamed input frame is being collected.
                    end else if (reg_ctrl[0] && !start_reg_r) begin
                        fft_start_pulse <= 1'b1;
                        state            <= S_FFT_RUN;
                        input_cnt        <= 0;
                    end
                end

                S_FFT_RUN: begin
                    if (fft_done) begin
                        state       <= S_PREFETCH;
                        output_cnt  <= 0;
                        rd_addr_ptr <= 0;
                    end
                end

                // Prime the synchronous RAM read path.
                S_PREFETCH: begin
                    rd_addr_ptr <= 1;
                    state       <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        rd_addr_ptr <= rd_addr_ptr + 1;

                        if (output_cnt == fft_n - 1) begin
                            state <= S_IDLE;
                        end else begin
                            output_cnt <= output_cnt + 1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

    // =========================================================================
    // 5. FFT DATA RAM MULTIPLEXING
    // =========================================================================

    // Select the write source:
    //
    //   IDLE     -> windowed input stream
    //   FFT_RUN  -> iterative FFT engine
    //
    assign ram_we =
        (state == S_IDLE)    ? (win_tvalid && fsm_ready) :
        (state == S_FFT_RUN) ? fft_ram_we :
        1'b0;

    assign ram_wr_addr =
        (state == S_IDLE) ? input_cnt :
        fft_ram_addr;

    assign ram_wr_data =
        (state == S_IDLE) ? win_tdata :
        fft_ram_wdata;

    // Generate synchronous RAM read enables.
    assign ram_re =
        (state == S_FFT_RUN && !fft_ram_we) ||
        (state == S_PREFETCH) ||
        (state == S_OUTPUT && m_axis_tready);

    assign ram_rd_addr =
        (state == S_FFT_RUN) ? fft_ram_addr :
        rd_addr_ptr;

    // =========================================================================
    // 6. AXI4-STREAM OUTPUT
    // =========================================================================

    assign m_axis_tvalid = (state == S_OUTPUT);
    assign m_axis_tdata  = ram_rd_data;

    assign m_axis_tlast =
        (state == S_OUTPUT) &&
        (output_cnt == fft_n - 1);

    // =========================================================================
    // 7. STATUS REGISTER
    // =========================================================================

    always @(posedge aclk) begin
        if (!aresetn) begin
            reg_status <= 32'h0;
        end else begin
            reg_status[0] <= fft_done;
            reg_status[1] <= fft_busy;
        end
    end

endmodule
