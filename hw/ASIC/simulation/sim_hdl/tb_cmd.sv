`timescale 1ns/1ps
module tb_cmd #(
    parameter int TB_CMD_IN_FIFO_WIDTH = 48,
    parameter int TB_CMD_IN_FIFO_DEPTH = 10,
    parameter int ADDR_WIDTH           = 5    // channel0~4 <<2 = 0x0~0x10，需5位
)(
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              tb_cmd_in_fifo_wr,
    //命令下达fifo，格式：[7:0]=0写/1读, [15:8]=通道0~4, [47:16]=32bit数据
    input  logic [TB_CMD_IN_FIFO_WIDTH-1:0]   tb_cmd_in_fifo_din,
    output logic                              tb_cmd_in_fifo_full,
    //读数据结果回传fifo
    input  logic                              tb_cmd_out_fifo_rd,
    output logic [TB_CMD_IN_FIFO_WIDTH-1:0]   tb_cmd_out_fifo_dout,
    output logic                              tb_cmd_out_fifo_empty,
    // ---- 错误定位：bit0=命令解析, bit1=写响应B错误, bit2=读数据R错误/读命令fifo满
    output logic [2:0]                        err_state,
    //AXI4-Lite Master
    output logic [ADDR_WIDTH-1:0]             m_axi_awaddr,
    output logic                              m_axi_awvalid,
    input  logic                              m_axi_awready,
    output logic [31:0]                       m_axi_wdata,
    output logic [3:0]                        m_axi_wstrb,
    output logic                              m_axi_wvalid,
    input  logic                              m_axi_wready,
    input  logic [1:0]                        m_axi_bresp,
    input  logic                              m_axi_bvalid,
    output logic                              m_axi_bready,
    output logic [ADDR_WIDTH-1:0]             m_axi_araddr,
    output logic                              m_axi_arvalid,
    input  logic                              m_axi_arready,
    input  logic [31:0]                       m_axi_rdata,
    input  logic [1:0]                        m_axi_rresp,
    input  logic                              m_axi_rvalid,
    output logic                              m_axi_rready,
    // ---- 忙状态：tb_top 判断读/写是否完成 ----
    output logic                              wr_busy,
    output logic                              rd_busy
);

//================ enum 定义 ================
//================ 命令路由状态机 ================
enum logic [0:0] {
    TB_CMD_IN_IDLE,
    TB_CMD_IN_READ
} tb_cmd_in_cs, tb_cmd_in_ns;

//================ 写地址 AW 状态机 ================
enum logic [0:0] {
    TB_CMD_IN_ADDR_IDLE,
    TB_CMD_IN_ADDR_READ
} tb_cmd_in_addr_cs, tb_cmd_in_addr_ns;

//================ 写数据 W 状态机 ================
enum logic [0:0] {
    TB_CMD_IN_DATA_IDLE,
    TB_CMD_IN_DATA_READ
} tb_cmd_in_data_cs, tb_cmd_in_data_ns;

//================ 读地址 AR 状态机 ================
enum logic [0:0] {
    TB_CMD_OUT_ADDR_IDLE,
    TB_CMD_OUT_ADDR_READ
} tb_cmd_out_addr_cs, tb_cmd_out_addr_ns;

// 命令 FIFO
logic                              tb_cmd_in_fifo_rd, tb_cmd_in_fifo_empty;
logic [TB_CMD_IN_FIFO_WIDTH-1:0]   tb_cmd_in_fifo_dout;

// 写地址 FIFO（AW 源）
logic                              tb_cmd_in_addr_fifo_wr, tb_cmd_in_addr_fifo_rd;
logic [TB_CMD_IN_FIFO_WIDTH-1:0]   tb_cmd_in_addr_fifo_din, tb_cmd_in_addr_fifo_dout;
logic                              tb_cmd_in_addr_fifo_full, tb_cmd_in_addr_fifo_empty;

// 写数据 FIFO（W 源）
logic                              tb_cmd_in_data_fifo_wr, tb_cmd_in_data_fifo_rd;
logic [TB_CMD_IN_FIFO_WIDTH-1:0]   tb_cmd_in_data_fifo_din, tb_cmd_in_data_fifo_dout;
logic                              tb_cmd_in_data_fifo_full, tb_cmd_in_data_fifo_empty;

// 读地址 FIFO（AR 源）
logic                              tb_cmd_out_addr_fifo_wr, tb_cmd_out_addr_fifo_rd;
logic [TB_CMD_IN_FIFO_WIDTH-1:0]   tb_cmd_out_addr_fifo_din, tb_cmd_out_addr_fifo_dout;
logic                              tb_cmd_out_addr_fifo_full, tb_cmd_out_addr_fifo_empty;

// 读通道号配对 FIFO（读数据按序返回，用它把 rdata 与 channel 配对）
logic                              rd_resp_fifo_wr, rd_resp_fifo_rd;
logic [7:0]                        rd_resp_fifo_din, rd_resp_fifo_dout;
logic                              rd_resp_fifo_full, rd_resp_fifo_empty;

// 结果 FIFO（回 tb_top）
logic                              tb_cmd_out_fifo_wr;
logic [TB_CMD_IN_FIFO_WIDTH-1:0]   tb_cmd_out_fifo_din;
logic                              tb_cmd_out_fifo_full;

// issued/done 计数（加宽，避免长仿真回绕）
logic [31:0]                       wr_issued, wr_done;
logic [31:0]                       rd_issued, rd_done;

// 错误 sticky 位（分属不同 always_ff，避免多重驱动）
logic                              err_full;   // 读/写握手指令下发状态机满
logic                              err_b;       // 写响应错误
logic                              err_r;       // 读数据错误/结果满

// rdata 延迟一拍，与 rd_resp fifo 队头对齐
logic        rvalid_d1;
logic [31:0] rdata_d1;

assign err_state    = {err_r, err_b, err_full};
// 忙状态 = 已分配 != 已完成
assign wr_busy = (wr_issued != wr_done);
assign rd_busy = (rd_issued != rd_done);
assign m_axi_bready = 1'b1;
assign m_axi_rready    = 1'b1;
// 收到读数据当拍弹出配对 channel（低有效）
assign rd_resp_fifo_rd = ~(m_axi_rvalid && m_axi_rready);
//================ FWFT FIFO 读使能（低有效，即用即弹）================
//FWFT下 empty==0 时 dout 已是队头，无需预读一拍；
//故在真正使用 dout 的那一拍（READ 态）拉低，把队头消费掉。
assign tb_cmd_in_fifo_rd       = ~((tb_cmd_in_cs       == TB_CMD_IN_READ)       && !tb_cmd_in_fifo_empty);
//AW/W/AR：需等握手成功那一拍才能弹出，否则 dout 提前变化会破坏正在发的地址/数据
assign tb_cmd_in_addr_fifo_rd  = ~((tb_cmd_in_addr_cs  == TB_CMD_IN_ADDR_READ)  && !tb_cmd_in_addr_fifo_empty
                                   && m_axi_awvalid && m_axi_awready);
assign tb_cmd_in_data_fifo_rd  = ~((tb_cmd_in_data_cs  == TB_CMD_IN_DATA_READ)  && !tb_cmd_in_data_fifo_empty
                                   && m_axi_wvalid && m_axi_wready);
assign tb_cmd_out_addr_fifo_rd = ~((tb_cmd_out_addr_cs == TB_CMD_OUT_ADDR_READ) && !tb_cmd_out_addr_fifo_empty
                                   && m_axi_arvalid && m_axi_arready);

// ---- 命令路由状态机 ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        tb_cmd_in_cs <= TB_CMD_IN_IDLE;
    end
    else begin
        tb_cmd_in_cs <= tb_cmd_in_ns;
    end
end

always_comb begin
    tb_cmd_in_ns = tb_cmd_in_cs;
    case (tb_cmd_in_cs)
        TB_CMD_IN_IDLE: begin
            if (!tb_cmd_in_fifo_empty) begin
                tb_cmd_in_ns = TB_CMD_IN_READ;
            end
        end
        TB_CMD_IN_READ: begin
            tb_cmd_in_ns = TB_CMD_IN_IDLE;
        end
        default: begin
            tb_cmd_in_ns = tb_cmd_in_cs;
        end
    endcase
end

always_ff @(posedge clk) begin
    if (!rst_n) begin
        err_full                <= 1'b0;
        wr_issued                <= '0;
        rd_issued                <= '0;
        tb_cmd_in_addr_fifo_wr   <= 1'b1;   // 低有效：默认不写
        tb_cmd_in_addr_fifo_din  <= '0;
        tb_cmd_in_data_fifo_wr   <= 1'b1;
        tb_cmd_in_data_fifo_din  <= '0;
        tb_cmd_out_addr_fifo_wr  <= 1'b1;
        tb_cmd_out_addr_fifo_din <= '0;
    end
    else begin
        tb_cmd_in_addr_fifo_wr   <= 1'b1;
        tb_cmd_in_data_fifo_wr   <= 1'b1;
        tb_cmd_out_addr_fifo_wr  <= 1'b1;
        case (tb_cmd_in_cs)
            TB_CMD_IN_READ: begin
                if (tb_cmd_in_fifo_dout[7:0] == 8'h00) begin          // 写
                    if (tb_cmd_in_addr_fifo_full || tb_cmd_in_data_fifo_full) begin
                        err_full <= 1'b1;
                    end
                    else begin
                        wr_issued               <= wr_issued + 1'b1;
                        tb_cmd_in_addr_fifo_wr  <= 1'b0;
                        tb_cmd_in_addr_fifo_din <= tb_cmd_in_fifo_dout;
                        tb_cmd_in_data_fifo_wr  <= 1'b0;
                        tb_cmd_in_data_fifo_din <= tb_cmd_in_fifo_dout;
                    end
                end
                else begin                                           // 读
                    if (tb_cmd_out_addr_fifo_full) begin
                        err_full <= 1'b1;
                    end
                    else begin
                        rd_issued               <= rd_issued + 1'b1;
                        tb_cmd_out_addr_fifo_wr  <= 1'b0;
                        tb_cmd_out_addr_fifo_din <= tb_cmd_in_fifo_dout;
                    end
                end
            end
            default: begin
            end
        endcase
    end
end

// ---- 写地址 AW 状态机 ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        tb_cmd_in_addr_cs <= TB_CMD_IN_ADDR_IDLE;
    end
    else begin
        tb_cmd_in_addr_cs <= tb_cmd_in_addr_ns;
    end
end

always_comb begin
    tb_cmd_in_addr_ns = tb_cmd_in_addr_cs;
    case (tb_cmd_in_addr_cs)
        TB_CMD_IN_ADDR_IDLE: begin
            if (!tb_cmd_in_addr_fifo_empty) begin
                tb_cmd_in_addr_ns = TB_CMD_IN_ADDR_READ;
            end
        end
        TB_CMD_IN_ADDR_READ: begin
            if (m_axi_awvalid && m_axi_awready) begin
                tb_cmd_in_addr_ns = TB_CMD_IN_ADDR_IDLE;
            end
        end
        default: begin
            tb_cmd_in_addr_ns = tb_cmd_in_addr_cs;
        end
    endcase
end

always_ff @(posedge clk) begin
    if (!rst_n) begin
        m_axi_awvalid <= 1'b0;
        m_axi_awaddr  <= '0;
    end
    else begin
        case (tb_cmd_in_addr_cs)
            TB_CMD_IN_ADDR_IDLE: begin
                m_axi_awvalid <= 1'b0;
            end
            TB_CMD_IN_ADDR_READ: begin
                m_axi_awvalid <= 1'b1;
                m_axi_awaddr  <= ADDR_WIDTH'(tb_cmd_in_addr_fifo_dout[15:8] << 2);
                if (m_axi_awvalid && m_axi_awready) begin
                    m_axi_awvalid <= 1'b0;
                end
            end
            default: begin
                m_axi_awvalid <= 1'b0;
            end
        endcase
    end
end

// ---- 写数据 W 状态机 ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        tb_cmd_in_data_cs <= TB_CMD_IN_DATA_IDLE;
    end
    else begin
        tb_cmd_in_data_cs <= tb_cmd_in_data_ns;
    end
end

always_comb begin
    tb_cmd_in_data_ns = tb_cmd_in_data_cs;
    case (tb_cmd_in_data_cs)
        TB_CMD_IN_DATA_IDLE: begin
            if (!tb_cmd_in_data_fifo_empty) begin
                tb_cmd_in_data_ns = TB_CMD_IN_DATA_READ;
            end
        end
        TB_CMD_IN_DATA_READ: begin
            if (m_axi_wvalid && m_axi_wready) begin
                tb_cmd_in_data_ns = TB_CMD_IN_DATA_IDLE;
            end
        end
        default: begin
            tb_cmd_in_data_ns = tb_cmd_in_data_cs;
        end
    endcase
end

always_ff @(posedge clk) begin
    if (!rst_n) begin
        m_axi_wvalid <= 1'b0;
        m_axi_wdata  <= '0;
        m_axi_wstrb  <= '0;
    end
    else begin
        case (tb_cmd_in_data_cs)
            TB_CMD_IN_DATA_IDLE: begin
                m_axi_wvalid <= 1'b0;
            end
            TB_CMD_IN_DATA_READ: begin
                m_axi_wvalid <= 1'b1;
                m_axi_wdata  <= tb_cmd_in_data_fifo_dout[47:16];
                m_axi_wstrb  <= 4'hF;   // 32bit 全字节有效
                if (m_axi_wvalid && m_axi_wready) begin
                    m_axi_wvalid <= 1'b0;
                end
            end
            default: begin
                m_axi_wvalid <= 1'b0;
            end
        endcase
    end
end

// ---- 写响应 B ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        wr_done <= '0;
        err_b   <= 1'b0;
    end
    else if (m_axi_bvalid && m_axi_bready) begin
        wr_done <= wr_done + 1'b1;
        if (m_axi_bresp != 2'b00) begin
            err_b <= 1'b1;
        end
    end
end

// ---- 读地址 AR 状态机 ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        tb_cmd_out_addr_cs <= TB_CMD_OUT_ADDR_IDLE;
    end
    else begin
        tb_cmd_out_addr_cs <= tb_cmd_out_addr_ns;
    end
end

always_comb begin
    tb_cmd_out_addr_ns = tb_cmd_out_addr_cs;
    case (tb_cmd_out_addr_cs)
        TB_CMD_OUT_ADDR_IDLE: begin
            if (!tb_cmd_out_addr_fifo_empty) begin
                tb_cmd_out_addr_ns = TB_CMD_OUT_ADDR_READ;
            end
        end
        TB_CMD_OUT_ADDR_READ: begin
            if (m_axi_arvalid && m_axi_arready) begin
                tb_cmd_out_addr_ns = TB_CMD_OUT_ADDR_IDLE;
            end
        end
        default: begin
            tb_cmd_out_addr_ns = tb_cmd_out_addr_cs;
        end
    endcase
end

always_ff @(posedge clk) begin
    if (!rst_n) begin
        m_axi_arvalid    <= 1'b0;
        m_axi_araddr     <= '0;
        rd_resp_fifo_wr  <= 1'b1;   // 低有效：默认不写
        rd_resp_fifo_din <= '0;
    end
    else begin
        rd_resp_fifo_wr <= 1'b1;
        case (tb_cmd_out_addr_cs)
            TB_CMD_OUT_ADDR_IDLE: begin
                m_axi_arvalid <= 1'b0;
            end
            TB_CMD_OUT_ADDR_READ: begin
                m_axi_arvalid <= 1'b1;
                m_axi_araddr  <= ADDR_WIDTH'(tb_cmd_out_addr_fifo_dout[15:8] << 2);
                if (m_axi_arvalid && m_axi_arready) begin
                    m_axi_arvalid    <= 1'b0;
                    rd_resp_fifo_wr  <= 1'b0;   // 压入 channel 供配对
                    rd_resp_fifo_din <= tb_cmd_out_addr_fifo_dout[15:8];
                end
            end
            default: begin
                m_axi_arvalid <= 1'b0;
            end
        endcase
    end
end

// ---- 读数据 R ----
always_ff @(posedge clk) begin
    if (!rst_n) begin
        rvalid_d1 <= 1'b0;
        rdata_d1  <= '0;
    end
    else begin
        rvalid_d1 <= m_axi_rvalid && m_axi_rready;
        rdata_d1  <= m_axi_rdata;
    end
end

always_ff @(posedge clk) begin
    if (!rst_n) begin
        rd_done            <= '0;
        err_r              <= 1'b0;
        tb_cmd_out_fifo_wr  <= 1'b1;   // 低有效：默认不写
        tb_cmd_out_fifo_din <= '0;
    end
    else begin
        tb_cmd_out_fifo_wr <= 1'b1;
        if (m_axi_rvalid && m_axi_rready && m_axi_rresp != 2'b00) begin
            err_r <= 1'b1;
        end
        if (rvalid_d1) begin
            rd_done <= rd_done + 1'b1;
            if (tb_cmd_out_fifo_full) begin
                err_r <= 1'b1;
            end
            else begin
                tb_cmd_out_fifo_wr  <= 1'b0;
                tb_cmd_out_fifo_din <= {rdata_d1, rd_resp_fifo_dout, 8'h01};
            end
        end
    end
end

//================ 例化 ================
sync_fifo #(
    .WIDTH(TB_CMD_IN_FIFO_WIDTH),
    .DEPTH(TB_CMD_IN_FIFO_DEPTH)
) u_cmd_in (
    .clk  (clk),
    .rst_n(rst_n),
    .wr_en(tb_cmd_in_fifo_wr),
    .rd_en(tb_cmd_in_fifo_rd),
    .din  (tb_cmd_in_fifo_din),
    .dout (tb_cmd_in_fifo_dout),
    .full (tb_cmd_in_fifo_full),
    .empty(tb_cmd_in_fifo_empty)
);

sync_fifo #(
    .WIDTH(TB_CMD_IN_FIFO_WIDTH),
    .DEPTH(TB_CMD_IN_FIFO_DEPTH)
) u_cmd_in_addr (
    .clk  (clk),
    .rst_n(rst_n),
    .wr_en(tb_cmd_in_addr_fifo_wr),
    .rd_en(tb_cmd_in_addr_fifo_rd),
    .din  (tb_cmd_in_addr_fifo_din),
    .dout (tb_cmd_in_addr_fifo_dout),
    .full (tb_cmd_in_addr_fifo_full),
    .empty(tb_cmd_in_addr_fifo_empty)
);

sync_fifo #(
    .WIDTH(TB_CMD_IN_FIFO_WIDTH),
    .DEPTH(TB_CMD_IN_FIFO_DEPTH)
) u_cmd_in_data (
    .clk  (clk),
    .rst_n(rst_n),
    .wr_en(tb_cmd_in_data_fifo_wr),
    .rd_en(tb_cmd_in_data_fifo_rd),
    .din  (tb_cmd_in_data_fifo_din),
    .dout (tb_cmd_in_data_fifo_dout),
    .full (tb_cmd_in_data_fifo_full),
    .empty(tb_cmd_in_data_fifo_empty)
);

sync_fifo #(
    .WIDTH(TB_CMD_IN_FIFO_WIDTH),
    .DEPTH(TB_CMD_IN_FIFO_DEPTH)
) u_cmd_out_addr (
    .clk  (clk),
    .rst_n(rst_n),
    .wr_en(tb_cmd_out_addr_fifo_wr),
    .rd_en(tb_cmd_out_addr_fifo_rd),
    .din  (tb_cmd_out_addr_fifo_din),
    .dout (tb_cmd_out_addr_fifo_dout),
    .full (tb_cmd_out_addr_fifo_full),
    .empty(tb_cmd_out_addr_fifo_empty)
);

sync_fifo #(
    .WIDTH(8),
    .DEPTH(TB_CMD_IN_FIFO_DEPTH)
) u_rd_resp (
    .clk  (clk),
    .rst_n(rst_n),
    .wr_en(rd_resp_fifo_wr),
    .rd_en(rd_resp_fifo_rd),
    .din  (rd_resp_fifo_din),
    .dout (rd_resp_fifo_dout),
    .full (rd_resp_fifo_full),
    .empty(rd_resp_fifo_empty)
);

sync_fifo #(
    .WIDTH(TB_CMD_IN_FIFO_WIDTH),
    .DEPTH(TB_CMD_IN_FIFO_DEPTH)
) u_cmd_out (
    .clk  (clk),
    .rst_n(rst_n),
    .wr_en(tb_cmd_out_fifo_wr),
    .rd_en(tb_cmd_out_fifo_rd),
    .din  (tb_cmd_out_fifo_din),
    .dout (tb_cmd_out_fifo_dout),
    .full (tb_cmd_out_fifo_full),
    .empty(tb_cmd_out_fifo_empty)
);

endmodule