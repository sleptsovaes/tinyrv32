`timescale 1ns/1ps

module imm_gen_tb;

    logic [31:0] instr;
    logic [31:0] imm;

    imm_gen dut (
        .instr(instr),
        .imm(imm)
    );

    task check(
        input logic [31:0] test_instr,
        input logic [31:0] expected
    );
    begin

        instr = test_instr;
        #1;

        if (imm !== expected)
            $display(
                "FAIL: instr=%h imm=%h expected=%h",
                instr, imm, expected
            );
        else
            $display(
                "PASS: instr=%h imm=%h",
                instr, imm
            );

    end
    endtask


    initial begin

        $dumpfile("imm_gen.vcd");
        $dumpvars(0, imm_gen_tb);


        // ADDI x1, x2, -5
        check(
            {12'hFFB, 5'd2, 3'b000, 5'd1, 7'b0010011},
            32'hFFFFFFFB
        );


        // LW x4, 16(x3)
        check(
            {12'd16, 5'd3, 3'b010, 5'd4, 7'b0000011},
            32'd16
        );


        // SW x5, -8(x6)
        check(
            {7'b1111111, 5'd5, 5'd6, 3'b010,
             5'b11000, 7'b0100011},
            32'hFFFFFFF8
        );


        // BEQ x1, x2, -4
        check(
            {1'b1, 6'b111111,
             5'd2, 5'd1, 3'b000,
             4'b1110, 1'b1,
             7'b1100011},
            32'hFFFFFFFC
        );


        // JAL x1, +20
        check(
            {1'b0,
             10'b0000001010,
             1'b0,
             8'b00000000,
             5'd1,
             7'b1101111},
            32'd20
        );


        // LUI x1, 0x12345
        check(
            {20'h12345, 5'd1, 7'b0110111},
            32'h12345000
        );


        $display("Immediate Generator tests finished");
        $finish;

    end

endmodule
