`timescale 1ns/1ps
module tb_top(
);

//=================================================================================
// Parameter declaration (same as top)
//=================================================================================
parameter integer DATA_WIDTH            = 32;
parameter integer REG_COUNT             = 5;
localparam integer ADDR_WIDTH           = (($clog2((DATA_WIDTH/8) * REG_COUNT) < 1) ? 1 : $clog2((DATA_WIDTH/8) * REG_COUNT));

parameter integer C_M_AXI_ID_WIDTH      = 2;
parameter integer C_M_AXI_ADDR_WIDTH    = 32;
parameter integer C_M_AXI_DATA_WIDTH    = 128;

//=================================================================================
// Signal declaration - global
//=================================================================================
logic                                   rst_n                       ;

//=================================================================================
// Signal declaration - AXI4-Lite slave
//=================================================================================
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

//=================================================================================
// Signal declaration - AXI4-Full master
//=================================================================================
logic                                   M_AXI4_ACLK                 ;
logic                                   M_AXI4_ARESETN              ;
//AW
logic   [C_M_AXI_ADDR_WIDTH-1 : 0]      M_AXI4_AWADDR               ;
logic   [7 : 0]                         M_AXI4_AWLEN                ;
logic                                   M_AXI4_AWREADY              ;
logic                                   M_AXI4_AWVALID              ;
logic   [5:0]                           M_AXI4_AWID                 ;
logic   [5:0]                           M_AXI4_AWPROT               ;
logic   [2 : 0]                         M_AXI4_AWSIZE               ;
logic   [1 : 0]                         M_AXI4_AWBURST              ;
logic   [1 : 0]                         M_AXI4_AWLOCK               ;
logic   [3 : 0]                         M_AXI4_AWCACHE              ;
logic   [3 : 0]                         M_AXI4_AWQOS                ;
logic   [3 : 0]                         M_AXI4_AWREGION             ;
//W
logic   [C_M_AXI_DATA_WIDTH-1 : 0]      M_AXI4_WDATA                ;
logic   [C_M_AXI_DATA_WIDTH/8-1 : 0]    M_AXI4_WSTRB                ;
logic                                   M_AXI4_WLAST                ;
logic                                   M_AXI4_WREADY               ;
logic                                   M_AXI4_WVALID               ;
//B
logic   [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI4_BID                  ;
logic                                   M_AXI4_BREADY               ;
logic   [1 : 0]                         M_AXI4_BRESP                ;
logic                                   M_AXI4_BVALID               ;
//AR
logic   [C_M_AXI_ADDR_WIDTH-1 : 0]      M_AXI4_ARADDR               ;
logic   [7 : 0]                         M_AXI4_ARLEN                ;
logic                                   M_AXI4_ARREADY              ;
logic                                   M_AXI4_ARVALID              ;
logic   [5:0]                           M_AXI4_ARID                 ;
logic   [2 : 0]                         M_AXI4_ARSIZE               ;
logic   [1 : 0]                         M_AXI4_ARBURST              ;
logic   [1 : 0]                         M_AXI4_ARLOCK               ;
logic   [3 : 0]                         M_AXI4_ARCACHE              ;
logic   [2 : 0]                         M_AXI4_ARPROT               ;
logic   [3 : 0]                         M_AXI4_ARQOS                ;
logic   [3 : 0]                         M_AXI4_ARREGION             ;
//R
logic   [C_M_AXI_DATA_WIDTH-1 : 0]      M_AXI4_RDATA                ;
logic   [C_M_AXI_ID_WIDTH-1 : 0]        M_AXI4_RID                  ;
logic                                   M_AXI4_RLAST                ;
logic                                   M_AXI4_RREADY               ;
logic   [1 : 0]                         M_AXI4_RRESP                ;
logic                                   M_AXI4_RVALID               ;

//=================================================================================
// DUT instantiation - top
//=================================================================================
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


endmodule