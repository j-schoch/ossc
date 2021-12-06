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


// startup logo image size
parameter IMG_SIZE_X = 10'd57;
parameter IMG_SIZE_Y = 10'd85;

// padding around image (colored procedurally)
// left, right, top, bottom
parameter IMG_PAD_L = 10'd62;
parameter IMG_PAD_R = 10'd61;
parameter IMG_PAD_T = 10'd18;
parameter IMG_PAD_B = 10'd17;

// total size of image + padding (should equal 180x120 to fit 720x480 screen)
parameter IMG_TOTAL_X = IMG_PAD_L + IMG_SIZE_X + IMG_PAD_R;
parameter IMG_TOTAL_Y = IMG_PAD_T + IMG_SIZE_Y + IMG_PAD_B;

// image edge positions for convenience
// left, right, top, bottom
parameter IMG_EDGE_L = IMG_PAD_L;
parameter IMG_EDGE_R = IMG_PAD_L + IMG_SIZE_X;
parameter IMG_EDGE_T = IMG_PAD_T;
parameter IMG_EDGE_B = IMG_PAD_T + IMG_SIZE_Y;

// each pixel cooresponds to an index in binary
parameter IMG_MEM_SIZE = IMG_SIZE_X * IMG_SIZE_Y;
    
// screen position scaled to pixel position (xpos and ypos / 4)
reg [9:0] px; 
reg [9:0] py;

// color index array memory
reg [2:0] colorIndexArray[0:IMG_MEM_SIZE-1];

initial begin
    // read the indices file into memory
    $readmemb("colorIndices.mem", colorIndexArray);
end

//HSYNC gen (negative polarity)
always @(posedge clk27 or negedge reset_n)
begin
    if (!reset_n) begin
        h_cnt <= 0;
        xpos <= 0;
        px <= 0;
        HSYNC_out <= 0;
    end else begin
        //Hsync counter
        if (h_cnt < H_TOTAL-1) begin
            h_cnt <= h_cnt + 1'b1;
            if (h_cnt >= X_START) begin
                xpos <= xpos + 1'b1;
                px <= (xpos>>2);
            end
        end else begin
            h_cnt <= 0;
            xpos <= 0;
            px <= 0;
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
        py <= 0;
        VSYNC_out <= 0;
    end else begin
        //Vsync counter
        if (h_cnt == H_TOTAL-1) begin
            if (v_cnt < V_TOTAL-1) begin
                v_cnt <= v_cnt + 1'b1;
                if (v_cnt >= Y_START) begin
                    ypos <= ypos + 1'b1;
                    py <= (ypos>>2);
                end
            end else begin
                v_cnt <= 0;
                ypos <= 0;
                py <= 0;
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
            // outside the image edge
            if((px < IMG_EDGE_L) || (px >= IMG_EDGE_R) || (py < IMG_EDGE_T) || (py >= IMG_EDGE_B)) begin
                // add solid color
                {R_out, G_out, B_out} <= {3{8'h00}};
            end else begin
                // inside the image edge
                // using pixel position px and py (offset for padding)
                // sample an index from the array
                case (colorIndexArray[(py - IMG_PAD_T) * IMG_SIZE_X + (px - IMG_PAD_L)])
                    3'b000 : begin
                        {R_out, G_out, B_out} <= {3{8'h00}};
                    end
                    3'b001 : begin
                        {R_out, G_out, B_out} <= {3{8'hff}};
                    end
                    3'b010 : begin
                        {R_out, G_out, B_out} <= {3{8'he8}};
                    end
                    3'b011 : begin
                        {R_out, G_out, B_out} <= {{8'hf0},{8'h54},{8'h57}};
                    end
                    3'b100 : begin
                        {R_out, G_out, B_out} <= {{8'hed},{8'h20},{8'h24}};
                    end
                    3'b101 : begin
                        {R_out, G_out, B_out} <= {{8'hca},{8'h02},{8'h06}};
                    end
                    default : begin
                        {R_out, G_out, B_out} <= {3{8'h00}};
                    end
                endcase
            end
        end
        DE_out <= (h_cnt >= X_START && h_cnt < X_START + H_ACTIVE && v_cnt >= Y_START && v_cnt < Y_START + V_ACTIVE);
    end
end

endmodule : videogen
