`timescale 1ns / 1ps

// ============================================================================
// Iterative FFT Processing Engine
//
// Performs an in-place radix-2 FFT/IFFT using external data and twiddle RAM.
//
// Data format:
//   [31:16] = Real component, Q15
//   [15:0]  = Imaginary component, Q15
//
// The engine supports FFT lengths up to MAX_N and performs the transform using
// a sequential state machine to reuse the arithmetic datapath.
// ============================================================================

module fft_stage_iterative #(
    parameter MAX_N = 2048,
    parameter DATA_W = 16,
    parameter TWID_W = 16
) (
    input wire clk,
    input wire rstn,

    input wire start,
    input wire mode,
    input wire [15:0] fft_n,

    // FFT data RAM interface
    output reg ram_data_we,
    output reg [$clog2(MAX_N)-1:0] ram_data_addr,
    output reg [31:0] ram_data_wdata,
    input  wire [31:0] ram_data_rdata,

    // Twiddle-factor RAM interface
    output reg ram_twid_re,
    output reg [$clog2(MAX_N/2)-1:0] ram_twid_addr,
    input wire [31:0] ram_twid_rdata,

    output reg done,
    output reg busy
);

    localparam ADDR_W = $clog2(MAX_N);

    // =========================================================================
    // FSM STATE DEFINITIONS
    // =========================================================================

    localparam S_IDLE         = 0;
    localparam S_INIT         = 1;
    localparam S_STAGE_LOOP   = 2;
    localparam S_J_LOOP       = 3;
    localparam S_K_LOOP       = 4;

    localparam S_READ_A       = 5;
    localparam S_WAIT_RD_A    = 6;
    localparam S_CAP_A        = 7;

    localparam S_READ_TW      = 8;
    localparam S_WAIT_TW      = 9;
    localparam S_CAP_TW       = 10;

    localparam S_READ_B       = 11;
    localparam S_WAIT_RD_B    = 12;
    localparam S_CAP_B        = 13;

    localparam S_CALC         = 14;

    localparam S_MUL1_LOAD    = 15;
    localparam S_MUL1_WAIT    = 16;
    localparam S_MUL1_CAP     = 17;

    localparam S_MUL2_LOAD    = 18;
    localparam S_MUL2_WAIT    = 19;
    localparam S_MUL2_CAP     = 20;

    localparam S_MUL3_LOAD    = 21;
    localparam S_MUL3_WAIT    = 22;
    localparam S_MUL3_CAP     = 23;

    localparam S_MUL4_LOAD    = 24;
    localparam S_MUL4_WAIT    = 25;
    localparam S_MUL4_CAP     = 26;

    localparam S_COMBINE      = 27;
    localparam S_WRITE_A      = 28;
    localparam S_WRITE_B      = 29;

    localparam S_NEXT_K       = 30;
    localparam S_NEXT_J       = 31;
    localparam S_NEXT_STAGE   = 32;

    // In-place bit-reversal states.
    localparam S_BR_LOOP          = 33;
    localparam S_BR_WAIT_A        = 34;
    localparam S_BR_CAP_A_REQ_B   = 35;
    localparam S_BR_WAIT_B        = 36;
    localparam S_BR_CAP_B_WR_A    = 37;
    localparam S_BR_WR_B          = 38;

    localparam S_DONE          = 39;

    reg [5:0] state;

    // =========================================================================
    // FFT CONTROL REGISTERS
    // =========================================================================

    reg [15:0] N;
    reg [3:0]  log2N;
    reg [3:0]  stage;

    reg [ADDR_W:0] stride;
    reg [ADDR_W:0] j;
    reg [ADDR_W:0] k;
    reg [ADDR_W:0] max_k;

    reg [ADDR_W-1:0] addr_a;
    reg [ADDR_W-1:0] addr_b;

    // =========================================================================
    // FFT DATAPATH REGISTERS
    // =========================================================================

    reg signed [15:0] Ar;
    reg signed [15:0] Ai;
    reg signed [15:0] Br;
    reg signed [15:0] Bi;

    reg signed [15:0] Wr;
    reg signed [15:0] Wi;

    reg signed [15:0] sum_r;
    reg signed [15:0] sum_i;

    reg signed [15:0] diff_r;
    reg signed [15:0] diff_i;

    reg signed [15:0] mul_a;
    reg signed [15:0] mul_b;

    wire signed [31:0] mul_result;

    reg signed [31:0] mul_reg;

    reg signed [31:0] prod1;
    reg signed [31:0] prod2;
    reg signed [31:0] prod3;
    reg signed [31:0] prod4;

    reg signed [31:0] prod_re;
    reg signed [31:0] prod_im;

    // =========================================================================
    // BIT-REVERSAL DATAPATH
    // =========================================================================

    reg [ADDR_W:0] br_i;

    reg [31:0] reg_br_a;
    reg [31:0] reg_br_b;

    // =========================================================================
    // COMBINATIONAL DATAPATH
    // =========================================================================

    assign mul_result = mul_a * mul_b;

    // Calculate the base address of the current butterfly.
    wire [ADDR_W-1:0] base_addr =
        (k << (log2N - stage)) + j;

    // -------------------------------------------------------------------------
    // Q15 Saturation
    // -------------------------------------------------------------------------
    //
    // Restricts a 32-bit signed value to the signed 16-bit Q15 range.
    //
    function signed [15:0] saturate;
        input signed [31:0] val;

        begin
            if (val > 32'sd32767)
                saturate = 16'sd32767;
            else if (val < -32'sd32768)
                saturate = -16'sd32768;
            else
                saturate = val[15:0];
        end
    endfunction

    // -------------------------------------------------------------------------
    // Full-width Bit Reversal
    // -------------------------------------------------------------------------
    //
    // Reverses all address bits available in the maximum FFT address space.
    // The active FFT length is then accounted for when generating br_rev_i.
    //
    function [ADDR_W-1:0] bit_reverse_full;
        input [ADDR_W-1:0] val;

        integer i;

        begin
            for (i = 0; i < ADDR_W; i = i + 1)
                bit_reverse_full[ADDR_W - 1 - i] = val[i];
        end
    endfunction

    // Generate the active-length bit-reversed address.
    wire [ADDR_W-1:0] br_rev_i =
        bit_reverse_full(br_i[ADDR_W-1:0]) >>
        (ADDR_W - log2N);

    // =========================================================================
    // MULTIPLIER PIPELINE REGISTER
    // =========================================================================

    // The multiplier result is registered to provide a sequential arithmetic
    // datapath that can be reused for all four complex multiplication terms.
    always @(posedge clk) begin
        if (!rstn)
            mul_reg <= 0;
        else
            mul_reg <= mul_result;
    end

    // =========================================================================
    // MAIN FFT CONTROL FSM
    // =========================================================================

    always @(posedge clk) begin
        if (!rstn) begin
            state <= S_IDLE;

            busy <= 1'b0;
            done <= 1'b0;

            ram_data_we   <= 1'b0;
            ram_twid_re   <= 1'b0;

            N       <= 0;
            log2N   <= 0;
            stage   <= 0;

            stride  <= 0;
            j       <= 0;
            k       <= 0;
            max_k   <= 0;

            br_i    <= 0;

            addr_a  <= 0;
            addr_b  <= 0;

            Ar <= 0;
            Ai <= 0;
            Br <= 0;
            Bi <= 0;
            Wr <= 0;
            Wi <= 0;

            sum_r  <= 0;
            sum_i  <= 0;
            diff_r <= 0;
            diff_i <= 0;

            mul_a <= 0;
            mul_b <= 0;

            prod1   <= 0;
            prod2   <= 0;
            prod3   <= 0;
            prod4   <= 0;
            prod_re <= 0;
            prod_im <= 0;

            ram_data_addr  <= 0;
            ram_data_wdata <= 0;
            ram_twid_addr  <= 0;

            reg_br_a <= 0;
            reg_br_b <= 0;

        end else begin

            // Memory control signals are asserted only for one clock cycle.
            ram_data_we <= 1'b0;
            ram_twid_re <= 1'b0;

            case (state)

                // ----------------------------------------------------------------
                // IDLE / START
                // ----------------------------------------------------------------
                S_IDLE: begin
                    done <= 1'b0;

                    if (start) begin
                        N <= fft_n;

                        case (fft_n)
                            16'd256:  log2N <= 8;
                            16'd512:  log2N <= 9;
                            16'd1024: log2N <= 10;
                            16'd2048: log2N <= 11;
                            default:  log2N <= 8;
                        endcase

                        busy  <= 1'b1;
                        state <= S_INIT;
                    end
                end

                // ----------------------------------------------------------------
                // FFT INITIALIZATION
                // ----------------------------------------------------------------
                S_INIT: begin
                    stage  <= 0;
                    stride <= fft_n >> 1;
                    state  <= S_STAGE_LOOP;
                end

                // ----------------------------------------------------------------
                // FFT STAGE ITERATION
                // ----------------------------------------------------------------
                S_STAGE_LOOP: begin
                    if (stage >= log2N) begin
                        br_i  <= 0;
                        state <= S_BR_LOOP;
                    end else begin
                        j     <= 0;
                        max_k <= (1 << stage);
                        state <= S_J_LOOP;
                    end
                end

                // ----------------------------------------------------------------
                // J LOOP
                // ----------------------------------------------------------------
                S_J_LOOP: begin
                    if (j >= stride) begin
                        state <= S_NEXT_STAGE;
                    end else begin
                        k     <= 0;
                        state <= S_K_LOOP;
                    end
                end

                // ----------------------------------------------------------------
                // K LOOP
                // ----------------------------------------------------------------
                S_K_LOOP: begin
                    if (k >= max_k) begin
                        state <= S_NEXT_J;
                    end else begin
                        addr_a <= base_addr;
                        addr_b <= base_addr + stride;
                        state  <= S_READ_A;
                    end
                end

                // ----------------------------------------------------------------
                // READ A
                // ----------------------------------------------------------------
                S_READ_A: begin
                    ram_data_addr <= addr_a;
                    state         <= S_WAIT_RD_A;
                end

                S_WAIT_RD_A: begin
                    state <= S_CAP_A;
                end

                S_CAP_A: begin
                    Ar    <= ram_data_rdata[31:16];
                    Ai    <= ram_data_rdata[15:0];
                    state <= S_READ_TW;
                end

                // ----------------------------------------------------------------
                // READ TWIDDLE FACTOR
                // ----------------------------------------------------------------
                S_READ_TW: begin
                    ram_twid_addr <= j << stage;
                    ram_twid_re   <= 1'b1;
                    state         <= S_WAIT_TW;
                end

                S_WAIT_TW: begin
                    state <= S_CAP_TW;
                end

                S_CAP_TW: begin
                    Wr <= ram_twid_rdata[31:16];

                    // IFFT uses the conjugated twiddle factor.
                    if (mode)
                        Wi <= -ram_twid_rdata[15:0];
                    else
                        Wi <= ram_twid_rdata[15:0];

                    ram_twid_re <= 1'b0;
                    state       <= S_READ_B;
                end

                // ----------------------------------------------------------------
                // READ B
                // ----------------------------------------------------------------
                S_READ_B: begin
                    ram_data_addr <= addr_b;
                    state         <= S_WAIT_RD_B;
                end

                S_WAIT_RD_B: begin
                    state <= S_CAP_B;
                end

                S_CAP_B: begin
                    Br    <= ram_data_rdata[31:16];
                    Bi    <= ram_data_rdata[15:0];
                    state <= S_CALC;
                end

                // ----------------------------------------------------------------
                // BUTTERFLY PRE-CALCULATION
                // ----------------------------------------------------------------
                //
                // The butterfly is scaled by one bit at every stage to control
                // fixed-point growth.
                //
                S_CALC: begin
                    sum_r <=
                        ($signed({Ar[15], Ar}) +
                         $signed({Br[15], Br})) >>> 1;

                    sum_i <=
                        ($signed({Ai[15], Ai}) +
                         $signed({Bi[15], Bi})) >>> 1;

                    diff_r <=
                        ($signed({Ar[15], Ar}) -
                         $signed({Br[15], Br})) >>> 1;

                    diff_i <=
                        ($signed({Ai[15], Ai}) -
                         $signed({Bi[15], Bi})) >>> 1;

                    state <= S_MUL1_LOAD;
                end

                // ----------------------------------------------------------------
                // COMPLEX MULTIPLICATION
                //
                // (diff_r + j*diff_i) * (Wr + j*Wi)
                //
                // Real:
                //   diff_r*Wr - diff_i*Wi
                //
                // Imaginary:
                //   diff_r*Wi + diff_i*Wr
                //
                // Four sequential multiplier operations are used to reduce
                // dedicated multiplier requirements.
                // ----------------------------------------------------------------

                S_MUL1_LOAD: begin
                    mul_a <= diff_r;
                    mul_b <= Wr;
                    state <= S_MUL1_WAIT;
                end

                S_MUL1_WAIT: begin
                    state <= S_MUL1_CAP;
                end

                S_MUL1_CAP: begin
                    prod1 <= mul_reg;
                    state <= S_MUL2_LOAD;
                end

                S_MUL2_LOAD: begin
                    mul_a <= diff_i;
                    mul_b <= Wi;
                    state <= S_MUL2_WAIT;
                end

                S_MUL2_WAIT: begin
                    state <= S_MUL2_CAP;
                end

                S_MUL2_CAP: begin
                    prod2 <= mul_reg;
                    state <= S_MUL3_LOAD;
                end

                S_MUL3_LOAD: begin
                    mul_a <= diff_r;
                    mul_b <= Wi;
                    state <= S_MUL3_WAIT;
                end

                S_MUL3_WAIT: begin
                    state <= S_MUL3_CAP;
                end

                S_MUL3_CAP: begin
                    prod3 <= mul_reg;
                    state <= S_MUL4_LOAD;
                end

                S_MUL4_LOAD: begin
                    mul_a <= diff_i;
                    mul_b <= Wr;
                    state <= S_MUL4_WAIT;
                end

                S_MUL4_WAIT: begin
                    state <= S_MUL4_CAP;
                end

                S_MUL4_CAP: begin
                    prod4 <= mul_reg;
                    state <= S_COMBINE;
                end

                // ----------------------------------------------------------------
                // COMPLEX PRODUCT COMBINATION
                // ----------------------------------------------------------------
                S_COMBINE: begin
                    prod_re <= (prod1 - prod2) >>> 15;
                    prod_im <= (prod3 + prod4) >>> 15;
                    state   <= S_WRITE_A;
                end

                // ----------------------------------------------------------------
                // WRITE BUTTERFLY RESULTS
                // ----------------------------------------------------------------
                S_WRITE_A: begin
                    ram_data_addr  <= addr_a;
                    ram_data_we    <= 1'b1;
                    ram_data_wdata <= {sum_r, sum_i};
                    state          <= S_WRITE_B;
                end

                S_WRITE_B: begin
                    ram_data_addr  <= addr_b;
                    ram_data_we    <= 1'b1;
                    ram_data_wdata <= {
                        saturate(prod_re),
                        saturate(prod_im)
                    };
                    state <= S_NEXT_K;
                end

                // ----------------------------------------------------------------
                // LOOP ADVANCEMENT
                // ----------------------------------------------------------------
                S_NEXT_K: begin
                    k     <= k + 1;
                    state <= S_K_LOOP;
                end

                S_NEXT_J: begin
                    j     <= j + 1;
                    state <= S_J_LOOP;
                end

                S_NEXT_STAGE: begin
                    stage  <= stage + 1;
                    stride <= stride >> 1;
                    state  <= S_STAGE_LOOP;
                end

                // =================================================================
                // IN-PLACE BIT REVERSAL
                // =================================================================
                //
                // Reorders the FFT result into natural output order.
                //
                // A swap is performed only when:
                //
                //     br_i < br_rev_i
                //
                // preventing the same pair from being swapped twice.
                // =================================================================

                S_BR_LOOP: begin
                    if (br_i >= N) begin
                        state <= S_DONE;

                    end else if (br_i < br_rev_i) begin
                        ram_data_addr <= br_i[ADDR_W-1:0];
                        state         <= S_BR_WAIT_A;

                    end else begin
                        br_i <= br_i + 1;
                    end
                end

                // Read sample A.
                S_BR_WAIT_A: begin
                    state <= S_BR_CAP_A_REQ_B;
                end

                // Capture sample A and request sample B.
                S_BR_CAP_A_REQ_B: begin
                    reg_br_a     <= ram_data_rdata;
                    ram_data_addr <= br_rev_i;
                    state        <= S_BR_WAIT_B;
                end

                // Wait for sample B read.
                S_BR_WAIT_B: begin
                    state <= S_BR_CAP_B_WR_A;
                end

                // Capture sample B and write it into address A.
                S_BR_CAP_B_WR_A: begin
                    reg_br_b <= ram_data_rdata;

                    ram_data_addr  <= br_i[ADDR_W-1:0];
                    ram_data_we    <= 1'b1;
                    ram_data_wdata <= ram_data_rdata;

                    state <= S_BR_WR_B;
                end

                // Write sample A into address B and advance the iterator.
                S_BR_WR_B: begin
                    ram_data_addr  <= br_rev_i;
                    ram_data_we    <= 1'b1;
                    ram_data_wdata <= reg_br_a;

                    br_i  <= br_i + 1;
                    state <= S_BR_LOOP;
                end

                // ----------------------------------------------------------------
                // FFT COMPLETE
                // ----------------------------------------------------------------
                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
