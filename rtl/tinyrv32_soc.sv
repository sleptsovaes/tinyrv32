// FPGA-oriented simulation/synthesis top: 16 KiB initialized RAM and 8N1 UART.
// A board-specific clock/reset/pin wrapper is intentionally a separate layer.
module tinyrv32_soc #(
    parameter MEM_FILE="",
    parameter integer BAUD_DIV=434,
    parameter bit STATIC_PREDICT=1'b1
)(
    input logic clk, reset,
    output logic serial_tx, halted,
    output logic [31:0] program_status,
    output logic status_valid,
    output logic [3:0] trap_cause
);
    logic imem_valid, imem_cancel, imem_ready;
    logic [31:0] imem_addr, imem_rdata;
    logic dmem_valid, dmem_ready, dmem_write;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0] dmem_wstrb;
    logic tx_ready;
    (* ram_style="block" *) logic [31:0] ram[0:4095];
    integer i, lane;
    rv32_core #(.STATIC_PREDICT(STATIC_PREDICT)) cpu(
        .clk(clk),.reset(reset),.imem_valid(imem_valid),.imem_cancel(imem_cancel),
        .imem_addr(imem_addr),.imem_ready(imem_ready),.imem_rdata(imem_rdata),
        .dmem_valid(dmem_valid),.dmem_write(dmem_write),.dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),.dmem_wstrb(dmem_wstrb),
        .dmem_ready(dmem_ready),.dmem_rdata(dmem_rdata),
        .halted(halted),.trap_cause(trap_cause)
    );
    uart_tx #(.BAUD_DIV(BAUD_DIV)) uart(
        .clk(clk),.reset(reset),
        .start(!reset && dmem_valid && dmem_ready && dmem_write && dmem_addr==32'h10000000),
        .data(dmem_wdata[7:0]),.tx(serial_tx),.ready(tx_ready)
    );
    initial begin
        for(i=0;i<4096;i=i+1) ram[i]=0;
        if (MEM_FILE!="") $readmemh(MEM_FILE,ram);
    end
    always @(posedge clk) begin
        if (reset) begin
            imem_ready<=0; dmem_ready<=0; imem_rdata<=0; dmem_rdata<=0;
            program_status<=0; status_valid<=0;
        end else begin
            imem_ready<=0; dmem_ready<=0;
            if (!imem_cancel && imem_valid && !imem_ready) begin
                imem_rdata<=imem_addr<16384 ? ram[imem_addr >> 2] : 0;
                imem_ready<=1;
            end
            if (dmem_valid && !dmem_ready &&
                (dmem_addr!=32'h10000000 || tx_ready)) begin
                dmem_rdata<=dmem_addr<16384 ? ram[dmem_addr >> 2] : 0;
                dmem_ready<=1;
            end
            if (dmem_valid && dmem_ready && dmem_write) begin
                if (dmem_addr==32'h10000004) begin
                    program_status<=dmem_wdata; status_valid<=1;
                end else if (dmem_addr<16384) begin
                    for(lane=0;lane<4;lane=lane+1)
                        if (dmem_wstrb[lane]) ram[dmem_addr >> 2][lane*8+:8]<=dmem_wdata[lane*8+:8];
                end
            end
        end
    end
endmodule
