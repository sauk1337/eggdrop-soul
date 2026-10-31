# lib/engine.tcl -- SOUL: a personality with a life of its own.
#
# The bot takes part in channel life like a regular: it answers when spoken
# to, reacts to hugs and slaps, joins in laughter, greets friends, learns
# facts it is taught, brings up what the channel has been talking about, gets
# bored, lonely, tired and sleepy, wakes up in the morning, holds (fading)
# grudges and learns per channel which of its behaviours people enjoy.
#
# Files:
#   rng.tcl       deterministic random numbers
#   grammar.tcl   phrase packs (packs/*.pack, <datadir>/soul-packs/*.pack)
#   mind.tcl      mood, energy/circadian rhythm, drives, reinforcement
#   memory.tcl    relationships, channel topics, taught facts, opt-outs
#   perceive.tcl  addressing, intents, sentiment, laughter
#   behave.tcl    behaviour catalogue, utility, decisions, explanations
#   express.tcl   typing delays, style, typos, delivery
#
# Safety rails: off in every channel until enabled; never talks to Eggdrop
# users flagged as bots, configured service nicks or people who opted out;
# a per-channel talk budget and a per-user reply budget stop loops between
# bots; "shut up" is obeyed; simulation mode logs instead of speaking; no
# message text is stored.

namespace eval ::soul {
    variable dir [file dirname [file dirname [file normalize [info script]]]]
    variable ticks 0
    variable kicked [dict create]     ;# chan -> key of whoever kicked the bot
    variable streak                   ;# chan -> unanswered spontaneous lines
    array set streak {}
}
namespace eval ::soul {
    variable D ::soul::rt::config::declare
    variable C {global channel}
    $D soul active -type bool -default no -scope $C -doc "Let the personality live in this channel"
    $D soul mode -type enum -values {quiet social chatty} -default social -scope $C -doc "quiet: only answers; social: also reacts and makes small talk; chatty: more of it"
    $D soul lang -type enum -values {en es fr pt de it} -default en -scope $C -doc "Default language (en is the master pack and the fallback)"
    $D soul autolang -type bool -default yes -scope $C -doc "Answer in the language people are speaking (detected per line, remembered per person and channel)"
    $D soul langs -type list -default "" -values {en es fr pt de it} -scope $C -doc "Languages it may answer in (empty = every installed pack)"
    $D soul simulate -type bool -default no -scope $C -doc "Log what it would say instead of speaking"
    $D soul names -type list -default "soul" -doc "Other names the bot answers to (besides its nick)"
    $D soul timezone -type str -default "Europe/Madrid" -maxlen 60 -doc "Time zone for the daily rhythm"
    $D soul sleep_start -type int -default 3 -min 0 -max 23 -doc "Hour when it gets sleepy"
    $D soul sleep_end -type int -default 9 -min 0 -max 23 -doc "Hour when it wakes up (same as start = never sleeps)"
    $D soul extraversion -type int -default 60 -min 0 -max 100 -doc "How much it seeks conversation"
    $D soul agreeableness -type int -default 65 -min 0 -max 100 -doc "How kind and forgiving it is"
    $D soul humor -type int -default 60 -min 0 -max 100 -doc "How much it jokes and laughs along"
    $D soul verbosity -type int -default 50 -min 0 -max 100 -doc "How long its answers are"
    $D soul typos -type bool -default yes -doc "Occasional typos with self-correction"
    $D soul topics -type bool -default yes -scope $C -doc "Track aggregated channel topics for small talk"
    $D soul learn_facts -type bool -default yes -scope $C -doc "Accept facts taught in this channel"
    $D soul facts_max -type int -default 500 -min 0 -max 20000 -doc "Maximum stored facts"
    $D soul idle_after -type duration -default 20m -min 60 -max 86400 -scope $C -doc "Silence before it considers small talk"
    $D soul shush_time -type duration -default 30m -min 60 -max 86400 -scope $C -doc "How long it stays quiet when told to"
    $D soul ignore_nicks -type list -default "Q L S D" -doc "Nicks never answered (network services, other bots)"
    $D soul private_chat -type bool -default no -doc "Also chat in private messages"
    $D soul away -type bool -default no -doc "Set AWAY while asleep"
    $D soul seed -type int -default 0 -min 0 -max 4294967295 -doc "Random seed (0 = different every start)"

    ::soul::rt::rl::declare soul.talk 8/5m "Lines soul may say per channel"
    ::soul::rt::rl::declare soul.user 4/60s "Replies to one person (stops bot loops)"

    ::soul::rt::perm::declare soul.view o "See soul's state, decisions and memory"
    ::soul::rt::perm::declare soul.admin m "Change soul's mood, make it speak, reload packs"
    ::soul::rt::perm::declare soul.hush o|o "Make soul be quiet in a channel"
    ::soul::rt::perm::declare soul.teach - "Teach soul facts"
    ::soul::rt::perm::declare soul.facts o "Delete any fact"

