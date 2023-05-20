/////////////////////////////////////////////////////////////////////
//
// EE488(G) Project 1
// Title: Mac.sv
//
/////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module Mac
#(
	parameter IFMAP_BITWIDTH                                          = 16,
	parameter W_BITWIDTH                                              = 8,
	parameter OFMAP_BITWIDTH                                          = 32
)
(
	input	 logic                                                      clk,
	input  logic                                                    	rstn,

	input  logic                                                      w_enable_in,
	input  logic																		w_valid_in,
	input  logic [W_BITWIDTH-1:0]                        					w_data_in,
	output logic																		w_valid_out,
	output logic [W_BITWIDTH-1:0]			    									w_data_out,

	input  logic                                        					ifmap_enable_in,
	input  logic [IFMAP_BITWIDTH-1:0]                    					ifmap_data_in,
	output logic																		ifmap_valid_out,
	output logic [IFMAP_BITWIDTH-1:0]											ifmap_data_out,

	input  logic [OFMAP_BITWIDTH-1:0]											psum_data_in,
	output logic [OFMAP_BITWIDTH-1:0]											psum_data_out	
);

	logic signed [W_BITWIDTH-1:0]					weight_reg;
	logic signed [IFMAP_BITWIDTH-1:0]			ifmap_reg;
	logic signed [OFMAP_BITWIDTH-1:0]			psum_data;
	logic signed [OFMAP_BITWIDTH-1:0]			mult_res;

	assign w_data_out		= weight_reg;
	assign psum_data		= psum_data_in;
	assign ifmap_reg		= ifmap_data_in;

	always_ff @(posedge clk)
	begin
		if (~rstn)
		begin
			weight_reg <= {W_BITWIDTH{1'b0}};
			ifmap_valid_out <= 1'b0;
		end
		else
		begin
			if (w_enable_in && w_valid_in) begin
				weight_reg <= w_data_in;
			end
			if (ifmap_enable_in) begin
				mult_res <= ifmap_reg * weight_reg;
			end
			if (ifmap_valid_out) begin
				psum_data_out <=  mult_res + psum_data;
			end
			ifmap_valid_out <= ifmap_enable_in;
			ifmap_data_out <= ifmap_data_in;
			w_valid_out <= w_valid_in;
		end
	end

endmodule


