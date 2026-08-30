`timescale 1 ns / 1 ps
`include "def_file.vh"

module para_sram
(
    input   logic           clk             ,
    input   logic           para_cs         ,// 低有效片选
    input   logic           para_wr         ,// 低有效写使能
    input   logic [ 11:0]   para_addr       ,// 地址
    input   logic [127:0]   para_din        ,// 数据输入
    output  logic [127:0]   para_dout_final  // 最终数据输出
);

localparam SRAM_CNT = 13;

logic [127:0] para_dout [0:SRAM_CNT-1];// 输出数据
logic [SRAM_CNT-1 : 0] spare_q;//冗余列输出，不接逻辑，单纯放在这防止综合器错误优化sram仿真模型
logic [SRAM_CNT-1 : 0] para_cs_final;//最终落实到单片SRAM的片选
logic [7 : 0] para_addr_final;//最终落实到单片SRAM的ADDR
logic [3 : 0] para_dout_bank;//与SRAM读时与读出数据过程并肩前行的片选信号，以此保证即使在数据输出的时候下一拍数据已经进入并且是写入其他SRAM片，本输出也能按照正确的SRAM输出。

assign para_addr_final = para_addr[7:0];

always_comb begin//decoder
    for(int i = 0; i<SRAM_CNT; i++)begin
        para_cs_final[i] = ~((para_addr[11: 8] == i) && (para_cs == 1'b0));
    end
end

always_ff @(posedge clk)begin//mux
    if(para_cs == 1'b0 && para_wr == 1'b1)begin
        para_dout_bank <= para_addr[11:8];
    end
    for(int unsigned i = 0; i<SRAM_CNT; i++)begin
        if(para_dout_bank == 4'(i))begin
            para_dout_final <= para_dout[i];
        end
    end
end

generate
    for(genvar i = 0; i<SRAM_CNT; i++)begin:para_sram_unit
        sram_1rw_256x128 para (
            .clk0      (clk),
            .csb0      (para_cs_final[i]),
            .web0      (para_wr),
            .spare_wen0(1'b0),
            .addr0     ({1'b0,para_addr_final}),
            .din0      ({1'b0, para_din}),
            .dout0     ({spare_q[i], para_dout[i]})
        );
    end
endgenerate

`ifdef SIMULATION
    logic [127:0] virtual_para_sram [0:256*SRAM_CNT-1];
    generate
        for(genvar i = 0; i<SRAM_CNT; i++)begin
            for(genvar j = 0; j<256; j++)begin
                assign virtual_para_sram[i*256 + j] = para_sram_unit[i].para.mem[j][127:0];
            end
        end
    endgenerate
`endif

endmodule