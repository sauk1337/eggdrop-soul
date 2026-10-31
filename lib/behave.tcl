# lib/behave.tcl -- behaviours, utility-based selection, learning.
#
# Every event produces a set of candidate behaviours. Each candidate gets a
# utility:
#
#   U = base x learned_weight(channel, behaviour) x modifiers
#
# modifiers come from the personality traits (extraversion, agreeableness,
# humour), the current mood and energy, the relationship with the person,
# the channel mode (quiet/social/chatty), how busy the channel is, and the
# "talk pressure" -- an exponentially decaying count of the bot's own recent
# lines, so it never dominates a conversation. Replies to direct address are
# penalised less by pressure than unprompted remarks.
#
# The bot then rolls against the best utility (P = min(0.97, U)) and, if it
# decides to speak, picks among candidates with probability proportional to
# U^2. Every decision -- including the decision to stay silent -- is kept in
# a per-channel log with all candidate scores: ".soul why #chan".

namespace eval ::soul::behave {
    # id -> {symbol base kind effects}
    #   kind: reply (direct address), act (action at the bot),
    #         ambient (not addressed), react (channel event),
    #         spont (unprompted, from the heartbeat)
    #   effects: {dv da daff denergy}
    variable catalogue {
        reply.greet      {greet.reply        0.90 reply   {0.05 0.05 0.05 0}}
        reply.bye        {bye.reply          0.85 reply   {0 0 0.02 0}}
        reply.thanks     {thanks.reply       0.85 reply   {0.06 0 0.06 0}}
        reply.howareyou  {mood.report        0.90 reply   {0.03 0 0.03 0}}
        reply.compliment {compliment.reply   0.90 reply   {0.15 0.1 0.15 0}}
        reply.insult     {insult.reply       0.80 reply   {-0.2 0.25 -0.25 0}}
        reply.love       {love.reply         0.85 reply   {0.1 0.1 0.1 0}}
        reply.joke       {joke               0.80 reply   {0.03 0.05 0.02 0}}
        reply.whoareyou  {whoami             0.85 reply   {0 0 0.02 0}}
        reply.coffee     {coffee.reply       0.90 reply   {0.08 0.15 0.05 0.2}}
        reply.shush      {shush.reply        0.97 reply   {-0.1 -0.1 -0.05 0}}
        reply.teach      {fact.learned       0.97 reply   {0.03 0 0.03 0}}
        reply.ask        {fact.recall        0.95 reply   {0 0 0.01 0}}
        reply.forget     {fact.forgotten     0.95 reply   {0 0 0 0}}
        reply.question   {yesno.answer       0.70 reply   {0 0 0.01 0}}
        reply.generic    {addressed.generic  0.60 reply   {0 0 0.01 0}}
        act.hug          {act.hug.reply      0.95 act     {0.15 0.05 0.1 0}}
        act.slap         {act.slap.reply     0.95 act     {-0.15 0.25 -0.15 0}}
        act.poke         {act.poke.reply     0.80 act     {0 0.1 0 0.02}}
        act.feed         {act.feed.reply     0.90 act     {0.1 0.05 0.08 0.1}}
        act.pet          {act.pet.reply      0.90 act     {0.1 -0.05 0.08 0}}
        act.kiss         {act.kiss.reply     0.85 act     {0.08 0.15 0.05 0}}
        act.generic      {act.generic.reply  0.60 act     {0 0.05 0 0}}
        amb.laugh        {ambient.laugh      0.10 ambient {0.03 0.05 0 0}}
        amb.greet        {ambient.greet      0.30 ambient {0.02 0 0.02 0}}
        amb.bye          {ambient.bye        0.20 ambient {0 0 0.01 0}}
        react.join       {join.friend        0.50 react   {0.04 0.02 0.01 0}}
        react.kicked     {kicked.return      0.90 react   {-0.3 0.3 -0.4 0}}
        react.topic      {topic.react        0.25 react   {0 0.05 0 0}}
        spont.idle       {idle.chatter       0.25 spont   {0 0 0 0}}
        spont.topic      {idle.topic         0.30 spont   {0 0.02 0 0}}
        spont.fact       {idle.fact          0.15 spont   {0 0 0 0}}
        spont.lonely     {lonely             0.30 spont   {-0.02 0 0 0}}
        routine.wakeup   {routine.wakeup     0.70 spont   {0.05 0.1 0 0}}
        routine.sleep    {routine.sleep      0.70 spont   {0 -0.2 0 0}}
        sleep.talk       {sleep.talk         0.45 reply   {0 0 0 0}}
        sleep.woken      {woken.reply        0.97 reply   {-0.1 0.3 -0.05 0}}
        reply.opinion    {opinion.neutral    0.90 reply   {0 0.03 0.01 0}}
        spont.opinion    {opinion.neutral    0.20 spont   {0 0.02 0 0}}
        vibe.comfort     {vibe.comfort       0.60 react   {0.02 0 0 0}}
        vibe.party       {vibe.party         0.35 react   {0.05 0.1 0 0}}
        anniv.person     {anniv.person       0.95 react   {0.1 0.1 0.1 0}}
        anniv.channel    {anniv.channel      0.90 spont   {0.1 0.1 0 0}}
        milestone.person {milestone.person   0.90 react   {0.05 0.05 0.05 0}}
    }
    variable intent_map {
        greet reply.greet bye reply.bye thanks reply.thanks howareyou reply.howareyou
        compliment reply.compliment insult reply.insult love reply.love joke reply.joke
        whoareyou reply.whoareyou coffee reply.coffee shush reply.shush teach reply.teach
        ask reply.ask forget reply.forget opinion reply.opinion
        act_hug act.hug act_slap act.slap act_poke act.poke act_feed act.feed act_pet act.pet
        act_kiss act.kiss
    }
    variable must_answer {reply.teach reply.ask reply.forget reply.shush sleep.woken anniv.person}
    variable why [dict create]    ;# chan -> list of decision records
    variable busy                 ;# chan -> list of ms of human lines
    array set busy {}
}

