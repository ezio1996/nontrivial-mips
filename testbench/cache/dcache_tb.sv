`include "common_defs.svh"

`define PATH_PREFIX "testbench/cache/cases/"

`define CASE_NAME "random.data"

module dcache_tb();

logic rst, clk;
axi_req_t axi_req;
axi_resp_t axi_resp;

always #5 clk = ~clk;

mem_device id (
	.clk (clk),
	.rst (rst),
	.axi_req (axi_req),
	.axi_resp (axi_resp)
);

cpu_dbus_if dbus();

// Size = 2048, Line-Width = 256 => 8 lines
// Assoc = 2, so we have 4 lines in each ram
//
// Line byte offset = 5,
// Index width = 2
// So we generated data in addr 0x00 ~ 0xFF should be enough to test all
// scenarios

dcache #(
    .SET_ASSOC (2), // Testing write-back
    .CACHE_SIZE(2048)
) cache (
	.clk (clk),
	.rst (rst),
	.axi_req (axi_req),
	.axi_resp (axi_resp),

	.dbus (dbus),
	.axi_req_awid ( /* open */ ),
	.axi_req_arid ( /* open */ ),
	.axi_req_wid ( /* open */ ),
	.axi_resp_rid (4'b0000),
	.axi_resp_bid (4'b0000)
);

localparam int unsigned REQ_COUNT = 256 * 5;
logic [$clog2(REQ_COUNT+3):0] req;
logic [REQ_COUNT+3:0][31:0] address;
logic [REQ_COUNT+3:0][31:0] data;
typedef enum logic [1:0] {
	READ, WRITE
} req_type_t;
req_type_t req_type [REQ_COUNT+3:0];
req_type_t current_type;

assign dbus.address = address[req];
assign dbus.wrdata = data[req];
assign current_type = req_type[req];
assign dbus.read           = current_type == READ;
assign dbus.write          = current_type == WRITE;
assign dbus.byteenable = 4'b1111;

always_ff @(posedge clk or posedge rst) begin
	if(rst) begin
		req <= 0;
	end else if(~dbus.stall) begin
		req <= req + 1;
	end
end

integer cycle;
always_ff @(negedge clk) begin
	cycle <= rst ? '0 : cycle + 1;
	if(~rst && req > 1 && ~dbus.stall) begin
		$display("[%0d] req = %0d, data = %08x", cycle, req-2, dbus.rddata);
		if(req_type[req-2] == READ && ~(dbus.rddata == data[req-2])) begin
			$display("[Error] expected = %08x", data[req-2]);
			$stop;
		end

        if(req == REQ_COUNT+1) begin
            $display("[pass]");
            $finish;
        end
	end
end

int fd, path_counter;
byte mode [REQ_COUNT-1:0];
int status;
string path;

initial begin
	rst = 1'b1;
	clk = 1'b1;

	path_counter = 0;
	if(!$fopen({ path, `CASE_NAME, ".ans"}, "r")) begin
		path = `PATH_PREFIX;
		while(!$fopen({ path, `CASE_NAME }, "r") && path_counter < 20) begin
			path_counter++;
			path = { "../", path };
		end
	end

    fd = $fopen({ path, `CASE_NAME }, "r");
    for(int i = 0; i < REQ_COUNT; i++) begin
        status = $fscanf(fd, "%c %h %h\n", mode[i], address[i], data[i]);
        $display("%d", status);
        case(mode[i])
            "r": req_type[i] = READ;
            "w": req_type[i] = WRITE;
        endcase
    end

    // Read file

	#51 rst = 1'b0;
	wait(req == REQ_COUNT + 2);
end

endmodule
