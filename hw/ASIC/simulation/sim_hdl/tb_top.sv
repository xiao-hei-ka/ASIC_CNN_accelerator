`timescale 1ns/1ps
module tb_top(
);

parameter integer DATA_WIDTH            = 32;
parameter integer REG_COUNT             = 5;
localparam integer ADDR_WIDTH           = (($clog2((DATA_WIDTH/8) * REG_COUNT) < 1) ? 1 : $clog2((DATA_WIDTH/8) * REG_COUNT));

parameter integer C_M_AXI_ID_WIDTH      = 6;
parameter integer C_M_AXI_ADDR_WIDTH    = 32;
parameter integer C_M_AXI_DATA_WIDTH    = 128;

localparam integer TB_CMD_WIDTH         = 48;
localparam integer TB_CMD_DEPTH         = 10;

//top
logic                                   rst_n                       ;
logic                                   S_AXI4_LITE_ACLK           ;
logic                                   S_AXI4_LITE_ARESETN        ;
logic   [ADDR_WIDTH-1 : 0]              S_AXI4_LITE_AWADDR         ;
logic   [2 : 0]                         S_AXI4_LITE_AWPROT         ;
logic                                   S_AXI4_LITE_AWVALID        ;
logic                                   S_AXI4_LITE_AWREADY        ;
logic   [DATA_WIDTH-1 : 0]              S_AXI4_LITE_WDATA          ;
logic   [(DATA_WIDTH/8)-1 : 0]          S_AXI4_LITE_WSTRB          ;
logic                                   S_AXI4_LITE_WVALID         ;
logic                                   S_AXI4_LITE_WREADY         ;
logic   [1 : 0]                         S_AXI4_LITE_BRESP          ;
logic                                   S_AXI4_LITE_BVALID         ;
logic                                   S_AXI4_LITE_BREADY         ;
logic   [ADDR_WIDTH-1 : 0]              S_AXI4_LITE_ARADDR         ;
logic   [2 : 0]                         S_AXI4_LITE_ARPROT         ;
logic                                   S_AXI4_LITE_ARVALID        ;
logic                                   S_AXI4_LITE_ARREADY        ;
logic   [DATA_WIDTH-1 : 0]              S_AXI4_LITE_RDATA          ;
logic   [1 : 0]                         S_AXI4_LITE_RRESP          ;
logic                                   S_AXI4_LITE_RVALID         ;
logic                                   S_AXI4_LITE_RREADY         ;
logic                                   M_AXI4_ACLK                 ;
logic                                   M_AXI4_ARESETN              ;
logic   [C_M_AXI_ADDR_WIDTH-1 : 0]      M_AXI4_AWADDR               ;
logic   [7 : 0]                         M_AXI4_AWLEN                ;
logic                                   M_AXI4_AWREADY              ;
logic                                   M_AXI4_AWVALID              ;
logic   [C_M_AXI_ID_WIDTH-1:0]          M_AXI4_AWID                 ;
logic   [2:0]                           M_AXI4_AWPROT               ;
logic   [2 : 0]                         M_AXI4_AWSIZE               ;
logic   [1 : 0]                         M_AXI4_AWBURST              ;
logic   [1 : 0]                         M_AXI4_AWLOCK               ;
logic   [3 : 0]                         M_AXI4_AWCACHE              ;
logic   [3 : 0]                         M_AXI4_AWQOS                ;
logic   [3 : 0]                         M_AXI4_AWREGION             ;
logic   [C_M_AXI_DATA_WIDTH-1 : 0]      M_AXI4_WDATA                ;
logic   [C_M_AXI_DATA_WIDTH/8-1 : 0]    M_AXI4_WSTRB                ;
logic                                   M_AXI4_WLAST                ;
logic                                   M_AXI4_WREADY               ;
logic                                   M_AXI4_WVALID               ;
logic   [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI4_BID                  ;
logic                                   M_AXI4_BREADY               ;
logic   [1 : 0]                         M_AXI4_BRESP                ;
logic                                   M_AXI4_BVALID               ;
logic   [C_M_AXI_ADDR_WIDTH-1 : 0]      M_AXI4_ARADDR               ;
logic   [7 : 0]                         M_AXI4_ARLEN                ;
logic                                   M_AXI4_ARREADY              ;
logic                                   M_AXI4_ARVALID              ;
logic   [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI4_ARID                 ;
logic   [2 : 0]                         M_AXI4_ARSIZE               ;
logic   [1 : 0]                         M_AXI4_ARBURST              ;
logic   [1 : 0]                         M_AXI4_ARLOCK               ;
logic   [3 : 0]                         M_AXI4_ARCACHE              ;
logic   [2 : 0]                         M_AXI4_ARPROT               ;
logic   [3 : 0]                         M_AXI4_ARQOS                ;
logic   [3 : 0]                         M_AXI4_ARREGION             ;
logic   [C_M_AXI_DATA_WIDTH-1 : 0]      M_AXI4_RDATA                ;
logic   [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI4_RID                  ;
logic                                   M_AXI4_RLAST                ;
logic                                   M_AXI4_RREADY               ;
logic   [1 : 0]                         M_AXI4_RRESP                ;
logic                                   M_AXI4_RVALID               ;

//ttb_cmd
logic                                   tb_cmd_in_fifo_wr   = 1'b1; // 低有效，默认不写
logic   [TB_CMD_WIDTH-1 : 0]            tb_cmd_in_fifo_din   = '0;
logic                                   tb_cmd_in_fifo_full;
logic                                   tb_cmd_out_fifo_rd  = 1'b1; // 低有效，默认不读
logic   [TB_CMD_WIDTH-1 : 0]            tb_cmd_out_fifo_dout;
logic                                   tb_cmd_out_fifo_empty;
logic   [2 : 0]                         tb_cmd_err_state;            // bit0=路由所用fifo满 bit1=B错误 bit2=R错误或返回fifo满
logic                                   tb_cmd_wr_busy;
logic                                   tb_cmd_rd_busy;

assign S_AXI4_LITE_AWPROT = 3'b000;
assign S_AXI4_LITE_ARPROT = 3'b000;


task axi4_lite_wcmd(input logic [7:0] addr, input logic [31:0] data);
    wait(tb_cmd_in_fifo_full == 1'b0);
    @(posedge S_AXI4_LITE_ACLK);
    tb_cmd_in_fifo_din[7:0]     <= 8'h00;   // 0=写命令
    tb_cmd_in_fifo_din[15:8]    <= addr;
    tb_cmd_in_fifo_din[47:16]   <= data;
    tb_cmd_in_fifo_wr           <= 1'b0;
    @(posedge S_AXI4_LITE_ACLK);
    tb_cmd_in_fifo_wr           <= 1'b1;
    // 等命令经 FIFO→路由→wr_issued 递增后再判忙，避免 busy 尚未拉高就穿过
    wait(tb_cmd_wr_busy == 1'b1);
    wait(tb_cmd_wr_busy == 1'b0);
endtask

task axi4_lite_rcmd(input logic [7:0] addr, output logic [31:0] data);
    wait(tb_cmd_in_fifo_full == 1'b0);
    @(posedge S_AXI4_LITE_ACLK);
    tb_cmd_in_fifo_din[7:0]     <= 8'h01;   // 1=读命令
    tb_cmd_in_fifo_din[15:8]    <= addr;
    tb_cmd_in_fifo_wr           <= 1'b0;
    @(posedge S_AXI4_LITE_ACLK);
    tb_cmd_in_fifo_wr           <= 1'b1;
    // 等命令经 FIFO→路由→wr_issued 递增后再判忙，避免 busy 尚未拉高就穿过
    wait(tb_cmd_rd_busy == 1'b1);
    @(posedge S_AXI4_LITE_ACLK iff tb_cmd_rd_busy == 1'b0);
    @(posedge S_AXI4_LITE_ACLK);
    assert (tb_cmd_out_fifo_empty == 1'b0)
    else $error("[AXI4_LITE_RCMD ASSERT FAIL] Read done but out_fifo is empty at time %0t!", $time);
    //FWFT：dout 当前已是队头，先取值再弹出
    data = tb_cmd_out_fifo_dout;
    tb_cmd_out_fifo_rd <= 1'b0;
    @(posedge S_AXI4_LITE_ACLK);
    tb_cmd_out_fifo_rd <= 1'b1;
endtask

initial begin//CPU侧主控逻辑
    #300 axi4_lite_wcmd(8'd0, {12'd0, 4'b0010, 16'h5A5A});
end



initial begin
    S_AXI4_LITE_ACLK = 1'b0;
    forever #5 S_AXI4_LITE_ACLK = ~S_AXI4_LITE_ACLK;
end

initial begin
    M_AXI4_ACLK = 1'b0;
    forever #2.5 M_AXI4_ACLK = ~M_AXI4_ACLK;
end

initial begin
    rst_n              = 1'b0;   // 芯片主复位
    S_AXI4_LITE_ARESETN = 1'b0;  // axi4lite 复位
    M_AXI4_ARESETN      = 1'b0;  // axi4 复位
  #200;                        // 200ns 后同时释放
    rst_n              = 1'b1;
    S_AXI4_LITE_ARESETN = 1'b1;
    M_AXI4_ARESETN      = 1'b1;
end

tb_cmd #
(
    .TB_CMD_IN_FIFO_WIDTH (TB_CMD_WIDTH),
    .TB_CMD_IN_FIFO_DEPTH (TB_CMD_DEPTH),
    .ADDR_WIDTH           (ADDR_WIDTH  )
)
u_tb_cmd
(
    .clk                            (S_AXI4_LITE_ACLK           ),
    .rst_n                          (S_AXI4_LITE_ARESETN & rst_n),

    // 命令/结果 FIFO（控制台驱动）
    .tb_cmd_in_fifo_wr              (tb_cmd_in_fifo_wr          ),
    .tb_cmd_in_fifo_din             (tb_cmd_in_fifo_din         ),
    .tb_cmd_in_fifo_full            (tb_cmd_in_fifo_full        ),
    .tb_cmd_out_fifo_rd             (tb_cmd_out_fifo_rd         ),
    .tb_cmd_out_fifo_dout           (tb_cmd_out_fifo_dout       ),
    .tb_cmd_out_fifo_empty          (tb_cmd_out_fifo_empty      ),
    .err_state                      (tb_cmd_err_state           ),

    // AXI4-Lite master -> top 的 lite slave
    .m_axi_awaddr                   (S_AXI4_LITE_AWADDR         ),
    .m_axi_awvalid                  (S_AXI4_LITE_AWVALID        ),
    .m_axi_awready                  (S_AXI4_LITE_AWREADY        ),
    .m_axi_wdata                    (S_AXI4_LITE_WDATA          ),
    .m_axi_wstrb                    (S_AXI4_LITE_WSTRB          ),
    .m_axi_wvalid                   (S_AXI4_LITE_WVALID         ),
    .m_axi_wready                   (S_AXI4_LITE_WREADY         ),
    .m_axi_bresp                    (S_AXI4_LITE_BRESP          ),
    .m_axi_bvalid                   (S_AXI4_LITE_BVALID         ),
    .m_axi_bready                   (S_AXI4_LITE_BREADY         ),
    .m_axi_araddr                   (S_AXI4_LITE_ARADDR         ),
    .m_axi_arvalid                  (S_AXI4_LITE_ARVALID        ),
    .m_axi_arready                  (S_AXI4_LITE_ARREADY        ),
    .m_axi_rdata                    (S_AXI4_LITE_RDATA          ),
    .m_axi_rresp                    (S_AXI4_LITE_RRESP          ),
    .m_axi_rvalid                   (S_AXI4_LITE_RVALID         ),
    .m_axi_rready                   (S_AXI4_LITE_RREADY         ),

    // 忙状态
    .wr_busy                        (tb_cmd_wr_busy             ),
    .rd_busy                        (tb_cmd_rd_busy             )
);

top #
(
    .DATA_WIDTH             (DATA_WIDTH            ),
    .REG_COUNT              (REG_COUNT             ),
    .ADDR_WIDTH             (ADDR_WIDTH            ),
    .C_M_AXI_ID_WIDTH       (C_M_AXI_ID_WIDTH      ),
    .C_M_AXI_ADDR_WIDTH     (C_M_AXI_ADDR_WIDTH    ),
    .C_M_AXI_DATA_WIDTH     (C_M_AXI_DATA_WIDTH    )
)
u_top
(
    .rst_n                          (rst_n                      ),

    //axi4-lite slave
    .S_AXI4_LITE_ACLK               (S_AXI4_LITE_ACLK           ),
    .S_AXI4_LITE_ARESETN            (S_AXI4_LITE_ARESETN        ),
    .S_AXI4_LITE_AWADDR             (S_AXI4_LITE_AWADDR         ),
    .S_AXI4_LITE_AWPROT             (S_AXI4_LITE_AWPROT         ),
    .S_AXI4_LITE_AWVALID            (S_AXI4_LITE_AWVALID        ),
    .S_AXI4_LITE_AWREADY            (S_AXI4_LITE_AWREADY        ),
    .S_AXI4_LITE_WDATA              (S_AXI4_LITE_WDATA          ),
    .S_AXI4_LITE_WSTRB              (S_AXI4_LITE_WSTRB          ),
    .S_AXI4_LITE_WVALID             (S_AXI4_LITE_WVALID         ),
    .S_AXI4_LITE_WREADY             (S_AXI4_LITE_WREADY         ),
    .S_AXI4_LITE_BRESP              (S_AXI4_LITE_BRESP          ),
    .S_AXI4_LITE_BVALID             (S_AXI4_LITE_BVALID         ),
    .S_AXI4_LITE_BREADY             (S_AXI4_LITE_BREADY         ),
    .S_AXI4_LITE_ARADDR             (S_AXI4_LITE_ARADDR         ),
    .S_AXI4_LITE_ARPROT             (S_AXI4_LITE_ARPROT         ),
    .S_AXI4_LITE_ARVALID            (S_AXI4_LITE_ARVALID        ),
    .S_AXI4_LITE_ARREADY            (S_AXI4_LITE_ARREADY        ),
    .S_AXI4_LITE_RDATA              (S_AXI4_LITE_RDATA          ),
    .S_AXI4_LITE_RRESP              (S_AXI4_LITE_RRESP          ),
    .S_AXI4_LITE_RVALID             (S_AXI4_LITE_RVALID         ),
    .S_AXI4_LITE_RREADY             (S_AXI4_LITE_RREADY         ),

    //axi4-full master
    .M_AXI4_ACLK                    (M_AXI4_ACLK                ),
    .M_AXI4_ARESETN                 (M_AXI4_ARESETN             ),
    //AW
    .M_AXI4_AWADDR                  (M_AXI4_AWADDR              ),
    .M_AXI4_AWLEN                   (M_AXI4_AWLEN               ),
    .M_AXI4_AWREADY                 (M_AXI4_AWREADY             ),
    .M_AXI4_AWVALID                 (M_AXI4_AWVALID             ),
    .M_AXI4_AWID                    (M_AXI4_AWID                ),
    .M_AXI4_AWPROT                  (M_AXI4_AWPROT              ),
    .M_AXI4_AWSIZE                  (M_AXI4_AWSIZE              ),
    .M_AXI4_AWBURST                 (M_AXI4_AWBURST             ),
    .M_AXI4_AWLOCK                  (M_AXI4_AWLOCK              ),
    .M_AXI4_AWCACHE                 (M_AXI4_AWCACHE             ),
    .M_AXI4_AWQOS                   (M_AXI4_AWQOS               ),
    .M_AXI4_AWREGION                (M_AXI4_AWREGION            ),
    //W
    .M_AXI4_WDATA                   (M_AXI4_WDATA               ),
    .M_AXI4_WSTRB                   (M_AXI4_WSTRB               ),
    .M_AXI4_WLAST                   (M_AXI4_WLAST               ),
    .M_AXI4_WREADY                  (M_AXI4_WREADY              ),
    .M_AXI4_WVALID                  (M_AXI4_WVALID              ),
    //B
    .M_AXI4_BID                     (M_AXI4_BID                 ),
    .M_AXI4_BREADY                  (M_AXI4_BREADY              ),
    .M_AXI4_BRESP                   (M_AXI4_BRESP               ),
    .M_AXI4_BVALID                  (M_AXI4_BVALID              ),
    //AR
    .M_AXI4_ARADDR                  (M_AXI4_ARADDR              ),
    .M_AXI4_ARLEN                   (M_AXI4_ARLEN               ),
    .M_AXI4_ARREADY                 (M_AXI4_ARREADY             ),
    .M_AXI4_ARVALID                 (M_AXI4_ARVALID             ),
    .M_AXI4_ARID                    (M_AXI4_ARID                ),
    .M_AXI4_ARSIZE                  (M_AXI4_ARSIZE              ),
    .M_AXI4_ARBURST                 (M_AXI4_ARBURST             ),
    .M_AXI4_ARLOCK                  (M_AXI4_ARLOCK              ),
    .M_AXI4_ARCACHE                 (M_AXI4_ARCACHE             ),
    .M_AXI4_ARPROT                  (M_AXI4_ARPROT              ),
    .M_AXI4_ARQOS                   (M_AXI4_ARQOS               ),
    .M_AXI4_ARREGION                (M_AXI4_ARREGION            ),
    //R
    .M_AXI4_RDATA                   (M_AXI4_RDATA               ),
    .M_AXI4_RID                     (M_AXI4_RID                 ),
    .M_AXI4_RLAST                   (M_AXI4_RLAST               ),
    .M_AXI4_RREADY                  (M_AXI4_RREADY              ),
    .M_AXI4_RRESP                   (M_AXI4_RRESP               ),
    .M_AXI4_RVALID                  (M_AXI4_RVALID              )
);

//tb_ram：模拟 CPU 侧 RAM（2MB），对接 DUT 的 AXI4 主端
tb_ram #
(
    .S_AXI_ID_WIDTH     (C_M_AXI_ID_WIDTH      ),
    .S_AXI_ADDR_WIDTH   (C_M_AXI_ADDR_WIDTH    ),
    .S_AXI_DATA_WIDTH   (C_M_AXI_DATA_WIDTH    ),
    .MEM_SIZE_BYTES     (2 * 1024 * 1024       )
)
u_tb_ram
(
    .clk                            (M_AXI4_ACLK                ),
    .rst_n                          (M_AXI4_ARESETN             ),

    //写地址通道 AW
    .s_axi_awaddr                   (M_AXI4_AWADDR              ),
    .s_axi_awlen                    (M_AXI4_AWLEN               ),
    .s_axi_awsize                   (M_AXI4_AWSIZE              ),
    .s_axi_awburst                  (M_AXI4_AWBURST             ),
    .s_axi_awlock                   (M_AXI4_AWLOCK              ),
    .s_axi_awcache                  (M_AXI4_AWCACHE             ),
    .s_axi_awprot                   (M_AXI4_AWPROT              ),
    .s_axi_awqos                    (M_AXI4_AWQOS               ),
    .s_axi_awregion                 (M_AXI4_AWREGION            ),
    .s_axi_awid                     (M_AXI4_AWID                ),
    .s_axi_awvalid                  (M_AXI4_AWVALID             ),
    .s_axi_awready                  (M_AXI4_AWREADY             ),

    //写数据通道 W
    .s_axi_wdata                    (M_AXI4_WDATA               ),
    .s_axi_wstrb                    (M_AXI4_WSTRB               ),
    .s_axi_wlast                    (M_AXI4_WLAST               ),
    .s_axi_wvalid                   (M_AXI4_WVALID              ),
    .s_axi_wready                   (M_AXI4_WREADY              ),

    //写响应通道 B
    .s_axi_bid                      (M_AXI4_BID                 ),
    .s_axi_bresp                    (M_AXI4_BRESP               ),
    .s_axi_bvalid                   (M_AXI4_BVALID              ),
    .s_axi_bready                   (M_AXI4_BREADY              ),

    //读地址通道 AR
    .s_axi_araddr                   (M_AXI4_ARADDR              ),
    .s_axi_arlen                    (M_AXI4_ARLEN               ),
    .s_axi_arsize                   (M_AXI4_ARSIZE              ),
    .s_axi_arburst                  (M_AXI4_ARBURST             ),
    .s_axi_arlock                   (M_AXI4_ARLOCK              ),
    .s_axi_arcache                  (M_AXI4_ARCACHE             ),
    .s_axi_arprot                   (M_AXI4_ARPROT              ),
    .s_axi_arqos                    (M_AXI4_ARQOS               ),
    .s_axi_arregion                 (M_AXI4_ARREGION            ),
    .s_axi_arid                     (M_AXI4_ARID                ),
    .s_axi_arvalid                  (M_AXI4_ARVALID             ),
    .s_axi_arready                  (M_AXI4_ARREADY             ),

    //读数据通道 R
    .s_axi_rdata                    (M_AXI4_RDATA               ),
    .s_axi_rid                      (M_AXI4_RID                 ),
    .s_axi_rlast                    (M_AXI4_RLAST               ),
    .s_axi_rresp                    (M_AXI4_RRESP               ),
    .s_axi_rvalid                   (M_AXI4_RVALID              ),
    .s_axi_rready                   (M_AXI4_RREADY              )
);

initial begin
    $fsdbDumpfile("wave.fsdb");   // 波形文件名
    $fsdbDumpvars(0, tb_top);     // 0 = 记录 tb_top 及以下所有层次的全部信号
    $fsdbDumpMDA(0, tb_top);      // 同步 dump 所有多维数组/存储器变量（mem、packed/unpacked array）
end

initial begin
    #1_000_000;   // timescale=1ns下为1ms
    $display("TB_TIMEOUT: simulation finished by timeout at %t", $time);
    $finish;
end

endmodule
