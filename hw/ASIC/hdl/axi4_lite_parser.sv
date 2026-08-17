`timescale 1 ns / 1 ps

    module axi4_lite_parser #
    (

        parameter integer DATA_WIDTH    = 32,
        parameter integer REG_COUNT    = 5,
        parameter integer ADDR_WIDTH = ($clog2((DATA_WIDTH/8) * REG_COUNT) < 1) ? 1 : $clog2((DATA_WIDTH/8) * REG_COUNT)
    )
    (
        input   logic   clk,
        input   logic   rst_n,

        input   logic                        S_AXI4_LITE_ACLK,
        input   logic                        S_AXI4_LITE_ARESETN,
        input   logic [ADDR_WIDTH-1 : 0]     S_AXI4_LITE_AWADDR,
        input   logic [2 : 0]                S_AXI4_LITE_AWPROT,
        input   logic                        S_AXI4_LITE_AWVALID,
        output  logic                        S_AXI4_LITE_AWREADY,
        input   logic [DATA_WIDTH-1 : 0]     S_AXI4_LITE_WDATA,
        input   logic [(DATA_WIDTH/8)-1 : 0] S_AXI4_LITE_WSTRB,
        input   logic                        S_AXI4_LITE_WVALID,
        output  logic                        S_AXI4_LITE_WREADY,
        output  logic [1 : 0]                S_AXI4_LITE_BRESP,
        output  logic                        S_AXI4_LITE_BVALID,
        input   logic                        S_AXI4_LITE_BREADY,
        input   logic [ADDR_WIDTH-1 : 0]     S_AXI4_LITE_ARADDR,
        input   logic [2 : 0]                S_AXI4_LITE_ARPROT,
        input   logic                        S_AXI4_LITE_ARVALID,
        output  logic                        S_AXI4_LITE_ARREADY,
        output  logic [DATA_WIDTH-1 : 0]     S_AXI4_LITE_RDATA,
        output  logic [1 : 0]                S_AXI4_LITE_RRESP,
        output  logic                        S_AXI4_LITE_RVALID,
        input   logic                        S_AXI4_LITE_RREADY,

        output  logic                        para_load                       ,//本次执行是否加载参数
        output  logic   [31:0]               udmabuf_in_base_addr            ,//udmabuf基地址
        output  logic                        cpu_men_in_buffer1_valid        ,//内存缓冲区1是否有效
        output  logic   [11:0]               cpu_men_in_buffer1_count        ,//内存缓冲区1数据量
        output  logic                        cpu_men_in_buffer2_valid        ,//内存缓冲区2是否有效
        output  logic   [11:0]               cpu_men_in_buffer2_count        ,//内存缓冲区2数据量
        input   logic                        cpu_men_in_buffer1_clear        ,//内存缓冲区1现可清除
        input   logic                        cpu_men_in_buffer2_clear        ,//内存缓冲区2现可清除
        input   logic                        cpu_men_result_buffer1_ok       ,//内存的结果缓冲区1填好了
        input   logic   [11:0]               cpu_men_result_buffer1_count    ,//内存的结果缓冲区1数据量
        input   logic                        cpu_men_result_buffer2_ok       ,//内存的结果缓冲区2填好了
        input   logic   [11:0]               cpu_men_result_buffer2_count    ,//内存的结果缓冲区2数据量
        output  logic                        cpu_men_result_buffer1_valid    ,//内存的结果缓冲区1是否有效
        output  logic                        cpu_men_result_buffer2_valid    ,//内存的结果缓冲区2是否有效
        input   logic   [31:0]               error_code                      ,//错误码
        output  logic                        gating_clk                      ,//门控时钟
        output  logic                        core_rst_n_2                     //软复位延时2，真正被子模块使用的复位信号
    );
//axi4_lite_interface <-> CDC
logic   [REG_COUNT-1 : 0]     ctrl_w_valid;
logic   [REG_COUNT-1 : 0]     ctrl_w_ready;
logic   [DATA_WIDTH-1 : 0]    data_w;
logic   [REG_COUNT-1 : 0]     ctrl_r_valid;
logic   [REG_COUNT-1 : 0]     ctrl_r_ready;
logic   [DATA_WIDTH-1 : 0]    data_r;


//CDC <-> axi4_frame_parser
logic   [REG_COUNT-1 : 0]       ctrl_w_core;
logic   [DATA_WIDTH-1 : 0]      data_w_core;
logic   [REG_COUNT-1 : 0]       status_r_core;
logic   [DATA_WIDTH-1 : 0]      data_r_core [0 : REG_COUNT-1];


axi4_lite_interface # (
    .C_S_AXI_DATA_WIDTH (DATA_WIDTH),
    .C_S_AXI_REG_COUNT  (REG_COUNT),
    .C_S_AXI_ADDR_WIDTH (ADDR_WIDTH)
) u_axi4_lite_interface
(
    .S_AXI4_LITE_ACLK         (S_AXI4_LITE_ACLK),
    .S_AXI4_LITE_ARESETN      (S_AXI4_LITE_ARESETN),
    .S_AXI4_LITE_AWADDR       (S_AXI4_LITE_AWADDR),
    .S_AXI4_LITE_AWPROT       (S_AXI4_LITE_AWPROT),
    .S_AXI4_LITE_AWVALID      (S_AXI4_LITE_AWVALID),
    .S_AXI4_LITE_AWREADY      (S_AXI4_LITE_AWREADY),
    .S_AXI4_LITE_WDATA        (S_AXI4_LITE_WDATA),
    .S_AXI4_LITE_WSTRB        (S_AXI4_LITE_WSTRB),
    .S_AXI4_LITE_WVALID       (S_AXI4_LITE_WVALID),
    .S_AXI4_LITE_WREADY       (S_AXI4_LITE_WREADY),
    .S_AXI4_LITE_BRESP        (S_AXI4_LITE_BRESP),
    .S_AXI4_LITE_BVALID       (S_AXI4_LITE_BVALID),
    .S_AXI4_LITE_BREADY       (S_AXI4_LITE_BREADY),
    .S_AXI4_LITE_ARADDR       (S_AXI4_LITE_ARADDR),
    .S_AXI4_LITE_ARPROT       (S_AXI4_LITE_ARPROT),
    .S_AXI4_LITE_ARVALID      (S_AXI4_LITE_ARVALID),
    .S_AXI4_LITE_ARREADY      (S_AXI4_LITE_ARREADY),
    .S_AXI4_LITE_RDATA        (S_AXI4_LITE_RDATA),
    .S_AXI4_LITE_RRESP        (S_AXI4_LITE_RRESP),
    .S_AXI4_LITE_RVALID       (S_AXI4_LITE_RVALID),
    .S_AXI4_LITE_RREADY       (S_AXI4_LITE_RREADY),
    .ctrl_w_valid (ctrl_w_valid),
    .ctrl_w_ready (ctrl_w_ready),
    .data_w       (data_w),
    .ctrl_r_valid (ctrl_r_valid),
    .ctrl_r_ready (ctrl_r_ready),
    .data_r       (data_r)
);

cdc # (
    .DATA_WIDTH         (DATA_WIDTH),
    .REG_COUNT          (REG_COUNT),
    .ADDR_WIDTH         (ADDR_WIDTH)
) u_cdc(
    .aclk               (S_AXI4_LITE_ACLK),
    .aresetn            (S_AXI4_LITE_ARESETN),
    .clk                (clk),
    .rst_n              (rst_n),
    .ctrl_w_valid       (ctrl_w_valid),
    .ctrl_w_ready_r2    (ctrl_w_ready),
    .data_w             (data_w),
    .ctrl_r_valid       (ctrl_r_valid),
    .ctrl_r_ready_r2    (ctrl_r_ready),
    .data_r             (data_r),

    .ctrl_w_core        (ctrl_w_core),
    .data_w_core        (data_w_core),
    .status_r_core      (status_r_core),
    .data_r_core        (data_r_core)
);

axi4_frame_parser #
(
    //axi4-lite
	.DATA_WIDTH(DATA_WIDTH),
	.REG_COUNT (REG_COUNT ),
	.ADDR_WIDTH(ADDR_WIDTH)
)
u_axi4_frame_parser(
    .clk                         (clk                         )    ,
    .rst_n                       (rst_n                       )    ,
    .ctrl_w_core                 (ctrl_w_core                 )    ,
    .data_w_core                 (data_w_core                 )    ,
    .status_r_core               (status_r_core               )    ,
    .data_axi4_lite              (data_r_core                 )    ,

    .para_load                   (para_load                   )    ,//本次执行是否加载参数
    .udmabuf_in_base_addr        (udmabuf_in_base_addr        )    ,//udmabuf基地址
    .cpu_men_in_buffer1_valid    (cpu_men_in_buffer1_valid    )    ,//内存缓冲区1是否有效
    .cpu_men_in_buffer1_count    (cpu_men_in_buffer1_count    )    ,//内存缓冲区1数据量
    .cpu_men_in_buffer2_valid    (cpu_men_in_buffer2_valid    )    ,//内存缓冲区2是否有效
    .cpu_men_in_buffer2_count    (cpu_men_in_buffer2_count    )    ,//内存缓冲区2数据量
    .cpu_men_in_buffer1_clear    (cpu_men_in_buffer1_clear    )    ,//内存缓冲区1现可清除
    .cpu_men_in_buffer2_clear    (cpu_men_in_buffer2_clear    )    ,//内存缓冲区2现可清除
    .cpu_men_result_buffer1_ok   (cpu_men_result_buffer1_ok   )    ,//内存的结果缓冲区1填好了
    .cpu_men_result_buffer1_count(cpu_men_result_buffer1_count)    ,//内存的结果缓冲区1数据量
    .cpu_men_result_buffer2_ok   (cpu_men_result_buffer2_ok   )    ,//内存的结果缓冲区2填好了
    .cpu_men_result_buffer2_count(cpu_men_result_buffer2_count)    ,//内存的结果缓冲区2数据量
    .cpu_men_result_buffer1_valid(cpu_men_result_buffer1_valid)    ,//内存的结果缓冲区1是否有效
    .cpu_men_result_buffer2_valid(cpu_men_result_buffer2_valid)    ,//内存的结果缓冲区2是否有效
    .error_code                  (error_code                  )    ,//错误码
    .gating_clk                  (gating_clk                  )    ,//门控时钟
    .core_rst_n_2                (core_rst_n_2                )     //软复位延时2，真正被子模块使用的复位信号
);

endmodule