`timescale 1 ns / 1 ps
`include def_file.vh
module sram_mgr #
(
    parameter integer C_M_AXI_ID_WIDTH	    = 6,
    parameter integer C_M_AXI_ADDR_WIDTH	= 32,
    parameter integer C_M_AXI_DATA_WIDTH	= 128,
    
    parameter integer DDR2SRAM_CMD_FIFO_WIDTH   = 18,
    parameter integer DDR2SRAM_CMD_FIFO_DEPTH	= 4
    
)
(
    input   logic                                clk                             ,
    input   logic                                rst_n                           ,
    
    input   logic                                ddr2sram_cmd_wr_en              ,
    //bit0-1:命令编号，0：para，1：ping1，2：ping2；
    //bit2：ping专用：指示本次读DDR中图像数据应从哪个缓冲区读取。 0：缓冲区1， 1：缓冲区2
    //bit3-11：ping专用：指示本次读DDR中图像数据应从该缓冲区第几个图像读,从0开始计数。
    //bit12-17：ping专用：指示本次读DDR中共读几个图像，从0开始计数。
    input   logic    [17:0]                      ddr2sram_cmd_din                ,
    output  logic                                ddr2sram_cmd_full               ,
    output  logic                                para_r_busy                     ,//para读正忙
    output  logic                                ping1_r_busy                    ,//ping1读正忙
    output  logic                                ping2_r_busy                    ,//ping2读正忙
    input   logic    [C_M_AXI_ADDR_WIDTH-1:0]    udmabuf_base_addr               ,//ddr udmabuf 基地址
    
    
    
    
    
    
    
    
    output  logic    [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI4_AWADDR                   ,
    output  logic    [7 : 0]                     M_AXI4_AWLEN                    ,
    input   logic                                M_AXI4_AWREADY                  ,
    output  logic                                M_AXI4_AWVALID                  ,
    output  logic    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_AWID                     ,
    
    output  logic    [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI4_WDATA                    ,
    output  logic                                M_AXI4_WLAST                    ,
    input   logic                                M_AXI4_WREADY                   ,
    output  logic                                M_AXI4_WVALID                   ,
    
    input   logic    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_BID                      ,
    output  logic                                M_AXI4_BREADY                   ,
    input   logic    [1 : 0]                     M_AXI4_BRESP                    ,
    input   logic                                M_AXI4_BVALID                   ,
    
    output  logic    [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI4_ARADDR                   ,
    output  logic    [7 : 0]                     M_AXI4_ARLEN                    ,
    input   logic                                M_AXI4_ARREADY                  ,
    output  logic                                M_AXI4_ARVALID                  ,
    output  logic    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_ARID                     ,
    
    input   logic    [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI4_RDATA                    ,
    input   logic    [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI4_RID                      ,//这个用不到，没有需要乱序读的场景
    input   logic                                M_AXI4_RLAST                    ,
    output  logic                                M_AXI4_RREADY                   ,
    input   logic    [1 : 0]                     M_AXI4_RRESP                    ,
    input   logic                                M_AXI4_RVALID                   ,

    output  logic    [3:0]                       error                           
);

localparam ddr2sram_ID = C_M_AXI_ID_WIDTH'(0);//所有从DDR到sram的写动作的id都为0
localparam r_leftMove_per_burst = 8'd12;////每次读事件地址握手突发事务后地址移动次数，每次突发传输256个字

enum logic [7:0]
{
    D2S_IDLE,
    D2S_RD_CMD
} ddr2sram_cs, ddr2sram_ns;//ddr2sram路由时状态机状态

enum logic [7:0]
{
    R_ADDR_IDLE,
    R_ADDR_RD_CMD,
    R_ADDR_AR_SEND
} r_addr_cs, r_addr_ns;//读ddr时地址握手状态机状态

enum logic [1:0]
{
    R_ADDR_PARA,
    R_ADDR_PING1,
    R_ADDR_PING2
} r_addr_pointer;//指示当前读ddr的地址握手正在路由到哪个sram

enum logic [7:0]
{
    R_DATA_IDLE,
    R_DATA_RD_CMD,
    R_DATA_RD_RCV
} r_data_cs, r_data_ns;//读ddr时数据握手状态机状态

enum logic [1:0]
{
    R_DATA_PARA,
    R_DATA_PING1,
    R_DATA_PING2
} r_data_pointer;//指示当前读ddr的数据握手正在路由到哪个sram

//fifo相关信号
logic [DDR2SRAM_CMD_FIFO_WIDTH-1:0] ddr2sram_cmd_dout           ;
logic                               ddr2sram_cmd_empty          ;
logic                               ddr2sram_cmd_rd_en          ;

logic                               ddr2sram_addr_routing_wr_en ;
logic                               ddr2sram_addr_routing_rd_en ;
logic [DDR2SRAM_CMD_FIFO_WIDTH-1:0] ddr2sram_addr_routing_din   ;
logic [DDR2SRAM_CMD_FIFO_WIDTH-1:0] ddr2sram_addr_routing_dout  ;
logic                               ddr2sram_addr_routing_full  ;
logic                               ddr2sram_addr_routing_empty ;

logic                               ddr2sram_data_routing_wr_en ;
logic                               ddr2sram_data_routing_rd_en ;
logic [DDR2SRAM_CMD_FIFO_WIDTH-1:0] ddr2sram_data_routing_din   ;
logic [DDR2SRAM_CMD_FIFO_WIDTH-1:0] ddr2sram_data_routing_dout  ;
logic                               ddr2sram_data_routing_full  ;
logic                               ddr2sram_data_routing_empty ;

//ddr2sram忙相关信号
logic                               para_r_addr_busy            ;
logic                               para_r_data_busy            ;
logic                               ping1_r_addr_busy           ;
logic                               ping1_r_data_busy           ;
logic                               ping2_r_addr_busy           ;
logic                               ping2_r_data_busy           ;
logic                               r_addr_finished             ;
logic                               r_data_finished             ;

//ddr2sram axi4传输相关信号
logic                               core_cmd_error              ;//fifo指令错误
//地址握手
logic  [ 7:0]                       r_addr_burst_times_already  ;//参数传递的全过程已经完整进行过的读地址握手事务次数
logic  [ 7:0]                       r_addr_last_len             ;//参数从ddr中读地址握手的最后一次突发读事物读取拍数。 
logic  [ 7:0]                       r_addr_burst_times          ;//参数总共该进行多少次突发事务
logic  [C_M_AXI_ADDR_WIDTH-1:0]     addr_base_addr              ;//本次传输任务的基地址
logic                               core_cmd_error_addr         ;//数据握手fifo指令错误
//数据握手
logic  [ 7:0]                       r_data_beat_times_already   ;//参数传递的该突发事务已经完整进行过的读数据握手节拍次数
logic  [ 7:0]                       r_data_burst_times_already  ;//参数传递的全过程已经完整进行过的读数据握手节拍次数
logic  [ 7:0]                       r_data_burst_times          ;//参数总共该进行多少次突发事务 
logic  [ 1:0]                       RRESP_err                   ;//从端回报错误信息
logic                               core_cmd_error_data         ;//数据握手fifo指令错误

//sram相关信号
logic           para_cs;        //参数sram片选使能，低有效
logic           para_wr;        //参数sram写使能，低有效（高则为读）
logic [11:0]    para_addr;      //参数sram地址
logic [127:0]   para_din;       //参数sram输入
logic [127:0]   para_dout_final;//参数sram输出





assign para_r_busy = {para_r_addr_busy, para_r_data_busy} != 2'b00;
assign ping1_r_busy = {ping1_r_addr_busy, ping1_r_data_busy} != 2'b00;
assign ping2_r_busy = {ping2_r_addr_busy, ping2_r_data_busy} != 2'b00;

assign core_cmd_error = core_cmd_error_addr | core_cmd_error_data;

//================ 写通道（AW/W/B）暂未实装：固定安全电平 ================
// 当前仅实装 DDR->SRAM 读路径。写通道输出若不驱动会悬空为 X，
// 从端（tb_ram）的写事务判断会被 X 污染，故先给出确定性电平。
// TODO: 实装写通道（DDR->SRAM 写路径）时删除本组赋值
assign M_AXI4_AWADDR  = '0;
assign M_AXI4_AWLEN   = '0;
assign M_AXI4_AWVALID = 1'b0;
assign M_AXI4_AWID    = '0;
assign M_AXI4_WDATA   = '0;
assign M_AXI4_WLAST   = 1'b0;
assign M_AXI4_WVALID  = 1'b0;
assign M_AXI4_BREADY  = 1'b1;   // 随时可接收（当前不会有）B 响应


//报error
always_ff @(posedge clk)begin
    if(rst_n == 1'b0) begin
        error <= 4'd0;
    end
    else if(core_cmd_error == 1'b1)begin
        error <= {2'b01, 2'd0};
    end
    else if(RRESP_err != 2'd0)begin
        error <= {2'b10, RRESP_err};
    end
end

//DDR -> SRAM 命令分发与busy管理状态机
//一段
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        ddr2sram_cs <= D2S_IDLE;
    end
    else begin
        ddr2sram_cs <= ddr2sram_ns;
    end
end
//二段
always_comb begin
    ddr2sram_ns = ddr2sram_cs;
    case(ddr2sram_cs)
        D2S_IDLE: begin
            if(ddr2sram_cmd_empty == 1'b0) begin
                ddr2sram_ns = D2S_RD_CMD;
            end
        end
        D2S_RD_CMD: begin
            // 命令 FIFO 排空且两个路由 FIFO 都有空间时才回 IDLE；
            // 若路由 FIFO 满，停留本状态等待（dout 保持当前命令，不丢不重）
            if((ddr2sram_cmd_empty == 1'b1) &&
               (ddr2sram_addr_routing_full == 1'b0) &&
               (ddr2sram_data_routing_full == 1'b0)) begin
                ddr2sram_ns = D2S_IDLE;
            end
        end
    endcase
end
//三段
always_ff @(posedge clk) begin
    if(rst_n ==1'b0) begin
        ddr2sram_cmd_rd_en           <= '1;    
        ddr2sram_addr_routing_wr_en  <= '1;
        ddr2sram_addr_routing_din    <= '0;
        ddr2sram_data_routing_wr_en  <= '1;
        ddr2sram_data_routing_din    <= '0;
        para_r_addr_busy             <= '0;
        para_r_data_busy             <= '0;
        ping1_r_addr_busy            <= '0;
        ping1_r_data_busy            <= '0;
        ping2_r_addr_busy            <= '0;
        ping2_r_data_busy            <= '0;
    end
    else begin
        if(r_addr_pointer == R_ADDR_PARA) begin
            para_r_addr_busy    <= para_r_addr_busy  & (~r_addr_finished);
        end
        if(r_addr_pointer == R_ADDR_PING1) begin
            ping1_r_addr_busy    <= ping1_r_addr_busy  & (~r_addr_finished);
        end
        if(r_addr_pointer == R_ADDR_PING2) begin
            ping2_r_addr_busy    <= ping2_r_addr_busy  & (~r_addr_finished);
        end
        if(r_data_pointer == R_DATA_PARA) begin
            para_r_data_busy    <= para_r_data_busy  & (~r_data_finished);
        end
        if(r_data_pointer == R_DATA_PING1) begin
            ping1_r_data_busy    <= ping1_r_data_busy  & (~r_data_finished);
        end
        if(r_data_pointer == R_DATA_PING2) begin
            ping2_r_data_busy    <= ping2_r_data_busy  & (~r_data_finished);
        end
        case(ddr2sram_cs)
            D2S_IDLE: begin
                if(ddr2sram_cmd_empty == 1'b0) begin
                    ddr2sram_cmd_rd_en <= 1'b0;
                end
            end
            D2S_RD_CMD: begin
                if((ddr2sram_addr_routing_full == 1'b1) || (ddr2sram_data_routing_full == 1'b1)) begin
                    // 路由 FIFO 满：本拍不转发、不弹出命令，dout 保持当前命令，下拍重试
                    ddr2sram_cmd_rd_en          <= 1'b1;
                    ddr2sram_addr_routing_wr_en <= 1'b1;
                    ddr2sram_data_routing_wr_en <= 1'b1;
                end
                else begin
                    // 转发当前命令：置忙 + 写入两个路由 FIFO
                    if(ddr2sram_cmd_dout[1:0] == 2'd0) begin
                        para_r_addr_busy <= 1'b1;
                        para_r_data_busy <= 1'b1;
                    end
                    else if(ddr2sram_cmd_dout[1:0] == 2'd1) begin
                        ping1_r_addr_busy <= 1'b1;
                        ping1_r_data_busy <= 1'b1;
                    end
                    else if(ddr2sram_cmd_dout[1:0] == 2'd2) begin
                        ping2_r_addr_busy <= 1'b1;
                        ping2_r_data_busy <= 1'b1;
                    end
                    ddr2sram_addr_routing_wr_en <= 1'b0;
                    ddr2sram_addr_routing_din   <= ddr2sram_cmd_dout;
                    ddr2sram_data_routing_wr_en <= 1'b0;
                    ddr2sram_data_routing_din   <= ddr2sram_cmd_dout;
                    // 弹出下一条命令
                    if(ddr2sram_cmd_empty == 1'b1) begin
                        ddr2sram_cmd_rd_en <= 1'b1;
                    end
                    else begin
                        ddr2sram_cmd_rd_en <= 1'b0;
                    end
                end
            end
        endcase
    end
end

//read_addr状态机
//一段
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        r_addr_cs <= R_ADDR_IDLE;
    end
    else begin
        r_addr_cs <= r_addr_ns;
    end
end
//二段
always_comb begin
    r_addr_ns = r_addr_cs;
    case(r_addr_cs)
        R_ADDR_IDLE:begin
            if(ddr2sram_addr_routing_empty == 0) begin
                r_addr_ns = R_ADDR_RD_CMD;
            end
        end
        R_ADDR_RD_CMD:begin
            if(ddr2sram_addr_routing_dout[1:0] == 2'd0)begin
                r_addr_ns = R_ADDR_AR_SEND;
            end
            else begin
                r_addr_ns = R_ADDR_IDLE;
            end
        end
        R_ADDR_AR_SEND:begin
            if((M_AXI4_ARVALID == 1'b1 && M_AXI4_ARREADY == 1'b1)&&(r_addr_burst_times_already >= (r_addr_burst_times-1))) begin
                r_addr_ns = R_ADDR_IDLE;
            end
        end
    endcase
end
//三段
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        M_AXI4_ARADDR               <= '0;
        M_AXI4_ARLEN                <= '0;
        M_AXI4_ARVALID              <= '0;
        M_AXI4_ARID                 <= '0;
        r_addr_burst_times_already  <= '0;
        r_addr_last_len             <= '0;
        r_addr_burst_times          <= '0;
        r_addr_finished             <= '0;
        r_addr_pointer              <= R_ADDR_PARA;
        ddr2sram_addr_routing_rd_en <= '1;
        addr_base_addr              <= '0;
        core_cmd_error_addr         <= '0;
    end
    else begin
        ddr2sram_addr_routing_rd_en <= 1'b1;
        M_AXI4_ARVALID              <= 1'b0;
        r_addr_finished             <= 1'b0;
        core_cmd_error_addr         <= 1'b0;
        case(r_addr_cs)
            R_ADDR_IDLE:begin
                r_addr_burst_times_already  <= 8'd0;
                if(ddr2sram_addr_routing_empty == 0) begin
                    ddr2sram_addr_routing_rd_en <= 1'b0;
                end
            end
            R_ADDR_RD_CMD:begin
                if(ddr2sram_addr_routing_dout[1:0] == 2'd0) begin//para
                    r_addr_pointer              <= R_ADDR_PARA ;
                    r_addr_burst_times          <= 8'd13;
                    r_addr_last_len             <= 8'd2;
                    addr_base_addr              <= udmabuf_base_addr + 32'd0;
                end
                else begin//else
                    core_cmd_error_addr <= 1'b1;
                end
            end
            R_ADDR_AR_SEND:begin
                M_AXI4_ARADDR <= addr_base_addr + (C_M_AXI_ADDR_WIDTH'(r_addr_burst_times_already) << r_leftMove_per_burst);
                M_AXI4_ARID   <= ddr2sram_ID;
                if(r_addr_burst_times_already < (r_addr_burst_times-1)) begin
                    M_AXI4_ARLEN <= 8'd255;
                end
                else begin
                    M_AXI4_ARLEN <= r_addr_last_len-1;
                end
                M_AXI4_ARVALID <= 1'b1;
                if(M_AXI4_ARVALID == 1'b1 && M_AXI4_ARREADY == 1'b1) begin
                    if(r_addr_burst_times_already < (r_addr_burst_times-1)) begin
                        r_addr_burst_times_already <= r_addr_burst_times_already + 8'd1;
                    end
                    else begin
                        r_addr_burst_times_already  <= 8'd0;
                        r_addr_finished             <= 1'b1;
                        M_AXI4_ARVALID              <= 1'b0;
                    end
                end
            end
        endcase
    end
end
                
//read_data状态机
//一段
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        r_data_cs <= R_DATA_IDLE;
    end
    else begin
        r_data_cs <= r_data_ns;
    end
end
//二段
always_comb begin
    r_data_ns = r_data_cs;
    case(r_data_cs)
        R_DATA_IDLE:begin
            if(ddr2sram_data_routing_empty == 0) begin
                r_data_ns = R_DATA_RD_CMD;
            end
        end
        R_DATA_RD_CMD:begin
            if(ddr2sram_data_routing_dout[1:0] == 2'd0)begin
                r_data_ns = R_DATA_RD_RCV;
            end
            else begin
                r_data_ns = R_DATA_IDLE;
            end
        end
        R_DATA_RD_RCV:begin
            if((M_AXI4_RVALID == 1'b1 && M_AXI4_RREADY == 1'b1)&&(M_AXI4_RLAST == 1'b1)&&(r_data_burst_times_already >= (r_data_burst_times-1))) begin
                r_data_ns = R_DATA_IDLE;
            end
        end
    endcase
end
//三段
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        M_AXI4_RREADY               <= '0;
        r_data_beat_times_already   <= '0;
        r_data_burst_times_already  <= '0;
        r_data_burst_times          <= '0;
        r_data_finished             <= '0;
        r_data_pointer              <= '0;
        ddr2sram_data_routing_rd_en <= '1;
        para_addr                   <= '0;
        para_cs                     <= 1'b1;
        para_wr                     <= 1'b1;
        RRESP_err                   <= '0;
        para_din                    <= '0;
        core_cmd_error_data         <= '0;
    end
    else begin
        ddr2sram_data_routing_rd_en <= 1'b1;
        M_AXI4_RREADY               <= 1'b0;
        r_data_finished             <= 1'b0;
        para_cs                     <= 1'b1;
        RRESP_err                   <= 2'd0;
        core_cmd_error_data         <= 1'b0;
        case(r_data_cs)
            R_DATA_IDLE:begin
                r_data_beat_times_already   <= 8'd0;
                r_data_burst_times_already  <= 8'd0;
                if(ddr2sram_data_routing_empty == 0) begin
                    ddr2sram_data_routing_rd_en <= 1'b0;
                end
            end
            R_DATA_RD_CMD:begin
                if(ddr2sram_data_routing_dout[1:0] == 2'd0)begin//para
                    r_data_pointer              <= R_DATA_PARA;
                    r_data_burst_times          <= 8'd13;
                end
                else begin//else
                    core_cmd_error_data <= 1'b1;
                end
            end
            R_DATA_RD_RCV:begin
                M_AXI4_RREADY <= 1'b1;
                if(M_AXI4_RVALID == 1'b1 && M_AXI4_RREADY == 1'b1)begin
                    RRESP_err <= M_AXI4_RRESP;
                    if(ddr2sram_data_routing_dout[1:0] == 2'd0)begin//para
                        para_addr <= {r_data_burst_times_already[3:0], r_data_beat_times_already};//读事务数据握手无需基地址，因为数据在sram都是从0地址开始写入的
                        para_cs <= 1'b0;
                        para_wr <= 1'b0;
                        para_din<= M_AXI4_RDATA;
                    end
                    r_data_beat_times_already <= r_data_beat_times_already + 8'd1;
                    if(M_AXI4_RLAST == 1'b1) begin
                        if(r_data_burst_times_already < (r_data_burst_times-1))begin
                            r_data_burst_times_already <= r_data_burst_times_already + 8'd1;
                        end
                        else begin
                            r_data_burst_times_already <= 8'd0;
                            r_data_finished             <= 1'b1;
                            M_AXI4_RREADY               <= 1'b0;
                        end
                    end
                end
            end
        endcase
    end
end
`ifdef SIMULATION
property p_full_burst_256_beats;
    @(posedge clk) disable iff (!rst_n)
    ((r_data_cs == R_DATA_RD_RCV) && M_AXI4_RVALID && M_AXI4_RREADY && M_AXI4_RLAST &&
     (r_data_burst_times_already < (r_data_burst_times - 1)))
    |->
    (r_data_beat_times_already == 8'd255);
endproperty
assert property (p_full_burst_256_beats);
`endif





sync_fifo ddr2sram_cmd #(
    .WIDTH      (DDR2SRAM_CMD_FIFO_WIDTH),
    .DEPTH      (DDR2SRAM_CMD_FIFO_DEPTH)
)
(
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (ddr2sram_cmd_wr_en ),
    .rd_en  (ddr2sram_cmd_rd_en ),
    .din    (ddr2sram_cmd_din   ),
    .dout   (ddr2sram_cmd_dout  ),
    .full   (ddr2sram_cmd_full  ),
    .empty  (ddr2sram_cmd_empty )
);

sync_fifo ddr2sram_addr_routing #(
    .WIDTH      (DDR2SRAM_CMD_FIFO_WIDTH),
    .DEPTH      (DDR2SRAM_CMD_FIFO_DEPTH)
)
(
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (ddr2sram_addr_routing_wr_en ),
    .rd_en  (ddr2sram_addr_routing_rd_en ),
    .din    (ddr2sram_addr_routing_din   ),
    .dout   (ddr2sram_addr_routing_dout  ),
    .full   (ddr2sram_addr_routing_full  ),
    .empty  (ddr2sram_addr_routing_empty )
);

sync_fifo ddr2sram_data_routing #(
    .WIDTH      (DDR2SRAM_CMD_FIFO_WIDTH),
    .DEPTH      (DDR2SRAM_CMD_FIFO_DEPTH)
)
(
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (ddr2sram_data_routing_wr_en ),
    .rd_en  (ddr2sram_data_routing_rd_en ),
    .din    (ddr2sram_data_routing_din   ),
    .dout   (ddr2sram_data_routing_dout  ),
    .full   (ddr2sram_data_routing_full  ),
    .empty  (ddr2sram_data_routing_empty )
);

para_sram u_para_sram
(
    .clk                (clk)               ,
    .para_cs            (para_cs)           ,// 低有效片选
    .para_wr            (para_wr)           ,// 低有效写使能
    .para_addr          (para_addr)         ,// 地址
    .para_din           (para_din)          ,// 数据输入
    .para_dout_final    (para_dout_final)    // 最终数据输出
);

endmodule