    ::soul::rt::cmd::register soul soul -proc ::soul::cmd -where {pub msg dcc} \
        -desc "Personality engine" -subs {
            ignoreme {::soul::cmd_ignoreme - "" "soul forgets you and never talks to you"}
            talktome {::soul::cmd_talktome - "" "Undo ignoreme"}
            shh      {::soul::cmd_shh soul.hush "?#channel? ?duration|off?" "Silence soul for a while"}
            status   {::soul::cmd_status soul.view "?#channel?" "Mood, energy, drives, packs"}
            why      {::soul::cmd_why soul.view "<#channel>" "Why it spoke or stayed silent (last decisions)"}
            test     {::soul::cmd_test soul.view "<#channel> <text>" "Dry-run: perception and candidate behaviours"}
            topics   {::soul::cmd_topics soul.view "<#channel>" "What the channel talks about (aggregated)"}
            rel      {::soul::cmd_rel soul.view "<nick>" "Relationship with someone"}
            facts    {::soul::cmd_facts soul.view "?word?" "List taught facts"}
            unlearn  {::soul::cmd_unlearn soul.facts "<key>" "Delete a fact"}
            forget   {::soul::cmd_forget soul.admin "<nick|mask>" "Delete what soul remembers about someone"}
            mood     {::soul::cmd_mood soul.admin "<valence|arousal|energy|social> <value>" "Set an internal value"}
            say      {::soul::cmd_say soul.admin "<#channel> <symbol>" "Make it perform a phrase symbol"}
            learning {::soul::cmd_learning soul.view "<#channel>" "Learned behaviour weights"}
            reload   {::soul::cmd_reload soul.admin "" "Reload phrase packs"}
            simlog   {::soul::cmd_simlog soul.view "" "Lines said in simulation mode"}
        }
}

# --- lifecycle -------------------------------------------------------------------------

proc ::soul::pack_dirs {} {
    variable dir
    return [list [file join $dir packs] [file join $::soul::rt::datadir soul-packs]]
}

proc ::soul::load_packs {} {
    set diags [grammar::load_dirs [pack_dirs]]
    foreach d [lrange $diags 0 19] { ::soul::rt::log warn soul "pack: $d" }
    if {[llength $diags] > 20} { ::soul::rt::log warn soul "pack: ... [expr {[llength $diags] - 20}] more problems" }
    return $diags
}

proc ::soul::start {} {
    variable ticks 0
    variable kicked [dict create]
    variable streak
    array unset streak
    mind::reset
    memory::reset
    behave::reset
    express::reset
    set seed [::soul::rt::cfg soul seed]
    rng::seed [expr {$seed ? $seed : ([clock clicks] ^ [pid])}]
    load_packs
    set s [::soul::rt::store::load soul [dict create]]
    if {[dict exists $s mind]} { mind::restore [dict get $s mind] }
    if {[dict exists $s memory]} { memory::restore [dict get $s memory] }

    ::soul::rt::bind soul pubm - * ::soul::on_pubm
    ::soul::rt::bind soul ctcp - ACTION ::soul::on_action
    ::soul::rt::bind soul join - * ::soul::on_join
    ::soul::rt::bind soul kick - * ::soul::on_kick
    ::soul::rt::bind soul topc - * ::soul::on_topic
    ::soul::rt::bind soul msgm - * ::soul::on_msgm
    ::soul::rt::sched::handler soul send ::soul::express::send
    ::soul::rt::sched::handler soul tick ::soul::tick
    ::soul::rt::sched::add -module soul -handler tick -in 60 -every 60 -name tick
}

proc ::soul::stop {} {
    save
}

proc ::soul::save {} {
    ::soul::rt::store::mark soul [dict create mind [mind::snapshot] memory [memory::snapshot]]
}

# --- gatekeeping ---------------------------------------------------------------------------

proc ::soul::live_in {chan} {
    return [expr {[::soul::rt::valid_chan $chan] && [::soul::rt::cfg soul active $chan]}]
}

# Should soul ignore this person entirely?
proc ::soul::ignored {nick uhost hand chan key} {
    if {[isbotnick $nick]} { return 1 }
    foreach n [::soul::rt::cfg soul ignore_nicks] { if {[string equal -nocase $n $nick]} { return 1 } }
    if {$hand ni {"" "*"} && [validuser $hand] && [matchattr $hand b]} { return 1 }
    if {[memory::opted_out $key]} { return 1 }
    return 0
}

proc ::soul::random_member {chan exclude} {
    set pool {}
    foreach m [chanlist $chan] {
        if {[isbotnick $m] || [string equal -nocase $m $exclude]} { continue }
        set uh [getchanhost $m $chan]
        set k [memory::who $m $uh [nick2hand $m $chan]]
        if {[memory::opted_out $k] || [ignored $m $uh [nick2hand $m $chan] "" $k]} { continue }
        lappend pool $m
    }
    return [rng::pick $pool]
}

# --- language choice ---------------------------------------------------------------

proc ::soul::allowed_langs {chan} {
    set have [grammar::langs]
    set want [::soul::rt::cfg soul langs $chan]
    if {![llength $want]} { return $have }
    return [lmap l $want { if {$l in $have} { set l } else continue }]
}

proc ::soul::lang_ok {lang chan} {
    return [expr {$lang ne "" && $lang in [allowed_langs $chan]}]
}

