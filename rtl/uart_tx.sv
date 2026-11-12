// 8N1 transmitter: start pulse is accepted only while ready is high.
module uart_tx #(parameter integer BAUD_DIV=434)(
    input logic clk, reset, start,
    input logic [7:0] data,
    output logic tx, ready
);
    localparam CW = BAUD_DIV<2 ? 1 : $clog2(BAUD_DIV);
    logic [CW-1:0] count;
    logic [3:0] bit_index;
    logic [9:0] frame;
    logic busy;
    assign ready=!busy;
    assign tx=busy ? frame[0] : 1'b1;
    always @(posedge clk) begin
        if (reset) begin
            count<=0; bit_index<=0; frame<=10'h3ff; busy<=0;
        end else if (!busy) begin
            if (start) begin
                frame<={1'b1,data,1'b0}; count<=0; bit_index<=0; busy<=1;
            end
        end else if (count==BAUD_DIV-1) begin
            count<=0;
            if (bit_index==9) busy<=0;
            else begin frame<={1'b1,frame[9:1]}; bit_index<=bit_index+1; end
        end else count<=count+1;
    end
endmodule
