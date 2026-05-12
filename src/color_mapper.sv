
module color_mapper (
    input  logic [23:0] filtered_rgb,   
    input  logic        pixel_valid,    

    output logic [3:0]  red,
    output logic [3:0]  green,
    output logic [3:0]  blue,
    output logic        vde          
);
    assign vde   = pixel_valid;
    assign red   = pixel_valid ? filtered_rgb[23:20] : 4'h0;
    assign green = pixel_valid ? filtered_rgb[15:12] : 4'h0;
    assign blue  = pixel_valid ? filtered_rgb[7:4]   : 4'h0;

endmodule
