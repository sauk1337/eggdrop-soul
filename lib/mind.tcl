# lib/mind.tcl -- internal state: mood, energy, drives, learning.
#
# Mood is a point in a 2-D affect space (valence = unpleasant..pleasant,
# arousal = calm..excited), both in [-1, 1]. Events push it; every minute it
# relaxes towards a baseline set by the personality traits.
#
# Energy (0..1) follows a circadian curve in the configured time zone, is
# drained by talking and restored by sleep or "coffee". During the sleep
# window, once energy is low, the bot falls asleep: it mostly ignores the
# channel and mumbles if poked; being woken up repeatedly annoys it.
#
# Drives: social need (global, grows when nobody talks *to* the bot) and
# boredom (per channel, grows while the channel is silent). High drives make
# spontaneous behaviours more likely.
#
# Learning: each behaviour has a weight per channel (0.2..3.0). After the bot
# speaks, a feedback window stays open; laughter or warm replies reward the
# behaviour, "shut up", insults or kicks punish it, and silence after an
# unprompted remark costs a little. Over time each channel shapes its own
# version of the bot.

namespace eval ::soul::mind {
    variable valence 0.1
    variable arousal 0.0
    variable energy 0.7
    variable social 0.3
    variable asleep 0
    variable cause "just started"
    variable wakes {}          ;# ms of recent wake-up pokes
    variable boredom           ;# chan -> 0..1
    variable last_human        ;# chan -> ms of last human line
    variable last_bot          ;# chan -> ms of last bot line
    variable last_addressed 0  ;# ms anybody last talked to the bot
    variable pressure          ;# chan -> {value ms}
    variable quiet_until       ;# chan -> ms
    variable vibe              ;# chan -> {value ms}  channel mood, -1..1
    variable lastfx            ;# chan,behaviour -> ms (cooldowns)
    variable weights [dict create]   ;# chan -> behaviour -> weight
    variable feedback [dict create]  ;# chan -> list of {behaviour ms spontaneous}
    array set boredom {}
    array set last_human {}
    array set last_bot {}
    array set pressure {}
    array set quiet_until {}
    array set vibe {}
    array set lastfx {}
}

proc ::soul::mind::clamp {v lo hi} {
    return [expr {$v < $lo ? $lo : ($v > $hi ? $hi : $v)}]
}

proc ::soul::mind::trait {name} {
    return [expr {[::soul::rt::cfg soul $name] / 100.0}]
}

proc ::soul::mind::reset {} {
    variable valence 0.1; variable arousal 0.0; variable energy 0.7; variable social 0.3
    variable asleep 0; variable cause "just started"; variable wakes {}
    variable last_addressed 0
    variable weights [dict create]; variable feedback [dict create]
    foreach a {boredom last_human last_bot pressure quiet_until vibe lastfx} { variable $a; array unset $a }
}

# --- persistence ----------------------------------------------------------------

proc ::soul::mind::snapshot {} {
    variable valence; variable arousal; variable energy; variable social; variable asleep
    variable cause; variable weights
    return [dict create valence $valence arousal $arousal energy $energy social $social \
                asleep $asleep cause $cause weights $weights]
}

proc ::soul::mind::restore {d} {
    foreach k {valence arousal energy social asleep cause weights} {
        variable $k
        if {[dict exists $d $k]} { set $k [dict get $d $k] }
    }
    foreach k {valence arousal} {
        if {![string is double -strict [set $k]]} { set $k 0.0 }
        set $k [clamp [set $k] -1.0 1.0]
    }
    foreach k {energy social} {
        if {![string is double -strict [set $k]]} { set $k 0.5 }
        set $k [clamp [set $k] 0.0 1.0]
    }
    if {[catch {dict size $weights}]} { set weights [dict create] }
}

# --- emotions -------------------------------------------------------------------

