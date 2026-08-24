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

    input   logic                               para_load                       ,//本次执行是否需要加载参数
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
    output                                      error_code                      ,//错误码

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

struct packed
{
    logic [23:0] rsv;
    logic [1:0] batch_mgr_err;
    logic [1:0] im_in_err;      //bit0:缓冲区1非法无效；bit1：缓冲区2非法无效
    logic [3:0] sram_mgr_err;
} error_code;

typedef enum logic [7:0]
{
    MAIN_IDLE,                      //初始状态
    MAIN_1_P_IN,                  //参数、新图像数据读入sram阶段
    MAIN_1_BITCH_ROUTING,                   //批次路由工作拍
    MAIN_1_IM_IN,//数据进入sram
    MAIN_1_IM_IN2,//等待数据进入sram完成
    MAIN_2,            
} main_status_t;
main_status_t main_cs, main_ns;

//sram_mgr
logic           ddr2sram_cmd_wr_en;//低有效
logic [18:0]    ddr2sram_cmd_din;
logic           ddr2sram_cmd_full;
logic           para_r_busy;
logic           ping1_r_busy;
logic           ping2_r_busy;
logic [3:0]     sram_mgr_error_code;
//sram有效指示
logic para_r_busy_q1;
logic para_sram_ok;
logic ping1_r_busy_q1;
logic ping1_sram_ok;
logic ping2_r_busy_q1;
logic ping2_sram_ok;
//ping指针
logic ping_ptr;//0:ping1;1:ping2
//batch_mgr
logic           is_routing = (main_cs == MAIN_1_BITCH_ROUTING); //当前是否为新一轮状态路由工作拍
logic           im_in_buffer_ptr;                       //指示本轮使用的缓冲区，0:缓冲区1，1:缓冲区2
logic [8:0]     im_in_data_ptr;                         //指示本轮计算从第几个图像开始，从0开始计数。
logic [6:0]     im_in_data_size;                        //指示本轮计算图像个数
logic           im_in_data_valid                        //指示图像数据是否有效



//错误码置位
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        error_code <= `{default '0};
    end
    else begin
        error_code.sram_mgr_err <= sram_mgr_error_code;
        if(im_in_buffer_ptr == 1'b0 && cpu_men_in_buffer1_valid == 1'b0)begin//指针指向缓冲区1，但缓冲区1数据无效
            error_code.im_in_err[0] <= 1'b1;
        end
        if(im_in_buffer_ptr == 1'b0 && cpu_men_in_buffer1_valid == 1'b0)begin//指针指向缓冲区2，但缓冲区2数据无效
            error_code.im_in_err[1] <= 1'b1;
        end
        error_code.batch_mgr_err <= batch_mgr_error_code;
    end
end

//para sram有效指示
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        para_r_busy_q1  <= 1'b0;
        para_sram_ok    <= 1'b0;
    end
    else begin
        para_r_busy_q1  <= para_r_busy;
        if(para_r_busy_q1 & (~para_r_busy) == 1'b1)begin
            para_sram_ok    <= 1'b1;
        end
    end
end

//ping1 sram有效指示
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        ping1_r_busy_q1  <= 1'b0;
        ping1_sram_ok    <= 1'b0;
    end
    else begin
        ping1_r_busy_q1  <= ping1_r_busy;
        if(main_cs == MAIN_IDLE)begin
            ping1_sram_ok    <= 1'b0;
        end
        else if(ping1_r_busy_q1 & (~ping1_r_busy) == 1'b1)begin
            ping1_sram_ok    <= 1'b1;
        end
    end
end

//ping2 sram有效指示
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        ping2_r_busy_q1  <= 1'b0;
        ping2_sram_ok    <= 1'b0;
    end
    else begin
        ping2_r_busy_q1  <= ping1_r_busy;
        if(main_cs == MAIN_IDLE)begin
            ping2_sram_ok    <= 1'b0;
        end
        else if(ping1_r_busy_q1 & (~ping1_r_busy) == 1'b1)begin
            ping2_sram_ok    <= 1'b1;
        end
    end
end

//第一次循环指示
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        is_first_cycle  <= 1'b1;
    end
    else begin
        if(main_cs == MAIN_IDLE)begin
            is_first_cycle    <= 1'b0;
        end
    end
end

//ping1、ping2选择
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        ping_ptr  <= 1'b0;
    end
    else begin
        if(main_cs == MAIN_1_BITCH_ROUTING)begin
            if(is_first_cycle == 1'b1)begin
                ping_ptr    <= 1'b0;
            end
            else begin
                ping_ptr    <= ping_ptr + 1'b1;
            end
        end
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
            if(para_load == 1'b0) begin
                main_ns = MAIN_1_P_IN;
            end
            else begin
                main_ns = MAIN_1_BITCH_ROUTING;
            end
        end
        MAIN_1_P_IN:begin
            main_ns = MAIN_1_BITCH_ROUTING;
        end
        MAIN_1_BITCH_ROUTING:begin
            if(im_in_data_valid == 1'b1) begin
                main_ns = MAIN_1_IM_IN;
            end
        end
        MAIN_1_IM_IN:begin
            main_ns = MAIN_1_IM_IN2;
        end
        MAIN_1_IM_IN2:begin
            if(para_sram_ok == 1'b1 && ping1_sram_ok)begin
                main_ns = MAIN_2;
            end
        end
    endcase
end
//三段
always_ff @(posedge gating_clk)begin
    if(core_rst_n_2 == 1'b0)begin
        ddr2sram_cmd_wr_en  <= 1'b1;
        ddr2sram_cmd_din    <= '0;
    end
    else begin
        ddr2sram_cmd_wr_en  <= 1'b1;
        case(main_cs)
            MAIN_IDLE:begin
            end
            MAIN_1_P_IN:begin
                ddr2sram_cmd_wr_en  <= 1'b0;
                ddr2sram_cmd_din    <= {7'd0, 9'd0, 1'b0, 2'd0};
            end
            MAIN_1_BITCH_ROUTING:begin
            end
            MAIN_1_IM_IN:begin
                ddr2sram_cmd_wr_en  <= 1'b0;
                ddr2sram_cmd_din    <= {im_in_data_size, im_in_data_ptr, im_in_buffer_ptr, 2'd1 + 2'(ping_ptr)};
            end
            MAIN_1_IM_IN2:begin
            end
            MAIN_2:begin
            end
        endcase            
    end
end

batch_mgr u_batch_mgr
(
    .gating_clk                 (gating_clk),
    .core_rst_n_2               (core_rst_n_2),
    .is_routing                 (is_routing),
    .cpu_men_in_buffer1_valid   (cpu_men_in_buffer1_valid),
    .cpu_men_in_buffer1_count   (cpu_men_in_buffer1_count),
    .cpu_men_in_buffer2_valid   (cpu_men_in_buffer2_valid),
    .cpu_men_in_buffer2_count   (cpu_men_in_buffer2_count),
    .im_in_buffer_ptr           (im_in_buffer_ptr),
    .im_in_data_ptr             (im_in_data_ptr),
    .im_in_data_size            (im_in_data_size),
    .im_in_data_valid           (im_in_data_valid),
    .batch_mgr_error_code       (batch_mgr_error_code)
);

sram_mgr #
(
    .C_M_AXI_ID_WIDTH           (C_M_AXI_ID_WIDTH),
    .C_M_AXI_ADDR_WIDTH         (C_M_AXI_ADDR_WIDTH),
    .C_M_AXI_DATA_WIDTH         (C_M_AXI_DATA_WIDTH)
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