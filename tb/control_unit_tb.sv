`timescale 1ns/1ps

module control_unit_tb;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    logic reg_write;
    logic alu_src_imm;

    logic mem_read;
    logic mem_write;
    logic mem_to_reg;

    logic branch;
    logic branch_ne;
    logic jump;

    logic [3:0] alu_op;

    control_unit dut (
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),

        .reg_write(reg_write),
        .alu_src_imm(alu_src_imm),

        .mem_read(mem_read),
        .mem_write(mem_write),
        .mem_to_reg(mem_to_reg),

        .branch(branch),
        .branch_ne(branch_ne),
        .jump(jump),

        .alu_op(alu_op)
    );


    task check(
        input logic [6:0] test_opcode,
        input logic [2:0] test_funct3,
        input logic [6:0] test_funct7,

        input logic exp_reg_write,
        input logic exp_alu_src_imm,

        input logic exp_mem_read,
        input logic exp_mem_write,
        input logic exp_mem_to_reg,

        input logic exp_branch,
        input logic exp_branch_ne,
        input logic exp_jump,

        input logic [3:0] exp_alu_op
    );

    begin

        opcode = test_opcode;
        funct3 = test_funct3;
        funct7 = test_funct7;

        #1;

        if (
            reg_write   !== exp_reg_write   ||
            alu_src_imm !== exp_alu_src_imm ||
            mem_read    !== exp_mem_read    ||
            mem_write   !== exp_mem_write   ||
            mem_to_reg  !== exp_mem_to_reg  ||
            branch      !== exp_branch      ||
            branch_ne   !== exp_branch_ne   ||
            jump        !== exp_jump        ||
            alu_op      !== exp_alu_op
        )
        begin

            $display(
                "FAIL opcode=%b funct3=%b funct7=%b",
                opcode, funct3, funct7
            );

        end
        else begin

            $display(
                "PASS opcode=%b funct3=%b alu_op=%0d",
                opcode, funct3, alu_op
            );

        end

    end

    endtask


    initial begin

        $dumpfile("control_unit.vcd");
        $dumpvars(0, control_unit_tb);


        // ADD
        check(
            7'b0110011, 3'b000, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd0
        );


        // SUB
        check(
            7'b0110011, 3'b000, 7'b0100000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd1
        );


        // AND
        check(
            7'b0110011, 3'b111, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd2
        );


        // OR
        check(
            7'b0110011, 3'b110, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd3
        );


        // XOR
        check(
            7'b0110011, 3'b100, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd4
        );


        // SLL
        check(
            7'b0110011, 3'b001, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd5
        );


        // SRL
        check(
            7'b0110011, 3'b101, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd6
        );


        // SLT
        check(
            7'b0110011, 3'b010, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 0,
            4'd7
        );


        // ADDI
        check(
            7'b0010011, 3'b000, 7'b0000000,
            1, 1,
            0, 0, 0,
            0, 0, 0,
            4'd0
        );


        // LW
        check(
            7'b0000011, 3'b010, 7'b0000000,
            1, 1,
            1, 0, 1,
            0, 0, 0,
            4'd0
        );


        // SW
        check(
            7'b0100011, 3'b010, 7'b0000000,
            0, 1,
            0, 1, 0,
            0, 0, 0,
            4'd0
        );


        // BEQ
        check(
            7'b1100011, 3'b000, 7'b0000000,
            0, 0,
            0, 0, 0,
            1, 0, 0,
            4'd1
        );


        // BNE
        check(
            7'b1100011, 3'b001, 7'b0000000,
            0, 0,
            0, 0, 0,
            1, 1, 0,
            4'd1
        );


        // JAL
        check(
            7'b1101111, 3'b000, 7'b0000000,
            1, 0,
            0, 0, 0,
            0, 0, 1,
            4'd0
        );


        $display("Control Unit tests finished");
        $finish;

    end

endmodule