proc ::soul::behave::def {id} {
    variable catalogue
    return [dict get $catalogue $id]
}

proc ::soul::behave::ids {} {
    variable catalogue
    return [dict keys $catalogue]
}

proc ::soul::behave::note_line {chan} {
    variable busy
    set c [::soul::rt::irclower $chan]
    set now [::soul::rt::nowms]
    set l [expr {[info exists busy($c)] ? $busy($c) : {}}]
    lappend l $now
    set busy($c) [lmap t [lrange $l end-49 end] { if {$now - $t < 120000} { set t } else continue }]
}

proc ::soul::behave::busyness {chan} {
    variable busy
    set c [::soul::rt::irclower $chan]
    if {![info exists busy($c)]} { return 0 }
    set now [::soul::rt::nowms]
    return [llength [lmap t $busy($c) { if {$now - $t < 120000} { set t } else continue }]]
}

# --- utility -------------------------------------------------------------------------

proc ::soul::behave::utility {chan id relclass} {
    lassign [def $id] sym base kind
    # Functional answers (facts, being told to shut up, being woken) and
    # anniversaries are always given: people rely on them.
    variable must_answer
    if {$id in $must_answer} { return $base }
    set M ::soul::mind
    set u [expr {$base * [${M}::weight $chan $id]}]
    set extra [${M}::trait extraversion]
    set agree [${M}::trait agreeableness]
    set humor [${M}::trait humor]
    set energy [set ${M}::energy]
    set mode [::soul::rt::cfg soul mode $chan]
    set modef [dict get {quiet 0.0 social 1.0 chatty 1.8} $mode]
    switch -- $kind {
        reply - act {
            if {$relclass eq "foe"} { set u [expr {$u * (0.5 + 0.5 * $agree)}] }
            if {$relclass eq "friend"} { set u [expr {$u * 1.1}] }
            # Being spoken to is an invitation: only a mild pressure penalty.
            set u [expr {$u * exp(-0.08 * [${M}::pressure_of $chan])}]
        }
        ambient - react {
            if {$mode eq "quiet"} { return 0.0 }
            set u [expr {$u * $modef * (0.5 + $extra) * (0.4 + 0.6 * $energy)}]
            set u [expr {$u * exp(-0.8 * [${M}::pressure_of $chan])}]
            if {[busyness $chan] > 15} { set u [expr {$u * 0.4}] }
        }
        spont {
            if {$mode eq "quiet" && $id ni {routine.wakeup routine.sleep}} { return 0.0 }
            if {$mode eq "quiet"} { set modef 0.5 }
            set u [expr {$u * $modef * (0.4 + $extra) * (0.3 + 0.7 * $energy)}]
            set u [expr {$u * exp(-1.0 * [${M}::pressure_of $chan])}]
        }
    }
    if {$id in {reply.joke amb.laugh}} { set u [expr {$u * (0.6 + 0.8 * $humor)}] }
    return $u
}

