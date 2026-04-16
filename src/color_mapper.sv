///////////////////////////////////////////////////////////////////////////////
// color_mapper.sv
// ECE 385 Final Project – Real-Time FPGA Video Processing Pipeline
//
// COLOR MAPPER
// ─────────────────────────────────────────────────────────────────────────────
// Converts the 24-bit RGB888 pixel from the filter/overlay pipeline to the
// 4-bit-per-channel format expected by the Real Digital VGA→HDMI IP
// (hdmi_tx_0, configured with Blue/Green/Red Channel Data Width = 4).
//
// During active video (pixel_valid = 1):
//   red   = filtered_rgb[23:20]   (upper 4 bits of R)
//   green = filtered_rgb[15:12]   (upper 4 bits of G)
//   blue  = filtered_rgb[7:4]     (upper 4 bits of B)
//
// During blanking (pixel_valid = 0):
//   All channels output 4'h0 (black).
//
// vde (Video Data Enable):
//   Drives the HDMI IP's vde input.  Must be aligned with the pixel data.
//   Connect directly to pixel_valid.
//
// This module is purely combinational (no registered outputs).
// The HDMI IP internally registers its inputs, so no additional
// pipeline registers are required here.
//
// NOTE: If you upgrade to the 8-bit-per-channel version of the HDMI IP,
// change output widths to [7:0] and pass filtered_rgb[23:16], [15:8], [7:0]
// directly.
///////////////////////////////////////////////////////////////////////////////

module color_mapper (
    input  logic [23:0] filtered_rgb,   // {R[7:0], G[7:0], B[7:0]} from text_overlay
    input  logic        pixel_valid,    // HIGH = active video; drives vde

    output logic [3:0]  red,
    output logic [3:0]  green,
    output logic [3:0]  blue,
    output logic        vde             // Video Data Enable for HDMI IP
);

    // =========================================================================
    // PSEUDO-CODE:
    //
    // if (pixel_valid):
    //   red   = filtered_rgb[23:20]   // R[7:4]
    //   green = filtered_rgb[15:12]   // G[7:4]
    //   blue  = filtered_rgb[7:4]     // B[7:4]
    // else:
    //   red   = 4'h0
    //   green = 4'h0
    //   blue  = 4'h0
    //
    // vde = pixel_valid
    // =========================================================================

    assign vde   = pixel_valid;

    assign red   = pixel_valid ? filtered_rgb[23:20] : 4'h0;
    assign green = pixel_valid ? filtered_rgb[15:12] : 4'h0;
    assign blue  = pixel_valid ? filtered_rgb[7:4]   : 4'h0;

endmodule
