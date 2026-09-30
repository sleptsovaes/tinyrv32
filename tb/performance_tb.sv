`timescale 1ns/1ps

module performance_tb;
    localparam integer IMEM_WORDS = 1024;
    localparam integer DMEM_WORDS = 256;

    logic clk = 1'b0;
    logic reset = 1'b1;
    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic dmem_we;
    logic [31:0] imem [0:IMEM_WORDS-1];
    logic [31:0] dmem [0:DMEM_WORDS-1];
    wire [31:0] current_pc, current_instr;
    wire current_valid;

    string program_path, state_path;
    logic [31:0] last_pc;
    integer max_cycles = 50000;
    integer cycles = 0;
    integer retired = 0;
    integer branches = 0;
    integer taken_branches = 0;
    integer jals = 0;
    integer redirects = 0;
    integer i, fd;
    logic done = 1'b0;
    logic take_branch;

    cpu_core dut (
        .clk(clk), .reset(reset),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_rdata(dmem_rdata)
    );

`ifdef BENCH_PIPELINED
    assign current_pc = dut.exec_pc;
    assign current_instr = dut.exec_instr;
    assign current_valid = dut.exec_valid;
`else
    assign current_pc = dut.pc_value;
    assign current_instr = imem_rdata;
    assign current_valid = 1'b1;
`endif

    always #5 clk = ~clk;

    always @* begin
        imem_rdata = 32'h00000013;
        if ((^imem_addr !== 1'bx) &&
            ((imem_addr >> 2) < IMEM_WORDS))
            imem_rdata = imem[imem_addr >> 2];
    end

    always @* begin
        dmem_rdata = 32'd0;
        if ((^dmem_addr !== 1'bx) &&
            ((dmem_addr >> 2) < DMEM_WORDS))
            dmem_rdata = dmem[dmem_addr >> 2];
    end

    // This block must also run on the final measured edge.
    always @(posedge clk) begin
        if (!reset) begin
            if (dmem_we === 1'bx)
                $fatal(1, "Unknown dmem_we");
            if (dmem_we) begin
                if ((^dmem_addr === 1'bx) ||
                    (dmem_addr[1:0] !== 2'b00) ||
                    ((dmem_addr >> 2) >= DMEM_WORDS))
                    $fatal(1, "Invalid store address %08x", dmem_addr);
                dmem[dmem_addr >> 2] <= dmem_wdata;
            end
        end
    end

    function automatic [31:0] architectural_register(input integer index);
        if (index == 0)
            architectural_register = 32'd0;
        else
            architectural_register = dut.rf.regs[index];
    endfunction

    task automatic dump_state;
        integer k;
        begin
            fd = $fopen(state_path, "w");
            if (fd == 0)
                $fatal(1, "Cannot open state output: %s", state_path);
            $fdisplay(fd, "CYCLES %0d", cycles);
            $fdisplay(fd, "RETIRED %0d", retired);
            $fdisplay(fd, "BRANCHES %0d", branches);
            $fdisplay(fd, "TAKEN_BRANCHES %0d", taken_branches);
            $fdisplay(fd, "JALS %0d", jals);
            $fdisplay(fd, "REDIRECTS %0d", redirects);
            $fdisplay(fd, "LAST_PC %08x", last_pc);
            for (k = 0; k < 32; k = k + 1)
                $fdisplay(fd, "X%0d %08x", k, architectural_register(k));
            for (k = 0; k < DMEM_WORDS; k = k + 1)
                $fdisplay(fd, "M%0d %08x", k, dmem[k]);
            $fclose(fd);
        end
    endtask

    // Sample execute state BEFORE nonblocking assignments update it.
    // The last useful instruction is a designated signature store.
    always @(posedge clk) begin
        if (!reset && !done) begin
            cycles = cycles + 1;
            if (cycles > max_cycles)
                $fatal(1, "Benchmark timeout after %0d cycles", cycles);
            if (current_valid === 1'bx)
                $fatal(1, "Unknown execute validity");
            if (current_valid) begin
                if ((^current_pc === 1'bx) ||
                    (^current_instr === 1'bx) ||
                    (current_pc[1:0] !== 2'b00) ||
                    ((current_pc >> 2) >= IMEM_WORDS))
                    $fatal(1, "Invalid executing instruction/PC");

                retired = retired + 1;
                case (current_instr[6:0])
                    7'h63: begin
                        branches = branches + 1;
                        case (current_instr[14:12])
                            3'b000: take_branch =
                                architectural_register(current_instr[19:15]) ==
                                architectural_register(current_instr[24:20]);
                            3'b001: take_branch =
                                architectural_register(current_instr[19:15]) !=
                                architectural_register(current_instr[24:20]);
                            default: $fatal(1, "Unsupported benchmark branch");
                        endcase
                        if (take_branch === 1'bx)
                            $fatal(1, "Unknown branch operands");
                        if (take_branch) begin
                            taken_branches = taken_branches + 1;
                            redirects = redirects + 1;
                        end
                    end
                    7'h6f: begin
                        jals = jals + 1;
                        redirects = redirects + 1;
                    end
                    default: begin end
                endcase

                if (current_pc == last_pc) begin
                    if ((current_instr[6:0] !== 7'h23) ||
                        (current_instr[14:12] !== 3'b010) ||
                        (dmem_we !== 1'b1) ||
                        (dmem_addr !== 32'd0))
                        $fatal(1, "Completion PC must commit the signature SW");
                    done = 1'b1;
                    // Include final RF/RAM writes in the snapshot.
                    #1;
                    dump_state();
                    $display("PERFORMANCE RUN PASSED: cycles=%0d retired=%0d redirects=%0d", cycles, retired, redirects);
                    $finish;
                end
            end
        end
    end

    initial begin
        if (!$value$plusargs("PROGRAM=%s", program_path))
            $fatal(1, "Missing +PROGRAM");
        if (!$value$plusargs("STATE=%s", state_path))
            $fatal(1, "Missing +STATE");
        if (!$value$plusargs("LAST_PC=%h", last_pc))
            $fatal(1, "Missing +LAST_PC");
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin end

        for (i = 0; i < IMEM_WORDS; i = i + 1)
            imem[i] = 32'h00000013;
        for (i = 0; i < DMEM_WORDS; i = i + 1)
            dmem[i] = 32'd0;
        $readmemh(program_path, imem);

        repeat (3) @(posedge clk);
        #1;
        // Controlled initial state, identical for the two microarchitectures.
        // These assignments occur while reset blocks architectural writes.
        for (i = 1; i < 32; i = i + 1)
            dut.rf.regs[i] = 32'd0;
        @(negedge clk);
        reset = 1'b0;
    end
endmodule
