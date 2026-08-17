`timescale 1ns / 1ps
module core#
(
	parameter integer C_M_AXI_ID_WIDTH   = 6,
	parameter integer C_M_AXI_ADDR_WIDTH = 32,
	parameter integer C_M_AXI_DATA_WIDTH = 128
)
(
    input   logic                               gating_clk                      ,//门控时钟
    input   logic                               core_rst_n_2                    ,//软复位延时2，真正被子模块使用的复位信号

    input   logic                               para_load                       ,//本次执行是否加载参数
    input   logic   [31:0]                      udmabuf_in_base_addr            ,//udmabuf基地址
    input   logic                               cpu_men_in_buffer1_valid        ,//内存缓冲区1是否有效
    input   logic   [11:0]                      cpu_men_in_buffer1_count        ,//内存缓冲区1数据量
    input   logic                               cpu_men_in_buffer2_valid        ,//内存缓冲区2是否有效
    input   logic   [11:0]                      cpu_men_in_buffer2_count        ,//内存缓冲区2数据量
    output  logic                               cpu_men_in_buffer1_clear        ,//内存缓冲区1现可清除
    output  logic                               cpu_men_in_buffer2_clear        ,//内存缓冲区2现可清除
    output  logic                               cpu_men_result_buffer1_ok       ,//内存的结果缓冲区1填好了
    output  logic   [11:0]                      cpu_men_result_buffer1_count    ,//内存的结果缓冲区1数据量
    output  logic                               cpu_men_result_buffer2_ok       ,//内存的结果缓冲区2填好了
    output  logic   [11:0]                      cpu_men_result_buffer2_count    ,//内存的结果缓冲区2数据量
    input   logic                               cpu_men_result_buffer1_valid    ,//内存的结果缓冲区1是否有效
    input   logic                               cpu_men_result_buffer2_valid    ,//内存的结果缓冲区2是否有效
    output  logic   [31:0]                      error_code                      ,//错误码

    input   wire                                M_AXI4_ACLK                     ,
    input   wire                                M_AXI4_ARESETN                  ,
    output  wire    [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI4_ARADDR                   ,
    output  wire    [7 : 0]                     M_AXI4_ARLEN                    ,
    input   wire                                M_AXI4_ARREADY                  ,
    output  wire                                M_AXI4_ARVALID                  ,
    output  wire    [C_M_AXI_ID_WIDTH-1:0]      M_AXI4_ARID                     ,
    output  wire    [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI4_AWADDR                   ,
    output  wire    [7 : 0]                     M_AXI4_AWLEN                    ,
    input   wire                                M_AXI4_AWREADY                  ,
    output  wire                                M_AXI4_AWVALID                  ,
    output  wire    [C_M_AXI_ID_WIDTH-1:0]      M_AXI4_AWID                     ,
    input   wire    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_BID                      ,
    output  wire                                M_AXI4_BREADY                   ,
    input   wire    [1 : 0]                     M_AXI4_BRESP                    ,
    input   wire                                M_AXI4_BVALID                   ,
    input   wire    [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI4_RDATA                    ,
    input   wire    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_RID                      ,
    input   wire                                M_AXI4_RLAST                    ,
    output  wire                                M_AXI4_RREADY                   ,
    input   wire    [1 : 0]                     M_AXI4_RRESP                    ,
    input   wire                                M_AXI4_RVALID                   ,
    output  wire    [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI4_WDATA                    ,
    output  wire                                M_AXI4_WLAST                    ,
    input   wire                                M_AXI4_WREADY                   ,
    output  wire                                M_AXI4_WVALID                   
);

enum logic [7:0]
{
    MAIN_IDLE,
    MAIN_TEST,
    MAIN_TEST2
} main_cs, main_ns;

//sram_mgr
logic           ddr2sram_cmd_wr_en;//低有效
logic [17:0]    ddr2sram_cmd_din;
logic           ddr2sram_cmd_full;
logic           para_r_busy;
logic           ping1_r_busy;
logic           ping2_r_busy;
logic [3:0]     sram_mgr_error_code;

always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        error_code <= '0;
    end
    else begin
        error_code[3:0] <= sram_mgr_error_code;
    end
end

//主逻辑状态机
//一段
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        main_cs <= MAIN_IDLE;
    end
    else begin
        main_cs <= main_ns;
    end
end
//二段
always_comb begin
    main_ns = main_cs;
    case(main_cs)
        MAIN_IDLE:begin
            main_ns = MAIN_TEST;
        end
        MAIN_TEST:begin
            // 命令 FIFO 满时停留等待，写成功后再进入 TEST2，避免命令被静默丢弃
            if(ddr2sram_cmd_full == 1'b0) begin
                main_ns = MAIN_TEST2;
            end
        end
        MAIN_TEST2:begin
            main_ns = MAIN_TEST2;
        end
    endcase
end
//三段
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        ddr2sram_cmd_wr_en  <= '1;
        ddr2sram_cmd_din    <= '0;
    end
    else begin
        case(main_cs)
            MAIN_IDLE:begin
                ddr2sram_cmd_wr_en  <= 1'b1;
                ddr2sram_cmd_din    <= 18'd0;
            end
            MAIN_TEST:begin
                ddr2sram_cmd_wr_en  <= 1'b0;
                ddr2sram_cmd_din    <= {2'd0, 1'b0, 9'd0, 6'd0};
            end
            MAIN_TEST2:begin
                ddr2sram_cmd_wr_en  <= 1'b1;
                ddr2sram_cmd_din    <= 18'd0;
            end
        endcase            
    end
end

sram_mgr #
(
    .C_M_AXI_ID_WIDTH           (C_M_AXI_ID_WIDTH),
    .C_M_AXI_ADDR_WIDTH         (C_M_AXI_ADDR_WIDTH),
    .C_M_AXI_DATA_WIDTH         (C_M_AXI_DATA_WIDTH),
    .DDR2SRAM_CMD_FIFO_WIDTH    (18),
    .DDR2SRAM_CMD_FIFO_DEPTH    (4)
)
u_sram_mgr
(
    .clk                    (gating_clk),
    .rst_n                  (core_rst_n_2),
    .ddr2sram_cmd_wr_en     (ddr2sram_cmd_wr_en),
    .ddr2sram_cmd_din       (ddr2sram_cmd_din),
    .ddr2sram_cmd_full      (ddr2sram_cmd_full),
    .para_r_busy            (para_r_busy),
    .ping1_r_busy           (ping1_r_busy),
    .ping2_r_busy           (ping2_r_busy),
    .udmabuf_base_addr      (udmabuf_in_base_addr),
    .M_AXI4_AWADDR          (M_AXI4_AWADDR),
    .M_AXI4_AWLEN           (M_AXI4_AWLEN),
    .M_AXI4_AWREADY         (M_AXI4_AWREADY),
    .M_AXI4_AWVALID         (M_AXI4_AWVALID),
    .M_AXI4_AWID            (M_AXI4_AWID),
    .M_AXI4_WDATA           (M_AXI4_WDATA),
    .M_AXI4_WLAST           (M_AXI4_WLAST),
    .M_AXI4_WREADY          (M_AXI4_WREADY),
    .M_AXI4_WVALID          (M_AXI4_WVALID),
    .M_AXI4_BID             (M_AXI4_BID),
    .M_AXI4_BREADY          (M_AXI4_BREADY),
    .M_AXI4_BRESP           (M_AXI4_BRESP),
    .M_AXI4_BVALID          (M_AXI4_BVALID),
    .M_AXI4_ARADDR          (M_AXI4_ARADDR),
    .M_AXI4_ARLEN           (M_AXI4_ARLEN),
    .M_AXI4_ARREADY         (M_AXI4_ARREADY),
    .M_AXI4_ARVALID         (M_AXI4_ARVALID),
    .M_AXI4_ARID            (M_AXI4_ARID),
    .M_AXI4_RDATA           (M_AXI4_RDATA),
    .M_AXI4_RID             (M_AXI4_RID),
    .M_AXI4_RLAST           (M_AXI4_RLAST),
    .M_AXI4_RREADY          (M_AXI4_RREADY),
    .M_AXI4_RRESP           (M_AXI4_RRESP),
    .M_AXI4_RVALID          (M_AXI4_RVALID),
    .error                  (sram_mgr_error_code)
);

endmodule