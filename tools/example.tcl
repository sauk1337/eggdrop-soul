#!/usr/bin/env tclsh
# tools/example.tcl -- write soul.conf.example from the option declarations.
#
#   tclsh tools/example.tcl            (writes soul.conf.example)
#   tclsh tools/example.tcl --check    (exit 1 if the file is out of date)

set ::soul_noboot 1
set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root tests harness eggsim.tcl]
source [file join $root soul.tcl]
::soul::rt::declare_core
set text [::soul::rt::config::example]
set path [file join $root soul.conf.example]
if {[lindex $argv 0] eq "--check"} {
    set fh [open $path r]; fconfigure $fh -encoding utf-8; set cur [read $fh]; close $fh
    if {$cur ne $text} { puts "soul.conf.example is out of date: run tclsh tools/example.tcl"; exit 1 }
    puts "soul.conf.example is up to date."
    exit 0
}
set fh [open $path w]; fconfigure $fh -encoding utf-8 -translation lf; puts -nonewline $fh $text; close $fh
puts "wrote $path"
