`timescale 1 ns / 1 ps

    module axi4_lite_interface #
    (
        // Users to add parameters here

        // User parameters ends
        // Do not modify the parameters beyond this line

        // Width of S_AXI data bus
        parameter integer C_S_AXI_DATA_WIDTH    = 32,
        // Width of S_AXI address bus
        parameter integer C_S_AXI_REG_COUNT     = 4,
        parameter integer C_S_AXI_ADDR_WIDTH    = 4
    )
    (
        // Users to add ports here

        // User ports ends
        // Do not modify the ports beyond this line

        // Global Clock Signal
         input wire  S_AXI4_LITE_ACLK,
        // Global Reset Signal. This Signal is Active LOW
        input wire  S_AXI4_LITE_ARESETN,
        // Write address (issued by master, acceped by Slave)
        input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI4_LITE_AWADDR,
        // Write channel Protection type. This signal indicates the
            // privilege and security level of the transaction, and whether
            // the transaction is a data access or an instruction access.
        input wire [2 : 0]  S_AXI4_LITE_AWPROT,
        // Write address valid. This signal indicates that the master signaling
            // valid write address and control information.
        input wire  S_AXI4_LITE_AWVALID,
        // Write address ready. This signal indicates that the slave is ready
            // to accept an address and associated control signals.
        output wire  S_AXI4_LITE_AWREADY,
        // Write data (issued by master, acceped by Slave)
        input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI4_LITE_WDATA,
        // Write strobes. This signal indicates which byte lanes hold
            // valid data. There is one write strobe bit for each eight
            // bits of the write data bus.
        input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI4_LITE_WSTRB,
        // Write valid. This signal indicates that valid write
            // data and strobes are available.
        input wire  S_AXI4_LITE_WVALID,
        // Write ready. This signal indicates that the slave
            // can accept the write data.
        output wire  S_AXI4_LITE_WREADY,
        // Write response. This signal indicates the status
            // of the write transaction.
        output wire [1 : 0] S_AXI4_LITE_BRESP,
        // Write response valid. This signal indicates that the channel
            // is signaling a valid write response.
        output wire  S_AXI4_LITE_BVALID,
        // Response ready. This signal indicates that the master
            // can accept a write response.
        input wire  S_AXI4_LITE_BREADY,
        // Read address (issued by master, acceped by Slave)
        input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI4_LITE_ARADDR,
        // Protection type. This signal indicates the privilege
            // and security level of the transaction, and whether the
            // transaction is a data access or an instruction access.
        input wire [2 : 0]  S_AXI4_LITE_ARPROT,
        // Read address valid. This signal indicates that the channel
            // is signaling valid read address and control information.
        input wire  S_AXI4_LITE_ARVALID,
        // Read address ready. This signal indicates that the slave is
            // ready to accept an address and associated control signals.
        output wire  S_AXI4_LITE_ARREADY,
        // Read data (issued by slave)
        output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI4_LITE_RDATA,
        // Read response. This signal indicates the status of the
            // read transfer.
        output wire [1 : 0] S_AXI4_LITE_RRESP,
        // Read valid. This signal indicates that the channel is
            // signaling the required read data.
        output wire  S_AXI4_LITE_RVALID,
        // Read ready. This signal indicates that the master can
            // accept the read data and response information.
        input  wire  S_AXI4_LITE_RREADY,


        output logic   [C_S_AXI_REG_COUNT-1 : 0]     ctrl_w_valid,
        input  wire    [C_S_AXI_REG_COUNT-1 : 0]     ctrl_w_ready,
        output logic   [C_S_AXI_DATA_WIDTH-1 : 0]    data_w,
        output logic   [C_S_AXI_REG_COUNT-1 : 0]     ctrl_r_valid,
        input  wire    [C_S_AXI_REG_COUNT-1 : 0]     ctrl_r_ready,
        input  wire    [C_S_AXI_DATA_WIDTH-1 : 0]    data_r
    );



    // AXI4LITE signals
    logic [C_S_AXI_ADDR_WIDTH-1 : 0]  axi_awaddr;
    logic                             axi_awready;
    logic                             axi_wready;
    logic [1 : 0]                     axi_bresp;
    logic                             axi_bvalid;
    logic [C_S_AXI_ADDR_WIDTH-1 : 0]  axi_araddr;
    logic                             axi_arready;
    logic [1 : 0]                     axi_rresp;
    logic                             axi_rvalid;
    logic [C_S_AXI_DATA_WIDTH-1 : 0]  axi_rdata;

    logic [7:0] cnt_wait_w;
    logic [7:0] cnt_wait_r;





    // Example-specific design signals
    // local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
    // ADDR_LSB is used for addressing 32/64 bit registers/memories
    // ADDR_LSB = 2 for 32 bits (n downto 2)
    // ADDR_LSB = 3 for 64 bits (n downto 3)
    localparam integer ADDR_LSB = $clog2(C_S_AXI_DATA_WIDTH/8);
    localparam integer REG_AW   = $clog2(C_S_AXI_REG_COUNT);
    localparam integer OPT_MEM_ADDR_BITS = C_S_AXI_ADDR_WIDTH - ADDR_LSB;
    //----------------------------------------------
    //-- Signals for user logic register space example
    //------------------------------------------------
    //-- Number of Slave Registers 5

    // I/O Connections assignments

    assign S_AXI4_LITE_AWREADY    = axi_awready;
    assign S_AXI4_LITE_WREADY     = axi_wready;
    assign S_AXI4_LITE_BRESP      = axi_bresp;
    assign S_AXI4_LITE_BVALID     = axi_bvalid;
    assign S_AXI4_LITE_ARREADY    = axi_arready;
    assign S_AXI4_LITE_RRESP      = axi_rresp;
    assign S_AXI4_LITE_RVALID     = axi_rvalid;
    assign S_AXI4_LITE_RDATA      = axi_rdata;
    //state machine varibles
    typedef enum logic [2:0]
    {
        S_IDLE,
        S_WAIT,
        S_WAIT_CDC,
        S_ADDR,
        S_DATA,
        S_RESP
    }fsm_state_handshake;
    fsm_state_handshake state_w, state_w_n, state_r, state_r_n;

    //State machine local parameters
    // Implement Write state machine
    // Outstanding write transactions are not supported by the slave i.e., master should assert bready to receive response on or before it starts sending the new transaction
    //designed by myself begin
    wire [REG_AW-1:0] idx_w = S_AXI4_LITE_AWADDR[ADDR_LSB +: REG_AW];
    logic[REG_AW-1:0] idx_w_reg;
    always_ff @(posedge S_AXI4_LITE_ACLK) begin
        if(S_AXI4_LITE_ARESETN == 1'b0) begin
            idx_w_reg <= '0;
        end
        else if(S_AXI4_LITE_AWVALID && axi_awready)begin
            idx_w_reg <= idx_w;
        end
    end
    wire [REG_AW-1:0] idx_r = S_AXI4_LITE_ARADDR[ADDR_LSB +: REG_AW];
    logic[REG_AW-1:0] idx_r_reg;
    always_ff @(posedge S_AXI4_LITE_ACLK) begin
        if(S_AXI4_LITE_ARESETN == 1'b0) begin
            idx_r_reg <= '0;
        end
        else if(S_AXI4_LITE_ARVALID && axi_arready)begin
            idx_r_reg <= idx_r;
        end
    end
    always_ff @(posedge S_AXI4_LITE_ACLK) begin
        if(S_AXI4_LITE_ARESETN == 1'b0) begin
            state_w <= S_IDLE;
        end
        else begin
            state_w <= state_w_n;
        end
    end

    always_comb begin
        state_w_n = state_w;
        case(state_w)
            S_IDLE: begin
                state_w_n = S_WAIT;
            end
            S_WAIT: begin
                if (S_AXI4_LITE_AWVALID && axi_awready && S_AXI4_LITE_WVALID && axi_wready) begin
                    if(ctrl_w_valid[idx_w] == ctrl_w_ready[idx_w]) begin
                        state_w_n = S_RESP;
                    end
                    else begin
                        state_w_n = S_WAIT_CDC;
                    end
                end
                else if(S_AXI4_LITE_AWVALID && axi_awready) begin
                    state_w_n = S_DATA;
                end
                else if(S_AXI4_LITE_WVALID && axi_wready) begin
                    state_w_n = S_ADDR;
                end
                else begin
                end
            end
            S_ADDR: begin
                if (S_AXI4_LITE_AWVALID && axi_awready) begin
                    if(ctrl_w_valid[idx_w] == ctrl_w_ready[idx_w]) begin
                        state_w_n = S_RESP;
                    end
                    else begin
                        state_w_n = S_WAIT_CDC;
                    end
                end
            end
            S_DATA: begin
                if (S_AXI4_LITE_WVALID && axi_wready) begin
                    if(ctrl_w_valid[idx_w_reg] == ctrl_w_ready[idx_w_reg]) begin
                        state_w_n = S_RESP;
                    end
                    else begin
                        state_w_n = S_WAIT_CDC;
                    end
                end
            end
            S_WAIT_CDC: begin
                if((ctrl_w_valid[idx_w_reg] == ctrl_w_ready[idx_w_reg]) || (cnt_wait_w >= 8'hff))begin
                    state_w_n = S_RESP;
                end
            end
            S_RESP: begin
                if(axi_bvalid && S_AXI4_LITE_BREADY) begin
                    state_w_n = S_IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge S_AXI4_LITE_ACLK) begin
        if(S_AXI4_LITE_ARESETN == 1'b0) begin
            axi_awready <= 1'b0;
            axi_wready  <= 1'b0;
            axi_bvalid  <= 1'b0;
            axi_bresp   <= 2'd0;
            axi_awaddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            cnt_wait_w  <= 8'h00;
        end
        else begin
            case(state_w)
                S_IDLE: begin
                    axi_awready <= 1'b1;
                    axi_wready  <= 1'b1;
                    axi_bvalid  <= 1'b0;
                    axi_bresp   <= 2'd0;
                    cnt_wait_w <= 8'h00;
                    ctrl_w_valid<= C_S_AXI_REG_COUNT'(0);
                end
                S_WAIT: begin
                    if (S_AXI4_LITE_AWVALID && axi_awready && S_AXI4_LITE_WVALID && axi_wready) begin
                        axi_awaddr <= S_AXI4_LITE_AWADDR;
                        data_w <= S_AXI4_LITE_WDATA;
                        axi_awready <= 1'b0;
                        axi_wready  <= 1'b0;
                        if(ctrl_w_valid[idx_w] == ctrl_w_ready[idx_w]) begin
                            if((S_AXI4_LITE_AWADDR[ADDR_LSB-1:0] == '0) && (idx_w < C_S_AXI_REG_COUNT)) begin
                                ctrl_w_valid[idx_w] <= ~ctrl_w_valid[idx_w];
                                axi_bresp   <= 2'd0;
                            end
                            else begin
                                axi_bresp   <= 2'd3;
                            end
                        end
                        else begin
                        end
                    end
                    else if (S_AXI4_LITE_AWVALID && axi_awready) begin
                        axi_awaddr <= S_AXI4_LITE_AWADDR;
                        axi_awready <= 1'b0;
                        axi_wready  <= 1'b1;
                    end
                    else if (S_AXI4_LITE_WVALID && axi_wready) begin
                        data_w <= S_AXI4_LITE_WDATA;
                        axi_awready <= 1'b1;
                        axi_wready  <= 1'b0;
                    end
                end
                S_ADDR: begin
                    if (S_AXI4_LITE_AWVALID && axi_awready) begin
                        axi_awaddr <= S_AXI4_LITE_AWADDR;
                        axi_awready <= 1'b0;
                        axi_wready  <= 1'b0;
                        if(ctrl_w_valid[idx_w] == ctrl_w_ready[idx_w]) begin
                            if((S_AXI4_LITE_AWADDR[ADDR_LSB-1:0] == '0) && (idx_w < C_S_AXI_REG_COUNT)) begin
                                ctrl_w_valid[idx_w] <= ~ctrl_w_valid[idx_w];
                                axi_bresp   <= 2'd0;
                            end
                            else begin
                                axi_bresp   <= 2'd3;
                            end
                        end
                        else begin
                        end
                    end
                    else begin
                    end
                end
                S_DATA: begin
                    if (S_AXI4_LITE_WVALID && axi_wready) begin
                        data_w <= S_AXI4_LITE_WDATA;
                        axi_awready <= 1'b0;
                        axi_wready  <= 1'b0;
                        if(ctrl_w_valid[idx_w_reg] == ctrl_w_ready[idx_w_reg]) begin
                            if((axi_awaddr[ADDR_LSB-1:0] == '0) && (idx_w_reg < C_S_AXI_REG_COUNT)) begin
                                ctrl_w_valid[idx_w_reg] <= ~ctrl_w_valid[idx_w_reg];
                                axi_bresp   <= 2'd0;
                            end
                            else begin
                                axi_bresp   <= 2'd3;
                            end
                        end
                        else begin
                        end
                    end
                    else begin
                    end
                end
                S_WAIT_CDC: begin
                    if(ctrl_w_valid[idx_w_reg] == ctrl_w_ready[idx_w_reg]) begin
                            if((axi_awaddr[ADDR_LSB-1:0] == '0) && (idx_w_reg < C_S_AXI_REG_COUNT)) begin
                                ctrl_w_valid[idx_w_reg] <= ~ctrl_w_valid[idx_w_reg];
                                axi_bresp   <= 2'd0;
                            end
                            else begin
                                axi_bresp   <= 2'd3;
                            end
                    end
                    else begin
                        cnt_wait_w <= cnt_wait_w + 8'd1;
                        if(cnt_wait_w >= 8'hff) begin
                            axi_bresp   <= 2'd2;
                        end
                    end
                end
                S_RESP: begin
                    if(axi_bvalid && S_AXI4_LITE_BREADY) begin
                        axi_bvalid <= 1'b0;
                    end
                    else if(axi_bvalid == 1'b0) begin
                        axi_bvalid <= 1'b1;
                    end
                end
                default: begin
                end
            endcase
        end
    end
    //read start
    always_ff @(posedge S_AXI4_LITE_ACLK) begin
        if(S_AXI4_LITE_ARESETN == 1'b0) begin
            state_r <= S_IDLE;
        end
        else begin
            state_r <= state_r_n;
        end
    end

    always_comb begin
        state_r_n = state_r;
        case(state_r)
            S_IDLE: begin
                state_r_n = S_WAIT;
            end
            S_WAIT: begin
                if (S_AXI4_LITE_ARVALID && axi_arready) begin
                    if(ctrl_r_valid[idx_r] == ctrl_r_ready[idx_r]) begin
                        if((S_AXI4_LITE_ARADDR[ADDR_LSB-1:0] == 0) && (idx_r < C_S_AXI_REG_COUNT)) begin
                            state_r_n = S_DATA;
                        end
                        else begin
                            state_r_n = S_RESP;
                        end
                    end
                    else begin
                        state_r_n = S_WAIT_CDC;
                    end
                end
                else begin
                end
            end
            S_WAIT_CDC: begin
                if((ctrl_r_valid[idx_r_reg] == ctrl_r_ready[idx_r_reg]) || (cnt_wait_r >= 8'hff))begin
                    state_r_n = S_DATA;
                end
            end
            S_DATA: begin
                if (axi_rvalid && S_AXI4_LITE_RREADY) begin
                    state_r_n = S_IDLE;
                end
            end
            S_RESP: begin
                if(axi_rvalid && S_AXI4_LITE_RREADY) begin
                    state_r_n = S_IDLE;
                end
            end
        endcase
    end

    always_ff @(posedge S_AXI4_LITE_ACLK) begin
        if(S_AXI4_LITE_ARESETN == 1'b0) begin
            axi_araddr  <= {C_S_AXI_ADDR_WIDTH{1'b0}};
            axi_arready <= 1'b0;
            axi_rvalid  <= 1'b0;
            axi_rresp   <= 2'd0;
            cnt_wait_r  <= 8'd0;
            ctrl_r_valid<= C_S_AXI_REG_COUNT'(0);
        end
        else begin
            case(state_r)
                S_IDLE: begin
                    axi_arready <= 1'b1;
                    axi_rvalid  <= 1'b0;
                    axi_rresp   <= 2'd0;
                    cnt_wait_r  <= 8'd0;
                    axi_rdata   <= C_S_AXI_DATA_WIDTH'(0);
                end
                S_WAIT: begin
                    if (S_AXI4_LITE_ARVALID && axi_arready) begin
                        axi_araddr <= S_AXI4_LITE_ARADDR;
                        axi_arready <= 1'b0;
                        axi_rvalid  <= 1'b0;
                        if(ctrl_r_valid[idx_r] == ctrl_r_ready[idx_r]) begin
                            if((S_AXI4_LITE_ARADDR[ADDR_LSB-1:0] == 0) && (idx_r < C_S_AXI_REG_COUNT)) begin
                                ctrl_r_valid[idx_r] <= ~ctrl_r_valid[idx_r];
                                axi_rresp <= 2'd0;
                            end
                            else begin
                                axi_rresp <= 2'd3;
                            end
                        end
                        else begin
                        end
                    end
                    else begin
                    end
                end
                S_WAIT_CDC: begin
                    if(ctrl_r_valid[idx_r_reg] == ctrl_r_ready[idx_r_reg]) begin
                        if((axi_araddr[ADDR_LSB-1:0] == 0) && (idx_r_reg < C_S_AXI_REG_COUNT)) begin
                            ctrl_r_valid[idx_r_reg] <= ~ctrl_r_valid[idx_r_reg];
                            axi_rresp <= 2'd0;
                        end
                        else begin
                            axi_rresp <= 2'd3;
                        end
                    end
                    else begin
                        cnt_wait_r <= cnt_wait_r + 8'd1;
                        if(cnt_wait_r >= 8'hff) begin
                            axi_rresp   <= 2'd2;
                        end
                    end
                end
                S_DATA: begin
                    if(ctrl_r_valid[idx_r_reg] == ctrl_r_ready[idx_r_reg]) begin
                        axi_arready <= 1'b0;
                        axi_rvalid <= 1'b1;
                        axi_rdata <= data_r;
                    end
                    else begin
                    end
                end
                S_RESP: begin
                    axi_rvalid <= 1'b1;
                    if(axi_rvalid && S_AXI4_LITE_RREADY) begin
                        axi_rvalid <= 1'b0;
                    end
                end
                default: begin
                end
            endcase
        end
    end
    //designed by myself begin


    endmodule