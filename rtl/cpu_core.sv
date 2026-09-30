module cpu_core (
    input  logic        clk,
    input  logic        reset,

    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic        dmem_we,
    input  logic [31:0] dmem_rdata
);

    // Pipeline state

    // Stage 1: fetch PC
    logic [31:0] fetch_pc;

    // Stage 2: instruction + PC
    logic [31:0] exec_pc;
    logic [31:0] exec_instr;
    logic        exec_valid;


    // Decode / datapath

    logic [31:0] next_pc_value;

    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;

    logic [31:0] read_data1;
    logic [31:0] read_data2;
    logic [31:0] write_data;

    logic [31:0] imm;

    logic reg_write;
    logic alu_src_imm;

    logic mem_read;
    logic mem_write;
    logic mem_to_reg;

    logic branch;
    logic branch_ne;
    logic jump;

    logic [3:0] alu_op;

    logic [31:0] alu_a;
    logic [31:0] alu_b;
    logic [31:0] alu_result;

    logic zero;

    logic branch_taken;
    logic redirect;

    logic rf_we;


    // Stage 1 - Instruction fetch

    assign imem_addr = fetch_pc;


    // Stage 2 — Decode

    assign rs1 = exec_instr[19:15];
    assign rs2 = exec_instr[24:20];
    assign rd  = exec_instr[11:7];


    // ALU

    assign alu_a = read_data1;

    assign alu_b =
        alu_src_imm
        ? imm
        : read_data2;

    assign zero =
        (alu_result == 32'd0);


    // Memory interface

    assign dmem_addr =
        alu_result;

    assign dmem_wdata =
        read_data2;

    // No architectural side effect from an invalid pipeline slot
    // or while reset is asserted.
    assign dmem_we =
        mem_write &&
        exec_valid &&
        !reset;


    // Register-file writeback

    assign rf_we =
        reg_write &&
        exec_valid &&
        !reset;

    assign write_data =
        jump
        ? (exec_pc + 32'd4)
        : (
            mem_to_reg
            ? dmem_rdata
            : alu_result
        );



    assign branch_taken =
        branch &&
        (
            (!branch_ne && zero) ||
            ( branch_ne && !zero)
        );

    assign redirect =
        exec_valid &&
        (
            jump ||
            branch_taken
        );



    always_ff @(posedge clk) begin

        if (reset) begin

            fetch_pc   <= 32'd0;
            exec_pc    <= 32'd0;
            exec_instr <= 32'h00000013;
            exec_valid <= 1'b0;

        end
        else begin

            if (redirect) begin

                // Wrong-path fetched instruction is discarded.
                fetch_pc <= next_pc_value;

                // Insert one bubble into execute stage.
                exec_valid <= 1'b0;

            end
            else begin

                // Move fetched instruction into execute stage.
                exec_pc    <= fetch_pc;
                exec_instr <= imem_rdata;
                exec_valid <= 1'b1;

                // Continue sequential fetching.
                fetch_pc <= fetch_pc + 32'd4;

            end

        end

    end


    // Next-PC calculation for instruction in execute stage

    next_pc npc_unit (
        .pc(exec_pc),
        .imm(imm),

        .branch(branch),
        .branch_ne(branch_ne),
        .zero(zero),
        .jump(jump),

        .next_pc_value(next_pc_value)
    );


    // Register file

    regfile rf (
        .clk(clk),
        .we(rf_we),

        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),

        .write_data(write_data),

        .read_data1(read_data1),
        .read_data2(read_data2)
    );


    // Immediate generator

    imm_gen immediate_unit (
        .instr(exec_instr),
        .imm(imm)
    );


    // Control unit

    control_unit control (
        .opcode(exec_instr[6:0]),
        .funct3(exec_instr[14:12]),
        .funct7(exec_instr[31:25]),

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


    // ALU

    alu alu_unit (
        .a(alu_a),
        .b(alu_b),
        .op(alu_op),
        .result(alu_result)
    );


endmodule
