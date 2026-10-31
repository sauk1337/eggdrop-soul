# soul.tcl -- a personality with a life of its own, for Eggdrop.
# Copyright (c) 2026 sauk1337. MIT License, see LICENSE.
#
# In eggdrop.conf, after the server/channels/irc modules are loaded:
#
#   set soul_config  "scripts/soul/soul.conf"   ;# optional (this is the default)
#   set soul_datadir "soul-data"                ;# optional (this is the default)
#   source scripts/soul/soul.tcl
#
# Then switch it on in a channel (soul.conf):
#
#   [channel #mychannel]
#   active = yes
#
# Safe to re-source: on .rehash the previous instance saves its memory and
# removes its binds and timers before loading again.

if {[llength [info commands ::soul::rt::shutdown]]} {
    if {[catch {::soul::rt::shutdown} err]} { catch {putlog "soul: shutdown of previous instance failed: $err"} }
}

namespace eval ::soul {
    variable base [file dirname [file normalize [info script]]]
}

# Sourced from a lambda: nothing leaks into Eggdrop's global namespace.
apply {{} {
    foreach f {rt rng grammar mind memory perceive behave express engine} {
        uplevel #0 [list source [file join $::soul::base lib $f.tcl]]
    }
}}

proc ::soul::rt::shutdown {} {
    stop stopped
    sched::stop
    catch {store::flush}
}

# Flush memory on Eggdrop's save/rehash/restart/shutdown events.
proc ::soul::rt::on_event {type} {
    catch {::soul::save}
    if {[catch {store::flush} err]} { log error store "flush on $type failed: $err" }
    return 0
}

proc ::soul::rt::boot {} {
    variable state
    variable datadir
    variable errors {}
    variable last_error ""
    set cfgpath [expr {[info exists ::soul_config] ? $::soul_config : [file join $::soul::base soul.conf]}]
    set datadir [file normalize [expr {[info exists ::soul_datadir] ? $::soul_datadir : "soul-data"}]]
    file mkdir $datadir
    catch {file attributes $datadir -permissions 0700}
    rl::reset
    declare_core
    set diags [config::load $cfgpath]
    foreach d $diags {
        set where [expr {[dict get $d line] ? "[file tail $cfgpath]:[dict get $d line]: " : ""}]
        putlog "soul: [string toupper [dict get $d sev]] $where[dict get $d msg]"
    }
    ::bind evnt - save ::soul::rt::on_event
    ::bind evnt - prerehash ::soul::rt::on_event
    ::bind evnt - prerestart ::soul::rt::on_event
    ::bind evnt - sigterm ::soul::rt::on_event
    ::bind evnt - die ::soul::rt::on_event
    if {![cfg soul enabled]} {
        set state stopped
        putlog "soul $::soul::rt::version loaded but disabled (soul.enabled = no)"
        return
    }
    if {[catch {
        set state running
        ::soul::start
        cmd::bind_all
    } err]} {
        set state broken
        unbind_all
        putlog "soul: ERROR could not start: $err"
        return
    }
    sched::start
    set n 0
    foreach c [channels] { if {[cfg soul active $c]} { incr n } }
    putlog "soul $::soul::rt::version loaded: [llength [dict keys $::soul::grammar::syms]] languages, active in $n channel(s)"
}

if {![info exists ::soul_noboot]} { ::soul::rt::boot }
