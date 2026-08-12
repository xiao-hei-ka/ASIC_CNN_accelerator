module cdc # (
    parameter integer DATA_WIDTH = 32,
    parameter integer REG_COUNT  = 4,
    parameter integer ADDR_WIDTH = 4
)
(
    input   logic                       aclk,
    input   logic                       aresetn,
    input   logic                       clk,
    input   logic                       rst_n,
    input   logic   [REG_COUNT-1 : 0]   ctrl_w_valid,
    output  logic   [REG_COUNT-1 : 0]   ctrl_w_ready_r2,
    input   logic   [DATA_WIDTH-1 : 0]  data_w,
    input   logic   [REG_COUNT-1 : 0]   ctrl_r_valid,
    output  logic   [REG_COUNT-1 : 0]   ctrl_r_ready_r2,
    output  logic   [DATA_WIDTH-1 : 0]  data_r,

    output  wire    [REG_COUNT-1 : 0]   ctrl_w_core,
    output  wire    [DATA_WIDTH-1 : 0]  data_w_core,
    output  logic   [REG_COUNT-1 : 0]   status_r_core,
    input   logic   [DATA_WIDTH-1 : 0]  data_r_core  [0 : REG_COUNT-1]
);

//(aclk -> clk) to reg
logic [REG_COUNT-1 : 0]     ctrl_w_valid_r1;
logic [REG_COUNT-1 : 0]     ctrl_w_valid_r2;
logic [REG_COUNT-1 : 0]     ctrl_r_valid_r1;
logic [REG_COUNT-1 : 0]     ctrl_r_valid_r2;
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        ctrl_w_valid_r1 <=  {REG_COUNT{1'b0}};
        ctrl_w_valid_r2 <=  {REG_COUNT{1'b0}};
        ctrl_r_valid_r1 <=  {REG_COUNT{1'b0}};
        ctrl_r_valid_r2 <=  {REG_COUNT{1'b0}};
    end
    else begin
        ctrl_w_valid_r1 <=  ctrl_w_valid;
        ctrl_w_valid_r2 <=  ctrl_w_valid_r1;
        ctrl_r_valid_r1 <=  ctrl_r_valid;
        ctrl_r_valid_r2 <=  ctrl_r_valid_r1;
    end
end

//(clk -> aclk) to reg
logic [REG_COUNT-1 : 0]     ctrl_w_ready;
logic [REG_COUNT-1 : 0]     ctrl_w_ready_r1;
logic [REG_COUNT-1 : 0]     ctrl_r_ready;
logic [REG_COUNT-1 : 0]     ctrl_r_ready_r1;
always_ff @(posedge aclk) begin
    if(aresetn == 1'b0) begin
        ctrl_w_ready_r1 <=  {REG_COUNT{1'b0}};
        ctrl_w_ready_r2 <=  {REG_COUNT{1'b0}};
        ctrl_r_ready_r1 <=  {REG_COUNT{1'b0}};
        ctrl_r_ready_r2 <=  {REG_COUNT{1'b0}};
    end
    else begin
        ctrl_w_ready_r1 <=  ctrl_w_ready;
        ctrl_w_ready_r2 <=  ctrl_w_ready_r1;
        ctrl_r_ready_r1 <=  ctrl_r_ready;
        ctrl_r_ready_r2 <=  ctrl_r_ready_r1;
    end
end

//CDC_W
assign ctrl_w_core = ctrl_w_valid_r2 ^ ctrl_w_ready;
assign data_w_core = data_w;
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        ctrl_w_ready    <=  {REG_COUNT{1'b0}};
    end
    else begin
        if(ctrl_w_core) begin
            ctrl_w_ready <= ctrl_w_valid_r2;
        end
    end
end

//CDC_R
reg    [REG_COUNT-1 : 0] r_flag;
assign r_flag = ctrl_r_valid_r2 ^ ctrl_r_ready;
assign status_r_core = r_flag;
logic [DATA_WIDTH-1 :0] data_r_comb;
always_comb begin
    data_r_comb = {DATA_WIDTH{1'b0}};
    for(int i = 0; i < REG_COUNT; i++) begin
        data_r_comb |= r_flag[i] ? data_r_core[i] : {DATA_WIDTH{1'b0}};
    end
end
always_ff @(posedge clk) begin
    if(rst_n == 1'b0) begin
        ctrl_r_ready    <=  {REG_COUNT{1'b0}};
        data_r          <=  {DATA_WIDTH{1'b0}};
    end
    else begin
        if(r_flag) begin
            ctrl_r_ready    <=  ctrl_r_valid_r2;
            data_r          <=  data_r_comb;
        end
    end
end
endmodule