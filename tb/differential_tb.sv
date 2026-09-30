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


    cpu_core dut (
        .clk(clk),
        .reset(reset),

        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),

        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we),
        .dmem_rdata(dmem_rdata)
    );


    assign imem_rdata = imem[imem_addr[7:2]];
    assign dmem_rdata = dmem[dmem_addr[7:2]];


    always @(posedge clk) begin
        if (dmem_we)
            dmem[dmem_addr[7:2]] <= dmem_wdata;
    end


    always #5 clk = ~clk;


    initial begin

        clk = 0;
        reset = 1;

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'd0;
        end

        $readmemh(
            "verification/generated/program.hex",
            imem
        );

        #12;
        reset = 0;

        // 40 instructions + margin + terminal JAL loop.
        repeat (60)
            @(posedge clk);

        fd = $fopen(
            "verification/generated/rtl_state.txt",
            "w"
        );

        if (fd == 0)
            $fatal(1, "Cannot open rtl_state.txt");

        $fdisplay(fd, "PC %08x", dut.pc_value);

        for (i = 0; i < 16; i = i + 1) begin
            if (i == 0)
                $fdisplay(fd, "X%0d %08x", i, 32'd0);
            else
                $fdisplay(
                    fd,
                    "X%0d %08x",
                    i,
                    dut.rf.regs[i]
                );
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

        $display("RTL state dumped");
        $finish;

    end

endmodule
