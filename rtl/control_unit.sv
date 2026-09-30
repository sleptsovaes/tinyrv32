module control_unit (
    input  logic [6:0] opcode,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,

    output logic       reg_write,
    output logic       alu_src_imm,

    output logic       mem_read,
    output logic       mem_write,
    output logic       mem_to_reg,

    output logic       branch,
    output logic       branch_ne,
    output logic       jump,

    output logic [3:0] alu_op
);

    always @(*) begin

        reg_write   = 1'b0;
        alu_src_imm = 1'b0;

        mem_read    = 1'b0;
        mem_write   = 1'b0;
        mem_to_reg  = 1'b0;

        branch      = 1'b0;
        branch_ne   = 1'b0;
        jump        = 1'b0;

        alu_op      = 4'd0;

        case (opcode)

            // R-type
            7'b0110011: begin

                reg_write = 1'b1;

                case (funct3)

                    3'b000: begin
                        if (funct7 == 7'b0100000)
                            alu_op = 4'd1;   // SUB
                        else
                            alu_op = 4'd0;   // ADD
                    end

                    3'b111:
                        alu_op = 4'd2;       // AND

                    3'b110:
                        alu_op = 4'd3;       // OR

                    3'b100:
                        alu_op = 4'd4;       // XOR

                    3'b001:
                        alu_op = 4'd5;       // SLL

                    3'b101:
                        alu_op = 4'd6;       // SRL

                    3'b010:
                        alu_op = 4'd7;       // SLT

                    default:
                        alu_op = 4'd0;

                endcase
            end


            // ADDI
            7'b0010011: begin
                if (funct3 == 3'b000) begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;
                    alu_op      = 4'd0;
                end
            end


            // LW
            7'b0000011: begin
                if (funct3 == 3'b010) begin
                    reg_write   = 1'b1;
                    alu_src_imm = 1'b1;

                    mem_read    = 1'b1;
                    mem_to_reg  = 1'b1;

                    alu_op      = 4'd0;
                end
            end


            // SW
            7'b0100011: begin
                if (funct3 == 3'b010) begin
                    alu_src_imm = 1'b1;
                    mem_write   = 1'b1;

                    alu_op      = 4'd0;
                end
            end


            // BEQ / BNE
            7'b1100011: begin

                alu_op = 4'd1;

                if (funct3 == 3'b000) begin
                    branch    = 1'b1;
                    branch_ne = 1'b0;
                end

                else if (funct3 == 3'b001) begin
                    branch    = 1'b1;
                    branch_ne = 1'b1;
                end

            end


            // JAL
            7'b1101111: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                alu_op    = 4'd0;
            end


            default: begin
            end

        endcase

    end

endmodule
