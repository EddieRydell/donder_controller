set repo_root [file normalize [file join [file dirname [info script]] .. ..]]
source [file join $repo_root hw scripts generated pl_config.tcl]
set hw_server_url "TCP:localhost:$donder_pl_jtag_hw_server_port"
set bit_file [file join $repo_root build vivado donder_controller.runs impl_1 donder_system_wrapper.bit]
set vitis_workspace [file join $repo_root build vitis]
set pl_control_base $donder_pl_control_baseaddr
set pl_frame_base $donder_pl_frame_ram_baseaddr
set bench_active_outputs ""
set bench_pixels_per_output ""

for {set arg_index 0} {$arg_index < [llength $argv]} {incr arg_index} {
    set arg [lindex $argv $arg_index]
    if {$arg eq "--active-outputs"} {
        incr arg_index
        set bench_active_outputs [lindex $argv $arg_index]
    } elseif {$arg eq "--pixels-per-output"} {
        incr arg_index
        set bench_pixels_per_output [lindex $argv $arg_index]
    } else {
        error "Unknown argument: $arg"
    }
}

set slcr_unlock 0xF8000008
set slcr_lock 0xF8000004
set slcr_unlock_key 0x0000DF0D
set slcr_lock_key 0x0000767B
set fpga_rst_ctrl 0xF8000240
set lvl_shftr_en 0xF8000900

proc newest {pattern} {
    set candidates [glob -nocomplain $pattern]
    if {[llength $candidates] == 0} {
        error "No file found: $pattern"
    }
    set pairs {}
    foreach path $candidates {
        lappend pairs [list [file mtime $path] $path]
    }
    set sorted [lsort -integer -decreasing -index 0 $pairs]
    return [lindex [lindex $sorted 0] 1]
}

proc mrd32 {addr} {
    set value [mrd -force -value $addr 1]
    return [expr {[lindex $value 0]}]
}

proc mwr32 {addr value} {
    mwr -force $addr $value
}

proc mask_write32 {addr mask value} {
    set current [mrd32 $addr]
    set updated [expr {($current & ~$mask) | ($value & $mask)}]
    mwr32 $addr $updated
}

proc print_reg {base offset name} {
    set value [mrd32 [expr {$base + $offset}]]
    puts [format "%s=0x%08x" $name $value]
    return $value
}

proc pl_reg_addr {name {index 0}} {
    global pl_control_base donder_pl_reg_offset donder_pl_reg_count donder_pl_reg_stride
    if {![info exists donder_pl_reg_offset($name)]} {
        error "Unknown PL register: $name"
    }
    set offset $donder_pl_reg_offset($name)
    if {[info exists donder_pl_reg_count($name)]} {
        if {$index < 0 || $index >= $donder_pl_reg_count($name)} {
            error "PL register index out of range: $name\[$index\]"
        }
        set offset [expr {$offset + ($index * $donder_pl_reg_stride($name))}]
    } elseif {$index != 0} {
        error "PL register is not arrayed: $name"
    }
    return [expr {$pl_control_base + $offset}]
}

proc print_pl_reg {name {label ""} {index 0}} {
    if {$label eq ""} {
        set label $name
    }
    set value [mrd32 [pl_reg_addr $name $index]]
    puts [format "%s=0x%08x" $label $value]
    return $value
}

proc print_frame_word {base bank_words bank word name} {
    set byte_offset [expr {(($bank * $bank_words) + $word) * 4}]
    set value [mrd32 [expr {$base + $byte_offset}]]
    puts [format "%s=0x%08x" $name $value]
    return $value
}

proc select_or_error {filter} {
    targets -set -filter $filter
}

proc post_config_pl {} {
    global slcr_unlock slcr_lock slcr_unlock_key slcr_lock_key fpga_rst_ctrl lvl_shftr_en
    mwr32 $slcr_unlock $slcr_unlock_key
    mask_write32 $lvl_shftr_en 0x0000000F 0x0000000F
    mwr32 $fpga_rst_ctrl 0x00000000
    mwr32 $slcr_lock $slcr_lock_key
}

