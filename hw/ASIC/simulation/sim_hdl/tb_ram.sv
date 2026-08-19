`timescale 1ns / 1ps
//======================================================================
// tb_ram：CPU 侧 RAM 仿真模型，自带 AXI4 从端逻辑
//
// 功能
//   - 2MB 内存，128bit 一行共 131072 行，地址从 0x0 映射
//   - 对接 DUT（top.sv / sram_mgr.sv）的 AXI4 主端 M_AXI4_*
//   - 地址握手与数据握手完全解耦：AR/AW 只要队列不满即可连续接收，
//     与 R 数据返回 / W 数据接收进度无关（匹配 sram_mgr 连发 13 笔 AR 的流水行为）
//   - 越界访问（突发结束地址越过 2MB）整笔返回 SLVERR：写不落内存、读返回全 0
//
// 事务生命周期（读通道为例，写通道对称）
//   一笔事务分四步，分布在入队拍与状态机的三个状态中：
//
//     ① 入队拍（AR 握手） ：{oob, id, len, addr} 写入 rdq_mem[tail]，
//                            oob 在本拍即冻结，R 通道异步返回时直接引用
//     ② 装载拍（RD_IDLE） ：rd_cur <= rdq_mem[head]，同一拍 head+1 弹出。
//                            非阻塞赋值读旧 head，弹出的正是装载的这笔
//     ③ RD_SEND          ：逐拍 rdata = mem[addr + beat*16]，beat==len 时 rlast=1
//     ④ R 握手完成        ：回 RD_IDLE，装载下一笔
//
//   维护时不可破坏的时序契约：
//     - 装载条件 rd_load == (rd_cs==RD_IDLE && rdq_cnt!=0) 与 head 推进同拍
//     - rd_cur 仅在"装载拍之后、回到 RD_IDLE 之前"有效
//     - 每拍固定 16 字节（忽略 arsize/awsize），行索引 = 拍地址[DATA_BYTES_W +: MEM_INDEX_W]
//======================================================================
module tb_ram #(
    parameter int S_AXI_ID_WIDTH    = 6,
    parameter int S_AXI_ADDR_WIDTH  = 32,
    parameter int S_AXI_DATA_WIDTH  = 128,
    parameter int MEM_SIZE_BYTES    = 2 * 1024 * 1024,  // 模拟 CPU RAM 大小：2MB
    parameter int RD_QUEUE_DEPTH    = 16,               // 读事务队列深度：须容纳 sram_mgr 单次下发的连续 AR 序列（当前 13 笔）
    parameter int WR_QUEUE_DEPTH    = 16                // 写事务队列深度：通用流水深度
)(
    input  logic                                clk,
    input  logic                                rst_n,

    //================ 写地址通道 AW ================
    input  logic [S_AXI_ADDR_WIDTH-1:0]         s_axi_awaddr,
    input  logic [7:0]                          s_axi_awlen,
    input  logic [2:0]                          s_axi_awsize,
    input  logic [1:0]                          s_axi_awburst,
    input  logic [1:0]                          s_axi_awlock,
    input  logic [3:0]                          s_axi_awcache,
    input  logic [2:0]                          s_axi_awprot,
    input  logic [3:0]                          s_axi_awqos,
    input  logic [3:0]                          s_axi_awregion,
    input  logic [S_AXI_ID_WIDTH-1:0]           s_axi_awid,
    input  logic                                s_axi_awvalid,
    output logic                                s_axi_awready,

    //================ 写数据通道 W ================
    input  logic [S_AXI_DATA_WIDTH-1:0]         s_axi_wdata,
    input  logic [S_AXI_DATA_WIDTH/8-1:0]       s_axi_wstrb,
    input  logic                                s_axi_wlast,
    input  logic                                s_axi_wvalid,
    output logic                                s_axi_wready,

    //================ 写响应通道 B ================
    output logic [S_AXI_ID_WIDTH-1:0]          s_axi_bid,
    output logic [1:0]                          s_axi_bresp,
    output logic                                s_axi_bvalid,
    input  logic                                s_axi_bready,

    //================ 读地址通道 AR ================
    input  logic [S_AXI_ADDR_WIDTH-1:0]         s_axi_araddr,
    input  logic [7:0]                          s_axi_arlen,
    input  logic [2:0]                          s_axi_arsize,
    input  logic [1:0]                          s_axi_arburst,
    input  logic [1:0]                          s_axi_arlock,
    input  logic [3:0]                          s_axi_arcache,
    input  logic [2:0]                          s_axi_arprot,
    input  logic [3:0]                          s_axi_arqos,
    input  logic [3:0]                          s_axi_arregion,
    input  logic [S_AXI_ID_WIDTH-1:0]           s_axi_arid,
    input  logic                                s_axi_arvalid,
    output logic                                s_axi_arready,

    //================ 读数据通道 R ================
    output logic [S_AXI_DATA_WIDTH-1:0]         s_axi_rdata,
    output logic [S_AXI_ID_WIDTH-1:0]           s_axi_rid,
    output logic                                s_axi_rlast,
    output logic [1:0]                          s_axi_rresp,
    output logic                                s_axi_rvalid,
    input  logic                                s_axi_rready
);

//================ 本地参数 ================
localparam int DATA_BYTES   = S_AXI_DATA_WIDTH / 8;             // 每次传输字节数 16
localparam int DATA_BYTES_W = $clog2(DATA_BYTES);               // 字节偏移位数 4
localparam int MEM_DEPTH    = MEM_SIZE_BYTES / DATA_BYTES;      // 存储行数 131072
localparam int MEM_INDEX_W  = $clog2(MEM_DEPTH);                // 存储行索引位宽 17
localparam int RDQ_PTR_W    = $clog2(RD_QUEUE_DEPTH);           // 读队列头尾指针位宽
localparam int WRQ_PTR_W    = $clog2(WR_QUEUE_DEPTH);           // 写队列头尾指针位宽

// AXI RRESP/BRESP 编码
localparam logic [1:0] RESP_OKAY   = 2'b00;                     // 正常访问
localparam logic [1:0] RESP_SLVERR = 2'b10;                     // 从端错误：越界访问

//================ 队列条目 typedef ================
// 读事务条目：{oob, id, len, addr}
typedef struct packed {
    logic                          oob ;   // 越界标记：突发越过内存末端，整笔以 SLVERR 响应
    logic [S_AXI_ID_WIDTH-1:0]     id  ;
    logic [7:0]                    len ;
    logic [S_AXI_ADDR_WIDTH-1:0]   addr;
} rd_req_t;

// 写事务条目：{oob, id, addr}（W 通道靠 wlast 收尾，无需 len）
typedef struct packed {
    logic                          oob ;
    logic [S_AXI_ID_WIDTH-1:0]     id  ;
    logic [S_AXI_ADDR_WIDTH-1:0]   addr;
} wr_req_t;

//================ enum 定义 ================
// 写事务状态机：从队列加载一笔写突发，接收 W 数据，返回 B 响应
enum logic [1:0] {
    WR_IDLE,   //等待队列中有写事务
    WR_RCV,    //接收 W 数据并写入内存
    WR_RESP    //返回 B 响应
} wr_cs, wr_ns;

// 读事务状态机：从队列加载一笔读突发，逐拍返回 R 数据
enum logic [1:0] {
    RD_IDLE,   //等待队列中有读事务
    RD_SEND    //返回 R 数据直至 RLAST
} rd_cs, rd_ns;

//================ 内部信号 ================
// 读事务队列（AR 连续入队，R 按序出队）
rd_req_t                          rdq_mem [RD_QUEUE_DEPTH]       ;
logic [RDQ_PTR_W-1:0]             rdq_head                       ;
logic [RDQ_PTR_W-1:0]             rdq_tail                       ;
logic [RDQ_PTR_W:0]               rdq_cnt                        ;

// 写事务队列（AW 连续入队，W/B 按序出队）
wr_req_t                          wrq_mem [WR_QUEUE_DEPTH]       ;
logic [WRQ_PTR_W-1:0]             wrq_head                       ;
logic [WRQ_PTR_W-1:0]             wrq_tail                       ;
logic [WRQ_PTR_W:0]               wrq_cnt                        ;

// 当前读写事务（从队列头装载）
rd_req_t                          rd_cur                         ;
wr_req_t                          wr_cur                         ;
logic [7:0]                       rd_beat_cnt                    ;//当前读突发已返回节拍数
logic [7:0]                       wr_beat_cnt                    ;//当前写突发已接收节拍数

// 握手接受/装载组合标志
logic                             aw_accept                      ;//AW 握手成功
logic                             w_last_hsk                     ;//W 最后一拍握手成功
logic                             b_hsk                          ;//B 握手成功
logic                             wr_load                        ;//从写队列装载当前写事务
logic                             ar_accept                      ;//AR 握手成功
logic                             r_last_hsk                     ;//R 最后一拍握手成功
logic                             rd_load                        ;//从读队列装载当前读事务

// 越界检测结果（在地址握手拍冻结，随事务入队）
logic                             aw_oob                         ;
logic                             ar_oob                         ;

// 内存数组：2MB，128bit 一行
logic [S_AXI_DATA_WIDTH-1:0]      mem [MEM_DEPTH] = '{default:'0};

// 组合计算：当前拍字节地址 / 存储行索引
logic [S_AXI_ADDR_WIDTH-1:0]      wr_beat_addr                   ;
logic [S_AXI_ADDR_WIDTH-1:0]      rd_beat_addr                   ;
logic [MEM_INDEX_W-1:0]           wr_mem_index                   ;
logic [MEM_INDEX_W-1:0]           rd_mem_index                   ;

//================ 地址计算辅助函数 ================
// 突发内第 beat 拍（从 0 计）的字节地址：start_addr + beat * DATA_BYTES
function automatic logic [S_AXI_ADDR_WIDTH-1:0] burst_beat_addr(
    input logic [S_AXI_ADDR_WIDTH-1:0] start_addr,
    input logic [7:0]                  beat
);
    burst_beat_addr = start_addr + (S_AXI_ADDR_WIDTH'(beat) << DATA_BYTES_W);
endfunction

// 突发占用区间 [start_addr, end) 的右端点：start_addr + (len+1) * DATA_BYTES
// 即"最后一拍之后第一个字节"的地址 —— 越界判断的精确边界
function automatic logic [S_AXI_ADDR_WIDTH-1:0] burst_end_addr(
    input logic [S_AXI_ADDR_WIDTH-1:0] start_addr,
    input logic [7:0]                  len
);
    burst_end_addr = start_addr + ((S_AXI_ADDR_WIDTH'(len) + S_AXI_ADDR_WIDTH'(1)) << DATA_BYTES_W);
endfunction

//================ assign ================
//---- 各通道握手成功标志 ----
assign aw_accept  = s_axi_awvalid && s_axi_awready;
assign w_last_hsk = s_axi_wvalid && s_axi_wready && s_axi_wlast;
assign b_hsk      = s_axi_bvalid && s_axi_bready;
assign ar_accept  = s_axi_arvalid && s_axi_arready;
assign r_last_hsk = s_axi_rvalid && s_axi_rready && s_axi_rlast;

//---- 队列弹出条件：状态机空闲且队列非空 ----
assign wr_load = (wr_cs == WR_IDLE) && (wrq_cnt != 0);
assign rd_load = (rd_cs == RD_IDLE) && (rdq_cnt != 0);

//---- 越界检测：突发结束地址越过内存末端（在入队拍冻结）----
assign ar_oob = burst_end_addr(s_axi_araddr, s_axi_arlen) > S_AXI_ADDR_WIDTH'(MEM_SIZE_BYTES);
assign aw_oob = burst_end_addr(s_axi_awaddr, s_axi_awlen) > S_AXI_ADDR_WIDTH'(MEM_SIZE_BYTES);

//---- 写通道（从端）----
// AW 仅受写队列深度限制，独立于 W/B 进度连续接收
assign s_axi_awready = (wrq_cnt < WR_QUEUE_DEPTH);
assign s_axi_wready  = (wr_cs == WR_RCV);
assign s_axi_bvalid  = (wr_cs == WR_RESP);
assign s_axi_bresp   = wr_cur.oob ? RESP_SLVERR : RESP_OKAY;
assign s_axi_bid     = S_AXI_ID_WIDTH'(wr_cur.id);

//---- 读通道（从端）----
// AR 仅受读队列深度限制，独立于 R 数据进度连续接收（地址/数据握手并行）
assign s_axi_arready = (rdq_cnt < RD_QUEUE_DEPTH);
assign s_axi_rvalid  = (rd_cs == RD_SEND);
assign s_axi_rlast   = (rd_cs == RD_SEND) && (rd_beat_cnt == rd_cur.len);
assign s_axi_rresp   = rd_cur.oob ? RESP_SLVERR : RESP_OKAY;
assign s_axi_rid     = S_AXI_ID_WIDTH'(rd_cur.id);
assign s_axi_rdata   = rd_cur.oob ? '0 : mem[rd_mem_index];

//---- 内部节拍地址 / 存储行索引 ----
// AXI INCR 突发，每拍字节地址按数据总线宽度（DATA_BYTES 字节）递增
assign wr_beat_addr = burst_beat_addr(wr_cur.addr, wr_beat_cnt);
assign rd_beat_addr = burst_beat_addr(rd_cur.addr, rd_beat_cnt);
// 对齐到 DATA_BYTES 字节：低 DATA_BYTES_W bit 为字节偏移，其后 MEM_INDEX_W bit 为存储行索引
assign wr_mem_index = wr_beat_addr[DATA_BYTES_W +: MEM_INDEX_W];
assign rd_mem_index = rd_beat_addr[DATA_BYTES_W +: MEM_INDEX_W];

//================ 读事务队列（AR 入队 / 装载出队） ================
always_ff @(posedge clk) begin
    if (!rst_n) begin
        rdq_head <= '0;
        rdq_tail <= '0;
        rdq_cnt  <= '0;
    end
    else begin
        if (ar_accept) begin
            // AR 每拍一笔连续入队，地址握手不被 R 数据返回阻塞；
            // oob 在本拍冻结，R 通道异步返回时仍使用该结论
            rdq_mem[rdq_tail] <= rd_req_t'{
                oob : ar_oob     ,
                id  : s_axi_arid ,
                len : s_axi_arlen,
                addr: s_axi_araddr
            };
            rdq_tail <= rdq_tail + 1'b1;
        end
        if (rd_load) begin
            rdq_head <= rdq_head + 1'b1;
        end
        // 同拍入队+出队则 cnt 不变
        rdq_cnt <= rdq_cnt + (ar_accept ? 1'b1 : 1'b0) - (rd_load ? 1'b1 : 1'b0);
    end
end

//================ 写事务队列（AW 入队 / 装载出队） ================
always_ff @(posedge clk) begin
    if (!rst_n) begin
        wrq_head <= '0;
        wrq_tail <= '0;
        wrq_cnt  <= '0;
    end
    else begin
        if (aw_accept) begin
            // AW 每拍一笔连续入队，地址握手独立于 W/B 进度
            wrq_mem[wrq_tail] <= wr_req_t'{
                oob : aw_oob    ,
                id  : s_axi_awid,
                addr: s_axi_awaddr
            };
            wrq_tail <= wrq_tail + 1'b1;
        end
        if (wr_load) begin
            wrq_head <= wrq_head + 1'b1;
        end
        // 同拍入队+出队则 cnt 不变
        wrq_cnt <= wrq_cnt + (aw_accept ? 1'b1 : 1'b0) - (wr_load ? 1'b1 : 1'b0);
    end
end

//================ 写事务状态机 ================
//---- 一段：状态寄存器 ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        wr_cs <= WR_IDLE;
    end
    else begin
        wr_cs <= wr_ns;
    end
end

//---- 二段：次态组合逻辑 ----
always_comb begin
    wr_ns = wr_cs;
    case (wr_cs)
        WR_IDLE: begin
            if (wrq_cnt != 0) begin
                wr_ns = WR_RCV;
            end
        end
        WR_RCV: begin
            if (w_last_hsk) begin
                wr_ns = WR_RESP;
            end
        end
        WR_RESP: begin
            if (b_hsk) begin
                wr_ns = WR_IDLE;
            end
        end
        default: begin
            wr_ns = wr_cs;
        end
    endcase
end

//---- 三段：事务装载 ----
// 与 head 弹出同拍（wr_load），非阻塞赋值读旧 head → 弹出的正是装载的这笔
always_ff @(posedge clk) begin
    if (!rst_n) begin
        wr_cur <= '0;
    end
    else if (wr_cs == WR_IDLE && wrq_cnt != 0) begin
        wr_cur <= wrq_mem[wrq_head];
    end
end

//---- 四段：W 节拍计数 ----
// WR_IDLE 拍清零；WR_RCV 每握手一拍 +1
always_ff @(posedge clk) begin
    if (!rst_n) begin
        wr_beat_cnt <= '0;
    end
    else begin
        case (wr_cs)
            WR_IDLE: begin
                wr_beat_cnt <= '0;
            end
            WR_RCV: begin
                if (s_axi_wvalid && s_axi_wready) begin
                    wr_beat_cnt <= wr_beat_cnt + 1'b1;
                end
            end
            default: begin
            end
        endcase
    end
end

//---- 写数据写入内存：按 WSTRB 逐字节掩码，越界事务不落内存 ----
always_ff @(posedge clk) begin
    if(!rst_n)begin
        for (int i = 0; i < MEM_DEPTH; i++) begin
            mem[i] <= {32'(i+12), 32'(i+8), 32'(i+4), 32'(i)};
        end
    end
    else if (rst_n && s_axi_wvalid && s_axi_wready && !wr_cur.oob) begin
        for (int i = 0; i < DATA_BYTES; i++) begin
            if (s_axi_wstrb[i]) begin
                mem[wr_mem_index][i*8 +: 8] <= s_axi_wdata[i*8 +: 8];
            end
        end
    end
end

//================ 读事务状态机 ================
//---- 一段：状态寄存器 ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        rd_cs <= RD_IDLE;
    end
    else begin
        rd_cs <= rd_ns;
    end
end

//---- 二段：次态组合逻辑 ----
always_comb begin
    rd_ns = rd_cs;
    case (rd_cs)
        RD_IDLE: begin
            if (rdq_cnt != 0) begin
                rd_ns = RD_SEND;
            end
        end
        RD_SEND: begin
            if (r_last_hsk) begin
                rd_ns = RD_IDLE;
            end
        end
        default: begin
            rd_ns = rd_cs;
        end
    endcase
end

//---- 三段：事务装载 ----
// 与 head 弹出同拍（rd_load），非阻塞赋值读旧 head → 弹出的正是装载的这笔
always_ff @(posedge clk) begin
    if (!rst_n) begin
        rd_cur <= '0;
    end
    else if (rd_cs == RD_IDLE && rdq_cnt != 0) begin
        rd_cur <= rdq_mem[rdq_head];
    end
end

//---- 四段：R 节拍计数 ----
// RD_IDLE 拍清零；RD_SEND 每握手一拍 +1
always_ff @(posedge clk) begin
    if (!rst_n) begin
        rd_beat_cnt <= '0;
    end
    else begin
        case (rd_cs)
            RD_IDLE: begin
                rd_beat_cnt <= '0;
            end
            RD_SEND: begin
                if (s_axi_rvalid && s_axi_rready) begin
                    rd_beat_cnt <= rd_beat_cnt + 1'b1;
                end
            end
            default: begin
            end
        endcase
    end
end

endmodule