# Push the mood. Sensitivity scales with arousal: an excited bot reacts more.
proc ::soul::mind::feel {dv da why} {
    variable valence; variable arousal; variable cause
    set k [expr {1.0 + 0.5 * max(0.0, $arousal)}]
    set valence [clamp [expr {$valence + $dv * $k}] -1.0 1.0]
    set arousal [clamp [expr {$arousal + $da}] -1.0 1.0]
    if {abs($dv) >= 0.05 || abs($da) >= 0.1} { set cause $why }
}

proc ::soul::mind::drain {amount} {
    variable energy
    set energy [clamp [expr {$energy - $amount}] 0.0 1.0]
}

proc ::soul::mind::boost {amount} {
    variable energy
    set energy [clamp [expr {$energy + $amount}] 0.0 1.0]
}

# --- time -----------------------------------------------------------------------

proc ::soul::mind::tz {} {
    set z [::soul::rt::cfg soul timezone]
    if {[catch {clock format 0 -timezone $z}]} { return :UTC }
    return $z
}

proc ::soul::mind::hour {} {
    return [scan [clock format [::soul::rt::now] -format %H -timezone [tz]] %d]
}

proc ::soul::mind::sleep_hour {{h ""}} {
    if {$h eq ""} { set h [hour] }
    set s [::soul::rt::cfg soul sleep_start]
    set e [::soul::rt::cfg soul sleep_end]
    if {$s == $e} { return 0 }
    if {$s < $e} { return [expr {$h >= $s && $h < $e}] }
    return [expr {$h >= $s || $h < $e}]
}

proc ::soul::mind::daypart {{h ""}} {
    if {$h eq ""} { set h [hour] }
    if {$h >= 6 && $h < 12} { return morning }
    if {$h >= 12 && $h < 19} { return afternoon }
    if {$h >= 19 && $h < 23} { return evening }
    return night
}

# Circadian energy target: low while asleep, rising in the morning, peak in
# the afternoon, easing off at night.
proc ::soul::mind::energy_target {h} {
    if {[sleep_hour $h]} { return 0.05 }
    return [expr {0.55 + 0.35 * sin(($h - 9) / 24.0 * 2 * 3.14159265)}]
}

# --- per-channel signals ----------------------------------------------------------

proc ::soul::mind::key {chan} { return [::soul::rt::irclower $chan] }

proc ::soul::mind::heard {chan} {
    variable last_human; variable boredom
    set c [key $chan]
    set last_human($c) [::soul::rt::nowms]
    if {[info exists boredom($c)]} { set boredom($c) [expr {$boredom($c) * 0.7}] }
}

proc ::soul::mind::addressed {} {
    variable last_addressed; variable social
    set last_addressed [::soul::rt::nowms]
    set social [clamp [expr {$social - 0.15}] 0.0 1.0]
}

proc ::soul::mind::pressure_of {chan} {
    variable pressure
    set c [key $chan]
    if {![info exists pressure($c)]} { return 0.0 }
    lassign $pressure($c) v t
    # Half-life of five minutes.
    return [expr {$v * pow(0.5, ([::soul::rt::nowms] - $t) / 300000.0)}]
}

proc ::soul::mind::spoke {chan} {
    variable pressure; variable last_bot
    set c [key $chan]
    set pressure($c) [list [expr {[pressure_of $chan] + 1.0}] [::soul::rt::nowms]]
    set last_bot($c) [::soul::rt::nowms]
    drain 0.008
}

proc ::soul::mind::boredom_of {chan} {
    variable boredom
    set c [key $chan]
    return [expr {[info exists boredom($c)] ? $boredom($c) : 0.0}]
}

proc ::soul::mind::silence_secs {chan} {
    variable last_human
    set c [key $chan]
    if {![info exists last_human($c)]} { return -1 }
    return [expr {([::soul::rt::nowms] - $last_human($c)) / 1000}]
}

