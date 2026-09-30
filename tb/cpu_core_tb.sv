`timescale 1ns/1ps

module cpu_core_tb;

    logic clk;
    logic reset;

    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic        dmem_we;
    logic [31:0] dmem_rdata;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    integer i;


    cpu_core dut (
        .clk(clk),
        .reset(reset),

        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),

        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we),
        .dmem_rdata(dmem_rdata)
    );


    assign imem_rdata = imem[imem_addr[7:2]];
    assign dmem_rdata = dmem[dmem_addr[7:2]];


    always @(posedge clk) begin
        if (dmem_we)
            dmem[dmem_addr[7:2]] <= dmem_wdata;
    end


    always #5 clk = ~clk;


    initial begin

        $dumpfile("cpu_core.vcd");
        $dumpvars(0, cpu_core_tb);

        clk = 0;
        reset = 1;

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'd0;
            dmem[i] = 32'd0;
        end


        // addi x1, x0, 5
        imem[0] = 32'h00500093;

        // addi x2, x0, 7
        imem[1] = 32'h00700113;

        // add x3, x1, x2
        imem[2] = 32'h002081B3;

        // sw x3, 0(x0)
        imem[3] = 32'h00302023;

        // lw x4, 0(x0)
        imem[4] = 32'h00002203;

        // beq x3, x4, +8
        imem[5] = 32'h00418463;

        // SHOULD BE SKIPPED:
        // addi x5, x0, 99
        imem[6] = 32'h06300293;

        // addi x5, x0, 42
        imem[7] = 32'h02A00293;

        // jal x0, 0
        // endless loop
        imem[8] = 32'h0000006F;


        #12;
        reset = 0;


        #90;


        if (dut.rf.regs[1] !== 32'd5)
            $display("FAIL: x1 expected 5");
        else
            $display("PASS: x1 = 5");


        if (dut.rf.regs[2] !== 32'd7)
            $display("FAIL: x2 expected 7");
        else
            $display("PASS: x2 = 7");


        if (dut.rf.regs[3] !== 32'd12)
            $display("FAIL: x3 expected 12");
        else
            $display("PASS: x3 = 12");


        if (dmem[0] !== 32'd12)
            $display("FAIL: memory[0] expected 12");
        else
            $display("PASS: memory[0] = 12");


        if (dut.rf.regs[4] !== 32'd12)
            $display("FAIL: x4 expected 12");
        else
            $display("PASS: x4 = 12");


        if (dut.rf.regs[5] !== 32'd42)
            $display(
                "FAIL: x5 expected 42, got %0d",
                dut.rf.regs[5]
            );
        else
            $display("PASS: branch worked, x5 = 42");


        $display("CPU integration tests finished");

        $finish;

    end

endmodule
