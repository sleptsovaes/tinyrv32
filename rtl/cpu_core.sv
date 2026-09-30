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

    logic [31:0] pc_value;
    logic [31:0] next_pc_value;
    logic [31:0] instr;

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

    assign instr = imem_rdata;
    assign imem_addr = pc_value;

    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign rd  = instr[11:7];

    assign alu_a = read_data1;

    assign alu_b =
        alu_src_imm
        ? imm
        : read_data2;

    assign zero = (alu_result == 32'd0);

    assign dmem_addr  = alu_result;
    assign dmem_wdata = read_data2;
    assign dmem_we    = mem_write;

    assign write_data =
        jump
        ? (pc_value + 32'd4)
        : (
            mem_to_reg
            ? dmem_rdata
            : alu_result
        );


    pc pc_unit (
        .clk(clk),
        .reset(reset),
        .next_pc(next_pc_value),
        .pc_out(pc_value)
    );


    next_pc npc_unit (
        .pc(pc_value),
        .imm(imm),

        .branch(branch),
        .branch_ne(branch_ne),
        .zero(zero),
        .jump(jump),

        .next_pc_value(next_pc_value)
    );


    regfile rf (
        .clk(clk),
        .we(reg_write),

        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),

        .write_data(write_data),

        .read_data1(read_data1),
        .read_data2(read_data2)
    );


    imm_gen immediate_unit (
        .instr(instr),
        .imm(imm)
    );


    control_unit control (
        .opcode(instr[6:0]),
        .funct3(instr[14:12]),
        .funct7(instr[31:25]),

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


    alu alu_unit (
        .a(alu_a),
        .b(alu_b),
        .op(alu_op),
        .result(alu_result)
    );

endmodule
