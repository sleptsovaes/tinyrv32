`timescale 1ns/1ps
module soc_uart_tb;
    localparam BAUD=4;
    logic clk=0, reset=1;
    wire serial_tx, halted, status_valid;
    wire [31:0] program_status;
    wire [3:0] trap_cause;
    string image_path, uart_path;
    integer i, bit_number, fd, count=0, cycles=0;
    reg [7:0] byte_value;
    tinyrv32_soc #(.BAUD_DIV(BAUD)) dut(.*);
    always #5 clk=~clk;
    always @(posedge clk) begin
        cycles=cycles+1;
        if (cycles>200000) $fatal(1,"SoC timeout");
        if (!reset && halted && dut.uart.ready) begin
            if (!status_valid || program_status!=0 || trap_cause!=3)
                $fatal(1,"Compiled C signature/trap failed");
            $fclose(fd);
            $display("SOC UART PASSED: %0d bytes, %0d cycles",count,cycles);
            $finish;
        end
    end
    // Decode the actual serial line; do not inspect the UART data register.
    initial begin
        if (!$value$plusargs("UART=%s",uart_path)) $fatal(1,"Missing UART output");
        fd=$fopen(uart_path,"w");
        if (!fd) $fatal(1,"Cannot open UART output");
        forever begin
            @(negedge serial_tx);
            if (!reset) begin
                repeat(BAUD+BAUD/2) @(posedge clk);
                #1;
                for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
                    byte_value[bit_number]=serial_tx;
                    repeat(BAUD) @(posedge clk);
                    #1;
                end
                if (serial_tx!==1'b1) $fatal(1,"Invalid UART stop bit");
                $fdisplay(fd,"%02x",byte_value); count=count+1;
            end
        end
    end
    initial begin
        if (!$value$plusargs("IMAGE=%s",image_path)) $fatal(1,"Missing image");
        for(i=0;i<4096;i=i+1) dut.ram[i]=0;
        $readmemh(image_path,dut.ram);
        repeat(3) @(posedge clk);
        @(negedge clk); reset=0;
    end
endmodule