proc ::soul::mind::quiet {chan secs} {
    variable quiet_until
    set quiet_until([key $chan]) [expr {[::soul::rt::nowms] + $secs * 1000}]
}

proc ::soul::mind::is_quiet {chan} {
    variable quiet_until
    set c [key $chan]
    return [expr {[info exists quiet_until($c)] && $quiet_until($c) > [::soul::rt::nowms]}]
}

proc ::soul::mind::unquiet {chan} {
    variable quiet_until
    unset -nocomplain quiet_until([key $chan])
}

# --- channel mood (emotional contagion) -------------------------------------------------

# The channel's mood: a decaying average of what people express (10 min
# half-life). Laughter counts as positive.
proc ::soul::mind::vibe_of {chan} {
    variable vibe
    set c [key $chan]
    if {![info exists vibe($c)]} { return 0.0 }
    lassign $vibe($c) v t
    return [expr {$v * pow(0.5, ([::soul::rt::nowms] - $t) / 600000.0)}]
}

proc ::soul::mind::sense {chan sentiment laugh} {
    variable vibe
    set x [expr {$sentiment + ($laugh ? 0.6 : 0.0)}]
    if {$x == 0} { return }
    set v [expr {[vibe_of $chan] * 0.85 + 0.15 * $x}]
    set vibe([key $chan]) [list [clamp $v -1.0 1.0] [::soul::rt::nowms]]
}

# Mood drifts towards the channels' mood; kinder bots empathise more.
proc ::soul::mind::contagion {chans} {
    variable valence
    variable arousal
    set agree [trait agreeableness]
    foreach ch $chans {
        set v [vibe_of $ch]
        if {abs($v) < 0.1} { continue }
        set valence [clamp [expr {$valence + ($v - $valence) * 0.03 * (0.5 + $agree)}] -1.0 1.0]
        set arousal [clamp [expr {$arousal + abs($v) * 0.02}] -1.0 1.0]
    }
}

# Simple per-channel cooldowns for special behaviours.
proc ::soul::mind::cooled {chan what secs} {
    variable lastfx
    set k "[key $chan],$what"
    if {[info exists lastfx($k)] && [::soul::rt::nowms] - $lastfx($k) < $secs * 1000} { return 0 }
    return 1
}

proc ::soul::mind::used {chan what} {
    variable lastfx
    set lastfx([key $chan],$what) [::soul::rt::nowms]
}

# --- sleep ----------------------------------------------------------------------------

# Returns 1 if a poke while asleep actually woke the bot up.
proc ::soul::mind::poke {} {
    variable asleep; variable wakes
    if {!$asleep} { return 0 }
    set now [::soul::rt::nowms]
    set wakes [lmap t $wakes { if {$now - $t < 120000} { set t } else continue }]
    lappend wakes $now
    if {[llength $wakes] >= 3} {
        set asleep 0
        set wakes {}
        boost 0.3
        feel -0.15 0.4 "woken up"
        return 1
    }
    return 0
}

# --- the one-minute heartbeat -----------------------------------------------------------

