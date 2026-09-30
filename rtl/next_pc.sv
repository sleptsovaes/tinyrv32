module next_pc (
    input  logic [31:0] pc,
    input  logic [31:0] imm,

    input  logic        branch,
    input  logic        branch_ne,
    input  logic        zero,
    input  logic        jump,

    output logic [31:0] next_pc_value
);

    logic branch_taken;

    always @(*) begin

        branch_taken =
            branch &&
            (
                (!branch_ne && zero) ||
                ( branch_ne && !zero)
            );

        if (jump)
            next_pc_value = pc + imm;

        else if (branch_taken)
            next_pc_value = pc + imm;

        else
            next_pc_value = pc + 32'd4;

    end

endmodule
