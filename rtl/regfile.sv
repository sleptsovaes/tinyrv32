module regfile (
    input  logic        clk,
    input  logic        we,

    input  logic [4:0]  rs1,
    input  logic [4:0]  rs2,
    input  logic [4:0]  rd,

    input  logic [31:0] write_data,

    output logic [31:0] read_data1,
    output logic [31:0] read_data2
);

    logic [31:0] regs [0:31];

    assign read_data1 = (rs1 == 5'd0) ? 32'd0 : regs[rs1];
    assign read_data2 = (rs2 == 5'd0) ? 32'd0 : regs[rs2];

    always_ff @(posedge clk) begin
        if (we && rd != 5'd0)
            regs[rd] <= write_data;
    end

endmodule
