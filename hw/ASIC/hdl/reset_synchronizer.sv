module reset_synchronizer (
    input logic clk,
    input logic rst_n,
    output logic rst_n_sync
);

logic rst_n_sync1;
logic rst_n_sync2;

assign rst_n_sync = rst_n_sync2;

always_ff @(posedge clk or negedge rst_n)begin
    if(rst_n == 1'b0) begin
        rst_n_sync1 <= '0;
        rst_n_sync2 <= '0;
    end
    else begin
        rst_n_sync1 <= 1'b1;
        rst_n_sync2 <= rst_n_sync1;
    end
end

endmodule
