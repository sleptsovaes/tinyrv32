`timescale 1ns/1ps

module pc_tb;

    logic clk;
    logic reset;

    logic [31:0] pc_out;
    logic [31:0] next_pc_value;

    logic [31:0] imm;

    logic branch;
    logic branch_ne;
    logic zero;
    logic jump;

    pc pc_dut (
        .clk(clk),
        .reset(reset),
        .next_pc(next_pc_value),
        .pc_out(pc_out)
    );

    next_pc next_pc_dut (
        .pc(pc_out),
        .imm(imm),
        .branch(branch),
        .branch_ne(branch_ne),
        .zero(zero),
        .jump(jump),
        .next_pc_value(next_pc_value)
    );

    always #5 clk = ~clk;

    initial begin

        $dumpfile("pc.vcd");
        $dumpvars(0, pc_tb);

        clk = 0;
        reset = 1;

        imm = 0;
        branch = 0;
        branch_ne = 0;
        zero = 0;
        jump = 0;

        // Reset
        #10;
        reset = 0;

        // Normal execution: PC 0 -> 4 -> 8
        #20;

        if (pc_out !== 32'd8)
            $display("FAIL: normal PC expected 8, got %0d", pc_out);
        else
            $display("PASS: normal PC = %0d", pc_out);


        // BEQ taken: 8 + 16 = 24
        branch = 1;
        branch_ne = 0;
        zero = 1;
        imm = 32'd16;

        #10;

        if (pc_out !== 32'd24)
            $display("FAIL: BEQ expected 24, got %0d", pc_out);
        else
            $display("PASS: BEQ taken, PC = %0d", pc_out);


        // BNE not taken: 24 + 4 = 28
        branch_ne = 1;
        zero = 1;

        #10;

        if (pc_out !== 32'd28)
            $display("FAIL: BNE not taken expected 28, got %0d", pc_out);
        else
            $display("PASS: BNE not taken, PC = %0d", pc_out);


        // BNE taken: 28 + 12 = 40
        zero = 0;
        imm = 32'd12;

        #10;

        if (pc_out !== 32'd40)
            $display("FAIL: BNE expected 40, got %0d", pc_out);
        else
            $display("PASS: BNE taken, PC = %0d", pc_out);


        // JAL: 40 + 20 = 60
        branch = 0;
        branch_ne = 0;
        jump = 1;
        imm = 32'd20;

        #10;

        if (pc_out !== 32'd60)
            $display("FAIL: JAL expected 60, got %0d", pc_out);
        else
            $display("PASS: JAL, PC = %0d", pc_out);


        $display("Program Counter tests finished");
        $finish;

    end

endmodule
