`timescale 1ns / 1ps
module axi4_frame_parser#
(
    //axi4-lite
	parameter integer DATA_WIDTH    = 32,
	parameter integer REG_COUNT    = 5,
	parameter integer ADDR_WIDTH = ($clog2((DATA_WIDTH/8) * REG_COUNT) < 1) ? 1 : $clog2((DATA_WIDTH/8) * REG_COUNT)
)
(
    input   logic                               clk                             ,
    input   logic                               rst_n                           ,
    input   logic   [REG_COUNT-1 : 0]           ctrl_w_core                     ,
    input   logic   [DATA_WIDTH-1 : 0]          data_w_core                     ,
    input   logic   [REG_COUNT-1 : 0]           status_r_core                   ,//每一个数据字是否被读了
    output  logic   [DATA_WIDTH-1 : 0]          data_axi4_lite [0 : REG_COUNT-1],

    output  logic                               para_load                       ,//本次执行是否加载参数
    output  logic   [31:0]                      udmabuf_in_base_addr            ,//udmabuf基地址
    output  logic                               cpu_men_in_buffer1_valid        ,//内存缓冲区1是否有效
    output  logic   [11:0]                      cpu_men_in_buffer1_count        ,//内存缓冲区1数据量
    output  logic                               cpu_men_in_buffer2_valid        ,//内存缓冲区2是否有效
    output  logic   [11:0]                      cpu_men_in_buffer2_count        ,//内存缓冲区2数据量
    input   logic                               cpu_men_in_buffer1_clear        ,//内存缓冲区1现可清除
    input   logic                               cpu_men_in_buffer2_clear        ,//内存缓冲区2现可清除
    input   logic                               cpu_men_result_buffer1_ok       ,//内存的结果缓冲区1填好了
    input   logic   [11:0]                      cpu_men_result_buffer1_count    ,//内存的结果缓冲区1数据量
    input   logic                               cpu_men_result_buffer2_ok       ,//内存的结果缓冲区2填好了
    input   logic   [11:0]                      cpu_men_result_buffer2_count    ,//内存的结果缓冲区2数据量
    output  logic                               cpu_men_result_buffer1_valid    ,//内存的结果缓冲区1是否有效
    output  logic                               cpu_men_result_buffer2_valid    ,//内存的结果缓冲区2是否有效
    input   logic   [31:0]                      error_code                      ,//错误码
    output  logic                               gating_clk                      ,//门控时钟
    output  logic                               core_rst_n_2                     //软复位延时2，真正被子模块使用的复位信号
);

//axi4_lite
logic core_en;
logic cmd_rst_n;
logic [DATA_WIDTH-1 : 0] data_axi4_lite_reg [0 : REG_COUNT-1];

//clock_gating
logic clock_gating;             //业务模块时钟门控

//rst
logic core_rst_n;               //软复位
logic core_rst_n_1;             //软复位延时

assign core_en = (data_axi4_lite[0][15:0] == 16'h5a5a);
assign cmd_rst_n = ~(data_axi4_lite[0][16] == 1'b1);
assign core_rst_n = ~((rst_n == 1'b0) || (cmd_rst_n == 1'b0) || (core_en == 1'b0));//给业务模块的软复位
assign para_load = data_axi4_lite[0][17];
assign udmabuf_in_base_addr = data_axi4_lite[1];
assign cpu_men_in_buffer1_valid = data_axi4_lite[2][0];
assign cpu_men_in_buffer1_count = data_axi4_lite[2][15:4];
assign cpu_men_in_buffer2_valid = data_axi4_lite[2][16];
assign cpu_men_in_buffer2_count = data_axi4_lite[2][31:20];
assign cpu_men_result_buffer1_valid = data_axi4_lite[3][0];
assign cpu_men_result_buffer2_valid = data_axi4_lite[3][16];
assign data_axi4_lite[3][15:4]  = cpu_men_result_buffer1_count;
assign data_axi4_lite[3][31:20] = cpu_men_result_buffer2_count;
assign data_axi4_lite[4]        = error_code;

assign data_axi4_lite[0]        = data_axi4_lite_reg[0];
assign data_axi4_lite[1]        = data_axi4_lite_reg[1];
assign data_axi4_lite[2]        = data_axi4_lite_reg[2];
assign data_axi4_lite[3][3:0]   = data_axi4_lite_reg[3][3:0];
assign data_axi4_lite[3][19:16] = data_axi4_lite_reg[3][19:16];

//arm与fpga通过axi4-lite进行任务沟通状态机
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        data_axi4_lite_reg <= '{default: '0};
    end
    else if(ctrl_w_core != '0) begin
        for(int i = 0; i < REG_COUNT; i++) begin
            if(ctrl_w_core[i] == 1'b1) begin
                data_axi4_lite_reg[i] <= data_w_core;
            end
        end
    end
    else begin
        data_axi4_lite_reg[0][16] <= 1'b0;
        data_axi4_lite_reg[0][18] <= 1'b0;
        data_axi4_lite_reg[0][19] <= 1'b0;
        if(cpu_men_in_buffer1_clear == 1'b1)begin
            data_axi4_lite_reg[2][0] <= 1'b0;
        end
        if(cpu_men_in_buffer2_clear == 1'b1)begin
            data_axi4_lite_reg[2][16] <= 1'b0;
        end
        if(cpu_men_result_buffer1_ok == 1'b1)begin
            data_axi4_lite_reg[3][0] <= 1'b1;
        end
        else if(data_axi4_lite[0][18] == 1'b1)begin
            data_axi4_lite_reg[3][0] <= 1'b0;
        end
        if(cpu_men_result_buffer2_ok == 1'b1)begin
            data_axi4_lite_reg[3][16] <= 1'b1;
        end
        else if(data_axi4_lite[0][19] == 1'b1)begin
            data_axi4_lite_reg[3][16] <= 1'b0;
        end
    end
end

//软复位逻辑
always_ff @(posedge clk)begin
    if(core_rst_n == 1'b0)begin
        core_rst_n_1    <= 1'b0;
        core_rst_n_2    <= 1'b0;
    end
    else begin
        core_rst_n_1    <= 1'b1;
        core_rst_n_2    <= core_rst_n_1;
    end
end

//时钟门控时序逻辑，在复位两个时钟周期后关闭门控（先引出逻辑，后续再实装）
always_ff @(posedge clk)begin
    if(core_rst_n == 1'b0)begin
        clock_gating    <= 1'b0;
    end
    else begin
        clock_gating    <= 1'b1;
    end
end
assign gating_clk = clk;

endmodule