proc ::soul::base_lang {chan} {
    set l [::soul::rt::cfg soul lang $chan]
    if {[lang_ok $l $chan]} { return $l }
    set a [allowed_langs $chan]
    return [expr {"en" in $a || ![llength $a] ? "en" : [lindex $a 0]}]
}

# Order in which intent patterns are tried (perceive puts the language it
# detects in the line itself first).
proc ::soul::order_for {chan key} {
    set cl [expr {$chan ne "" ? [memory::channel_lang $chan] : ""}]
    return [list [memory::person_lang $key] $cl [base_lang $chan] en]
}

# Language for answering a person: the language of their line when it is
# clear, else the one they usually speak, else the channel's, else the
# configured default.
proc ::soul::reply_lang {chan key p} {
    if {![::soul::rt::cfg soul autolang $chan]} { return [base_lang $chan] }
    set l [dict get $p lang]
    if {[lang_ok $l $chan] && ([dict get $p conf] >= 0.3 || [dict get $p intent] ne "")} { return $l }
    foreach l [list [memory::person_lang $key] [expr {$chan ne "" ? [memory::channel_lang $chan] : ""}]] {
        if {[lang_ok $l $chan]} { return $l }
    }
    return [base_lang $chan]
}

# Language for unprompted remarks: what the channel speaks lately.
proc ::soul::chan_lang {chan} {
    if {[::soul::rt::cfg soul autolang $chan]} {
        set l [memory::channel_lang $chan]
        if {[lang_ok $l $chan]} { return $l }
    }
    return [base_lang $chan]
}

proc ::soul::vars {chan nick {extra {}}} {
    set v [dict create nick $nick chan $chan botnick $::botnick \
        time [clock format [::soul::rt::now] -format %H:%M -timezone [mind::tz]]]
    if {[::soul::rt::valid_chan $chan] && [validchan $chan]} {
        dict set v randnick [random_member $chan $nick]
        set t [memory::top_topics $chan 5]
        if {[llength $t]} { dict set v topic [lindex [rng::pick $t] 0] }
    }
    return [dict merge $v $extra]
}

# Render and deliver a behaviour. Returns 1 if something was queued.
proc ::soul::perform {target chan id nick key {sym ""} {extra {}} {relclass stranger} {force 0} {effects 1} {lang ""}} {
    lassign [behave::def $id] dsym base kind
    if {$sym eq ""} { set sym $dsym }
    if {$lang eq ""} { set lang [expr {[::soul::rt::valid_chan $chan] ? [chan_lang $chan] : [base_lang ""]}] }
    set v [vars $chan $nick $extra]
    set have [lmap {k x} $v { if {$x ne ""} { set k } else continue }]
    set ctx [dict merge [mind::context] [dict create rel $relclass have $have]]
    lassign [grammar::expand $lang $sym $ctx] text action
    set text [grammar::render $text $v]
    if {$text eq ""} { return 0 }
    set spont [expr {$kind in {spont ambient react}}]
    express::utter $target $text $action [dict create id $id chan $chan spont $spont force $force]
    if {$effects} { behave::apply_effects $id $key $nick }
    if {$spont && [::soul::rt::valid_chan $chan]} {
        variable streak
        set c [::soul::rt::irclower $chan]
        set streak($c) [expr {[info exists streak($c)] ? $streak($c) + 1 : 1}]
    }
    return 1
}

# --- reactions to what people say -----------------------------------------------------------

# Reinforcement from the channel's reaction to recent bot lines.
proc ::soul::credit_reaction {chan p} {
    set addressed [expr {[dict get $p addressed] ne "0"}]
    set intent [dict get $p intent]
    # Only genuine reactions count. A functional request ("remember that the
    # machine is broken") may contain negative words without being a
    # judgement of what the bot just said.
    set r ""
    if {$intent in {shush insult} && $addressed} {
        set r -1.0
    } elseif {[dict get $p laugh]} {
        set r 1.0
    } elseif {$addressed && $intent in {thanks compliment love}} {
        set r 0.6
    } elseif {$addressed && $intent eq "" && [dict get $p sentiment] > 0.3} {
        set r 0.6
    } elseif {$addressed && $intent eq "" && [dict get $p sentiment] < -0.3} {
        set r -0.6
    }
    if {$r ne ""} {
        set got [mind::credit $chan $r]
        if {[llength $got]} {
            mind::feel [expr {$r * 0.08}] 0.02 [expr {$r > 0 ? "people liked what I said" : "people did not like what I said"}]
        }
    }
}

proc ::soul::on_pubm {nick uhost hand chan text} {
    if {![live_in $chan]} { return 0 }
    set prefix [::soul::rt::cfg soul prefix $chan]
    if {$prefix ne "" && [string first $prefix [string trimleft $text]] == 0} { return 0 }
    set key [memory::who $nick $uhost $hand]
    if {[ignored $nick $uhost $hand $chan $key]} { return 0 }
    handle $chan $chan $nick $key [perceive::line [order_for $chan $key] $text]
    return 0
}

proc ::soul::on_action {nick uhost hand dest keyword text} {
    if {![live_in $dest]} { return 0 }
    set key [memory::who $nick $uhost $hand]
    if {[ignored $nick $uhost $hand $dest $key]} { return 0 }
    handle $dest $dest $nick $key [perceive::action [order_for $dest $key] $text]
    return 0
}

