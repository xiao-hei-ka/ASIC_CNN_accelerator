`timescale 1ns / 1ps
module top#
(
    //axi4-lite
	parameter integer DATA_WIDTH    = 32,
	parameter integer REG_COUNT    = 5,
	parameter integer ADDR_WIDTH = ($clog2((DATA_WIDTH/8) * REG_COUNT) < 1) ? 1 : $clog2((DATA_WIDTH/8) * REG_COUNT),

	parameter integer C_M_AXI_ID_WIDTH   = 6,
	parameter integer C_M_AXI_ADDR_WIDTH = 32,
	parameter integer C_M_AXI_DATA_WIDTH = 128
)
(
    input   logic                               rst_n                           ,

    //axi4-lite slave
    input   logic                               S_AXI4_LITE_ACLK               ,
    input   logic                               S_AXI4_LITE_ARESETN            ,
    input   logic   [ADDR_WIDTH-1 : 0]          S_AXI4_LITE_AWADDR             ,
    input   logic   [2 : 0]                     S_AXI4_LITE_AWPROT             ,
    input   logic                               S_AXI4_LITE_AWVALID            ,
    output  logic                               S_AXI4_LITE_AWREADY            ,
    input   logic   [DATA_WIDTH-1 : 0]          S_AXI4_LITE_WDATA              ,
    input   logic   [(DATA_WIDTH/8)-1 : 0]      S_AXI4_LITE_WSTRB              ,
    input   logic                               S_AXI4_LITE_WVALID             ,
    output  logic                               S_AXI4_LITE_WREADY             ,
    output  logic   [1 : 0]                     S_AXI4_LITE_BRESP              ,
    output  logic                               S_AXI4_LITE_BVALID             ,
    input   logic                               S_AXI4_LITE_BREADY             ,
    input   logic   [ADDR_WIDTH-1 : 0]          S_AXI4_LITE_ARADDR             ,
    input   logic   [2 : 0]                     S_AXI4_LITE_ARPROT             ,
    input   logic                               S_AXI4_LITE_ARVALID            ,
    output  logic                               S_AXI4_LITE_ARREADY            ,
    output  logic   [DATA_WIDTH-1 : 0]          S_AXI4_LITE_RDATA              ,
    output  logic   [1 : 0]                     S_AXI4_LITE_RRESP              ,
    output  logic                               S_AXI4_LITE_RVALID             ,
    input   logic                               S_AXI4_LITE_RREADY             ,

    //axi4-full master
    input   wire                                M_AXI4_ACLK                     ,
    input   wire                                M_AXI4_ARESETN                  ,
    //AW
    output  wire    [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI4_AWADDR                   ,
    output  wire    [7 : 0]                     M_AXI4_AWLEN                    ,
    input   wire                                M_AXI4_AWREADY                  ,
    output  wire                                M_AXI4_AWVALID                  ,
    output  wire    [5:0]                       M_AXI4_AWID                     ,
    output  wire    [5:0]                       M_AXI4_AWPROT                   ,
    output  wire    [2 : 0]                     M_AXI4_AWSIZE                   ,   // 未用到：每次传输的字节数
    output  wire    [1 : 0]                     M_AXI4_AWBURST                  ,   // 未用到：突发类型 FIXED/INCR/WRAP
    output  wire    [1 : 0]                     M_AXI4_AWLOCK                   ,   // 未用到：锁类型（AXI4 规范为 2bit）
    output  wire    [3 : 0]                     M_AXI4_AWCACHE                  ,   // 未用到：缓存属性
    output  wire    [3 : 0]                     M_AXI4_AWQOS                    ,   // 未用到：QoS 优先级
    output  wire    [3 : 0]                     M_AXI4_AWREGION                 ,   // 未用到：区域标识（可选）
    //W
    output  wire    [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI4_WDATA                    ,
    output  wire    [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI4_WSTRB                   ,   // 未用到：写 strobe（写数据必备，缺失则写无效）
    output  wire                                M_AXI4_WLAST                    ,
    input   wire                                M_AXI4_WREADY                   ,
    output  wire                                M_AXI4_WVALID                   ,
    //B
    input   wire    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_BID                      ,
    output  wire                                M_AXI4_BREADY                   ,
    input   wire    [1 : 0]                     M_AXI4_BRESP                    ,
    input   wire                                M_AXI4_BVALID                   ,
    //AR
    output  wire    [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI4_ARADDR                   ,
    output  wire    [7 : 0]                     M_AXI4_ARLEN                    ,
    input   wire                                M_AXI4_ARREADY                  ,
    output  wire                                M_AXI4_ARVALID                  ,
    output  wire    [5:0]                       M_AXI4_ARID                     ,
    output  wire    [2 : 0]                     M_AXI4_ARSIZE                   ,   // 未用到：每次传输的字节数
    output  wire    [1 : 0]                     M_AXI4_ARBURST                  ,   // 未用到：突发类型 FIXED/INCR/WRAP
    output  wire    [1 : 0]                     M_AXI4_ARLOCK                   ,   // 未用到：锁类型（AXI4 规范为 2bit）
    output  wire    [3 : 0]                     M_AXI4_ARCACHE                  ,   // 未用到：缓存属性
    output  wire    [2 : 0]                     M_AXI4_ARPROT                   ,   // 未用到：保护/权限属性
    output  wire    [3 : 0]                     M_AXI4_ARQOS                    ,   // 未用到：QoS 优先级
    output  wire    [3 : 0]                     M_AXI4_ARREGION                 ,   // 未用到：区域标识（可选）
    //R
    input   wire    [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI4_RDATA                    ,
    input   wire    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_RID                      ,
    input   wire                                M_AXI4_RLAST                    ,
    output  wire                                M_AXI4_RREADY                   ,
    input   wire    [1 : 0]                     M_AXI4_RRESP                    ,
    input   wire                                M_AXI4_RVALID

);

logic clk;

//axi4_lite_parser <-> core 连线
logic                               para_load                       ;//本次执行是否加载参数
logic   [31:0]                      udmabuf_in_base_addr            ;//udmabuf基地址
logic                               cpu_men_in_buffer1_valid        ;//内存缓冲区1是否有效
logic   [11:0]                      cpu_men_in_buffer1_count        ;//内存缓冲区1数据量
logic                               cpu_men_in_buffer2_valid        ;//内存缓冲区2是否有效
logic   [11:0]                      cpu_men_in_buffer2_count        ;//内存缓冲区2数据量
logic                               cpu_men_in_buffer1_clear        ;//内存缓冲区1现可清除
logic                               cpu_men_in_buffer2_clear        ;//内存缓冲区2现可清除
logic                               cpu_men_result_buffer1_ok       ;//内存的结果缓冲区1填好了
logic   [11:0]                      cpu_men_result_buffer1_count    ;//内存的结果缓冲区1数据量
logic                               cpu_men_result_buffer2_ok       ;//内存的结果缓冲区2填好了
logic   [11:0]                      cpu_men_result_buffer2_count    ;//内存的结果缓冲区2数据量
logic                               cpu_men_result_buffer1_valid    ;//内存的结果缓冲区1是否有效
logic                               cpu_men_result_buffer2_valid    ;//内存的结果缓冲区2是否有效
logic   [31:0]                      error_code                      ;//错误码
logic                               gating_clk                      ;//门控时钟
logic                               core_rst_n_2                    ;//软复位延时2，真正被子模块使用的复位信号

assign clk = M_AXI4_ACLK;
assign rst_n_comb = rst_n & S_AXI4_LITE_ARESETN & M_AXI4_ARESETN;

reset_synchronizer u_reset_synchronizer
(
    .clk(clk),
    .rst_n(rst_n_comb)
    .rst_n_sync(rst_n_sync)
)

axi4_lite_parser #
(
    .DATA_WIDTH         (DATA_WIDTH),
    .REG_COUNT          (REG_COUNT),
    .ADDR_WIDTH         (ADDR_WIDTH)
)
u_axi4_lite_parser
(
    .clk                            (clk),
    .rst_n                          (rst_n_sync),

    .S_AXI4_LITE_ACLK               (S_AXI4_LITE_ACLK),
    .S_AXI4_LITE_ARESETN            (S_AXI4_LITE_ARESETN),
    .S_AXI4_LITE_AWADDR             (S_AXI4_LITE_AWADDR),
    .S_AXI4_LITE_AWPROT             (S_AXI4_LITE_AWPROT),
    .S_AXI4_LITE_AWVALID            (S_AXI4_LITE_AWVALID),
    .S_AXI4_LITE_AWREADY            (S_AXI4_LITE_AWREADY),
    .S_AXI4_LITE_WDATA              (S_AXI4_LITE_WDATA),
    .S_AXI4_LITE_WSTRB              (S_AXI4_LITE_WSTRB),
    .S_AXI4_LITE_WVALID             (S_AXI4_LITE_WVALID),
    .S_AXI4_LITE_WREADY             (S_AXI4_LITE_WREADY),
    .S_AXI4_LITE_BRESP              (S_AXI4_LITE_BRESP),
    .S_AXI4_LITE_BVALID             (S_AXI4_LITE_BVALID),
    .S_AXI4_LITE_BREADY             (S_AXI4_LITE_BREADY),
    .S_AXI4_LITE_ARADDR             (S_AXI4_LITE_ARADDR),
    .S_AXI4_LITE_ARPROT             (S_AXI4_LITE_ARPROT),
    .S_AXI4_LITE_ARVALID            (S_AXI4_LITE_ARVALID),
    .S_AXI4_LITE_ARREADY            (S_AXI4_LITE_ARREADY),
    .S_AXI4_LITE_RDATA              (S_AXI4_LITE_RDATA),
    .S_AXI4_LITE_RRESP              (S_AXI4_LITE_RRESP),
    .S_AXI4_LITE_RVALID             (S_AXI4_LITE_RVALID),
    .S_AXI4_LITE_RREADY             (S_AXI4_LITE_RREADY),

    .para_load                      (para_load),
    .udmabuf_in_base_addr           (udmabuf_in_base_addr),
    .cpu_men_in_buffer1_valid       (cpu_men_in_buffer1_valid),
    .cpu_men_in_buffer1_count       (cpu_men_in_buffer1_count),
    .cpu_men_in_buffer2_valid       (cpu_men_in_buffer2_valid),
    .cpu_men_in_buffer2_count       (cpu_men_in_buffer2_count),
    .cpu_men_in_buffer1_clear       (cpu_men_in_buffer1_clear),
    .cpu_men_in_buffer2_clear       (cpu_men_in_buffer2_clear),
    .cpu_men_result_buffer1_ok      (cpu_men_result_buffer1_ok),
    .cpu_men_result_buffer1_count   (cpu_men_result_buffer1_count),
    .cpu_men_result_buffer2_ok      (cpu_men_result_buffer2_ok),
    .cpu_men_result_buffer2_count   (cpu_men_result_buffer2_count),
    .cpu_men_result_buffer1_valid   (cpu_men_result_buffer1_valid),
    .cpu_men_result_buffer2_valid   (cpu_men_result_buffer2_valid),
    .error_code                     (error_code),
    .gating_clk                     (gating_clk),
    .core_rst_n_2                   (core_rst_n_2)
);

core #
(
    .C_M_AXI_ID_WIDTH               (C_M_AXI_ID_WIDTH),
    .C_M_AXI_ADDR_WIDTH             (C_M_AXI_ADDR_WIDTH),
    .C_M_AXI_DATA_WIDTH             (C_M_AXI_DATA_WIDTH)
)
u_core
(
    .clk                            (gating_clk),
    .rst_n                          (core_rst_n_2),
    .para_load                      (para_load),
    .udmabuf_in_base_addr           (udmabuf_in_base_addr),
    .cpu_men_in_buffer1_valid       (cpu_men_in_buffer1_valid),
    .cpu_men_in_buffer1_count       (cpu_men_in_buffer1_count),
    .cpu_men_in_buffer2_valid       (cpu_men_in_buffer2_valid),
    .cpu_men_in_buffer2_count       (cpu_men_in_buffer2_count),
    .cpu_men_in_buffer1_clear       (cpu_men_in_buffer1_clear),
    .cpu_men_in_buffer2_clear       (cpu_men_in_buffer2_clear),
    .cpu_men_result_buffer1_ok      (cpu_men_result_buffer1_ok),
    .cpu_men_result_buffer1_count   (cpu_men_result_buffer1_count),
    .cpu_men_result_buffer2_ok      (cpu_men_result_buffer2_ok),
    .cpu_men_result_buffer2_count   (cpu_men_result_buffer2_count),
    .cpu_men_result_buffer1_valid   (cpu_men_result_buffer1_valid),
    .cpu_men_result_buffer2_valid   (cpu_men_result_buffer2_valid),
    .error_code                     (error_code),
    .gating_clk                     (gating_clk),
    .core_rst_n_2                   (core_rst_n_2),

    .M_AXI4_ACLK                    (M_AXI4_ACLK),
    .M_AXI4_ARESETN                 (M_AXI4_ARESETN),
    .M_AXI4_ARADDR                  (M_AXI4_ARADDR),
    .M_AXI4_ARLEN                   (M_AXI4_ARLEN),
    .M_AXI4_ARREADY                 (M_AXI4_ARREADY),
    .M_AXI4_ARVALID                 (M_AXI4_ARVALID),
    .M_AXI4_ARID                    (M_AXI4_ARID),
    .M_AXI4_AWADDR                  (M_AXI4_AWADDR),
    .M_AXI4_AWLEN                   (M_AXI4_AWLEN),
    .M_AXI4_AWREADY                 (M_AXI4_AWREADY),
    .M_AXI4_AWVALID                 (M_AXI4_AWVALID),
    .M_AXI4_AWID                    (M_AXI4_AWID),
    .M_AXI4_BID                     (M_AXI4_BID),
    .M_AXI4_BREADY                  (M_AXI4_BREADY),
    .M_AXI4_BRESP                   (M_AXI4_BRESP),
    .M_AXI4_BVALID                  (M_AXI4_BVALID),
    .M_AXI4_RDATA                   (M_AXI4_RDATA),
    .M_AXI4_RID                     (M_AXI4_RID),
    .M_AXI4_RLAST                   (M_AXI4_RLAST),
    .M_AXI4_RREADY                  (M_AXI4_RREADY),
    .M_AXI4_RRESP                   (M_AXI4_RRESP),
    .M_AXI4_RVALID                  (M_AXI4_RVALID),
    .M_AXI4_WDATA                   (M_AXI4_WDATA),
    .M_AXI4_WLAST                   (M_AXI4_WLAST),
    .M_AXI4_WREADY                  (M_AXI4_WREADY),
    .M_AXI4_WVALID                  (M_AXI4_WVALID)
);





endmodule