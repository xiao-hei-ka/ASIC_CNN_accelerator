`timescale 1 ns / 1 ps

module ping_sram
(
    input   logic           clk             ,
    input   logic           ping_cs         ,// 低有效片选
    input   logic           ping_wr         ,// 低有效写使能
    input   logic [ 11:0]   ping_addr       ,// 地址
    input   logic [127:0]   ping_din        ,// 数据输入
    output  logic [127:0]   ping_dout_final  // 最终数据输出
);

localparam SRAM_CNT = 16;

logic [127:0] ping_dout [0:SRAM_CNT-1];// 输出数据
logic [SRAM_CNT-1 : 0] spare_q;//冗余列输出，不接逻辑，单纯放在这防止综合器错误优化sram仿真模型
logic [SRAM_CNT-1 : 0] ping_cs_final;//最终落实到单片SRAM的片选
logic [7 : 0] ping_addr_final;//最终落实到单片SRAM的ADDR
logic [3 : 0] ping_dout_bank;//与SRAM读时与读出数据过程并肩前行的片选信号，以此保证即使在数据输出的时候下一拍数据已经进入并且是写入其他SRAM片，本输出也能按照正确的SRAM输出。

assign ping_addr_final = ping_addr[7:0];

always_comb begin//decoder
    for(int i = 0; i<SRAM_CNT; i++)begin
        ping_cs_final[i] = ~((ping_addr[11: 8] == i) && (ping_cs == 1'b0));
    end
end

always_ff @(posedge clk)begin//mux
    if(ping_cs == 1'b0 && ping_wr == 1'b1)begin
        ping_dout_bank <= ping_addr[11:8];
    end
    for(int unsigned i = 0; i<SRAM_CNT; i++)begin
        if(ping_dout_bank == 4'(i))begin
            ping_dout_final <= ping_dout[i];
        end
    end
end

generate
    for(genvar i = 0; i<SRAM_CNT; i++)begin:ping_sram_unit
        sram_1rw_256x128 ping (
            .clk0      (clk),
            .csb0      (ping_cs_final[i]),
            .web0      (ping_wr),
            .spare_wen0(1'b0),
            .addr0     ({1'b0,ping_addr_final}),
            .din0      ({1'b0, ping_din}),
            .dout0     ({spare_q[i], ping_dout[i]})
        );
    end
endgenerate

`ifdef SIMULATION
    logic [127:0] virtual_ping_sram [0:256*SRAM_CNT-1];
    generate
        for(genvar i = 0; i<SRAM_CNT; i++)begin
            for(genvar j = 0; j<256; j++)begin
                assign virtual_ping_sram[i*256 + j] = ping_sram_unit[i].ping.mem[j][127:0];
            end
        end
    endgenerate
`endif

endmodule