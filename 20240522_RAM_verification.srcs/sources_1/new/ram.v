`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/05/22 14:22:44
// Design Name: 
// Module Name: ram
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ram (
    input        clk,
    input  [9:0] address,
    input  [7:0] wdata,
    input        wr_en,
    output [7:0] rdata
);
    reg [7:0] mem[0:2**10-1];  // width:8, depth:1024

    integer i;
    initial begin
        for (i = 0; i < 2 ** 10; i = i + 1) begin 
            mem[i] = 0; // default 0으로 초기화
        end
    end

    always @(posedge clk) begin
        if (!wr_en) begin
            mem[address] <= wdata;
        end
    end

    assign rdata = mem[address];

endmodule
