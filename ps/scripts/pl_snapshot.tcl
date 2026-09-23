set repo_root [file normalize [file join [file dirname [info script]] .. ..]]
source [file join $repo_root hw scripts generated pl_config.tcl]
set hw_server_url "TCP:localhost:$donder_pl_jtag_hw_server_port"
set pl_control_base $donder_pl_control_baseaddr

proc mrd32 {addr} {
    set value [mrd -force -value $addr 1]
    return [expr {[lindex $value 0]}]
}

proc select_or_error {filter} {
    targets -set -filter $filter
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

puts "CONNECT $hw_server_url"
connect -url $hw_server_url
select_or_error {name =~ "APU"}
configparams force-mem-accesses 1

puts "PL_SNAPSHOT"
print_pl_reg ID CORE_ID
print_pl_reg VERSION
print_pl_reg STATUS
print_pl_reg FRAME_COUNT
print_pl_reg COMMITTED_WORDS
print_pl_reg ERROR_COUNT
print_pl_reg FRAME_BANK_WORDS
print_pl_reg ACTIVE_BANK
print_pl_reg WRITE_BANK
print_pl_reg FRAME_SEQUENCE
print_pl_reg CONSUMER_STATUS
print_pl_reg CONSUMER_SEQUENCE
print_pl_reg CONSUMER_FRAME_COUNT
print_pl_reg CONSUMER_ERROR_COUNT
print_pl_reg WS281X_OUTPUT_COUNT
print_pl_reg WS281X_PIXELS_PER_OUTPUT
print_pl_reg WRITE_BANK_VALID
print_pl_reg BUSY_BANK
print_pl_reg FRAME_DROPPED
print_pl_reg FRAME_REJECTED
print_pl_reg ACTIVE_OUTPUT_COUNT
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT0 0
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT1 1
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT2 2
print_pl_reg STRAND_PIXEL_COUNT STRAND_PIXEL_COUNT3 3
print_pl_reg CONFIG_STATUS
print_pl_reg STRAND_LENGTH_CLAMPED STRAND_LENGTH_CLAMPED0 0
print_pl_reg OUTPUT_INVERT_MASK OUTPUT_INVERT_MASK0 0

disconnect
