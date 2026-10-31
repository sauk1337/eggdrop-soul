# tests/harness/setup.tcl -- shared fixtures for the test files.

package require tcltest 2.5
namespace import ::tcltest::*

# Keep test data out of the source tree.
foreach v {TMPDIR TEMP TMP} {
    if {[info exists ::env($v)] && [file isdirectory $::env($v)]} {
        ::tcltest::configure -tmpdir [file join $::env($v) soul-tests]
        break
    }
}
file mkdir [::tcltest::temporaryDirectory]

namespace eval ::testenv {
    variable root [file normalize [file join [file dirname [info script]] .. ..]]
    variable tmp ""
}

if {![llength [info commands ::sim::reset]]} {
    source [file join $::testenv::root tests harness eggsim.tcl]
}

# Boot soul on a fresh simulator with the given soul.conf text.
# Creates #test with the bot opped, an owner "admin" and a channel op "op".
# With $keepdata the previous data directory is reused (restart test).
proc ::testenv::boot {{conf ""} {keepdata 0}} {
    variable root
    variable tmp
    if {[llength [info commands ::soul::rt::shutdown]]} { ::soul::rt::shutdown }
    ::sim::reset
    if {!$keepdata || $tmp eq ""} {
        if {$tmp ne ""} { catch {file delete -force $tmp} }
        set tmp [file join [::tcltest::temporaryDirectory] soul-[pid]-[clock clicks]]
        file delete -force $tmp
        file mkdir $tmp
    }
    set fh [open [file join $tmp soul.conf] w]
    puts $fh $conf
    close $fh
    set ::soul_config [file join $tmp soul.conf]
    set ::soul_datadir [file join $tmp data]
    ::sim::addchan #test 1
    ::sim::adduser admin "*!*@admin.users.quakenet.org" n
    ::sim::adduser op "*!*@op.users.quakenet.org" "" {#test o}
    uplevel #0 [list source [file join $root soul.tcl]]
    ::sim::out
    return $tmp
}

proc ::testenv::cleanup {} {
    variable tmp
    if {[llength [info commands ::soul::rt::shutdown]]} { ::soul::rt::shutdown }
    if {$tmp ne ""} { catch {file delete -force $tmp} }
    set tmp ""
}
