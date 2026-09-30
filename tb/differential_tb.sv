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


    // =========================================================
    // DUT
    // =========================================================

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


    // =========================================================
    // Instruction memory
    // =========================================================

    assign imem_rdata =
        imem[imem_addr[7:2]];


    // =========================================================
    // Data memory read
    // =========================================================

    assign dmem_rdata =
        dmem[dmem_addr[7:2]];


    // =========================================================
    // Data memory write
    // =========================================================

    always @(posedge clk) begin
        if (dmem_we) begin
            dmem[dmem_addr[7:2]]
                <= dmem_wdata;
        end
    end


    // =========================================================
    // Clock
    // =========================================================

    always #5 clk = ~clk;


    // =========================================================
    // Test
    // =========================================================

    initial begin

        clk   = 0;
        reset = 1;


        // -----------------------------------------------------
        // Initialize simulation memories.
        //
        // Register-file initialization is intentionally NOT
        // performed through hierarchical backdoor access.
        // The generated RISC-V program initializes every
        // register that it is allowed to use.
        // -----------------------------------------------------

        for (i = 0; i < 64; i = i + 1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 32'h00000000;
        end


        // -----------------------------------------------------
        // Load generated program.
        //
        // generate_program.py writes exactly 64 words,
        // padding unused locations with ADDI x0,x0,0.
        // -----------------------------------------------------

        $readmemh(
            "verification/generated/program.hex",
            imem
        );


        // -----------------------------------------------------
        // Hold synchronous reset across at least one clock edge.
        // -----------------------------------------------------

        #12;
        reset = 0;


        // -----------------------------------------------------
        // Generated programs currently contain at most about
        // 55 instructions plus terminal JAL x0,0.
        //
        // Once the processor reaches the terminal JAL, PC
        // remains fixed, so extra cycles do not alter the
        // architectural state.
        // -----------------------------------------------------

        repeat (80)
            @(posedge clk);


        // -----------------------------------------------------
        // Dump architectural state for Python comparison.
        // -----------------------------------------------------

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


        // -----------------------------------------------------
        // Program counter
        // -----------------------------------------------------

        $fdisplay(
            fd,
            "PC %08x",
            dut.pc_value
        );


        // -----------------------------------------------------
        // Registers
        //
        // Current randomized generator intentionally operates
        // only on x0..x15.
        //
        // x16..x31 are not used and are therefore allowed to
        // remain uninitialized in the RTL simulation.
        // -----------------------------------------------------

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


        // -----------------------------------------------------
        // Complete data memory
        // -----------------------------------------------------

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
