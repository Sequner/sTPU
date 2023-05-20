/////////////////////////////////////////////////////////////////////
//
// EE488(G) Project 3
// Title: Systolic.sv
//
/////////////////////////////////////////////////////////////////////
 
`timescale 1 ns / 1 ps

module Systolic 
#(
	// logic parameter
	parameter MAC_ROW                           = 16,
	parameter MAC_COL                           = 16,
	parameter W_BITWIDTH                        = 8,
	parameter IFMAP_BITWIDTH                    = 16,
	parameter OFMAP_BITWIDTH                    = 32,
	parameter W_ADDR_BIT                        = 11,
	parameter IFMAP_ADDR_BIT                    = 9,
	parameter OFMAP_ADDR_BIT                    = 10,
	// operation parameter
	parameter OFMAP_CAHNNEL_NUM                 = 64,
	parameter IFMAP_CAHNNEL_NUM                 = 32,
	parameter WEIGHT_WIDTH                      = 3,
	parameter WEIGHT_HEIGHT                     = 3,
	parameter IFMAP_WIDTH                       = 16,
	parameter IFMAP_HEIGHT                      = 16,
	parameter OFMAP_WIDTH                       = 14,
	parameter OFMAP_HEIGHT                      = 14,
	// initialization data path
	parameter IFMAP_DATA_PATH                   = "",
	parameter WEIGHT_DATA_PATH                  = "",
	parameter OFMAP_DATA_PATH                   = ""
)
(
	input  logic                                clk,
	input  logic                                rstn,

	// do not modify this port: for verification at simulation
	input  logic [OFMAP_ADDR_BIT-1:0]           test_output_addr_in,
	input  logic                                test_check_in,
	output logic [MAC_COL*OFMAP_BITWIDTH-1:0]   test_output_out,

	input  logic                                start_in,

	output logic                                finish_out
);

	localparam	NUM_OUT_TILE = (OFMAP_CAHNNEL_NUM-1)/MAC_COL + 1,
					OFMAP_SIZE = OFMAP_WIDTH * OFMAP_HEIGHT * OFMAP_CAHNNEL_NUM / MAC_COL;

	logic [MAC_COL-1:0][W_BITWIDTH-1:0]         			w_data;
	logic [W_ADDR_BIT-1:0]                      			w_addr;

	logic [MAC_ROW-1:0][IFMAP_BITWIDTH-1:0]     			ifmap_data;
	logic [IFMAP_ADDR_BIT-1:0]                  			ifmap_addr;

	logic [MAC_COL-1:0][OFMAP_BITWIDTH-1:0]     			ofmap_wdata;
	logic [OFMAP_ADDR_BIT-1:0]                  			ofmap_addr;
	logic                                       			ofmap_wen;

	logic signed [MAC_COL-1:0][OFMAP_BITWIDTH-1:0]     psum_data;
	logic [OFMAP_ADDR_BIT-1:0]                  			psum_addr;
	logic [OFMAP_ADDR_BIT-1:0]                  			psum_addr_mux;
	
	logic 															w_prefetch;
	logic 															w_read_en;
	logic																array_w_read_en;
	
	logic																memctrl_ifmap_start;
	logic																memctrl_ifmap_read_en;
	
	logic [MAC_ROW-1:0]											fifo_ifmap_read_en;
	logic																fifo_ifmap_write_en;
	logic	[MAC_ROW-1:0][IFMAP_BITWIDTH-1:0]				fifo_ifmap_data_out;
	
	logic	[MAC_COL-1:0][OFMAP_BITWIDTH-1:0]				fifo_ofmap_data_in; 
	logic	[MAC_COL-1:0]											fifo_ofmap_write_en;
	logic signed [MAC_COL-1:0][OFMAP_BITWIDTH-1:0]		fifo_ofmap_data_out;
	logic																fifo_ofmap_read_en;

	logic																repeated_ofmap;
	
	// To increase clock frequency
	logic	[MAC_ROW-1:0][IFMAP_BITWIDTH-1:0]				ifmap_buffer;
	logic	[MAC_ROW-1:0]											ifmap_read_en_delay;
	
	logic [MAC_COL-1:0][OFMAP_BITWIDTH-1:0]				psum_buffer;
	logic [MAC_COL-1:0][OFMAP_BITWIDTH-1:0]				ofmap_buffer;
	logic 															ofmap_ready;
	
	always_comb begin
		fifo_ofmap_read_en = fifo_ofmap_write_en[MAC_COL-1];
		fifo_ofmap_data_out[MAC_COL-1] = fifo_ofmap_data_in[MAC_COL-1];
		fifo_ifmap_data_out[0] = ifmap_data[MAC_ROW-1];
		for (int i = 0; i < MAC_COL; i++) begin
			ofmap_wdata[i] = (repeated_ofmap) ? ofmap_buffer[i] + psum_buffer[i] : ofmap_buffer[i];
		end
	end
	
	always_ff @(posedge clk) begin
		if (~rstn) begin
			psum_addr <= 0;
			array_w_read_en <= 1'b0;
			fifo_ifmap_read_en[0] <= 1'b0;
			fifo_ifmap_write_en <= 1'b0;
		end
		else begin
			// weight
			array_w_read_en <= w_read_en;
			
			// input fifo
			fifo_ifmap_read_en[0] <= memctrl_ifmap_read_en;
			fifo_ifmap_write_en <= memctrl_ifmap_read_en;
			
			// input array
			ifmap_read_en_delay <= fifo_ifmap_read_en;
			ifmap_buffer <= fifo_ifmap_data_out;
			
			// output array
			psum_buffer <= psum_data;
			ofmap_ready <= fifo_ofmap_write_en[MAC_COL-1];
			ofmap_buffer <= fifo_ofmap_data_out;
			
			// read ofmap mem
			if (fifo_ofmap_write_en[MAC_COL-2]) begin		// since SRAM has 1 cycle delay		
				psum_addr <= psum_addr + NUM_OUT_TILE;		// we need to prefetch data
			end
			else begin
				psum_addr <= ofmap_addr;
			end
		end
	end
	
	always_ff @(posedge clk) begin
		if (~rstn) begin
			repeated_ofmap <= 1'b0;
		end
		else begin
			if ((repeated_ofmap || ofmap_addr == OFMAP_SIZE-1) && ~finish_out) begin
				repeated_ofmap <= 1'b1;
			end
			else begin
				repeated_ofmap <= 1'b0;
			end
		end
	end
	
	MacArray
	#(
		 .MAC_ROW								(MAC_ROW),
		 .MAC_COL								(MAC_COL),
		 .IFMAP_BITWIDTH						(IFMAP_BITWIDTH),
		 .W_BITWIDTH							(W_BITWIDTH),
		 .OFMAP_BITWIDTH						(OFMAP_BITWIDTH)
	)
	Array (
		 .clk										(clk),
		 .rstn									(rstn),
		 .w_prefetch_in						(w_prefetch),				// don't care about this signal, but it was in specifications
		 .w_enable_in							(array_w_read_en),
		 .w_data_in								(w_data),
		 .ifmap_start_in						(memctrl_ifmap_start), 	// don't care about this signal, but it was in specifications
		 .ifmap_enable_in						(ifmap_read_en_delay),
		 .ifmap_data_in						(ifmap_buffer),
		 .ofmap_valid_out						(fifo_ofmap_write_en),
		 .ofmap_data_out						(fifo_ofmap_data_in)
	);
	
	MemoryController
	#(
		// logic parameter
		.MAC_ROW									(MAC_ROW),
		.MAC_COL									(MAC_COL),
		.W_BITWIDTH								(W_BITWIDTH),
		.IFMAP_BITWIDTH						(IFMAP_BITWIDTH),
		.OFMAP_BITWIDTH						(OFMAP_BITWIDTH),
		.W_ADDR_BIT								(W_ADDR_BIT),
		.IFMAP_ADDR_BIT						(IFMAP_ADDR_BIT),
		.OFMAP_ADDR_BIT						(OFMAP_ADDR_BIT),
		// operation parameter
		.OFMAP_CAHNNEL_NUM					(OFMAP_CAHNNEL_NUM),
		.IFMAP_CAHNNEL_NUM					(IFMAP_CAHNNEL_NUM),
		.WEIGHT_WIDTH							(WEIGHT_WIDTH),
		.WEIGHT_HEIGHT							(WEIGHT_HEIGHT),
		.IFMAP_WIDTH							(IFMAP_WIDTH),
		.IFMAP_HEIGHT							(IFMAP_HEIGHT),
		.OFMAP_WIDTH							(OFMAP_WIDTH),
		.OFMAP_HEIGHT							(OFMAP_HEIGHT)
	)
	MemCtrl(
		.clk										(clk),
		.rstn										(rstn),
		.start_in								(start_in),
		.ofmap_ready_in						(ofmap_ready),
		.w_prefetch_out						(w_prefetch),
		.w_addr_out								(w_addr),
		.w_read_en_out							(w_read_en),
		.ifmap_start_out						(memctrl_ifmap_start),
		.ifmap_addr_out						(ifmap_addr),
		.ifmap_read_en_out					(memctrl_ifmap_read_en),
		.mac_done_out							(),
		.ofmap_addr_out						(ofmap_addr),
		.ofmap_write_en_out					(ofmap_wen),
		.ofmap_write_done_out				(finish_out)
	);
	
	generate
	genvar r;
	genvar c;
	for (r = 1; r < MAC_ROW; r++) begin :ifMap
		always_ff @(posedge clk) begin
			fifo_ifmap_read_en[r] <= fifo_ifmap_read_en[r-1];
		end
		
		FIFO
		#(
			.DATA_WIDTH                	(IFMAP_BITWIDTH),
			.LOG_DEPTH                 	($clog2(r+1)),
			.FIFO_DEPTH                	()
		)   
		ifMapFIFO(   
			.clk									(clk),
			.rstn									(rstn),
			.wrreq								(fifo_ifmap_write_en),
			.rdreq								(fifo_ifmap_read_en[r]),
			.data									(ifmap_data[MAC_ROW-1-r]),          
			.q										(fifo_ifmap_data_out[r]),             
			.full									(),
			.empty								()
		);
	end
	
	for (c = 0; c < MAC_COL-1; c++) begin :ofMap
		FIFO
		#(
			.DATA_WIDTH                	(OFMAP_BITWIDTH),
			.LOG_DEPTH                 	($clog2(MAC_COL-c)),
			.FIFO_DEPTH                	()
		)   
		ofMapFIFO(   
			.clk									(clk),
			.rstn									(rstn),
			.wrreq								(fifo_ofmap_write_en[c]),
			.rdreq								(fifo_ofmap_read_en),
			.data									(fifo_ofmap_data_in[c]),          
			.q										(fifo_ofmap_data_out[c]),             
			.full									(),
			.empty								()
		);
	end
	endgenerate
	
	

	// verificate functionality
	assign test_output_out                      = psum_data;
	assign psum_addr_mux                        = test_check_in ? test_output_addr_in : psum_addr;

	// Memory instances
	ifmap_mem i_mem
	(
	  .address                                (ifmap_addr),
	  .clock                                  (clk),
	  .data                                   ({(IFMAP_BITWIDTH*MAC_ROW){1'b0}}),
	  .wren                                   (1'b0),
	  .q                                      (ifmap_data)
	);

	weight_mem w_mem
	(
	  .address                                (w_addr),
	  .clock                                  (clk),
	  .data                                   ({(W_BITWIDTH*MAC_COL){1'b0}}),
	  .wren                                   (1'b0),
	  .q                                      (w_data)
	);

	ofmap_mem o_mem
	(
	  .clock                                  (clk),            
	  .data                                   (ofmap_wdata),            
	  .rdaddress                              (psum_addr_mux),                
	  .wraddress                              (ofmap_addr),                
	  .wren                                   (ofmap_wen),            
	  .q                                      (psum_data)
	);

endmodule
