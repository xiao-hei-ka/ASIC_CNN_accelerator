`timescale 1 ns / 1 ps

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

assign para_addr_final = para_addr[7:0];

always_comb begin//decoder
    for(int i = 0; i<SRAM_CNT; i++)begin
        para_cs_final[i] = ~((para_addr[11: 8] == i) && (para_cs == 1'b0));
    end
end

always_ff @(posedge clk)begin//mux
    for(int i = 0; i<SRAM_CNT; i++)begin
        if(para_addr[11: 8] == i)begin
            para_dout_final <= para_dout[i];
        end
    end
end

generate
    for(genvar i = 0; i<SRAM_CNT; i++)begin:para_sram
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

endmodule