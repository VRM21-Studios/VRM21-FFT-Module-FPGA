`timescale 1ns / 1ps

// ============================================================================
// Testbench   : tb_vrm_ifft_axi_impulse
// Description : AXI4-Lite / AXI4-Stream IFFT Verification Testbench
//
// Verifies the IFFT path of vrm_fft_iterative_axi using a sparse frequency-
// domain stimulus. Two symmetric frequency bins are populated to generate
// a real-valued cosine waveform after the inverse transform.
//
// Test configuration:
//   - FFT size       : 2048 points
//   - Transform mode: IFFT
//   - Windowing      : Disabled
//   - Input domain   : Frequency domain
//   - Output domain  : Time domain
//   - Active bins    : 10 and 2038
//   - Input amplitude: 16000 (Q1.15)
//
// Verification flow:
//   1. Load the twiddle-factor table into the DUT through AXI4-Lite.
//   2. Configure the DUT for a 2048-point IFFT with windowing disabled.
//   3. Inject the frequency-domain stimulus through AXI4-Stream.
//   4. Wait for the IFFT engine to complete.
//   5. Capture the resulting time-domain samples.
//   6. Apply output scaling compensation.
//   7. Export the captured waveform to a CSV file.
//
// Notes:
//   - The twiddle-factor memory image must be available in the simulator's
//     working directory.
//   - The testbench uses a 100 MHz clock.
//   - Output samples are sign-extended from Q1.15 before scaling.
//   - The additional left shift compensates for the internal 1/N scaling
//     associated with the iterative IFFT implementation.
//
// Author      : VRM21-Studios
// License     : MIT
// ============================================================================

module tb_vrm_ifft_axi_impulse;

    // =========================================================================
    // 1. CLOCK AND RESET
    // =========================================================================

    reg clk  = 1'b0;
    reg rstn = 1'b0;

    // =========================================================================
    // 2. AXI4-LITE SIGNALS
    // =========================================================================

    reg  [12:0] axi_awaddr;
    reg          axi_awvalid = 1'b0;
    wire         axi_awready;

    reg  [31:0] axi_wdata;
    reg  [3:0]  axi_wstrb = 4'b0;
    reg         axi_wvalid = 1'b0;
    wire        axi_wready;

    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    reg         axi_bready = 1'b0;

    reg  [12:0] axi_araddr;
    reg          axi_arvalid = 1'b0;
    wire         axi_arready;

    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    reg         axi_rready = 1'b0;

    // =========================================================================
    // 3. AXI4-STREAM INPUT
    // =========================================================================
    //
    // The input stream represents frequency-domain complex samples.
    //
    // Data packing:
    //   [31:16] = Imaginary component
    //   [15:0]  = Real component
    // =========================================================================

    reg  [31:0] s_axis_tdata;
    reg          s_axis_tvalid = 1'b0;
    reg          s_axis_tlast  = 1'b0;
    wire         s_axis_tready;

    // =========================================================================
    // 4. AXI4-STREAM OUTPUT
    // =========================================================================
    //
    // The output stream contains time-domain complex samples.
    //
    // Data packing:
    //   [31:16] = Imaginary component
    //   [15:0]  = Real component
    // =========================================================================

    wire [31:0] m_axis_tdata;
    wire         m_axis_tvalid;
    wire         m_axis_tlast;
    reg          m_axis_tready = 1'b0;

    // =========================================================================
    // 5. TWIDDLE-FACTOR MEMORY IMAGE
    // =========================================================================
    //
    // The twiddle-factor table is loaded from the same memory image used by
    // the FFT design and subsequently written into the DUT's twiddle RAM
    // through the AXI4-Lite interface.
    // =========================================================================

    reg [31:0] twiddle_rom [0:1023];

    initial begin
        $readmemh("twiddle_factors.mem", twiddle_rom);
    end

    // =========================================================================
    // 6. DEVICE UNDER TEST
    // =========================================================================

    vrm_fft_iterative_axi #(
        .C_S_AXI_DATA_WIDTH(32),
        .C_S_AXI_ADDR_WIDTH(13),
        .C_AXIS_TDATA_WIDTH(32),
        .FFT_MAX_PTS(2048)
    ) u_dut (
        .aclk            (clk),
        .aresetn         (rstn),

        // AXI4-Lite
        .s_axi_awaddr   (axi_awaddr),
        .s_axi_awvalid  (axi_awvalid),
        .s_axi_awready  (axi_awready),

        .s_axi_wdata    (axi_wdata),
        .s_axi_wstrb    (axi_wstrb),
        .s_axi_wvalid   (axi_wvalid),
        .s_axi_wready   (axi_wready),

        .s_axi_bresp    (axi_bresp),
        .s_axi_bvalid   (axi_bvalid),
        .s_axi_bready   (axi_bready),

        .s_axi_araddr   (axi_araddr),
        .s_axi_arvalid  (axi_arvalid),
        .s_axi_arready  (axi_arready),

        .s_axi_rdata    (axi_rdata),
        .s_axi_rresp    (axi_rresp),
        .s_axi_rvalid   (axi_rvalid),
        .s_axi_rready   (axi_rready),

        // AXI4-Stream input
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tlast   (s_axis_tlast),
        .s_axis_tready  (s_axis_tready),

        // AXI4-Stream output
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tlast   (m_axis_tlast),
        .m_axis_tready  (m_axis_tready)
    );

    // =========================================================================
    // 7. CLOCK GENERATION
    // =========================================================================
    //
    // 100 MHz clock:
    //   Period = 10 ns
    // =========================================================================

    always #5 clk = ~clk;

    // =========================================================================
    // 8. AXI4-LITE WRITE TASK
    // =========================================================================
    //
    // Performs a single AXI4-Lite write transaction.
    // The testbench presents the address and data together and waits for the
    // write response before returning.
    // =========================================================================

    task axi_write(
        input [12:0] addr,
        input [31:0] data
    );
        begin
            @(posedge clk);

            axi_awaddr  <= addr;
            axi_awvalid <= 1'b1;

            axi_wdata   <= data;
            axi_wvalid  <= 1'b1;
            axi_wstrb   <= 4'hF;

            axi_bready  <= 1'b1;

            wait (axi_awready && axi_wready);

            @(posedge clk);

            wait (axi_bvalid);

            axi_awvalid <= 1'b0;
            axi_wvalid  <= 1'b0;
            axi_bready  <= 1'b0;

            @(posedge clk);
        end
    endtask

    // =========================================================================
    // 9. AXI4-LITE READ TASK
    // =========================================================================
    //
    // Performs a single AXI4-Lite read transaction and returns the received
    // data through the task output argument.
    // =========================================================================

    task axi_read(
        input  [12:0] addr,
        output [31:0] data
    );
        begin
            @(posedge clk);

            axi_araddr  <= addr;
            axi_arvalid <= 1'b1;
            axi_rready  <= 1'b1;

            wait (axi_arready);

            @(posedge clk);

            wait (axi_rvalid);

            data = axi_rdata;

            axi_arvalid <= 1'b0;
            axi_rready  <= 1'b0;

            @(posedge clk);
        end
    endtask

    // =========================================================================
    // 10. AXI4-STREAM INPUT TASK
    // =========================================================================
    //
    // Injects one complex sample into the DUT.
    //
    // The stimulus is updated on the falling edge of the clock to avoid
    // changing AXI signals at the active sampling edge.
    //
    // Arguments:
    //   data_real : Real component
    //   data_imag : Imaginary component
    //   is_last   : TLAST indicator
    // =========================================================================

    task axis_push_data(
        input signed [15:0] data_real,
        input signed [15:0] data_imag,
        input               is_last
    );
        begin
            @(negedge clk);

            // Pack the complex sample:
            //   [31:16] = Imaginary
            //   [15:0]  = Real
            s_axis_tdata  <= {data_imag, data_real};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= is_last;

            @(posedge clk);

            // Hold the transaction until the DUT accepts the sample.
            while (s_axis_tready == 1'b0) begin
                @(posedge clk);
            end

            @(negedge clk);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
        end
    endtask

    // =========================================================================
    // 11. SIMULATION VARIABLES
    // =========================================================================

    integer n  = 0;
    integer fd = 0;

    reg [31:0] read_val = 32'h0;

    // Captured output samples after sign extension and scaling compensation.
    reg signed [31:0] result_re [0:2047];
    reg signed [31:0] result_im [0:2047];

    // =========================================================================
    // 12. MAIN TEST SEQUENCE
    // =========================================================================

    initial begin

        // ---------------------------------------------------------------------
        // Reset DUT
        // ---------------------------------------------------------------------

        rstn = 1'b0;

        repeat (5) @(posedge clk);

        rstn = 1'b1;

        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------------
        // Step 1: Load twiddle factors
        // ---------------------------------------------------------------------

        $display("Loading twiddle factors into DUT via AXI4-Lite...");

        for (n = 0; n < 1024; n = n + 1) begin
            axi_write(
                13'h1000 + (n * 4),
                twiddle_rom[n]
            );
        end

        // ---------------------------------------------------------------------
        // Step 2: Configure IFFT
        // ---------------------------------------------------------------------
        //
        // Register 0x08:
        //   FFT length = 2048
        //
        // Register 0x00:
        //   Bit [2] = 0 -> Windowing disabled
        //   Bit [1] = 1 -> IFFT mode
        //   Bit [0] = 0 -> Start disabled
        // ---------------------------------------------------------------------

        $display("Configuring DUT for 2048-point IFFT mode...");

        axi_write(13'h08, 32'd2048);
        axi_write(13'h00, 32'd2);

        // ---------------------------------------------------------------------
        // Step 3: Inject frequency-domain stimulus
        // ---------------------------------------------------------------------
        //
        // Populate bins 10 and 2038 with equal real-valued amplitudes.
        // These bins form a conjugate-symmetric pair, producing a real-valued
        // cosine waveform in the time domain.
        // ---------------------------------------------------------------------

        $display("Injecting frequency-domain stimulus...");

        for (n = 0; n < 2048; n = n + 1) begin

            if (n == 10 || n == 2038) begin

                // Frequency bins 10 and 2038:
                //   Real      = 16000
                //   Imaginary = 0
                //
                // The pair is conjugate symmetric.
                axis_push_data(
                    16'sd16000,
                    16'sd0,
                    (n == 2047)
                );

            end else begin

                // All remaining frequency bins are zero.
                axis_push_data(
                    16'sd0,
                    16'sd0,
                    (n == 2047)
                );

            end
        end

        $display("Frequency-domain stimulus transmitted.");

        // ---------------------------------------------------------------------
        // Step 4: Wait for IFFT completion
        // ---------------------------------------------------------------------

        $display("Waiting for IFFT engine to complete...");

        axi_read(13'h04, read_val);

        while (read_val[1]) begin
            repeat (100) @(posedge clk);
            axi_read(13'h04, read_val);
        end

        $display("IFFT operation completed.");

        // ---------------------------------------------------------------------
        // Step 5: Capture time-domain output
        // ---------------------------------------------------------------------

        $display("Capturing time-domain output samples...");

        m_axis_tready <= 1'b1;

        n = 0;

        while (n < 2048) begin
            @(posedge clk);

            if (m_axis_tvalid && m_axis_tready) begin

                // Sign-extend the Q1.15 real component to 32 bits and apply
                // the scaling compensation used by this verification.
                result_re[n] =
                    { {16{m_axis_tdata[15]}}, m_axis_tdata[15:0] } <<< 10;

                // Sign-extend the Q1.15 imaginary component to 32 bits and
                // apply the same scaling compensation.
                result_im[n] =
                    { {16{m_axis_tdata[31]}}, m_axis_tdata[31:16] } <<< 10;

                n = n + 1;
            end
        end

        m_axis_tready <= 1'b0;

        // ---------------------------------------------------------------------
        // Step 6: Export captured samples
        // ---------------------------------------------------------------------

        $display("Writing IFFT results to CSV...");

        fd = $fopen("ifft_result.csv", "w");

        if (!fd) begin
            $display("Error: Unable to open ifft_result.csv.");
            $finish;
        end

        $fwrite(fd, "sample_n,real,imag\n");

        for (n = 0; n < 2048; n = n + 1) begin
            $fwrite(
                fd,
                "%d,%d,%d\n",
                n,
                result_re[n],
                result_im[n]
            );
        end

        $fclose(fd);

        $display("IFFT results written to ifft_result.csv.");

        $finish;
    end

endmodule