# Private conversation (optional). Lines that look like commands for
# Eggdrop's own msg binds or for soul itself are never touched, so passwords
# sent with "pass"/"ident" are not even looked at.
proc ::soul::on_msgm {nick uhost hand text} {
    if {![::soul::rt::cfg soul private_chat]} { return 0 }
    set first [string tolower [lindex [::soul::rt::words $text] 0]]
    if {$first eq ""} { return 0 }
    foreach b [binds msg] { if {[string equal -nocase [lindex $b 2] $first]} { return 0 } }
    set prefix [::soul::rt::cfg soul prefix]
    if {[::soul::rt::cmd::lookup [string trimleft $first $prefix]] ne ""} { return 0 }
    set key [memory::who $nick $uhost $hand]
    if {[ignored $nick $uhost $hand "" $key]} { return 0 }
    handle $nick "" $nick $key [perceive::line [order_for "" $key] $text 1]
    return 0
}

# Common pipeline for channel lines, actions and private messages.
proc ::soul::handle {target chan nick key p} {
    set ischan [expr {$chan ne ""}]
    set addressed [expr {[dict get $p addressed] ne "0"}]
    if {$ischan} {
        behave::note_line $chan
        mind::heard $chan
        variable streak
        unset -nocomplain streak([::soul::rt::irclower $chan])
        memory::chan_seen $chan
        set plang [expr {[dict get $p lang] ne "" ? [dict get $p lang] : [chan_lang $chan]}]
        memory::observe_words $chan [dict get $p words] $plang
        if {[::soul::rt::cfg soul topics $chan]} { memory::learn_opinion [dict get $p words] [dict get $p sentiment] }
        mind::sense $chan [dict get $p sentiment] [dict get $p laugh]
        credit_reaction $chan $p
    }
    set lang [reply_lang $chan $key $p]
    if {!$addressed} {
        if {$ischan} {
            memory::touch $key $nick 0.0 0.002
            if {[dict get $p conf] >= 0.3} { memory::note_lang $key $chan [dict get $p detected] }
            if {[celebrate $chan $nick $key $lang]} { return }
        }
        if {$ischan && ![set ::soul::mind::asleep] && ![mind::is_quiet $chan]} {
            set cands [behave::candidates_for_line $p]
            if {[llength $cands]} {
                set rc [memory::relclass $key]
                set id [behave::decide $chan "ambient [join $cands ,]" $cands $rc]
                if {$id ne ""} { perform $chan $chan $id $nick $key "" {} $rc 0 1 $lang }
            }
        }
        return
    }

    # Spoken to.
    mind::addressed
    set r [memory::touch $key $nick [expr {[dict get $p sentiment] * 0.05}] 0.04]
    if {[dict get $p conf] >= 0.3} { memory::note_lang $key $chan [dict get $p detected] }
    mind::feel [expr {[dict get $p sentiment] * 0.08}] 0.03 "$nick talked to me"
    set rc [memory::relclass $key]
    set pchan [expr {$ischan ? $chan : "priv:[string tolower $nick]"}]
    if {![::soul::rt::rl::allow soul.user $key]} { return }

    if {[set ::soul::mind::asleep]} {
        set woke [mind::poke]
        set id [behave::decide $pchan "asleep, poked by $nick" [list [expr {$woke ? "sleep.woken" : "sleep.talk"}]] $rc]
        if {$id ne ""} { perform $target $chan $id $nick $key "" {} $rc 0 1 $lang }
        return
    }
    if {$ischan} { celebrate $chan $nick $key $lang }
    if {$ischan && [mind::is_quiet $chan] && [dict get $p intent] ne "shush"} {
        # Hushed: only a direct question about a fact is answered.
        if {[dict get $p intent] ne "ask"} { return }
    }

    set cands [behave::candidates_for_line $p]
    # What was done to the bot affects it whether or not it answers.
    if {[llength $cands]} { behave::apply_effects [lindex $cands 0] $key $nick }
    set id [behave::decide $pchan "[dict get $p addressed] by $nick: [join $cands ,]" $cands $rc]
    if {$id eq ""} { return }

    set sym ""
    set extra {}
    set force 0
    set groups [dict get $p groups]
    switch -- $id {
        reply.teach {
            lassign $groups k v
            if {$ischan && ![::soul::rt::cfg soul learn_facts $chan]} {
                set sym fact.refused
            } elseif {![::soul::rt::perm::allowed [nick2hand $nick $chan] soul.teach $chan]} {
                set sym fact.refused
            } else {
                lassign [memory::learn $chan $k $v [list $key $nick]] ok sym
            }
            set extra [dict create fact_key $k fact $v]
        }
        reply.ask {
            if {$ischan && [mind::is_quiet $chan]} { set force 1 }
            set f [memory::recall [lindex $groups 0]]
            if {$f eq ""} {
                set sym fact.unknown
                set extra [dict create fact_key [lindex $groups 0]]
            } else {
                set extra [dict create fact_key [dict get $f key] fact [dict get $f text] fact_by [lindex [dict get $f by] 1]]
            }
        }
        reply.forget {
            set f [memory::recall [lindex $groups 0]]
            set extra [dict create fact_key [lindex $groups 0]]
            if {$f eq ""} {
                set sym fact.unknown
            } elseif {[lindex [dict get $f by] 0] eq $key || [::soul::rt::perm::allowed [nick2hand $nick $chan] soul.facts $chan]} {
                memory::unlearn [lindex $groups 0]
            } else {
                set sym fact.notyours
            }
        }
        reply.opinion {
            set subject [lindex $groups 0]
            set sym "opinion.[memory::opinion_class $subject]"
            set extra [dict create subject $subject]
        }
        reply.shush {
            set force 1
            if {$ischan} {
                express::cancel $chan
                mind::credit $chan -1.0
            }
        }
    }
    perform $target $chan $id $nick $key $sym $extra $rc $force 0 $lang
    if {$id eq "reply.shush" && $ischan} { mind::quiet $chan [::soul::rt::cfg soul shush_time $chan] }
}