# --- decision ------------------------------------------------------------------------

# $cands: list of behaviour ids. Returns the chosen id or "".
proc ::soul::behave::decide {chan event cands relclass} {
    variable why
    set scored {}
    foreach id [lsort -unique $cands] {
        lappend scored [list $id [utility $chan $id $relclass]]
    }
    set scored [lsort -real -decreasing -index 1 $scored]
    set best [expr {[llength $scored] ? [lindex $scored 0 1] : 0.0}]
    set p [expr {min(0.97, $best)}]
    # Answers people rely on (facts, "shut up", anniversaries) never lose
    # the roll.
    variable must_answer
    if {[llength $scored] && [lindex $scored 0 0] in $must_answer} { set p 1.0 }
    set roll [::soul::rng::rand]
    set chosen ""
    if {$roll < $p} {
        set i [::soul::rng::weighted [lmap s $scored {expr {[lindex $s 1] ** 2}}]]
        if {$i >= 0} { set chosen [lindex $scored $i 0] }
    }
    set c [::soul::rt::irclower $chan]
    set rec [dict create ts [::soul::rt::now] event $event cands [lmap s $scored {list [lindex $s 0] [format %.2f [lindex $s 1]]}] \
                 p [format %.2f $p] roll [format %.2f $roll] chosen $chosen]
    set l [expr {[dict exists $why $c] ? [dict get $why $c] : {}}]
    lappend l $rec
    dict set why $c [lrange $l end-19 end]
    return $chosen
}

proc ::soul::behave::explain {chan {n 5}} {
    variable why
    set c [::soul::rt::irclower $chan]
    if {![dict exists $why $c]} { return {} }
    set out {}
    foreach rec [lrange [dict get $why $c] end-[expr {$n - 1}] end] {
        set cands [join [lmap x [dict get $rec cands] {join $x =}] ", "]
        set res [expr {[dict get $rec chosen] ne "" ? "-> [dict get $rec chosen]" : "-> silence"}]
        lappend out "[clock format [dict get $rec ts] -format %H:%M:%S -gmt 1] [dict get $rec event]: $cands | P=[dict get $rec p] roll=[dict get $rec roll] $res"
    }
    return $out
}

proc ::soul::behave::reset {} {
    variable why [dict create]
    variable busy
    array unset busy
}

# Candidate behaviours for a percept from a channel line.
proc ::soul::behave::candidates_for_line {p} {
    variable intent_map
    set mode [dict get $p addressed]
    set intent [dict get $p intent]
    set cands {}
    if {$mode ne "0"} {
        if {$intent ne "" && [dict exists $intent_map $intent]} {
            lappend cands [dict get $intent_map $intent]
        } elseif {$mode eq "action"} {
            lappend cands act.generic
        } elseif {[dict get $p question]} {
            lappend cands reply.question
        } else {
            lappend cands reply.generic
        }
    } else {
        if {$intent eq "greet"} { lappend cands amb.greet }
        if {$intent eq "bye"} { lappend cands amb.bye }
        if {[dict get $p laugh]} { lappend cands amb.laugh }
    }
    return $cands
}

# Effects of a behaviour on the mind and on the relationship.
proc ::soul::behave::apply_effects {id key nick} {
    lassign [def $id] sym base kind effects
    lassign $effects dv da daff den
    ::soul::mind::feel $dv $da $id
    if {$den > 0} { ::soul::mind::boost $den }
    if {$key ne "" && $daff != 0} { ::soul::memory::touch $key $nick $daff 0.0 }
}