# Returns a list of transitions that happened: wakeup, fallasleep.
proc ::soul::mind::tick {chans} {
    variable valence; variable arousal; variable energy; variable social; variable asleep
    variable boredom; variable last_human; variable last_addressed
    set events {}
    set h [hour]
    # Energy drifts 10% of the way to the circadian target each minute.
    set target [energy_target $h]
    set energy [clamp [expr {$energy + ($target - $energy) * 0.10}] 0.0 1.0]
    # Mood relaxes to the personality baseline.
    set base [expr {([trait agreeableness] - 0.5) * 0.4 + 0.05}]
    set valence [expr {$valence + ($base - $valence) * 0.05}]
    set arousal [expr {$arousal * 0.90 + ($energy - 0.5) * 0.02}]
    # Social need grows while nobody addresses the bot (faster if extravert).
    if {[::soul::rt::nowms] - $last_addressed > 600000} {
        set social [clamp [expr {$social + 0.004 + 0.01 * [trait extraversion]}] 0.0 1.0]
    }
    if {$social > 0.85} { feel -0.01 0.0 "lonely" }
    # Boredom per channel while the channel is quiet.
    foreach ch $chans {
        set c [key $ch]
        set b [expr {[info exists boredom($c)] ? $boredom($c) : 0.0}]
        set s [silence_secs $ch]
        if {$s < 0 || $s > 300} { set b [expr {$b + 0.02 + 0.02 * [trait extraversion]}] } else { set b [expr {$b * 0.9}] }
        set boredom($c) [clamp $b 0.0 1.0]
    }
    # Sleep transitions.
    if {!$asleep && [sleep_hour $h] && $energy < 0.2} {
        set asleep 1
        lappend events fallasleep
    } elseif {$asleep && ![sleep_hour $h] && $energy > 0.25} {
        set asleep 0
        boost 0.1
        feel 0.05 0.1 "a new day"
        lappend events wakeup
    }
    return $events
}

# --- context for the grammar --------------------------------------------------------------

proc ::soul::mind::context {} {
    variable valence; variable arousal; variable energy
    return [dict create \
        mood [expr {$valence > 0.25 ? "pos" : ($valence < -0.25 ? "neg" : "neu")}] \
        energy [expr {$energy < 0.3 ? "low" : ($energy > 0.65 ? "high" : "mid")}] \
        arousal [expr {$arousal < -0.3 ? "low" : ($arousal > 0.3 ? "high" : "mid")}] \
        time [daypart]]
}

proc ::soul::mind::describe {} {
    variable valence; variable arousal; variable energy; variable social; variable asleep; variable cause
    return [format "valence %+.2f  arousal %+.2f  energy %.2f  social need %.2f  %s  (last cause: %s)" \
        $valence $arousal $energy $social [expr {$asleep ? "ASLEEP" : "awake"}] $cause]
}

# --- learning ---------------------------------------------------------------------------------

proc ::soul::mind::weight {chan beh} {
    variable weights
    set c [key $chan]
    if {[dict exists $weights $c $beh]} { return [dict get $weights $c $beh] }
    return 1.0
}

proc ::soul::mind::reward {chan beh r} {
    variable weights
    set c [key $chan]
    set w [weight $chan $beh]
    set w [clamp [expr {$w + 0.15 * $r}] 0.2 3.0]
    dict set weights $c $beh $w
    return $w
}

proc ::soul::mind::open_feedback {chan beh spont} {
    variable feedback
    set c [key $chan]
    set l [expr {[dict exists $feedback $c] ? [dict get $feedback $c] : {}}]
    lappend l [list $beh [::soul::rt::nowms] $spont]
    dict set feedback $c [lrange $l end-4 end]
}

# Apply a reaction ($r in [-1, 1]) to every behaviour whose window is open.
# Returns the behaviours that were credited.
proc ::soul::mind::credit {chan r} {
    variable feedback
    set c [key $chan]
    if {![dict exists $feedback $c]} { return {} }
    set now [::soul::rt::nowms]
    set out {}
    set keep {}
    foreach f [dict get $feedback $c] {
        lassign $f beh t spont
        if {$now - $t > 90000} { continue }
        reward $chan $beh $r
        lappend out $beh
    }
    # A window closes after its first clear reaction.
    dict set feedback $c $keep
    return $out
}

# Expire windows; an unprompted remark nobody reacted to costs a little.
proc ::soul::mind::expire_feedback {} {
    variable feedback
    set now [::soul::rt::nowms]
    dict for {c l} $feedback {
        set keep {}
        foreach f $l {
            lassign $f beh t spont
            if {$now - $t <= 90000} { lappend keep $f; continue }
            if {$spont} { reward $c $beh -0.15 }
        }
        dict set feedback $c $keep
    }
}