# --- channel events ------------------------------------------------------------------------

proc ::soul::on_join {nick uhost hand chan} {
    variable kicked
    if {![live_in $chan]} { return 0 }
    set lc [::soul::rt::irclower $chan]
    if {[isbotnick $nick]} {
        if {[dict exists $kicked $lc]} {
            lassign [dict get $kicked $lc] kkey knick
            dict unset kicked $lc
            set id [behave::decide $chan "rejoined after kick by $knick" {react.kicked} foe]
            if {$id ne ""} { perform $chan $chan $id $knick $kkey "" [dict create kicker $knick] foe 1 }
        }
        return 0
    }
    set key [memory::who $nick $uhost $hand]
    if {[ignored $nick $uhost $hand $chan $key] || [set ::soul::mind::asleep]} { return 0 }
    set rc [memory::relclass $key]
    if {$rc ni {friend known}} { return 0 }
    # Greeting known people is less likely than greeting friends; nobody is
    # greeted twice within an hour.
    set r [memory::get_rel $key]
    if {[::soul::rt::now] - [dict get $r seen] < 3600} { return 0 }
    memory::touch $key $nick 0.0 0.0
    set id [behave::decide $chan "join of $nick ($rc)" {react.join} $rc]
    set lang [memory::person_lang $key]
    if {![lang_ok $lang $chan] || ![::soul::rt::cfg soul autolang $chan]} { set lang [chan_lang $chan] }
    if {[celebrate $chan $nick $key $lang]} { return 0 }
    if {$id ne "" && ($rc eq "friend" || [rng::chance 0.3])} {
        perform $chan $chan $id $nick $key "" {} $rc 0 1 $lang
    }
    return 0
}

# Anniversary of meeting someone, or an interaction milestone. Returns 1 if
# something was said.
proc ::soul::celebrate {chan nick key lang} {
    if {[set ::soul::mind::asleep] || [mind::is_quiet $chan]} { return 0 }
    set rc [memory::relclass $key]
    set years [memory::person_anniversary $key [mind::tz]]
    if {$years} {
        set id [behave::decide $chan "anniversary with $nick ($years y)" {anniv.person} $rc]
        if {$id ne ""} { return [perform $chan $chan $id $nick $key "" [dict create years $years] $rc 1 1 $lang] }
        return 0
    }
    set n [memory::milestone $key]
    if {$n} {
        set id [behave::decide $chan "milestone with $nick ($n)" {milestone.person} $rc]
        if {$id ne ""} { return [perform $chan $chan $id $nick $key "" [dict create count $n] $rc 0 1 $lang] }
    }
    return 0
}

proc ::soul::on_kick {nick uhost hand chan target reason} {
    variable kicked
    if {![live_in $chan] || ![isbotnick $target]} { return 0 }
    set key [memory::who $nick $uhost $hand]
    dict set kicked [::soul::rt::irclower $chan] [list $key $nick]
    memory::touch $key $nick -0.4 0.0
    mind::feel -0.3 0.3 "$nick kicked me from $chan"
    mind::credit $chan -1.0
    express::cancel $chan
    return 0
}

proc ::soul::on_topic {nick uhost hand chan topic} {
    if {![live_in $chan] || $nick eq "*" || [isbotnick $nick] || [set ::soul::mind::asleep]} { return 0 }
    set key [memory::who $nick $uhost $hand]
    if {[ignored $nick $uhost $hand $chan $key] || [mind::is_quiet $chan]} { return 0 }
    set id [behave::decide $chan "topic changed by $nick" {react.topic} [memory::relclass $key]]
    if {$id ne ""} { perform $chan $chan $id $nick $key "" {} [memory::relclass $key] }
    return 0
}

# --- the heartbeat: a life of its own -----------------------------------------------------

