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

    logic wrong_path_executed;


    // DUT

    cpu_core dut (
        .clk        (clk),
        .reset      (reset),

        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),

        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_we    (dmem_we),
        .dmem_rdata (dmem_rdata)
    );


    // Memories

    assign imem_rdata =
        imem[imem_addr[7:2]];

    assign dmem_rdata =
        dmem[dmem_addr[7:2]];


    always @(posedge clk) begin
        if (dmem_we) begin
            dmem[dmem_addr[7:2]]
                <= dmem_wdata;
        end
    end


    // Clock

    always #5 clk = ~clk;


    // Wrong-path execution detector

    always @(posedge clk) begin

        if (
            !reset &&
            dut.exec_valid &&
            dut.exec_pc == 32'h0000001C
        ) begin
            wrong_path_executed <= 1'b1;
        end

    end


    // Test

    initial begin

        clk                 = 0;
        reset               = 1;
        errors              = 0;
        wrong_path_executed = 0;


        // Initialize memories

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h00000000;
        end


        // TEST 1
        // Reset must block register-file side effects

        $display(
            "TEST: register write blocked during reset"
        );

        dut.rf.regs[31] = 32'h13579BDF;

        // addi x31, x0, 123
        imem[0] = 32'h07B00F93;

        repeat (3)
            @(posedge clk);

        #1;

        if (dut.rf_we !== 1'b0) begin

            $display(
                "FAIL: rf_we asserted during reset"
            );

            errors = errors + 1;

        end


        if (
            dut.rf.regs[31]
            !== 32'h13579BDF
        ) begin

            $display(
                "FAIL: x31 changed during reset"
            );

            errors = errors + 1;

        end


        // TEST 2
        // Reset must block data-memory writes

        $display(
            "TEST: memory write blocked during reset"
        );

        dmem[0] = 32'hDEADBEEF;

        // sw x0, 0(x0)
        imem[0] = 32'h00002023;

        repeat (3)
            @(posedge clk);

        #1;

        if (dmem_we !== 1'b0) begin

            $display(
                "FAIL: dmem_we asserted during reset"
            );

            errors = errors + 1;

        end


        if (
            dmem[0]
            !== 32'hDEADBEEF
        ) begin

            $display(
                "FAIL: data memory changed during reset"
            );

            errors = errors + 1;

        end


        // Load integration-test program

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h00000000;
        end


        // PC 0x00
        // addi x1, x0, 5
        imem[0] = 32'h00500093;

        // PC 0x04
        // addi x2, x0, 7
        imem[1] = 32'h00700113;

        // PC 0x08
        // add x3, x1, x2
        imem[2] = 32'h002081B3;

        // PC 0x0C
        // sw x3, 0(x0)
        imem[3] = 32'h00302023;

        // PC 0x10
        // lw x4, 0(x0)
        imem[4] = 32'h00002203;

        // PC 0x14
        // x6 is the wrong-path sentinel
        // addi x6, x0, 0
        imem[5] = 32'h00000313;

        // PC 0x18
        // beq x3, x4, +8
        //
        // Target = 0x20
        imem[6] = 32'h00418463;

        // PC 0x1C
        // MUST NOT COMMIT
        //
        // addi x6, x0, 99
        imem[7] = 32'h06300313;

        // PC 0x20
        // addi x5, x0, 42
        imem[8] = 32'h02A00293;

        // PC 0x24
        // terminal loop
        //
        // jal x0, 0
        imem[9] = 32'h0000006F;



        @(posedge clk);
        #1;

        // Release away from the active clock edge.
        @(negedge clk);
        reset = 0;


        // Run program

        repeat (40)
            @(posedge clk);

        #1;


        // Architectural-state checks

        if (
            dut.rf.regs[1]
            !== 32'd5
        ) begin

            $display(
                "FAIL x1: expected 5, got %0d",
                dut.rf.regs[1]
            );

            errors = errors + 1;

        end


        if (
            dut.rf.regs[2]
            !== 32'd7
        ) begin

            $display(
                "FAIL x2: expected 7, got %0d",
                dut.rf.regs[2]
            );

            errors = errors + 1;

        end


        if (
            dut.rf.regs[3]
            !== 32'd12
        ) begin

            $display(
                "FAIL x3: expected 12, got %0d",
                dut.rf.regs[3]
            );

            errors = errors + 1;

        end


        if (
            dmem[0]
            !== 32'd12
        ) begin

            $display(
                "FAIL memory[0]: expected 12, got %0d",
                dmem[0]
            );

            errors = errors + 1;

        end


        if (
            dut.rf.regs[4]
            !== 32'd12
        ) begin

            $display(
                "FAIL x4: expected 12, got %0d",
                dut.rf.regs[4]
            );

            errors = errors + 1;

        end


        // Critical branch-flush check.

        if (
            dut.rf.regs[6]
            !== 32'd0
        ) begin

            $display(
                "FAIL branch flush: x6=%0d, expected 0",
                dut.rf.regs[6]
            );

            errors = errors + 1;

        end


        // wrong-path PC may appear on imem_addr, but must never
        // enter the execute stage as a valid instruction.

        if (
            wrong_path_executed
            !== 1'b0
        ) begin

            $display(
                "FAIL: wrong-path instruction at PC=0x1C became valid in execute stage"
            );

            errors = errors + 1;

        end

        if (
            dut.rf.regs[5]
            !== 32'd42
        ) begin

            $display(
                "FAIL x5: expected 42, got %0d",
                dut.rf.regs[5]
            );

            errors = errors + 1;

        end


        // Final result

        if (errors != 0) begin

            $fatal(
                1,
                "CPU REGRESSION FAILED: %0d error(s)",
                errors
            );

        end
        else begin

            $display(
            );

            $display(
                "CPU REGRESSION PASSED"
            );

            $display(
                "Two-stage pipeline branch flush PASSED"
            );

            $display(
            );

            $finish;

        end

    end

endmodule
