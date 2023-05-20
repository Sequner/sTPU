/////////////////////////////////////////////////////////////////////
//
// EE488(G) Project 2
// Title: MemoryController.sv
// Author: Sanzhar Shabdarov
//
/////////////////////////////////////////////////////////////////////

`timescale 1 ns / 1 ps

module MemoryController
#(
	// logic parameter
	parameter MAC_ROW                                           = 16,
	parameter MAC_COL                                           = 16,
	parameter W_BITWIDTH                                        = 8,
	parameter IFMAP_BITWIDTH                                    = 16,
	parameter OFMAP_BITWIDTH                                    = 32,
	parameter W_ADDR_BIT                                        = 11,
	parameter IFMAP_ADDR_BIT                                    = 9,
	parameter OFMAP_ADDR_BIT                                    = 10,
	// operation parameter
	parameter OFMAP_CAHNNEL_NUM                                 = 64,
	parameter IFMAP_CAHNNEL_NUM                                 = 32,
	parameter WEIGHT_WIDTH                                      = 3,
	parameter WEIGHT_HEIGHT                                     = 3,
	parameter IFMAP_WIDTH                                       = 16,
	parameter IFMAP_HEIGHT                                      = 16,
	parameter OFMAP_WIDTH                                       = 14,
	parameter OFMAP_HEIGHT                                      = 14
)
(
	input  logic                                                clk,
	input  logic                                                rstn,

	input  logic                                                start_in,

	input  logic                                                ofmap_ready_in,

	output logic                                                w_prefetch_out,
	output logic [W_ADDR_BIT-1:0]                               w_addr_out,
	output logic                                                w_read_en_out,

	output logic                                                ifmap_start_out,
	output logic [IFMAP_ADDR_BIT-1:0]                           ifmap_addr_out,
	output logic                                                ifmap_read_en_out,

	output logic                                                mac_done_out,

	output logic [OFMAP_ADDR_BIT-1:0]                           ofmap_addr_out,
	output logic                                                ofmap_write_en_out,
	output logic                                                ofmap_write_done_out
);
	
	logic [1:0] state;
	localparam 	IDLE 		= 2'd0, 
					WEIGHT 	= 2'd1, 
					IFMAP 	= 2'd2, 
					WAIT		= 2'd3;

	localparam	NUM_OUT_TILE = OFMAP_CAHNNEL_NUM/MAC_COL,
					NUM_IN_TILE = IFMAP_CAHNNEL_NUM/MAC_ROW,
					WEIGHT_OUT_STRIDE = NUM_OUT_TILE * (MAC_ROW-1),
					IFMAP_WEIGHT_STRIDE = WEIGHT_WIDTH * NUM_IN_TILE,	// to move to a new row of ifmap skipping next WEIGHT_WIDTH elements
					IFMAP_OFHEIGHT_STRIDE = (OFMAP_HEIGHT-1) * MAC_ROW * NUM_IN_TILE - 1,	// get to the new row of the ifmap, when next weight tile is on
																													// a new row. For example, prev tile on (0, 2), next is (1, 0)
					IFMAP_OUT_STRIDE = ((OFMAP_HEIGHT-1) * MAC_ROW + OFMAP_WIDTH - 1) * NUM_IN_TILE, // get back to starting address 
																																// of ifmap in this iteration of weight tiling
					OFMAP_SIZE = OFMAP_WIDTH * OFMAP_HEIGHT * OFMAP_CAHNNEL_NUM / MAC_COL;
	
	logic [$clog2(MAC_ROW)-1:0] row_counter;
	logic [$clog2(MAC_COL)-1:0] col_counter;
	
	logic [$clog2(WEIGHT_HEIGHT)-1:0] row_offset;
	logic [$clog2(WEIGHT_WIDTH)-1:0] col_offset;
	
	logic [$clog2(OFMAP_WIDTH)-1:0] ifwidth_counter;
	logic [$clog2(OFMAP_HEIGHT)-1:0] ifheight_counter;
	
	logic [$clog2(NUM_OUT_TILE)-1:0] outchannel_tile;
	logic [$clog2(NUM_IN_TILE)-1:0] inchannel_tile;
	
	logic ifmap_finish, ifmap_prefinish, last_tile, last_channel_tile;
	
	assign ifmap_finish = ifwidth_counter == OFMAP_WIDTH-1 && ifheight_counter == OFMAP_HEIGHT-1;
	assign ifmap_prefinish = ifheight_counter == OFMAP_HEIGHT-1 && ifwidth_counter == OFMAP_WIDTH-2;
	assign last_channel_tile = outchannel_tile == NUM_OUT_TILE-1 && inchannel_tile == NUM_IN_TILE-1;
	assign last_tile = last_channel_tile && row_offset == WEIGHT_HEIGHT-1 && col_offset == WEIGHT_WIDTH-1;
	
	assign ofmap_write_en_out = ofmap_ready_in;

	always_ff @(posedge clk) begin
		if (~rstn) begin
			w_prefetch_out <= 1'b0;
			w_addr_out <= 0;
			w_read_en_out <= 1'b0;
			ifmap_start_out <= 1'b0;
			ifmap_addr_out <= 0;
			ifmap_read_en_out <= 1'b0;
			mac_done_out <= 1'b0;
			
			state <= IDLE;
			row_counter <= 0;
			row_offset <= 0;
			col_offset <= 0;
			ifwidth_counter <= 0;
			ifheight_counter <= 0;
			outchannel_tile <= 0;
			inchannel_tile <= 0;
			col_counter <= 0;
		end
		else begin
			case (state)
				IDLE: begin
						col_counter <= 0;
						row_counter <= 0;
						row_offset <= 0;
						col_offset <= 0;
						ifwidth_counter <= 0;
						ifheight_counter <= 0;
						outchannel_tile <= 0;
						inchannel_tile <= 0;
						ifmap_addr_out <= 0;
					if (start_in) begin
						state <= WEIGHT;
						w_prefetch_out <= 1'b1;
						w_addr_out <= 0;
						w_read_en_out <= 1'b1;
					end
				end
				WEIGHT: begin		// maybe need 1 clock cycle delay to read
					w_prefetch_out <= 1'b0;
					
					if (row_counter == MAC_ROW-1) begin
						row_counter <= 0;
						w_read_en_out <= 1'b0;
						state <= IFMAP;
						ifmap_start_out <= 1'b1;
						ifmap_read_en_out <= 1'b1;
					end
					else begin
						row_counter <= row_counter + 1'b1;
						w_addr_out <= w_addr_out + NUM_OUT_TILE;
					end
				end
				IFMAP: begin		// maybe need 1 clock cycle delay to read
					ifmap_start_out <= 1'b0;
					
					if (last_tile && ifmap_prefinish) begin
						mac_done_out <= 1'b1;
					end
					else begin
						mac_done_out <= 1'b0;
					end
					
					if (ifmap_finish) begin
						ifwidth_counter <= 0;
						ifheight_counter <= 0;
						ifmap_read_en_out <= 1'b0;
						if (last_tile) begin
							state <= IDLE;
						end
						else begin
							state <= WAIT;
							if (last_channel_tile) begin
								outchannel_tile <= 0;
								inchannel_tile <= 0;
								w_addr_out <= w_addr_out + 1'b1;
								if (col_offset == WEIGHT_WIDTH-1) begin
									row_offset <= row_offset + 1'b1;
									col_offset <= 0;
									ifmap_addr_out <= ifmap_addr_out - IFMAP_OFHEIGHT_STRIDE;
								end
								else begin
									col_offset <= col_offset + 1'b1;
									ifmap_addr_out <= ifmap_addr_out - IFMAP_OUT_STRIDE + 1'b1;
								end
							end
							else begin
								if (outchannel_tile == NUM_OUT_TILE-1) begin
									outchannel_tile <= 0;
									inchannel_tile <= inchannel_tile + 1'b1;
									w_addr_out <= w_addr_out + 1'b1;
									ifmap_addr_out <= ifmap_addr_out - IFMAP_OUT_STRIDE + 1'b1;
								end
								else begin
									outchannel_tile <= outchannel_tile + 1'b1;
									w_addr_out <= w_addr_out - WEIGHT_OUT_STRIDE + 1'b1;
									ifmap_addr_out <= ifmap_addr_out - IFMAP_OUT_STRIDE;
								end
							end
						end
					end
					else begin
						if (ifwidth_counter == OFMAP_WIDTH-1) begin
							ifwidth_counter <= 0;
							ifheight_counter <= ifheight_counter + 1'b1;
							ifmap_addr_out <= ifmap_addr_out + IFMAP_WEIGHT_STRIDE;
						end
						else begin
							ifwidth_counter <= ifwidth_counter + 1'b1;
							ifmap_addr_out <= ifmap_addr_out + NUM_IN_TILE;
						end
					end
				end
				WAIT: begin
					if (col_counter < MAC_COL-1) begin
						col_counter <= col_counter + 1'b1;
					end
					else begin
						col_counter <= 0;
						state <= WEIGHT;
						w_prefetch_out <= 1'b1;
						w_read_en_out <= 1'b1;
					end
				end
			endcase
		end
	end

	always @(posedge clk) begin
		if (~rstn) begin
			ofmap_addr_out <= {OFMAP_ADDR_BIT{1'b0}};
			ofmap_write_done_out <= 1'b0;
		end
		else begin
			if (ofmap_ready_in) begin
				if (ofmap_addr_out < OFMAP_SIZE - NUM_OUT_TILE) begin
					ofmap_addr_out <= ofmap_addr_out + NUM_OUT_TILE;
				end
				else if (ofmap_addr_out == OFMAP_SIZE - 1) begin
					ofmap_addr_out <= 0;
				end
				else begin
					ofmap_addr_out <= ofmap_addr_out - (OFMAP_SIZE - NUM_OUT_TILE) + 1;
				end
				
				if (state == IDLE) begin		// if all input is given and state is already IDLE
					if (ofmap_addr_out == OFMAP_SIZE - 1 - NUM_OUT_TILE) begin
						ofmap_write_done_out <= 1'b1;
					end
					else begin
						ofmap_write_done_out <= 1'b0;
					end
				end
			end
		end
	end
endmodule
