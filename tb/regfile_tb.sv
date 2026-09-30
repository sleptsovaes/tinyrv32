`timescale 1ns/1ps

module regfile_tb;

    logic clk;
    logic we;

    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rd;

    logic [31:0] write_data;
    logic [31:0] read_data1;
    logic [31:0] read_data2;

    regfile dut (
        .clk(clk),
        .we(we),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .write_data(write_data),
        .read_data1(read_data1),
        .read_data2(read_data2)
    );

    always #5 clk = ~clk;

    initial begin

        $dumpfile("regfile.vcd");
        $dumpvars(0, regfile_tb);

        clk = 0;
        we = 0;
        rs1 = 0;
        rs2 = 0;
        rd = 0;
        write_data = 0;

        #2;

        if (read_data1 !== 32'd0 || read_data2 !== 32'd0)
            $display("FAIL: x0 must always be zero");
        else
            $display("PASS: x0 is zero");

        rd = 5'd5;
        write_data = 32'd123;
        we = 1;

        #10;

        we = 0;
        rs1 = 5'd5;

        #1;

        if (read_data1 !== 32'd123)
            $display("FAIL: x5 expected 123, got %0d", read_data1);
        else
            $display("PASS: x5 = %0d", read_data1);

        rd = 5'd10;
        write_data = 32'hDEADBEEF;
        we = 1;

        #10;

        we = 0;
        rs2 = 5'd10;

        #1;

        if (read_data2 !== 32'hDEADBEEF)
            $display("FAIL: x10 expected DEADBEEF, got %h", read_data2);
        else
            $display("PASS: x10 = %h", read_data2);

        rd = 5'd0;
        write_data = 32'd999;
        we = 1;

        #10;

        we = 0;
        rs1 = 5'd0;

        #1;

        if (read_data1 !== 32'd0)
            $display("FAIL: x0 was modified");
        else
            $display("PASS: write to x0 ignored");

        $display("Register file tests finished");
        $finish;
    end

endmodule
