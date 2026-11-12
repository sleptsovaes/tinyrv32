// Latency-tolerant RV32I execution core. See docs/RV32_UPGRADE.md for the bus
// contract, architectural scope and the distinction from the historical core.
module rv32_core #(
    parameter bit STATIC_PREDICT = 1'b0
) (
    input  logic clk, reset,
    output logic imem_valid, imem_cancel,
    output logic [31:0] imem_addr,
    input  logic imem_ready,
    input  logic [31:0] imem_rdata,
    output logic dmem_valid, dmem_write,
    output logic [31:0] dmem_addr, dmem_wdata,
    output logic [3:0] dmem_wstrb,
    input  logic dmem_ready,
    input  logic [31:0] dmem_rdata,
    output logic halted,
    output logic [31:0] trap_pc,
    output logic [3:0] trap_cause,
    output logic commit_valid,
    output logic [31:0] commit_pc, commit_instr, commit_next_pc,
    output logic [4:0] commit_rd,
    output logic [31:0] commit_rd_data,
    output logic commit_store,
    output logic [31:0] commit_mem_addr, commit_mem_data,
    output logic [3:0] commit_mem_strb,
    output logic mispredict
);
    logic [31:0] regs [0:31];
    logic [31:0] fetch_pc, exec_pc, exec_instr, exec_prediction;
    logic [31:0] buffer_pc, buffer_instr, buffer_prediction;
    logic exec_valid, buffer_valid;
    logic [31:0] a, b, imm_i, imm_s, imm_b, imm_j;
    logic [31:0] result, effective_addr, actual_next_pc, shifted_load;
    logic [4:0] rd, rs1, rs2;
    logic [6:0] opcode, funct7;
    logic [2:0] funct3;
    logic write_rd, load_op, store_op, legal, branch_taken;
    logic fault, execute_done, fetch_fire;
    logic [3:0] fault_cause, store_mask;
    logic [31:0] store_value;
    integer i;

    assign opcode = exec_instr[6:0];
    assign funct3 = exec_instr[14:12];
    assign funct7 = exec_instr[31:25];
    assign rd = exec_instr[11:7];
    assign rs1 = exec_instr[19:15];
    assign rs2 = exec_instr[24:20];
    assign a = rs1 == 0 ? 32'd0 : regs[rs1];
    assign b = rs2 == 0 ? 32'd0 : regs[rs2];
    assign imm_i = {{20{exec_instr[31]}}, exec_instr[31:20]};
    assign imm_s = {{20{exec_instr[31]}},exec_instr[31:25],exec_instr[11:7]};
    assign imm_b = {{19{exec_instr[31]}},exec_instr[31],exec_instr[7],
                    exec_instr[30:25],exec_instr[11:8],1'b0};
    assign imm_j = {{11{exec_instr[31]}},exec_instr[31],exec_instr[19:12],
                    exec_instr[20],exec_instr[30:21],1'b0};

    // BTFNT: predict backward conditional branches taken, forward branches
    // not taken; predict the target of direct JAL. JALR resolves in Execute.
    function automatic [31:0] predict_next(input [31:0] pc, input [31:0] instr);
        reg [31:0] displacement;
        begin
            predict_next = pc + 4;
            if (STATIC_PREDICT && instr[6:0] == 7'h6f) begin
                displacement = {{11{instr[31]}},instr[31],instr[19:12],
                                instr[20],instr[30:21],1'b0};
                predict_next = pc + displacement;
            end else if (STATIC_PREDICT && instr[6:0] == 7'h63 && instr[31]) begin
                displacement = {{19{instr[31]}},instr[31],instr[7],
                                instr[30:25],instr[11:8],1'b0};
                predict_next = pc + displacement;
            end
        end
    endfunction

    // Decoder validates funct7 as well as opcode/funct3. Unsupported encodings
    // stop precisely, rather than silently aliasing another operation.
    always @* begin
        result = 0;
        effective_addr = a + imm_i;
        actual_next_pc = exec_pc + 4;
        write_rd = 0; load_op = 0; store_op = 0;
        legal = 1; branch_taken = 0;
        fault_cause = 4'd2;
        store_mask = 0; store_value = b << (8 * effective_addr[1:0]);
        shifted_load = dmem_rdata >> (8 * effective_addr[1:0]);
        case (opcode)
            7'h37: begin write_rd = 1; result = {exec_instr[31:12],12'd0}; end
            7'h17: begin write_rd = 1; result = exec_pc + {exec_instr[31:12],12'd0}; end
            7'h6f: begin
                write_rd = 1; result = exec_pc + 4;
                actual_next_pc = exec_pc + imm_j;
            end
            7'h67: begin
                legal = funct3 == 0;
                write_rd = 1; result = exec_pc + 4;
                actual_next_pc = (a + imm_i) & 32'hfffffffe;
            end
            7'h63: begin
                case (funct3)
                    0: branch_taken = a == b;
                    1: branch_taken = a != b;
                    4: branch_taken = $signed(a) < $signed(b);
                    5: branch_taken = $signed(a) >= $signed(b);
                    6: branch_taken = a < b;
                    7: branch_taken = a >= b;
                    default: legal = 0;
                endcase
                if (branch_taken) actual_next_pc = exec_pc + imm_b;
            end
            7'h13: begin
                write_rd = 1;
                case (funct3)
                    0: result = a + imm_i;
                    2: result = {31'd0,($signed(a) < $signed(imm_i))};
                    3: result = {31'd0,(a < imm_i)};
                    4: result = a ^ imm_i;
                    6: result = a | imm_i;
                    7: result = a & imm_i;
                    1: begin legal = funct7 == 0; result = a << exec_instr[24:20]; end
                    5: begin
                        legal = funct7 == 0 || funct7 == 7'h20;
                        if (funct7 == 7'h20) result = $signed(a) >>> exec_instr[24:20];
                        else result = a >> exec_instr[24:20];
                    end
                    default: legal = 0;
                endcase
            end
            7'h33: begin
                write_rd = 1;
                legal = funct7 == 0 || ((funct3 == 0 || funct3 == 5) && funct7 == 7'h20);
                case (funct3)
                    0: result = funct7 == 7'h20 ? a - b : a + b;
                    1: result = a << b[4:0];
                    2: result = {31'd0,($signed(a) < $signed(b))};
                    3: result = {31'd0,(a < b)};
                    4: result = a ^ b;
                    5: begin
                        if (funct7 == 7'h20) result = $signed(a) >>> b[4:0];
                        else result = a >> b[4:0];
                    end
                    6: result = a | b;
                    7: result = a & b;
                endcase
            end
            7'h03: begin
                load_op = 1; write_rd = 1;
                case (funct3)
                    0: result = {{24{shifted_load[7]}},shifted_load[7:0]};
                    1: result = {{16{shifted_load[15]}},shifted_load[15:0]};
                    2: result = dmem_rdata;
                    4: result = {24'd0,shifted_load[7:0]};
                    5: result = {16'd0,shifted_load[15:0]};
                    default: legal = 0;
                endcase
            end
            7'h23: begin
                store_op = 1;
                effective_addr = a + imm_s;
                store_value = b << (8 * effective_addr[1:0]);
                case (funct3)
                    0: store_mask = 4'b0001 << effective_addr[1:0];
                    1: store_mask = 4'b0011 << effective_addr[1:0];
                    2: store_mask = 4'b1111;
                    default: legal = 0;
                endcase
            end
            7'h0f: legal = funct3 == 0; // FENCE: requests already complete in order.
            7'h73: begin
                legal = 0;
                if (exec_instr == 32'h00000073) fault_cause = 4'd11; // ECALL
                else if (exec_instr == 32'h00100073) fault_cause = 4'd3; // EBREAK
            end
            default: legal = 0;
        endcase
        fault = !legal;
        if (legal && actual_next_pc[1:0] != 0) begin
            fault = 1; fault_cause = 0;
        end
        if (legal && (load_op || store_op) &&
            ((funct3[1:0] == 1 && effective_addr[0]) ||
             (funct3[1:0] == 2 && effective_addr[1:0] != 0))) begin
            fault = 1; fault_cause = store_op ? 4'd6 : 4'd4;
        end
    end

    assign dmem_valid = !reset && !halted && exec_valid && !fault && (load_op || store_op);
    assign dmem_write = store_op;
    assign dmem_addr = effective_addr;
    assign dmem_wdata = store_value;
    assign dmem_wstrb = store_op ? store_mask : 4'd0;
    assign execute_done = exec_valid && (!load_op && !store_op || dmem_ready);
    assign commit_valid = !reset && !halted && execute_done && !fault;
    assign commit_pc = exec_pc;
    assign commit_instr = exec_instr;
    assign commit_next_pc = actual_next_pc;
    assign commit_rd = write_rd && rd != 0 ? rd : 5'd0;
    assign commit_rd_data = commit_rd != 0 ? result : 32'd0;
    assign commit_store = commit_valid && store_op;
    assign commit_mem_addr = store_op ? effective_addr : 32'd0;
    assign commit_mem_data = store_op ? store_value : 32'd0;
    assign commit_mem_strb = store_op ? store_mask : 4'd0;
    assign mispredict = commit_valid && actual_next_pc != exec_prediction;
    assign imem_valid = !reset && !halted && !buffer_valid;
    assign imem_addr = fetch_pc;
    assign imem_cancel = !reset && !halted &&
                         (mispredict || (exec_valid && fault));
    assign fetch_fire = imem_valid && imem_ready && !imem_cancel;

    always @(posedge clk) begin
        if (reset) begin
            fetch_pc <= 0; exec_pc <= 0; exec_instr <= 32'h13;
            exec_prediction <= 4; exec_valid <= 0; buffer_valid <= 0;
            buffer_pc <= 0; buffer_instr <= 32'h13; buffer_prediction <= 4;
            halted <= 0; trap_pc <= 0; trap_cause <= 0;
            for (i=0; i<32; i=i+1) regs[i] <= 0;
        end else if (!halted) begin
            if (exec_valid && fault) begin
                halted <= 1; trap_pc <= exec_pc; trap_cause <= fault_cause;
                exec_valid <= 0; buffer_valid <= 0;
            end else begin
                if (commit_valid && commit_rd != 0) regs[commit_rd] <= result;
                if (mispredict) begin
                    fetch_pc <= actual_next_pc;
                    exec_valid <= 0; buffer_valid <= 0;
                end else begin
                    if (fetch_fire)
                        fetch_pc <= predict_next(fetch_pc, imem_rdata);
                    if (!exec_valid || commit_valid) begin
                        if (buffer_valid) begin
                            exec_pc <= buffer_pc; exec_instr <= buffer_instr;
                            exec_prediction <= buffer_prediction;
                            exec_valid <= 1; buffer_valid <= 0;
                        end else if (fetch_fire) begin
                            exec_pc <= fetch_pc; exec_instr <= imem_rdata;
                            exec_prediction <= predict_next(fetch_pc, imem_rdata);
                            exec_valid <= 1;
                        end else exec_valid <= 0;
                    end else if (fetch_fire) begin
                        // One-entry elastic fetch buffer while Execute waits.
                        buffer_pc <= fetch_pc; buffer_instr <= imem_rdata;
                        buffer_prediction <= predict_next(fetch_pc, imem_rdata);
                        buffer_valid <= 1;
                    end
                end
            end
        end
    end

`ifdef FORMAL
    // Bounded safety checks. Bus data/ready and instruction encodings remain
    // unconstrained; the first sampled cycle is reset. This is not an ISA proof.
    reg f_past_valid=0;
    integer f;
    always @(posedge clk) begin
        f_past_valid <= 1;
        if (!f_past_valid) assume(reset);
        if (f_past_valid && !reset && !$past(reset)) begin
            assert(regs[0]==0);
            if ($past(dmem_valid && !dmem_ready)) begin
                assert(dmem_valid);
                assert({dmem_addr,dmem_wdata,dmem_wstrb,dmem_write} ==
                       $past({dmem_addr,dmem_wdata,dmem_wstrb,dmem_write}));
                assert(exec_pc==$past(exec_pc) && exec_instr==$past(exec_instr));
            end
            if ($past(imem_valid && !imem_ready && !imem_cancel) && !imem_cancel)
                assert(imem_addr==$past(imem_addr));
            if ($past(mispredict)) assert(!exec_valid && !buffer_valid);
            if (!$past(commit_valid))
                for(f=0;f<32;f=f+1) assert(regs[f]==$past(regs[f]));
        end
        if (reset) assert(!commit_valid && !dmem_valid);
        if (!exec_valid) assert(!commit_valid && !dmem_valid);
    end
`endif
endmodule
