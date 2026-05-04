///////////////////////////////////////////////////////////////////////////////
// ov7670_capture.sv
// ECE 385 Final Project - Real-Time FPGA Video Processing Pipeline
///////////////////////////////////////////////////////////////////////////////

module ov7670_capture (
    input  logic        cam_pclk,
    input  logic        cam_vsync,
    input  logic        cam_href,
    input  logic [7:0]  cam_data,

    output logic [16:0] wr_addr,
    output logic [15:0] wr_data,
    output logic        wr_en
);

    logic [15:0] high_byte;
    logic        byte_sel;
    logic [8:0]  col;
    logic [7:0]  row;
    logic        vsync_prev;

    always_ff @(posedge cam_pclk) begin
        vsync_prev <= cam_vsync;
        wr_en      <= 1'b0;         // Default: don't write to memory

        // 1. Detect New Frame (Falling edge of VSYNC)
        if (vsync_prev && !cam_vsync) begin
            col      <= 9'd0;
            row      <= 8'd0;
            byte_sel <= 1'b0;

        // 2. Detect Horizontal Blanking (End of a line)
        // Resetting byte_sel here ensures we always start the next line on Byte 0.
        end else if (!cam_href) begin
            byte_sel <= 1'b0;
            col <= 9'd0;

        // 3. Process Active Data
        end else begin
            if (!byte_sel) begin
                // Capture first byte {R[4:0], G[5:3]}
                high_byte <= cam_data;
                byte_sel  <= 1'b1;
            end else begin
                // Capture second byte {G[2:0], B[4:0]} and assemble pixel
                wr_data  <= {high_byte[7:0], cam_data[7:0]};
               
                // Calculate address: row * 320 + col
                wr_addr  <= ({9'b0, row} << 8) + ({9'b0, row} << 6) + {8'b0, col};
                wr_en    <= 1'b1;
                byte_sel <= 1'b0;

                // Update coordinates for 320x240 (QVGA)
                if (col == 9'd319) begin
                    col <= 9'd0;
                    if (row < 8'd239)
                        row <= row + 1;
                end else begin
                    col <= col + 1;
                end
            end
        end
    end

endmodule