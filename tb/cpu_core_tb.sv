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
    integer errors;

    logic visited_skipped_pc;


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


    always @(imem_addr) begin
        if (!reset && imem_addr == 32'h0000001C)
            visited_skipped_pc = 1'b1;
    end


    always #5 clk = ~clk;


    initial begin

        $dumpfile("cpu_core.vcd");
        $dumpvars(0, cpu_core_tb);

        clk = 0;
        reset = 1;
        errors = 0;
        visited_skipped_pc = 0;

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'd0;
            dmem[i] = 32'd0;
        end


        // RESET REGRESSION 1:
        // register writes must be blocked during reset
   
        // addi x31, x0, 123
        imem[0] = 32'h07B00F93;

        #6;

        if (dut.rf_we !== 1'b0) begin
            $display("FAIL: register write enable active during reset");
            errors = errors + 1;
        end
        else begin
            $display("PASS: register writes blocked during reset");
        end

        if (dut.rf.regs[31] === 32'd123) begin
            $display("FAIL: x31 modified during reset");
            errors = errors + 1;
        end
        else begin
            $display("PASS: architectural register state not modified");
        end


        // RESET REGRESSION 2:
        // memory writes must be blocked during reset
      

        dmem[0] = 32'hDEADBEEF;

        // sw x0, 0(x0)
        imem[0] = 32'h00002023;

        #10;

        if (dmem_we !== 1'b0) begin
            $display("FAIL: dmem_we active during reset");
            errors = errors + 1;
        end
        else begin
            $display("PASS: memory writes blocked during reset");
        end

        if (dmem[0] !== 32'hDEADBEEF) begin
            $display(
                "FAIL: memory modified during reset: %h",
                dmem[0]
            );
            errors = errors + 1;
        end
        else begin
            $display("PASS: external memory unchanged during reset");
        end


        // NORMAL CPU PROGRAM

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

        // Initialize x6 = 0.
        // This register becomes our branch sentinel.
        imem[5] = 32'h00000313;

        // beq x3, x4, +8
        // PC 0x18 -> 0x20 if branch is taken
        imem[6] = 32'h00418463;

        // MUST BE SKIPPED:
        // addi x6, x0, 99
        imem[7] = 32'h06300313;

        // addi x5, x0, 42
        imem[8] = 32'h02A00293;

        // jal x0, 0
        imem[9] = 32'h0000006F;


        // Release reset.
        #1;
        reset = 0;


        // Allow complete program execution.
        #110;


        // ARCHITECTURAL STATE CHECKS
 

        if (dut.rf.regs[1] !== 32'd5) begin
            $display(
                "FAIL: x1 expected 5, got %0d",
                dut.rf.regs[1]
            );
            errors = errors + 1;
        end
        else
            $display("PASS: x1 = 5");


        if (dut.rf.regs[2] !== 32'd7) begin
            $display(
                "FAIL: x2 expected 7, got %0d",
                dut.rf.regs[2]
            );
            errors = errors + 1;
        end
        else
            $display("PASS: x2 = 7");


        if (dut.rf.regs[3] !== 32'd12) begin
            $display(
                "FAIL: x3 expected 12, got %0d",
                dut.rf.regs[3]
            );
            errors = errors + 1;
        end
        else
            $display("PASS: x3 = 12");


        if (dmem[0] !== 32'd12) begin
            $display(
                "FAIL: memory[0] expected 12, got %0d",
                dmem[0]
            );
            errors = errors + 1;
        end
        else
            $display("PASS: memory[0] = 12");


        if (dut.rf.regs[4] !== 32'd12) begin
            $display(
                "FAIL: x4 expected 12, got %0d",
                dut.rf.regs[4]
            );
            errors = errors + 1;
        end
        else
            $display("PASS: x4 = 12");


        // REAL BRANCH REGRESSION

        // If BEQ fails, instruction at 0x1C writes 99 to x6.
        if (dut.rf.regs[6] !== 32'd0) begin
            $display(
                "FAIL: branch instruction was not skipped; x6=%0d",
                dut.rf.regs[6]
            );
            errors = errors + 1;
        end
        else
            $display("PASS: skipped instruction did not execute");


        if (visited_skipped_pc !== 1'b0) begin
            $display("FAIL: PC visited skipped address 0x1C");
            errors = errors + 1;
        end
        else
            $display("PASS: PC correctly skipped address 0x1C");


        if (dut.rf.regs[5] !== 32'd42) begin
            $display(
                "FAIL: x5 expected 42, got %0d",
                dut.rf.regs[5]
            );
            errors = errors + 1;
        end
        else
            $display("PASS: branch target executed, x5 = 42");


        // FINAL REGRESSION RESULT


        if (errors != 0) begin
            $fatal(
                1,
                "CPU REGRESSION FAILED: %0d error(s)",
                errors
            );
        end;

        $display("CPU REGRESSION PASSED");

        $finish;

    end

endmodule
