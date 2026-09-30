current_design cpu_core

set clk_name core_clock
set clk_port_name clk

set clk_period 8.849557522
set io_delay 2.0

set clk_port [get_ports $clk_port_name]

create_clock \
    -name $clk_name \
    -period $clk_period \
    $clk_port

set non_clock_inputs \
    [lsearch -inline -all -not -exact [all_inputs] $clk_port]

set_input_delay \
    $io_delay \
    -clock $clk_name \
    $non_clock_inputs

set_output_delay \
    $io_delay \
    -clock $clk_name \
    [all_outputs]
