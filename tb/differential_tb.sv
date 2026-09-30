`timescale 1ns/1ps

module differential_tb;

    logic clk;
    logic reset;

    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;

    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic        dmem_we;
    logic [31:0] dmem_rdata;

    logic [31:0] imem [0:63];
    logic [31:0] dmem [0:63];

    integer i;
    integer fd;


    // DUT

    cpu_core dut (
        .clk        (clk),
        .reset      (reset),

        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),

        .dmem_addr  (dmem_addr),
        .dmem_wdata (dmem_wdata),
        .dmem_we    (dmem_we),
        .dmem_rdata (dmem_rdata)
    );


    // Instruction memory

    assign imem_rdata =
        imem[imem_addr[7:2]];


    // Data memory read

    assign dmem_rdata =
        dmem[dmem_addr[7:2]];


    // Data memory write

    always @(posedge clk) begin
        if (dmem_we) begin
            dmem[dmem_addr[7:2]]
                <= dmem_wdata;
        end
    end


    // Clock

    always #5 clk = ~clk;


    // Test

    initial begin

        clk   = 0;
        reset = 1;



        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h00000000;
        end

        $readmemh(
            "verification/generated/program.hex",
            imem
        );

        #12;
        reset = 0;

        repeat (120)
            @(posedge clk);


        fd = $fopen(
            "verification/generated/rtl_state.txt",
            "w"
        );

        if (fd == 0) begin
            $fatal(
                1,
                "Cannot open rtl_state.txt"
            );
        end

        $fdisplay(
            fd,
            "PC %08x",
            dut.exec_pc
        );


        for (i = 0; i < 16; i = i + 1) begin

            if (i == 0) begin

                $fdisplay(
                    fd,
                    "X%0d %08x",
                    i,
                    32'h00000000
                );

            end
            else begin

                $fdisplay(
                    fd,
                    "X%0d %08x",
                    i,
                    dut.rf.regs[i]
                );

            end

        end

        for (i = 0; i < 64; i = i + 1) begin

            $fdisplay(
                fd,
                "M%0d %08x",
                i,
                dmem[i]
            );

        end


        $fclose(fd);


        $display(
            "RTL state dumped"
        );

        $finish;

    end

endmodule
