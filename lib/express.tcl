# lib/express.tcl -- how the bot says things.
#
# * Typing delay: proportional to length, faster when energetic, with a
#   little jitter; multi-part messages ("a || b") are spaced like a person
#   typing several lines.
# * Style: a tired bot writes in lowercase and trails off; an excited,
#   happy one adds exclamation marks.
# * Typos: occasionally (more when tired) two letters are swapped and the
#   bot corrects itself in the next line ("*word").
# * Every line is scheduled through the runtime scheduler (no extra timers),
#   re-checked at send time (still on the channel? hushed? rate limit?) and
#   sent through the runtime output functions, which split long lines and turn
#   CR/LF into separate messages. \001 is stripped so nothing can forge a CTCP.
# * Simulation mode records what would be said without saying it.

namespace eval ::soul::express {
    variable seq 0
    variable pending [dict create]    ;# target -> list of task ids
    variable simlog {}                ;# recent simulated lines (for admins/tests)
}

proc ::soul::express::reset {} {
    variable pending [dict create]
    variable simlog {}
}

proc ::soul::express::style {text} {
    set M ::soul::mind
    set energy [set ${M}::energy]
    set valence [set ${M}::valence]
    set arousal [set ${M}::arousal]
    if {$energy < 0.3 && [::soul::rng::chance 0.5]} {
        set text [string tolower $text]
        regsub {!+$} $text "..." text
    } elseif {$arousal > 0.35 && $valence > 0.2 && [regexp {[[:alpha:]]$} $text] && [::soul::rng::chance 0.35]} {
        append text "!"
    }
    return $text
}

# Returns {text correction} where correction may be "".
proc ::soul::express::typo {text} {
    if {![::soul::rt::cfg soul typos]} { return [list $text ""] }
    set energy [set ::soul::mind::energy]
    if {![::soul::rng::chance [expr {0.03 + 0.08 * (1.0 - $energy)}]]} { return [list $text ""] }
    set words [regexp -all -inline -indices {[[:alpha:]]{5,}} $text]
    if {![llength $words]} { return [list $text ""] }
    lassign [::soul::rng::pick $words] a b
    set w [string range $text $a $b]
    set i [expr {1 + [::soul::rng::int [expr {[string length $w] - 2}]]}]
    set bad "[string range $w 0 $i-1][string index $w $i+1][string index $w $i][string range $w $i+2 end]"
    if {$bad eq $w} { return [list $text ""] }
    return [list [string replace $text $a $b $bad] "*$w"]
}

proc ::soul::express::delay {text} {
    set energy [set ::soul::mind::energy]
    set cps [expr {6.0 + 8.0 * $energy}]
    set d [expr {1.0 + [string length $text] / $cps + [::soul::rng::rand] * 1.5}]
    return [expr {int(min(10.0, max(1.0, $d)))}]
}

# Say $text (may contain "||") to $target ("#chan" or a nick).
# $meta: dict with id (behaviour), chan, spont, force.
proc ::soul::express::utter {target text action meta} {
    variable pending
    set parts [lmap s [split [string map {"||" "\x1f"} $text] "\x1f"] {
        set s [string trim $s]
        if {$s eq ""} continue
        set s
    }]
    if {![llength $parts]} { return 0 }
    # Low verbosity trims long multi-line answers.
    set verb [::soul::rt::cfg soul verbosity]
    if {[llength $parts] > 1 && [::soul::rng::chance [expr {(100 - $verb) / 200.0}]]} {
        set parts [lrange $parts 0 0]
    }
    set t [string tolower $target]
    # Unprompted remarks never stack: a newer one replaces a queued one.
    if {[dict get $meta spont]} { cancel $target }
    set at 0
    set ids {}
    if {[dict exists $pending $t]} {
        foreach id [dict get $pending $t] { if {[::soul::rt::sched::get $id] ne ""} { lappend ids $id } }
    }
    set n [llength $parts]
    for {set i 0} {$i < $n} {incr i} {
        # An action ("/me ...") is the first part only; what follows is said
        # normally. "*text*" inside an action would show up as
        # "* bot *text*", so the asterisks are dropped.
        set isact [expr {$action && $i == 0}]
        set part [lindex $parts $i]
        if {$isact} { regsub {^\*(.*)\*$} $part {\1} part }
        set part [style $part]
        set fix ""
        if {!$isact} { lassign [typo $part] part fix }
        incr at [delay $part]
        set last [expr {$i == $n - 1 && $fix eq ""}]
        lappend ids [::soul::rt::sched::add -module soul -handler send -in $at \
            -args [list $target $part $isact [dict merge $meta [dict create last $last]]]]
        if {$fix ne ""} {
            incr at 2
            lappend ids [::soul::rt::sched::add -module soul -handler send -in $at \
                -args [list $target $fix 0 [dict merge $meta [dict create last [expr {$i == $n - 1}]]]]]
        }
    }
    dict set pending $t $ids
    return 1
}

proc ::soul::express::cancel {target} {
    variable pending
    set t [string tolower $target]
    if {![dict exists $pending $t]} { return }
    foreach id [dict get $pending $t] { ::soul::rt::sched::cancel $id }
    dict unset pending $t
}

# Scheduler handler: actually deliver one line.
proc ::soul::express::send {target text action meta} {
    variable simlog
    set chan [dict get $meta chan]
    set ischan [::soul::rt::valid_chan $target]
    if {$ischan} {
        if {![validchan $target] || ![botonchan $target]} { return }
        if {![dict get $meta force] && [::soul::mind::is_quiet $target]} { return }
        if {![::soul::rt::rl::allow soul.talk [::soul::rt::irclower $target] $target]} { return }
    } elseif {![::soul::rt::rl::allow soul.talk "priv:[string tolower $target]"]} {
        return
    }
    set text [string map {"\001" ""} $text]
    if {$ischan && [::soul::rt::cfg soul simulate $target]} {
        lappend simlog [list [::soul::rt::now] $target [expr {$action ? "* $text" : $text}]]
        set simlog [lrange $simlog end-49 end]
        ::soul::rt::log info soul "SIMULATE $target: [expr {$action ? "* " : ""}]$text"
    } elseif {$action} {
        foreach line [::soul::rt::split_text $text 380 2] {
            puthelp "PRIVMSG $target :\001ACTION $line\001"
        }
    } else {
        ::soul::rt::say $target $text
    }
    ::soul::mind::spoke [expr {$ischan ? $target : "priv:$target"}]
    if {[dict get $meta last] && $ischan} {
        ::soul::mind::open_feedback $target [dict get $meta id] [dict get $meta spont]
    }
}
