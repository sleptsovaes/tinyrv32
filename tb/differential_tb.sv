`timescale 1ns/1ps
module differential_tb;
    logic clk = 0, reset = 1;
    logic [31:0] imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata;
    logic dmem_we;
    logic [31:0] imem [0:63], dmem [0:63];
    integer i, state_fd, trace_fd, stores_fd, cycles = 0;
    integer max_cycles = 350;
    string image_path = "verification/generated/program.hex";
    string state_path = "verification/generated/rtl_state.txt";
    string trace_path = "verification/generated/rtl_trace.txt";
    string stores_path = "verification/generated/rtl_stores.txt";
    cpu_core dut(.*);
    assign imem_rdata = imem[imem_addr[7:2]];
    assign dmem_rdata = dmem[dmem_addr[7:2]];
    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (reset) begin
            if (dmem_we !== 1'b0 || dut.rf_we !== 1'b0)
                $fatal(1, "Side effect during reset");
        end else begin
            cycles = cycles + 1;
            if (cycles > max_cycles) $fatal(1, "Differential program timed out");
            if (!dut.exec_valid && (dmem_we !== 1'b0 || dut.rf_we !== 1'b0))
                $fatal(1, "Side effect from invalid execute slot");
            if (dmem_we) begin
                if ($isunknown({dmem_addr, dmem_wdata}) ||
                    dmem_addr[1:0] != 0 || dmem_addr >= 256)
                    $fatal(1, "Invalid store address");
                // Record actual external writes separately from CPU commits.
                $fdisplay(stores_fd, "%08x %08x %08x",
                    dut.exec_pc, dmem_addr, dmem_wdata);
                dmem[dmem_addr >> 2] <= dmem_wdata;
            end
            if (dut.exec_valid) begin
                if (dut.exec_instr == 32'h0000006f) begin
                    // Snapshot after the preceding instruction's NBA writes.
                    #1;
                    state_fd = $fopen(state_path, "w");
                    if (!state_fd) $fatal(1, "Cannot open state output");
                    $fdisplay(state_fd, "PC %08x", dut.exec_pc);
                    for (i=0; i<32; i=i+1)
                        $fdisplay(state_fd, "X%0d %08x", i, i==0 ? 32'd0 : dut.rf.regs[i]);
                    for (i=0; i<64; i=i+1)
                        $fdisplay(state_fd, "M%0d %08x", i, dmem[i]);
                    $fclose(state_fd);
                    $fclose(trace_fd);
                    $fclose(stores_fd);
                    $display("RTL state, ordered commits and memory writes dumped");
                    $finish;
                end else begin
                    $fdisplay(trace_fd, "%08x %08x %08x %08x %08x %08x %08x %08x",
                        dut.exec_pc, dut.exec_instr, dut.next_pc_value,
                        dut.rf_we && dut.rd != 0 ? {27'd0,dut.rd} : 32'd0,
                        dut.rf_we && dut.rd != 0 ? dut.write_data : 32'd0,
                        {31'd0,dmem_we}, dmem_we ? dmem_addr : 32'd0,
                        dmem_we ? dmem_wdata : 32'd0);
                end
            end
        end
    end

    initial begin
        if ($value$plusargs("IMAGE=%s", image_path)) begin end
        if ($value$plusargs("STATE=%s", state_path)) begin end
        if ($value$plusargs("TRACE=%s", trace_path)) begin end
        if ($value$plusargs("STORES=%s", stores_path)) begin end
        if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin end
        if (max_cycles < 1) $fatal(1, "MAX_CYCLES must be positive");
        for (i=0; i<64; i=i+1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 0;
        end
        $readmemh(image_path, imem);
        trace_fd = $fopen(trace_path, "w");
        stores_fd = $fopen(stores_path, "w");
        if (!trace_fd || !stores_fd) $fatal(1, "Cannot open trace output");
        repeat (3) @(posedge clk);
        #1;
        // The ISA does not promise reset values for x1..x31. Both models
        // receive the same explicitly controlled initial state in this test.
        for (i=1; i<32; i=i+1) dut.rf.regs[i] = 0;
        @(negedge clk); reset = 0;
    end
endmodule
