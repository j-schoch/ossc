//
// Copyright (C) 2015-2017  Markus Hiienkari <mhiienka@niksula.hut.fi>
//
// This file is part of Open Source Scan Converter project.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

`include "lat_tester_includes.v"

module videogen (
    input clk27,
    input reset_n,
    input lt_active,
    input [1:0] lt_mode,
    output reg [7:0] R_out,
    output reg [7:0] G_out,
    output reg [7:0] B_out,
    output reg HSYNC_out,
    output reg VSYNC_out,
    output reg DE_out,
    output reg [9:0] xpos,
    output reg [9:0] ypos
);

//Parameters for 720x480@59.94Hz (858px x 525lines, pclk 27MHz -> 59.94Hz)
parameter   H_SYNCLEN       =   10'd62;
parameter   H_BACKPORCH     =   10'd60;
parameter   H_ACTIVE        =   10'd720;
parameter   H_FRONTPORCH    =   10'd16;
parameter   H_TOTAL         =   10'd858;

parameter   V_SYNCLEN       =   10'd6;
parameter   V_BACKPORCH     =   10'd30;
parameter   V_ACTIVE        =   10'd480;
parameter   V_FRONTPORCH    =   10'd9;
parameter   V_TOTAL         =   10'd525;

parameter   X_START     =   H_SYNCLEN + H_BACKPORCH;
parameter   Y_START     =   V_SYNCLEN + V_BACKPORCH;

//Counters
reg [9:0] h_cnt; //max. 1024
reg [9:0] v_cnt; //max. 1024

// Default image dimensions in pixels
parameter IMAGE_SIZE_X = 10'd180;
parameter IMAGE_SIZE_Y = 10'd120;

// Assumes 24bit color - each pixel requires 3 bytes (RGB 8 bits each, no alpha)
parameter IMAGE_MEMORY_SIZE = IMAGE_SIZE_X * IMAGE_SIZE_Y * 3;

// Hex array image memory declaration
reg [7:0] imageHexArray24bit[0:IMAGE_MEMORY_SIZE-1];

initial begin
    // read the image file into memory (file is a 24bit image converted to hex array)
    $readmemh("startup_image_180x120.hex", imageHexArray24bit);
end

//HSYNC gen (negative polarity)
always @(posedge clk27 or negedge reset_n)
begin
    if (!reset_n) begin
        h_cnt <= 0;
        xpos <= 0;
        HSYNC_out <= 0;
    end else begin
        //Hsync counter
        if (h_cnt < H_TOTAL-1) begin
            h_cnt <= h_cnt + 1'b1;
            if (h_cnt >= X_START)
                xpos <= xpos + 1'b1;
        end else begin
            h_cnt <= 0;
            xpos <= 0;
        end

        //Hsync signal
        HSYNC_out <= (h_cnt < H_SYNCLEN) ? 1'b0 : 1'b1;
    end
end

//VSYNC gen (negative polarity)
always @(posedge clk27 or negedge reset_n)
begin
    if (!reset_n) begin
        v_cnt <= 0;
        ypos <= 0;
        VSYNC_out <= 0;
    end else begin
        //Vsync counter
        if (h_cnt == H_TOTAL-1) begin
            if (v_cnt < V_TOTAL-1) begin
                v_cnt <= v_cnt + 1'b1;
                if (v_cnt >= Y_START)
                    ypos <= ypos + 1'b1;
            end else begin
                v_cnt <= 0;
                ypos <= 0;
            end
        end

        //Vsync signal
        VSYNC_out <= (v_cnt < V_SYNCLEN) ? 1'b0 : 1'b1;
    end
end

//Data and ENABLE gen
always @(posedge clk27 or negedge reset_n)
begin
    if (!reset_n) begin
        R_out <= 8'h00;
        G_out <= 8'h00;
        B_out <= 8'h00;
        DE_out <= 1'b0;
    end else begin
        if (lt_active) begin
            case (lt_mode)
                default: begin
                    {R_out, G_out, B_out} <= {3{8'h00}};
                end
                `LT_POS_TOPLEFT: begin
                    {R_out, G_out, B_out} <= {3{((xpos < (H_ACTIVE/`LT_WIDTH_DIV)) && (ypos < (V_ACTIVE/`LT_HEIGHT_DIV))) ? 8'hff : 8'h00}};
                end
                `LT_POS_CENTER: begin
                    {R_out, G_out, B_out} <= {3{((xpos >= ((H_ACTIVE/2)-(H_ACTIVE/(`LT_WIDTH_DIV*2)))) && (xpos < ((H_ACTIVE/2)+(H_ACTIVE/(`LT_WIDTH_DIV*2)))) && (ypos >= ((V_ACTIVE/2)-(V_ACTIVE/(`LT_HEIGHT_DIV*2)))) && (ypos < ((V_ACTIVE/2)+(V_ACTIVE/(`LT_HEIGHT_DIV*2))))) ? 8'hff : 8'h00}};
                end
                `LT_POS_BOTTOMRIGHT: begin
                    {R_out, G_out, B_out} <= {3{((xpos >= (H_ACTIVE-(H_ACTIVE/`LT_WIDTH_DIV))) && (ypos >= (V_ACTIVE-(V_ACTIVE/`LT_HEIGHT_DIV)))) ? 8'hff : 8'h00}};
                end
            endcase
        end else begin
            // Sample RGB values from the hex array based on current position.
            // xpos and ypos divided by 4 to scale from 720x480 to 180x120.
            // If I were more confident in verilog syntax I would make the code more readable.
            // This formula:
            // 1. Take input between (0,0) and (719,479), and divide by 4 to remap to the image size
            // 2. Multiply by 3 because each pixel has 3 array entries (RGB)
            // 3. Multiply Y by the image width to convert the 2D coordinate into the 1D array index
            // 4. Add an offset of 1 and 2 to get the G and B components
            R_out <= imageHexArray24bit[((ypos>>2) * 3 * IMAGE_SIZE_X) + ((xpos>>2) * 3) + 0];
            G_out <= imageHexArray24bit[((ypos>>2) * 3 * IMAGE_SIZE_X) + ((xpos>>2) * 3) + 1];
            B_out <= imageHexArray24bit[((ypos>>2) * 3 * IMAGE_SIZE_X) + ((xpos>>2) * 3) + 2];
        end
        DE_out <= (h_cnt >= X_START && h_cnt < X_START + H_ACTIVE && v_cnt >= Y_START && v_cnt < Y_START + V_ACTIVE);
    end
end

endmodule
