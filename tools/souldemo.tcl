#!/usr/bin/env tclsh
# tools/souldemo.tcl -- watch soul live through a simulated day.
#
#   tclsh tools/souldemo.tcl ?lang? ?seed?        e.g.  tclsh tools/souldemo.tcl es 3
#
# Runs entirely in the Eggdrop simulator: nothing connects anywhere. Prints
# the channel as a transcript, interleaved with the bot's internal state, so
# you can see its mood, energy and decisions evolve. Change the traits in
# $conf below to try other personalities.

set lang [expr {[llength $argv] > 0 ? [lindex $argv 0] : "en"}]
set seed [expr {[llength $argv] > 1 ? [lindex $argv 1] : 1}]
set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root tests harness eggsim.tcl]
set tmp [file join [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : "/tmp"}] souldemo-[pid]]
file mkdir $tmp
set conf [file join $tmp soul.conf]
set fh [open $conf w]
puts $fh "\[soul\]\nenabled = yes\nseed = $seed\ntimezone = :UTC\nsleep_start = 2\nsleep_end = 8\nextraversion = 75\nhumor = 70\n\[channel #cafe\]\nsoul.active = yes\nsoul.lang = $lang\nsoul.mode = chatty\nsoul.idle_after = 15m\n"
close $fh
set ::soul_config $conf
set ::soul_datadir [file join $tmp data]
::sim::addchan #cafe 1
# Start the day at 10:00 UTC.
set ::sim::now_ms [expr {[clock scan "2026-03-14 10:00:00" -gmt 1] * 1000}]
source [file join $root soul.tcl]
::sim::out

proc clock_str {} { clock format [unixtime] -format %H:%M -gmt 1 }
proc show {} {
    foreach o [::sim::out_timed] {
        lassign $o ts l
        set at [clock format $ts -format %H:%M -gmt 1]
        if {[regexp {^PRIVMSG (\S+) :\001ACTION (.*)\001$} $l -> t text]} {
            puts "$at  * $::botnick $text"
        } elseif {[regexp {^PRIVMSG (\S+) :(.*)$} $l -> t text]} {
            puts "$at <$::botnick> $text"
        }
    }
}
proc say {nick text} { puts "[clock_str] <$nick> $text"; ::sim::pub $nick #cafe $text; ::sim::advance 12; show }
proc act {nick text} { puts "[clock_str]  * $nick $text"; ::sim::action $nick #cafe $text; ::sim::advance 12; show }
proc wait {mins} { ::sim::advance [expr {$mins * 60}]; show }
proc state {} { puts "        \[[::soul::mind::describe]\]" }

set S [dict create \
  en {g "hi Meepo" h "Meepo: how are you?" t "Meepo: remember that the coffee machine is broken again" q "Meepo: what is the coffee machine?" j "Meepo: tell me a joke" l "hahaha" hug "hugs Meepo" slap "slaps Meepo" sh "Meepo: shut up" c1 "the deployment pipeline failed again" c2 "pipeline logs show a timeout in the deployment step" ins "Meepo you are useless" bye "bye all" co "Meepo: have a coffee"} \
  es {g "hola Meepo" h "Meepo: como estas?" t "Meepo: recuerda que la cafetera es un desastre" q "Meepo: que es la cafetera?" j "Meepo: cuentame un chiste" l "jajaja" hug "abraza a Meepo" slap "abofetea a Meepo" sh "Meepo: callate" c1 "el despliegue ha vuelto a fallar" c2 "los logs del despliegue dicen timeout en el servidor" ins "Meepo eres un inutil" bye "adios a todos" co "Meepo: toma un cafe"}]
set L [dict get $S [expr {[dict exists $S $lang] ? $lang : "en"}]]

puts "=== A day in #cafe (bot language=$lang, seed=$seed) ==="
if {![dict exists $S $lang]} { puts "    (users speak English here: the English master intents are the fallback)" }
::sim::enter laura laura@l.example #cafe
::sim::enter marc marc@m.example #cafe
state
say laura [dict get $L g]
say laura [dict get $L h]
say marc [dict get $L t]
wait 2
say laura [dict get $L q]
say marc [dict get $L j]
say laura [dict get $L l]
act laura [dict get $L hug]
say marc [dict get $L c1]
say laura [dict get $L c2]
say marc [dict get $L c1]
state
puts "        ... the channel goes quiet for a while ..."
wait 45
state
say marc [dict get $L ins]
act marc [dict get $L slap]
state
say laura [dict get $L sh]
wait 40
puts "        ... evening ..."
wait 300
say laura [dict get $L co]
say laura [dict get $L bye]
puts "        ... night falls ..."
wait 600
state
say marc [dict get $L g]
say marc [dict get $L g]
say marc [dict get $L g]
state
puts "        ... morning ..."
wait 420
state
puts "        ... a multilingual afternoon: everyone in their own language ..."
::sim::enter joao joao@j.example #cafe
::sim::enter klaus klaus@k.example #cafe
::sim::enter chloe chloe@c.example #cafe
say joao "ol\u00e1 Meepo, tudo bem com voc\u00ea?"
say klaus "hallo Meepo, wie geht es dir?"
say chloe "salut Meepo, \u00e7a va ?"
say laura "Meepo: what do you think about pizza?"
say joao "Meepo: o que voc\u00ea acha de futebol?"
say klaus "Meepo: was h\u00e4ltst du von Kaffee?"
foreach i {1 2 3 4 5} { say chloe "c'est g\u00e9nial, on rigole bien ici haha $i" }
wait 3
puts "\nLanguages heard in #cafe: [join [lmap x [::soul::memory::channel_langs #cafe] {join $x =}] {, }]"
puts "\nWhy it did what it did (last decisions):"
foreach l [::soul::behave::explain #cafe 8] { puts "  $l" }
puts "\nWhat it learned in #cafe:"
foreach id [lsort [::soul::behave::ids]] {
    set w [::soul::mind::weight #cafe $id]
    if {$w != 1.0} { puts [format "  %-16s %.2f" $id $w] }
}
::soul::rt::shutdown
file delete -force $tmp
