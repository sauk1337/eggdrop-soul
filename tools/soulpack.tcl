#!/usr/bin/env tclsh
# tools/soulpack.tcl -- validate soul phrase packs against the English master.
#
#   tclsh tools/soulpack.tcl ?pack.pack ...?     (default: all bundled packs)
#
# Checks, for every language:
#   * the pack parses without diagnostics (tags, regexes, references);
#   * it defines every symbol and every intent the master (en) defines;
#   * functional intents capture the same number of groups as the master
#     (teach = 2, ask = 1, forget = 1);
#   * only known {variables} are used;
#   * lexicon.pos, lexicon.neg and stopwords are present.
# Exit status 1 if any problem is found.

set ::soul_noboot 1
set root [file dirname [file dirname [file normalize [info script]]]]
source [file join $root tests harness eggsim.tcl]
source [file join $root soul.tcl]
unset ::soul_noboot
namespace eval ::soul {}
foreach f {rng grammar} { source [file join $root lib $f.tcl] }

set G ::soul::grammar
set files $argv
if {![llength $files]} { set files [lsort [glob -directory [file join $root packs] *.pack]] }
set master [file join $root packs en.pack]
set knownvars {nick chan botnick randnick topic time fact_key fact fact_by kicker subject years count}
set problems 0

proc problem {msg} { global problems; incr problems; puts "  PROBLEM: $msg" }

# Load the master alone to get the reference sets.
${G}::reset
${G}::load_file $master
set refsyms [${G}::symbols en]
set refintents [lsort -unique [lmap p [dict get $::soul::grammar::intents en] {lindex $p 0}]]

proc groups_of {re} {
    # Count capturing groups: "(" not followed by "?" and not escaped.
    return [regexp -all {(?:^|[^\\])\((?!\?)} $re]
}

foreach f $files {
    ${G}::reset
    ${G}::load_file $f
    ${G}::check_refs
    set langs [dict keys $::soul::grammar::syms]
    puts "[file tail $f]: languages [join $langs ,]"
    foreach d $::soul::grammar::diags { problem $d }
    foreach lang $langs {
        set syms [${G}::symbols $lang]
        foreach s $refsyms { if {$s ni $syms} { problem "$lang: missing symbol \[$s\]" } }
        foreach s $syms { if {$s ni $refsyms} { problem "$lang: extra symbol \[$s\] not in master" } }
        set ints {}
        if {[dict exists $::soul::grammar::intents $lang]} { set ints [dict get $::soul::grammar::intents $lang] }
        set names [lsort -unique [lmap p $ints {lindex $p 0}]]
        foreach i $refintents { if {$i ni $names} { problem "$lang: missing intent \[intent.$i\]" } }
        foreach p $ints {
            lassign $p name re
            if {$name in {teach ask forget opinion}} {
                set want [dict get {teach 2 ask 1 forget 1 opinion 1} $name]
                set got [groups_of $re]
                if {$got != $want} { problem "$lang: intent.$name must capture $want group(s), pattern has $got: $re" }
            }
        }
        dict for {s alts} [dict get $::soul::grammar::syms $lang] {
            foreach a $alts {
                foreach {- v} [regexp -all -inline {\{([a-z_]+)(?:\|[^|{}]*\|[^|{}]*)?\}} [dict get $a text]] {
                    if {$v ni $knownvars} { problem "$lang: \[$s\] uses unknown variable {$v}" }
                }
            }
        }
        foreach k {pos neg stop detect} {
            if {![dict size [${G}::lexicon $lang $k]]} { problem "$lang: empty [dict get {pos lexicon.pos neg lexicon.neg stop stopwords detect detect} $k]" }
        }
        set n 0
        dict for {s alts} [dict get $::soul::grammar::syms $lang] { incr n [llength $alts] }
        puts "  $lang: [llength $syms] symbols, $n phrases, [llength $ints] intent patterns"
    }
}
puts [expr {$problems ? "$problems problem(s)." : "All packs OK."}]
exit [expr {$problems > 0}]
