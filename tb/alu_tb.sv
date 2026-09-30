`timescale 1ns/1ps

module alu_tb;

    logic [31:0] a;
    logic [31:0] b;
    logic [3:0]  op;
    logic [31:0] result;

    alu dut (
        .a(a),
        .b(b),
        .op(op),
        .result(result)
    );

    task check(
        input logic [31:0] test_a,
        input logic [31:0] test_b,
        input logic [3:0]  test_op,
        input logic [31:0] expected
    );
    begin
        a = test_a;
        b = test_b;
        op = test_op;

        #1;

        if (result !== expected) begin
            $display(
                "FAIL: op=%0d a=%0d b=%0d result=%0d expected=%0d",
                op, a, b, result, expected
            );
        end
        else begin
            $display(
                "PASS: op=%0d a=%0d b=%0d result=%0d",
                op, a, b, result
            );
        end
    end
    endtask

    initial begin

	$dumpfile("alu.vcd");
	$dumpvars(0, alu_tb);

        check(32'd10, 32'd5, 4'd0, 32'd15);
        check(32'd10, 32'd5, 4'd1, 32'd5);

        check(32'hF0F0, 32'h0FF0, 4'd2, 32'h00F0);
        check(32'hF000, 32'h0F00, 4'd3, 32'hFF00);
        check(32'hAAAA, 32'h5555, 4'd4, 32'hFFFF);

        check(32'd1, 32'd4, 4'd5, 32'd16);
        check(32'd16, 32'd2, 4'd6, 32'd4);

        check(32'd5, 32'd10, 4'd7, 32'd1);
        check(32'd10, 32'd5, 4'd7, 32'd0);

        check(-32'sd5, 32'sd3, 4'd7, 32'd1);

        $display("ALU tests finished");
        $finish;
    end

endmodule