proc ::soul::tick {} {
    variable ticks
    variable streak
    incr ticks
    set chans [lmap c [channels] { if {[live_in $c] && [botonchan $c]} { set c } else continue }]
    set events [mind::tick $chans]
    mind::contagion $chans
    mind::expire_feedback
    if {"fallasleep" in $events && [::soul::rt::cfg soul away]} { putserv "AWAY :zzz" }
    if {"wakeup" in $events && [::soul::rt::cfg soul away]} { putserv "AWAY" }
    foreach chan $chans {
        set c [::soul::rt::irclower $chan]
        if {"wakeup" in $events} {
            if {[behave::decide $chan "woke up" {routine.wakeup} stranger] ne ""} { perform $chan $chan routine.wakeup "" "" }
            continue
        }
        if {"fallasleep" in $events} {
            if {[behave::decide $chan "falling asleep" {routine.sleep} stranger] ne ""} { perform $chan $chan routine.sleep "" "" }
            continue
        }
        if {[set ::soul::mind::asleep] || [mind::is_quiet $chan]} { continue }
        set silence [mind::silence_secs $chan]
        # The channel's anniversary (once a year, from mid-morning).
        if {[mind::hour] >= 10} {
            set years [memory::channel_anniversary $chan [mind::tz]]
            if {$years && [behave::decide $chan "channel anniversary ($years y)" {anniv.channel} stranger] ne ""} {
                perform $chan $chan anniv.channel "" "" "" [dict create years $years]
                continue
            }
        }
        # Emotional contagion: comfort a sad or angry channel, join a happy one.
        if {$silence >= 0 && $silence < 600} {
            set vb [mind::vibe_of $chan]
            if {$vb < -0.35 && [mind::cooled $chan comfort 7200]} {
                if {[decide_drives $chan {vibe.comfort} [dict create vibe.comfort [expr {-1.5 * $vb}]]] ne ""} {
                    perform $chan $chan vibe.comfort "" ""
                    mind::used $chan comfort
                }
            } elseif {$vb > 0.45 && [mind::cooled $chan party 3600]} {
                if {[decide_drives $chan {vibe.party} [dict create vibe.party [expr {1.5 * $vb}]]] ne ""} {
                    perform $chan $chan vibe.party "" ""
                    mind::used $chan party
                }
            }
        }
        # Never talk to an empty room: needs some human activity in the last
        # six hours, and at most two unanswered remarks in a row.
        if {$silence < [::soul::rt::cfg soul idle_after $chan] || $silence > 21600} { continue }
        if {[info exists streak($c)] && $streak($c) >= 2} { continue }
        set bored [mind::boredom_of $chan]
        set social [set ::soul::mind::social]
        set cands [list spont.idle]
        set mult [dict create spont.idle $bored]
        if {[llength [memory::top_topics $chan 1]]} {
            lappend cands spont.topic spont.opinion
            dict set mult spont.topic [expr {$bored * 1.2}]
            dict set mult spont.opinion [expr {$bored * 0.8}]
        }
        if {[memory::fact_count]} { lappend cands spont.fact; dict set mult spont.fact [expr {$bored * 0.6}] }
        if {$social > 0.6} { lappend cands spont.lonely; dict set mult spont.lonely $social }
        set id [decide_drives $chan $cands $mult]
        if {$id ne ""} {
            set extra {}
            set sym ""
            if {$id eq "spont.opinion"} {
                set subject [lindex [rng::pick [memory::top_topics $chan 5]] 0]
                set sym "opinion.[memory::opinion_class $subject]"
                set extra [dict create subject $subject]
            }
            if {$id eq "spont.fact"} {
                set f [memory::random_fact]
                set extra [dict create fact_key [dict get $f key] fact [dict get $f text] fact_by [lindex [dict get $f by] 1]]
            }
            if {[perform $chan $chan $id "" "" $sym $extra]} {
                set ::soul::mind::boredom($c) [expr {$bored * 0.3}]
            }
        }
    }
    if {$ticks % 60 == 0} {
        memory::decay
        memory::prune_topics
    }
    save
}

# Spontaneous decisions scale each candidate by the drive behind it.
proc ::soul::decide_drives {chan cands mult} {
    set weighted {}
    foreach id $cands {
        lappend weighted [list $id [expr {[behave::utility $chan $id stranger] * [dict get $mult $id]}]]
    }
    set weighted [lsort -real -decreasing -index 1 $weighted]
    set p [expr {min(0.97, [lindex $weighted 0 1])}]
    set roll [rng::rand]
    set chosen ""
    if {$roll < $p} {
        set i [rng::weighted [lmap w $weighted {expr {[lindex $w 1] ** 2}}]]
        set chosen [lindex $weighted $i 0]
    }
    # Record it like any other decision.
    set c [::soul::rt::irclower $chan]
    set rec [dict create ts [::soul::rt::now] event "idle [mind::silence_secs $chan]s" \
        cands [lmap w $weighted {list [lindex $w 0] [format %.2f [lindex $w 1]]}] \
        p [format %.2f $p] roll [format %.2f $roll] chosen $chosen]
    set l [expr {[dict exists $behave::why $c] ? [dict get $behave::why $c] : {}}]
    lappend l $rec
    dict set behave::why $c [lrange $l end-19 end]
    return $chosen
}

# --- commands --------------------------------------------------------------------------------

proc ::soul::cmd {ctx} {}

proc ::soul::ctx_key {ctx} {
    set uh [dict get $ctx uhost]
    if {[dict get $ctx where] eq "dcc"} { return "h:[string tolower [dict get $ctx hand]]" }
    return [memory::who [dict get $ctx nick] $uh [dict get $ctx hand]]
}

