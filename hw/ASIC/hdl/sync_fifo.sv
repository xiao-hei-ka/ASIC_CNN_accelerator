module sync_fifo #(
    parameter WIDTH = 18,
    parameter DEPTH = 4,
    parameter RST_MODE = "sync"
)(
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout,
    output logic full,
    output logic empty
);

localparam ADDR_W = $clog2(DEPTH);
localparam IF_SYNC = (RST_MODE == "sync");

logic [WIDTH-1:0] mem [0:DEPTH-1];
logic [ADDR_W:0] wr_ptr, rd_ptr;

assign full = ((wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]) && (wr_ptr[ADDR_W] != rd_ptr[ADDR_W]));
assign empty= ((wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]) && (wr_ptr[ADDR_W] == rd_ptr[ADDR_W]));

generate
    if(IF_SYNC == 1'b1) begin:sync_rst
        always_ff @(posedge clk) begin
            if(rst_n == 1'b0) begin
                dout <= '0;
                wr_ptr<= '0;
                rd_ptr<= '0;
            end
            else begin
                if(wr_en == 1'b1 && full != 1'b1) begin
                    mem[wr_ptr[ADDR_W-1 : 0]] <= din;
                    wr_ptr <= wr_ptr + (ADDR_W+1)'(1);
                end
                if(rd_en == 1'b1 && empty != 1'b1) begin
                    dout <= mem[rd_ptr[ADDR_W-1 : 0]];
                    rd_ptr <= rd_ptr + (ADDR_W+1)'(1);
                end
            end
        end
    end
    else begin:async_rst
        logic rst_n_sync1;
        logic rst_n_sync2;
        always_ff @(posedge clk or negedge rst_n) begin
            if(rst_n == 1'b0) begin
                rst_n_sync1 <= '0;
                rst_n_sync2 <= '0;
            end
            else begin
                rst_n_sync1 <= 1'b1;
                rst_n_sync2 <= rst_n_sync1;
            end
        end
        always_ff @(posedge clk or negedge rst_n_sync2) begin
            if(rst_n_sync2 == 1'b0) begin
                dout <= '0;
                wr_ptr<= '0;
                rd_ptr<= '0;
            end
            else begin
                if(wr_en == 1'b1 && full != 1'b1) begin
                    mem[wr_ptr[ADDR_W-1 : 0]] <= din;
                    wr_ptr <= wr_ptr + (ADDR_W+1)'(1);
                end
                if(rd_en == 1'b1 && empty != 1'b1) begin
                    dout <= mem[rd_ptr[ADDR_W-1 : 0]];
                    rd_ptr <= rd_ptr + (ADDR_W+1)'(1);
                end
            end
        end
    end
endgenerate

endmodule
