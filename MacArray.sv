/////////////////////////////////////////////////////////////////////
//
// EE488(G) Project 1
// Title: MacArray.sv
//
/////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module MacArray
#(
    parameter MAC_ROW                                                   = 16,
    parameter MAC_COL                                                   = 16,
    parameter IFMAP_BITWIDTH                                            = 16,
    parameter W_BITWIDTH                                                = 8,
    parameter OFMAP_BITWIDTH                                            = 32
)
(
    input  logic                                                        clk,
    input  logic                                                        rstn,

    input  logic                                                        w_prefetch_in,
    input  logic                                                        w_enable_in,
    input  logic [MAC_COL-1:0][W_BITWIDTH-1:0]                          w_data_in,

    input  logic                                                        ifmap_start_in,
    input  logic [MAC_ROW-1:0]                                          ifmap_enable_in,
    input  logic [MAC_ROW-1:0][IFMAP_BITWIDTH-1:0]                      ifmap_data_in,

    output logic [MAC_COL-1:0]                                          ofmap_valid_out,
    output logic [MAC_COL-1:0][OFMAP_BITWIDTH-1:0]                      ofmap_data_out
);

	// your code here
	logic [W_BITWIDTH-1:0] 		conn_w_data[MAC_ROW+1][MAC_COL];
	logic								conn_w_valid[MAC_ROW+1][MAC_COL];
	
	logic [IFMAP_BITWIDTH-1:0] conn_i_data[MAC_ROW][MAC_COL+1];
	logic								conn_i_enable[MAC_ROW][MAC_COL+1];
	
	logic [OFMAP_BITWIDTH-1:0] conn_o_data[MAC_ROW+1][MAC_COL];
	logic ofmap_valid_buff;
	
	always_ff @(posedge clk) begin
		if (~rstn) begin
			ofmap_valid_out <= {MAC_COL{1'b0}};
		end
		else begin
			// ofmap
			ofmap_valid_buff <= conn_i_enable[MAC_ROW-1][0];
			ofmap_valid_out[0] <= ofmap_valid_buff;
			for (int i = 1; i < MAC_COL; i++) begin
				ofmap_valid_out[i] <= ofmap_valid_out[i-1];
			end
		end
	end
	
	generate
	genvar r;
	genvar c;
	
	for (c = 0; c < MAC_COL; c++) begin :initRow
		assign conn_w_data[0][c] 	= w_data_in[c];
		assign conn_o_data[0][c]	= {OFMAP_BITWIDTH{1'b0}};
		assign ofmap_data_out[c]	= conn_o_data[MAC_ROW][c];
		assign conn_w_valid[0][c] 	= w_enable_in;
	end
	
	for (r = 0; r < MAC_ROW; r++) begin :initCol
		assign conn_i_enable[r][0] = ifmap_enable_in[r];
		assign conn_i_data[r][0]	= ifmap_data_in[r];
	end
	
	for (r = 0; r < MAC_ROW; r++) begin : row
		for (c = 0; c < MAC_COL; c++) begin : col
			Mac
			#(
				.IFMAP_BITWIDTH(IFMAP_BITWIDTH),
				.W_BITWIDTH(W_BITWIDTH),
				.OFMAP_BITWIDTH(OFMAP_BITWIDTH)
			)
			PE(
				.clk(clk),
				.rstn(rstn),

				.w_enable_in(w_enable_in),
				.w_valid_in(conn_w_valid[r][c]),
				.w_data_in(conn_w_data[r][c]),
				.w_data_out(conn_w_data[r+1][c]),
				.w_valid_out(conn_w_valid[r+1][c]),

				.ifmap_enable_in(conn_i_enable[r][c]),
				.ifmap_data_in(conn_i_data[r][c]),
				.ifmap_valid_out(conn_i_enable[r][c+1]),
				.ifmap_data_out(conn_i_data[r][c+1]),

				.psum_data_in(conn_o_data[r][c]),
				.psum_data_out(conn_o_data[r+1][c])	
			);
		end
	 end
	 endgenerate

endmodule



