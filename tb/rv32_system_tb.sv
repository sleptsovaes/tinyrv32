`timescale 1ns/1ps
module rv32_system_tb;
`ifdef STATIC_PREDICT
    localparam PREDICT = 1;
`else
    localparam PREDICT = 0;
`endif
    localparam WORDS = 4096;
    logic clk=0, reset=1;
    wire imem_valid, imem_cancel, dmem_valid, dmem_write, halted;
    wire [31:0] imem_addr, dmem_addr, dmem_wdata;
    wire [3:0] dmem_wstrb;
    logic [31:0] imem_rdata, dmem_rdata;
    wire imem_ready, dmem_ready;
    wire [31:0] trap_pc, commit_pc, commit_instr, commit_next_pc;
    wire [31:0] commit_rd_data, commit_mem_addr, commit_mem_data;
    wire [4:0] commit_rd;
    wire [3:0] trap_cause, commit_mem_strb;
    wire commit_valid, commit_store, mispredict;
    logic [31:0] mem[0:WORDS-1];
    logic i_pending=0, d_pending=0;
    logic [31:0] i_address, d_address, d_value, i_response, d_response;
    logic d_write;
    logic [3:0] d_strobe;
    integer i_count=0, d_count=0, i_wait=0, d_wait=0;
    integer random_wait=0, reset_pending=0, max_cycles=2000000;
    integer cycles=0, commits=0, mispredictions=0, stores=0, trace_stores=0;
    integer fd, state_fd, uart_fd, stats_fd, j, k;
    reg [31:0] rng=32'h12345678, status_value=0;
    reg status_written=0;
    string image_path, state_path, trace_path, uart_path, stats_path;
    rv32_core #(.STATIC_PREDICT(PREDICT)) dut(.*);
    always #5 clk=~clk;

    function automatic [31:0] read_word(input [31:0] address);
        if ((address >> 2)<WORDS) read_word=mem[address >> 2];
        else read_word=0;
    endfunction
    assign imem_ready=imem_valid && !imem_cancel &&
        (i_wait==0 && !random_wait || i_pending && i_count==0);
    assign dmem_ready=dmem_valid &&
        (d_wait==0 && !random_wait || d_pending && d_count==0);
    always @* begin
        imem_rdata=i_wait==0 && !random_wait ? read_word(imem_addr) : i_response;
        dmem_rdata=d_wait==0 && !random_wait ? read_word(dmem_addr) : d_response;
    end

    // Completion buses: a request stays stable until ready. Instruction
    // requests can be cancelled explicitly on a redirect; data cannot.
    always @(posedge clk) begin
        if (reset) begin
            i_pending<=0; d_pending<=0;
            cycles=0; commits=0; stores=0; trace_stores=0; mispredictions=0;
            if (dmem_valid || commit_valid) $fatal(1,"Side effect during reset");
        end else if (!halted) begin
            cycles=cycles+1;
            if (cycles>max_cycles) $fatal(1,"System timeout");
            rng <= (rng<<1) ^ (rng[31] ? 32'h04c11db7 : 32'd0);
            if (imem_cancel || !imem_valid) i_pending<=0;
            else if (imem_ready) i_pending<=0;
            else if (!i_pending) begin
                i_pending<=1; i_address<=imem_addr; i_response<=read_word(imem_addr);
                i_count<=random_wait ? (rng[2:0] % 4) : i_wait-1;
            end else begin
                if (imem_addr!==i_address) $fatal(1,"Fetch address changed while waiting");
                if (i_count>0) i_count<=i_count-1;
            end
            if (!dmem_valid) begin
                if (d_pending) $fatal(1,"Data request dropped before completion");
                d_pending<=0;
            end else if (dmem_ready) d_pending<=0;
            else if (!d_pending) begin
                d_pending<=1; d_address<=dmem_addr; d_value<=dmem_wdata;
                d_strobe<=dmem_wstrb; d_write<=dmem_write;
                d_response<=read_word(dmem_addr);
                d_count<=random_wait ? (rng[5:3] % 4) : d_wait-1;
            end else begin
                if ({dmem_addr,dmem_wdata,dmem_wstrb,dmem_write} !==
                    {d_address,d_value,d_strobe,d_write})
                    $fatal(1,"Data request changed while waiting");
                if (d_count>0) d_count<=d_count-1;
            end
            if (dmem_valid && dmem_ready && dmem_write) begin
                if (!commit_valid || !commit_store) $fatal(1,"Store without commit");
                stores=stores+1;
                if (dmem_addr==32'h10000000)
                    $fdisplay(uart_fd,"%02x",dmem_wdata[7:0]);
                else if (dmem_addr==32'h10000004) begin
                    status_value=dmem_wdata; status_written=1;
                end else if ((dmem_addr >> 2)<WORDS) begin
                    for (k=0;k<4;k=k+1)
                        if (dmem_wstrb[k]) mem[dmem_addr >> 2][8*k+:8]<=dmem_wdata[8*k+:8];
                end else $fatal(1,"Out-of-range store %08x",dmem_addr);
            end
            if (commit_valid) begin
                commits=commits+1;
                if (mispredict) mispredictions=mispredictions+1;
                if (commit_store) trace_stores=trace_stores+1;
                $fdisplay(fd,"%08x %08x %08x %08x %08x %08x %08x %08x %08x",
                    commit_pc,commit_instr,commit_next_pc,{27'd0,commit_rd},
                    commit_rd_data,{31'd0,commit_store},commit_mem_addr,
                    commit_mem_data,{28'd0,commit_mem_strb});
            end
        end else begin
            if (stores != trace_stores) $fatal(1,"Duplicate or missing store");
            state_fd=$fopen(state_path,"w");
            if (!state_fd) $fatal(1,"Cannot open state output");
            $fdisplay(state_fd,"PC %08x",trap_pc);
            for(j=0;j<32;j=j+1) $fdisplay(state_fd,"X%0d %08x",j,dut.regs[j]);
            for(j=0;j<WORDS;j=j+1) $fdisplay(state_fd,"M%0d %08x",j,mem[j]);
            $fclose(state_fd); $fclose(fd); $fclose(uart_fd);
            stats_fd=$fopen(stats_path,"w");
            if (!stats_fd) $fatal(1,"Cannot open stats output");
            $fdisplay(stats_fd,"CYCLES %0d\nCOMMITS %0d\nMISPREDICTIONS %0d\nSTORES %0d\nTRAP %0d\nSTATUS_WRITTEN %0d\nSTATUS %0d",
                cycles,commits,mispredictions,stores,trap_cause,status_written,status_value);
            $fclose(stats_fd);
            $display("RV32 RUN COMPLETE: commits=%0d cycles=%0d trap=%0d",commits,cycles,trap_cause);
            $finish;
        end
    end

    initial begin
        if (!$value$plusargs("IMAGE=%s",image_path) || !$value$plusargs("STATE=%s",state_path) ||
            !$value$plusargs("TRACE=%s",trace_path) || !$value$plusargs("UART=%s",uart_path) ||
            !$value$plusargs("STATS=%s",stats_path)) $fatal(1,"Missing output/image argument");
        if ($value$plusargs("IWAIT=%d",i_wait)) begin end
        if ($value$plusargs("DWAIT=%d",d_wait)) begin end
        if ($value$plusargs("RANDOM_WAIT=%d",random_wait)) begin end
        if ($value$plusargs("RESET_PENDING=%d",reset_pending)) begin end
        if ($value$plusargs("MAX_CYCLES=%d",max_cycles)) begin end
        for(j=0;j<WORDS;j=j+1) mem[j]=0;
        $readmemh(image_path,mem);
        fd=$fopen(trace_path,"w"); uart_fd=$fopen(uart_path,"w");
        if (!fd || !uart_fd) $fatal(1,"Cannot open trace/UART output");
        repeat(3) @(posedge clk);
        @(negedge clk); reset=0;
        if (reset_pending) begin
            // This test image has no store before the first pending request.
            while (!(dmem_valid && !dmem_ready)) @(negedge clk);
            if (stores) $fatal(1,"Reset test must begin before the first store");
            reset=1;
            $fclose(fd); fd=$fopen(trace_path,"w");
            repeat(3) @(posedge clk);
            @(negedge clk); reset=0;
        end
    end
endmodule