proc configure_runtime_strands {active_outputs pixels_per_output} {
    global donder_pl_output_count
    if {$active_outputs eq "" && $pixels_per_output eq ""} {
        return
    }
    if {$active_outputs eq "" || $pixels_per_output eq ""} {
        error "Both --active-outputs and --pixels-per-output are required for runtime strand config"
    }
    puts [format "CONFIGURE_RUNTIME_STRANDS active_outputs=%u pixels_per_output=%u" $active_outputs $pixels_per_output]
    mwr32 [pl_reg_addr ACTIVE_OUTPUT_COUNT] $active_outputs
    for {set output 0} {$output < $donder_pl_output_count} {incr output} {
        set length [expr {$output < $active_outputs ? $pixels_per_output : 0}]
        mwr32 [pl_reg_addr STRAND_PIXEL_COUNT $output] $length
    }
    print_pl_reg ACTIVE_OUTPUT_COUNT ACTIVE_OUTPUT_COUNT_CONFIGURED
    print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT0_CONFIGURED 0
    print_pl_reg CONFIG_STATUS CONFIG_STATUS_CONFIGURED
}

if {![file exists $bit_file]} {
    error "Missing bitstream: $bit_file"
}

set app [newest [file join $vitis_workspace * donder_controller build donder_controller.elf]]
set fsbl [newest [file join $vitis_workspace * donder_platform zynq_fsbl build fsbl.elf]]

puts "CONNECT $hw_server_url"
connect -url $hw_server_url

puts "TARGETS_START"
puts [targets]

select_or_error {name =~ "*Cortex-A9*#0*"}
catch {stop}
puts "RESET_PROCESSOR"
rst -processor
catch {stop}

puts "DOWNLOAD_FSBL $fsbl"
dow -force $fsbl
con
after 8000
catch {stop}

puts "PROGRAM_FPGA $bit_file"
select_or_error {name =~ "xc7z020"}
fpga -file $bit_file

puts "POST_CONFIG_PL"
select_or_error {name =~ "APU"}
configparams force-mem-accesses 1
post_config_pl

puts "PL_PROBE"
set core_id [print_pl_reg ID CORE_ID]
print_pl_reg VERSION
print_pl_reg STATUS
print_pl_reg PIN_OUT
print_pl_reg FRAME_CAPACITY
print_pl_reg FRAME_BANK_WORDS
print_pl_reg ACTIVE_BANK
print_pl_reg WRITE_BANK
print_pl_reg WRITE_BANK_VALID
print_pl_reg BUSY_BANK
print_reg $pl_frame_base 0 FRAME_WORD0
if {$core_id != 0x4546504c} {
    error [format "Unexpected PL core ID: 0x%08x" $core_id]
}
configure_runtime_strands $bench_active_outputs $bench_pixels_per_output

puts "DOWNLOAD_APP $app"
select_or_error {name =~ "*Cortex-A9*#0*"}
catch {stop}
dow -force $app
con

after 5000
puts "PL_AFTER_APP"
print_pl_reg PIN_OUT
print_pl_reg FRAME_COUNT
print_pl_reg COMMITTED_WORDS
print_pl_reg FIRST_FRAME_WORD
print_pl_reg LAST_FRAME_WORD
print_pl_reg ERROR_COUNT
set bank_words [print_pl_reg FRAME_BANK_WORDS]
set active_bank [print_pl_reg ACTIVE_BANK]
print_pl_reg WRITE_BANK
print_pl_reg FRAME_SEQUENCE
print_pl_reg CONSUMER_STATUS
print_pl_reg CONSUMER_SEQUENCE
print_pl_reg CONSUMER_FRAME_COUNT
print_pl_reg CONSUMER_ERROR_COUNT
print_pl_reg WS281X_BIT_RATE
print_pl_reg WS281X_OUTPUT_COUNT
print_pl_reg WS281X_PIXELS_PER_OUTPUT
print_pl_reg ACTIVE_OUTPUT_COUNT
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT0 0
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT1 1
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT2 2
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT3 3
print_pl_reg CONFIG_STATUS
print_pl_reg STRAND_LENGTH_CLAMPED STRAND_LENGTH_CLAMPED0 0
print_pl_reg OUTPUT_INVERT_MASK OUTPUT_INVERT_MASK0 0
print_pl_reg CONSUMER_DEBUG
print_pl_reg WRITE_BANK_VALID
print_pl_reg BUSY_BANK
print_pl_reg FRAME_DROPPED
print_pl_reg FRAME_REJECTED
print_pl_reg STATUS
print_frame_word $pl_frame_base $bank_words $active_bank 0 ACTIVE_FRAME_WORD0

disconnect
