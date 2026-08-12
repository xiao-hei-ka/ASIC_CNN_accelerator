`timescale 1ns/1ps
module tb_cmd(
input clk,
input rst_n,
input tb_cmd_in_fifo_wr,
input [WIDTH_IN-1 : 0] tb_cmd_in_fifo_din,
output tb_cmd_in_fifo_full,
input tb_cmd_out_fifo_rd,
output [WIDTH_OUT-1 : 0] tb_cmd_fifo_dout,
output tb_cmd_out_fifo_empty
)

enum logic [7:0]{
    TB_CMD_IN_IDLE,
}

always_ff @(posedge clk)begin
if(rst_n == 1'b0)begin
tb_cmd_in_cs <= TB_CMD_IN_IDLE;
end
else begin
tb_cmd_in_cs <= tb_cmd_in_ns
end
end
always_comb begin
tb_cmd_in_ns = tb_cmd_in_cs;