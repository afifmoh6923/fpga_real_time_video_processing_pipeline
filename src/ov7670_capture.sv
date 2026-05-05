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
    logic href_prev; // 1. Track the previous HREF state

    always_ff @(posedge cam_pclk) begin
        vsync_prev <= cam_vsync;
        href_prev  <= cam_href;  // 2. Assign it here
        wr_en      <= 1'b0;

        // 1. Detect New Frame
        if (vsync_prev && !cam_vsync) begin
            col      <= 9'd0;
            row      <= 8'd0;
            byte_sel <= 1'b0;

        // 2. Detect Horizontal Blanking (End of a line)
        end else if (!cam_href) begin
            byte_sel <= 1'b0;
            col <= 9'd0;
            
            // 3. Increment row ONLY on the falling edge of HREF
            if (href_prev && (row < 8'd239)) begin
                row <= row + 1;
            end

        // 3. Process Active Data
        end else begin
            if (!byte_sel) begin
                high_byte <= cam_data;
                byte_sel  <= 1'b1;
            end else begin
                // If colors are still slightly off after fixing COM15, 
                // flip the high_byte and cam_data order here!
                wr_data  <= {cam_data[7:0], high_byte[7:0]};; 
                wr_addr  <= ({9'b0, row} << 8) + ({9'b0, row} << 6) + {8'b0, col};
                wr_en <= (col < 9'd320 && row < 8'd240) ? 1'b1 : 1'b0;
                byte_sel <= 1'b0;

                // 4. Update coordinates (Row logic removed from here)
                if (col < 9'd319) begin
                    col <= col + 1;
                end
            end
        end
    end

endmodule