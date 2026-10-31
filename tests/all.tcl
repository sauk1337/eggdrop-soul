# tests/all.tcl -- run the whole suite:   tclsh tests/all.tcl ?glob?
#
# Each *.test file runs in its own tclsh process, so one file can never leak
# simulator state into another. Exits non-zero on any failure.

set dir [file dirname [file normalize [info script]]]
set pattern [expr {[llength $argv] ? [lindex $argv 0] : "*"}]
set tclsh [info nameofexecutable]
set totals [dict create total 0 passed 0 skipped 0 failed 0]
set bad {}
foreach f [lsort [glob -nocomplain -directory $dir $pattern.test]] {
    set name [file tail $f]
    catch {exec $tclsh $f 2>@1} out
    if {[regexp {Total\s+(\d+)\s+Passed\s+(\d+)\s+Skipped\s+(\d+)\s+Failed\s+(\d+)} $out -> t p s fl]} {
        foreach k {total passed skipped failed} v [list $t $p $s $fl] { dict incr totals $k $v }
        puts [format "%-24s %4d passed %3d skipped %3d failed" $name $p $s $fl]
        if {$fl > 0} { lappend bad $name; puts $out }
    } else {
        puts "$name: DID NOT COMPLETE"
        puts $out
        lappend bad $name
    }
}
puts "\nTOTAL [dict get $totals total]  passed [dict get $totals passed]  skipped [dict get $totals skipped]  failed [dict get $totals failed]"
if {[llength $bad]} { puts "Problems in: [join $bad {, }]"; exit 1 }
