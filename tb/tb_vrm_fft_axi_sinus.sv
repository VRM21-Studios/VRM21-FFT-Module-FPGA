`timescale 1ns / 1ps

// ============================================================================
// Testbench   : tb_vrm_fft_axi_sinus
// Description : FFT verification using three sinusoidal input components.
//
// Input Signal:
//   - Sample rate : 48 kHz
//   - FFT size    : 2048 points
//   - Tone 1      : 100 Hz
//   - Tone 2      : 300 Hz
//   - Tone 3      : 500 Hz
//
// Features:
//   - AXI4-Lite control and status access
//   - AXI4-Stream input/output
//   - Windowing enabled
//   - Twiddle-factor loading from a memory initialization file
//   - Robust AXI4-Stream stimulus with backpressure handling
//   - FFT output exported to CSV for external analysis
//
// Output:
//   fft_result.csv
//
// Notes:
//   - Input samples are generated as signed Q1.15-compatible integers.
//   - Complex AXI-Stream data is packed as:
//       [31:16] = Real
//       [15:0]  = Imaginary
//   - The DUT is configured for a 2048-point forward FFT.
// ============================================================================

module tb_vrm_fft_axi_sinus;

    // =========================================================================
    // CLOCK AND RESET
    // =========================================================================

    reg clk = 0;
    reg rstn = 0;

    // =========================================================================
    // AXI4-LITE SLAVE INTERFACE
    // =========================================================================

    reg  [12:0] axi_awaddr;
    reg          axi_awvalid = 0;
    wire         axi_awready;

    reg  [31:0] axi_wdata;
    reg  [3:0]  axi_wstrb = 0;
    reg         axi_wvalid = 0;
    wire         axi_wready;

    wire [1:0]  axi_bresp;
    wire        axi_bvalid;
    reg         axi_bready = 0;

    reg  [12:0] axi_araddr;
    reg          axi_arvalid = 0;
    wire         axi_arready;

    wire [31:0] axi_rdata;
    wire [1:0]  axi_rresp;
    wire        axi_rvalid;
    reg         axi_rready = 0;

    // =========================================================================
    // AXI4-STREAM INPUT INTERFACE
    // =========================================================================

    // Packed complex input sample:
    //   [31:16] = Real
    //   [15:0]  = Imaginary

    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid = 0;
    reg         s_axis_tlast  = 0;
    wire        s_axis_tready;

    // =========================================================================
    // AXI4-STREAM OUTPUT INTERFACE
    // =========================================================================

    // Packed complex output sample:
    //   [31:16] = Real
    //   [15:0]  = Imaginary

    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;
    reg         m_axis_tready = 0;

    // =========================================================================
    // TWIDDLE-FACTOR INITIALIZATION MEMORY
    // =========================================================================

    // Local ROM used to load the DUT twiddle-factor RAM through AXI4-Lite.
    reg [31:0] twiddle_rom [0:1023];

    initial begin
        $readmemh("twiddle_factors.mem", twiddle_rom);
    end

    // =========================================================================
    // DEVICE UNDER TEST
    // =========================================================================

    vrm_fft_iterative_axi #(
        .C_S_AXI_DATA_WIDTH (32),
        .C_S_AXI_ADDR_WIDTH (13),
        .C_AXIS_TDATA_WIDTH (32),
        .FFT_MAX_PTS        (2048)
    ) u_dut (
        .aclk           (clk),
        .aresetn        (rstn),

        // AXI4-Lite write channel
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

        // AXI4-Lite read channel
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
    // CLOCK GENERATION
    // =========================================================================

    // 100 MHz clock.
    always #5 clk = ~clk;

    // =========================================================================
    // AXI4-LITE WRITE TASK
    // =========================================================================
    //
    // Performs a single AXI4-Lite write transaction.
    //
    // The DUT expects the address and write-data channels to be presented
    // together, therefore AWVALID and WVALID are asserted simultaneously.
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
    // AXI4-LITE READ TASK
    // =========================================================================
    //
    // Performs a single AXI4-Lite read transaction and returns the read data.
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
    // AXI4-STREAM INPUT TASK
    // =========================================================================
    //
    // Injects one complex sample into the DUT.
    //
    // The stimulus is changed on the falling clock edge to avoid changing
    // AXI4-Stream signals at the same edge used by the DUT for sampling.
    //
    // The task waits until TREADY is asserted before completing the transfer,
    // allowing the DUT to apply backpressure safely.
    // =========================================================================

    task axis_push_data(
        input signed [15:0] data_real,
        input signed [15:0] data_imag,
        input              is_last
    );
        begin
            @(negedge clk);

            // AXI-Stream packing:
            //   [31:16] = Imaginary
            //   [15:0]  = Real
            s_axis_tdata  <= {data_imag, data_real};
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= is_last;

            @(posedge clk);

            while (s_axis_tready == 1'b0) begin
                @(posedge clk);
            end

            @(negedge clk);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
        end
    endtask

    // =========================================================================
    // SIMULATION VARIABLES
    // =========================================================================

    integer n = 0;
    integer fd = 0;

    reg [31:0] read_val = 0;

    reg signed [31:0] result_re [0:2047];
    reg signed [31:0] result_im [0:2047];

    real    sample_real = 0;
    real    bin_freq    = 0;
    real    FS          = 48000.0;
    integer samp_int;

    // =========================================================================
    // MAIN SIMULATION PROCESS
    // =========================================================================

    initial begin

        // ---------------------------------------------------------------------
        // 1. SYSTEM RESET
        // ---------------------------------------------------------------------

        rstn = 0;

        repeat (5) @(posedge clk);

        rstn = 1;

        repeat (5) @(posedge clk);

        // ---------------------------------------------------------------------
        // 2. LOAD TWIDDLE FACTORS
        // ---------------------------------------------------------------------

        $display("Loading twiddle factors into FFT RAM...");

        for (n = 0; n < 1024; n = n + 1) begin
            axi_write(
                13'h1000 + (n * 4),
                twiddle_rom[n]
            );
        end

        $display("Twiddle factors loaded.");

        // ---------------------------------------------------------------------
        // 3. CONFIGURE FFT
        // ---------------------------------------------------------------------
        //
        // Control register:
        //   [2] = Windowing enable -> 1
        //   [1] = Transform mode   -> 0 (FFT)
        //   [0] = Start            -> 0
        //
        // The FFT operation is automatically started when TLAST is received.
        // ---------------------------------------------------------------------

        $display("Configuring FFT...");

        // Set FFT length to 2048 points.
        axi_write(13'h08, 32'd2048);

        // Enable windowing and select forward FFT mode.
        axi_write(13'h00, 32'd4);

        // ---------------------------------------------------------------------
        // 4. GENERATE AND SEND INPUT SIGNAL
        // ---------------------------------------------------------------------
        //
        // The input consists of three sinusoidal components:
        //
        //   100 Hz
        //   300 Hz
        //   500 Hz
        //
        // Each tone has an amplitude of 10000.
        //
        // The resulting signal is quantized to a signed 16-bit integer before
        // being sent through the AXI4-Stream interface.
        // ---------------------------------------------------------------------

        $display("Sending input samples at Fs = 48 kHz...");

        for (n = 0; n < 2048; n = n + 1) begin

            sample_real =
                  10000.0 * $sin(
                      2.0 * 3.1415926535 * 100.0 *
                      real'(n) / FS
                  )
                + 10000.0 * $sin(
                      2.0 * 3.1415926535 * 300.0 *
                      real'(n) / FS
                  )
                + 10000.0 * $sin(
                      2.0 * 3.1415926535 * 500.0 *
                      real'(n) / FS
                  );

            // Round the generated floating-point sample to an integer.
            samp_int = int'($floor(sample_real + 0.5));

            // Clamp to the signed 16-bit range.
            if (samp_int > 32767)
                samp_int = 32767;

            if (samp_int < -32768)
                samp_int = -32768;

            // Input is real-valued, therefore the imaginary component is zero.
            axis_push_data(
                samp_int[15:0],
                16'd0,
                (n == 2047)
            );
        end

        $display("Input samples sent.");

        // ---------------------------------------------------------------------
        // 5. WAIT FOR FFT COMPLETION
        // ---------------------------------------------------------------------

        $display("Waiting for FFT to complete...");

        axi_read(13'h04, read_val);

        while (read_val[1]) begin
            // Poll the status register periodically while the FFT is busy.
            repeat (100) @(posedge clk);

            axi_read(13'h04, read_val);
        end

        $display("FFT completed.");

        // ---------------------------------------------------------------------
        // 6. CAPTURE FFT OUTPUT
        // ---------------------------------------------------------------------
        //
        // Enable the AXI4-Stream output sink and capture all 2048 complex FFT
        // samples.
        //
        // Output packing:
        //   [31:16] = Real
        //   [15:0]  = Imaginary
        // ---------------------------------------------------------------------

        $display("Capturing FFT output...");

        m_axis_tready <= 1'b1;

        n = 0;

        while (n < 2048) begin
            @(posedge clk);

            if (m_axis_tvalid && m_axis_tready) begin

                // Sign-extend the 16-bit real component to 32 bits.
                result_re[n] = {
                    {16{m_axis_tdata[31]}},
                    m_axis_tdata[31:16]
                };

                // Sign-extend the 16-bit imaginary component to 32 bits.
                result_im[n] = {
                    {16{m_axis_tdata[15]}},
                    m_axis_tdata[15:0]
                };

                n = n + 1;
            end
        end

        m_axis_tready <= 1'b0;

        // ---------------------------------------------------------------------
        // 7. EXPORT RESULTS TO CSV
        // ---------------------------------------------------------------------

        $display("Writing FFT results to CSV...");

        fd = $fopen("fft_result.csv", "w");

        if (!fd) begin
            $display("Error: Unable to open fft_result.csv.");
            $finish;
        end

        $fwrite(fd, "index,freq_hz,real,imag\n");

        for (n = 0; n < 2048; n = n + 1) begin

            // FFT bin frequency:
            //   f_bin = bin_index * Fs / N
            bin_freq = real'(n) * (FS / 2048.0);

            $fwrite(
                fd,
                "%d,%.2f,%d,%d\n",
                n,
                bin_freq,
                result_re[n],
                result_im[n]
            );
        end

        $fclose(fd);

        $display("FFT results written to fft_result.csv.");

        // ---------------------------------------------------------------------
        // 8. END SIMULATION
        // ---------------------------------------------------------------------

        $finish;

    end

endmodule