proc ::soul::private_only {ctx} {
    if {[dict get $ctx where] eq "pub"} {
        ::soul::rt::reply_private $ctx "Use this by /msg or on the partyline."
        return -code return
    }
}

proc ::soul::cmd_ignoreme {ctx} {
    memory::set_optout [ctx_key $ctx] 1
    save
    ::soul::rt::reply_private $ctx "Done: soul has forgotten you and will not talk to you or about you. Undo with: soul talktome"
}

proc ::soul::cmd_talktome {ctx} {
    memory::set_optout [ctx_key $ctx] 0
    save
    ::soul::rt::reply_private $ctx "soul may talk to you again."
}

proc ::soul::chan_arg {ctx} {
    set a [lindex [dict get $ctx argv] 0]
    if {[::soul::rt::valid_chan $a]} { return $a }
    return [dict get $ctx chan]
}

proc ::soul::cmd_shh {ctx} {
    set chan [chan_arg $ctx]
    set rest [lsearch -all -inline -not -regexp [dict get $ctx argv] {^[#&]}]
    if {$chan eq ""} { ::soul::rt::reply_private $ctx "Usage: soul shh <#channel> ?duration|off?"; return }
    set d [lindex $rest 0]
    if {$d eq "off"} {
        mind::unquiet $chan
        ::soul::rt::reply_private $ctx "soul may speak again in $chan."
        return
    }
    set secs [expr {$d eq "" ? [::soul::rt::cfg soul shush_time $chan] : [::soul::rt::parse_duration $d]}]
    if {$secs <= 0 || $secs > 604800} { ::soul::rt::reply_private $ctx "Duration must be between 1s and 7d."; return }
    mind::quiet $chan $secs
    express::cancel $chan
    ::soul::rt::journal::add soul info admin "[dict get $ctx nick] hushed soul in $chan for [::soul::rt::fmt_duration $secs]"
    ::soul::rt::reply_private $ctx "soul will stay quiet in $chan for [::soul::rt::fmt_duration $secs]."
}

proc ::soul::cmd_status {ctx} {
    private_only $ctx
    set chan [chan_arg $ctx]
    set out [list "Mind: [mind::describe]" "Grammar: [join [grammar::stats] {; }]" \
        "Memory: [dict size $memory::rel] people, [memory::fact_count] facts, [dict size $memory::optout] opted out"]
    if {$chan ne ""} {
        lappend out [format "%s: languages heard: %s (speaks %s), vibe %+.2f" $chan \
            [join [lmap x [memory::channel_langs $chan] {join $x =}] { }] [chan_lang $chan] [mind::vibe_of $chan]]
        lappend out [format "%s: active=%s mode=%s lang=%s simulate=%s boredom=%.2f pressure=%.2f quiet=%s silence=%ss" \
            $chan [::soul::rt::cfg soul active $chan] [::soul::rt::cfg soul mode $chan] [::soul::rt::cfg soul lang $chan] \
            [::soul::rt::cfg soul simulate $chan] [mind::boredom_of $chan] [mind::pressure_of $chan] \
            [mind::is_quiet $chan] [mind::silence_secs $chan]]
    }
    ::soul::rt::reply $ctx [join $out "\n"]
}

proc ::soul::cmd_why {ctx} {
    private_only $ctx
    set chan [chan_arg $ctx]
    set l [behave::explain $chan 8]
    ::soul::rt::reply $ctx [expr {[llength $l] ? [join $l "\n"] : "No decisions recorded for $chan yet."}]
}

proc ::soul::cmd_test {ctx} {
    private_only $ctx
    set chan [lindex [dict get $ctx argv] 0]
    set text [::soul::rt::rest [dict get $ctx text] 1]
    if {![::soul::rt::valid_chan $chan] || $text eq ""} { ::soul::rt::reply $ctx "Usage: soul test <#channel> <text>"; return }
    set p [perceive::line [order_for $chan ""] $text]
    set cands [behave::candidates_for_line $p]
    set scores [lmap c $cands {format "%s=%.2f" $c [behave::utility $chan $c stranger]}]
    ::soul::rt::reply $ctx [format "language=%s (detected %s, confidence %s) -> would answer in %s" \
        [expr {[dict get $p lang] eq "" ? "?" : [dict get $p lang]}] \
        [expr {[dict get $p detected] eq "" ? "-" : [dict get $p detected]}] [dict get $p conf] [reply_lang $chan "" $p]]
    ::soul::rt::reply $ctx [format "addressed=%s intent=%s groups=\[%s\] sentiment=%+.2f laugh=%d question=%d\ncandidates: %s" \
        [dict get $p addressed] [expr {[dict get $p intent] eq "" ? "-" : [dict get $p intent]}] \
        [join [dict get $p groups] " | "] [dict get $p sentiment] [dict get $p laugh] [dict get $p question] \
        [expr {[llength $scores] ? [join $scores {, }] : "none"}]]
}

proc ::soul::cmd_topics {ctx} {
    private_only $ctx
    set chan [chan_arg $ctx]
    set t [memory::top_topics $chan 10]
    ::soul::rt::reply $ctx [expr {[llength $t] ? "Topics in $chan: [join [lmap x $t {join $x =}] {, }]" : "No notable topics in $chan."}]
}

proc ::soul::cmd_rel {ctx} {
    private_only $ctx
    set who [lindex [dict get $ctx argv] 0]
    set key ""
    foreach c [channels] {
        if {[onchan $who $c]} { set key [memory::who $who [getchanhost $who $c] [nick2hand $who $c]]; break }
    }
    if {$key eq ""} { set key [string tolower $who] }
    set r [memory::get_rel $key]
    ::soul::rt::reply $ctx [format "%s (%s): familiarity %.2f, affinity %+.2f, %d interactions, class %s%s" \
        $who $key [dict get $r fam] [dict get $r aff] [dict get $r n] [memory::relclass $key] \
        [expr {[memory::opted_out $key] ? ", OPTED OUT" : ""}]]
}

proc ::soul::cmd_facts {ctx} {
    private_only $ctx
    set w [string tolower [lindex [dict get $ctx argv] 0]]
    set out {}
    dict for {k f} [memory::fact_list] {
        if {$w ne "" && [string first $w $k] < 0} { continue }
        lappend out "$k = [dict get $f text] ([lindex [dict get $f by] 1])"
        if {[llength $out] >= 20} { lappend out "..."; break }
    }
    ::soul::rt::reply $ctx [expr {[llength $out] ? [join $out "\n"] : "No facts."}]
}

proc ::soul::cmd_unlearn {ctx} {
    private_only $ctx
    set k [dict get $ctx text]
    if {[memory::unlearn $k]} {
        save
        ::soul::rt::journal::add soul info admin "[dict get $ctx hand] deleted fact '$k'"
        ::soul::rt::reply $ctx "Fact '$k' deleted."
    } else {
        ::soul::rt::reply $ctx "No fact '$k'."
    }
}

proc ::soul::cmd_forget {ctx} {
    private_only $ctx
    set who [lindex [dict get $ctx argv] 0]
    set keys {}
    if {[string match *!*@* $who]} { lappend keys [string tolower $who] }
    foreach c [channels] {
        if {[onchan $who $c]} { lappend keys [memory::who $who [getchanhost $who $c] [nick2hand $who $c]] }
    }
    if {[validuser $who]} { lappend keys "h:[string tolower $who]" }
    foreach k [lsort -unique $keys] { memory::forget $k }
    save
    ::soul::rt::journal::add soul info admin "[dict get $ctx hand] made soul forget $who"
    ::soul::rt::reply $ctx "Forgot [llength [lsort -unique $keys]] record(s) for $who."
}

proc ::soul::cmd_mood {ctx} {
    private_only $ctx
    lassign [dict get $ctx argv] var val
    if {$var ni {valence arousal energy social} || ![string is double -strict $val]} {
        ::soul::rt::reply $ctx "Usage: soul mood <valence|arousal|energy|social> <value>"; return
    }
    set lo [expr {$var in {valence arousal} ? -1.0 : 0.0}]
    set ::soul::mind::$var [mind::clamp [expr {double($val)}] $lo 1.0]
    if {$var eq "energy" && $val > 0.3} { set ::soul::mind::asleep 0 }
    ::soul::rt::journal::add soul info admin "[dict get $ctx hand] set soul $var to $val"
    ::soul::rt::reply $ctx [mind::describe]
}

proc ::soul::cmd_say {ctx} {
    private_only $ctx
    lassign [dict get $ctx argv] chan sym
    if {![::soul::rt::valid_chan $chan] || ![grammar::has [chan_lang $chan] $sym]} {
        ::soul::rt::reply $ctx "Usage: soul say <#channel> <symbol> (symbols: [join [lrange [grammar::symbols [base_lang $chan]] 0 40] { }] ...)"
        return
    }
    perform $chan $chan reply.generic "" "" $sym {} stranger 1
    ::soul::rt::reply $ctx "Queued <$sym> for $chan."
}

proc ::soul::cmd_learning {ctx} {
    private_only $ctx
    set chan [chan_arg $ctx]
    set out {}
    foreach id [lsort [behave::ids]] {
        set w [mind::weight $chan $id]
        if {$w != 1.0} { lappend out [format "%-16s %.2f" $id $w] }
    }
    ::soul::rt::reply $ctx [expr {[llength $out] ? "Learned weights in $chan (1.00 = neutral):\n[join $out \n]" : "Nothing learned yet in $chan."}]
}

proc ::soul::cmd_reload {ctx} {
    private_only $ctx
    set d [load_packs]
    ::soul::rt::reply $ctx "Packs reloaded: [join [grammar::stats] {; }]. Problems: [llength $d][expr {[llength $d] ? " (first: [lindex $d 0])" : ""}]"
}

proc ::soul::cmd_simlog {ctx} {
    private_only $ctx
    set l [lrange $express::simlog end-14 end]
    ::soul::rt::reply $ctx [expr {[llength $l] ? [join [lmap e $l {format "%s %s %s" [clock format [lindex $e 0] -format %H:%M:%S -gmt 1] [lindex $e 1] [lindex $e 2]}] "\n"] : "Nothing simulated yet."}]
}
