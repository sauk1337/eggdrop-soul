# lib/memory.tcl -- what the bot remembers, and what it refuses to.
#
# Relationships (per person): familiarity 0..1 grows with every interaction
# and fades slowly; affinity -1..1 moves with how the person treats the bot
# and drifts back to neutral (grudges do not last forever). A person is
# keyed by Eggdrop handle when known ("h:alice"), otherwise by host key, so
# a nick change keeps the relationship and nick theft does not steal it.
#
# Topics (per channel): words of 5+ letters that are not stopwords, nicks or
# links are counted with exponential decay (6 h half-life). Only aggregated
# counts are kept -- never who said what, never sentences. Used to make
# small talk relevant ("still on the subject of {topic}?").
#
# Facts: only taught explicitly ("bot: remember that X is Y"). Each keeps its
# author and can be removed by its author or an admin. Facts containing
# links, adverts or channel invitations are refused.
#
# Opt-out: "!soul ignoreme" -- the person is forgotten and never addressed,
# mentioned or remembered again until they opt back in.

namespace eval ::soul::memory {
    variable rel    [dict create]   ;# key -> {nick fam aff seen n}
    variable topics [dict create]   ;# chan -> word -> {score ms}
    variable facts  [dict create]   ;# normalised key -> {key text by ts}
    variable optout [dict create]   ;# key -> ts
    variable chanlang [dict create] ;# chan -> lang -> {score ms}
    variable chanmeta [dict create] ;# chan -> {since ts anniv year}
    variable opinions [dict create] ;# word -> learned shift (-1..1)
    variable max_opinions 1000
    variable milestones {100 500 1000 5000 10000 50000}
    variable max_rel 2000
    variable max_topics 300
}

proc ::soul::memory::reset {} {
    variable rel [dict create]; variable topics [dict create]
    variable facts [dict create]; variable optout [dict create]
    variable chanlang [dict create]; variable chanmeta [dict create]
    variable opinions [dict create]
}

proc ::soul::memory::snapshot {} {
    variable rel; variable topics; variable facts; variable optout
    variable chanlang; variable chanmeta; variable opinions
    return [dict create rel $rel topics $topics facts $facts optout $optout \
                chanlang $chanlang chanmeta $chanmeta opinions $opinions]
}

proc ::soul::memory::restore {d} {
    foreach k {rel topics facts optout chanlang chanmeta opinions} {
        variable $k
        if {[dict exists $d $k] && ![catch {dict size [dict get $d $k]}]} { set $k [dict get $d $k] }
    }
}

# Identity of a person.
proc ::soul::memory::who {nick uhost hand} {
    if {$hand ni {"" "*"} && [validuser $hand]} { return "h:[string tolower $hand]" }
    return [::soul::rt::hostkey $uhost]
}

# --- opt-out --------------------------------------------------------------------

proc ::soul::memory::opted_out {key} {
    variable optout
    return [dict exists $optout $key]
}

proc ::soul::memory::set_optout {key on} {
    variable optout; variable rel
    if {$on} {
        dict set optout $key [::soul::rt::now]
        dict unset rel $key
    } else {
        dict unset optout $key
    }
}

# --- relationships ----------------------------------------------------------------

proc ::soul::memory::get_rel {key} {
    variable rel
    # Defaults first, so records saved by older versions gain new fields.
    set d [dict create nick "" fam 0.0 aff 0.0 seen 0 n 0 since [::soul::rt::now] anniv 0 ms 0 lang {}]
    if {[dict exists $rel $key]} { return [dict merge $d [dict get $rel $key]] }
    return $d
}

# Record an interaction; $daff moves affinity. Returns the updated record.
proc ::soul::memory::touch {key nick {daff 0.0} {dfam 0.03}} {
    variable rel
    variable max_rel
    if {[opted_out $key]} { return [get_rel $key] }
    set r [get_rel $key]
    dict set r nick $nick
    dict set r fam [::soul::mind::clamp [expr {[dict get $r fam] + $dfam * (1.0 - [dict get $r fam])}] 0.0 1.0]
    dict set r aff [::soul::mind::clamp [expr {[dict get $r aff] + $daff}] -1.0 1.0]
    dict set r seen [::soul::rt::now]
    dict incr r n
    dict set rel $key $r
    if {[dict size $rel] > $max_rel} { evict }
    return $r
}

proc ::soul::memory::evict {} {
    variable rel
    variable max_rel
    set pairs {}
    dict for {k r} $rel { lappend pairs [list $k [dict get $r seen]] }
    foreach p [lrange [lsort -integer -index 1 $pairs] 0 [expr {[llength $pairs] - $max_rel * 9 / 10}]] {
        dict unset rel [lindex $p 0]
    }
}

proc ::soul::memory::relclass {key} {
    set r [get_rel $key]
    if {[dict get $r aff] < -0.3} { return foe }
    if {[dict get $r fam] > 0.3 && [dict get $r aff] > 0.3} { return friend }
    if {[dict get $r fam] > 0.1} { return known }
    return stranger
}

# Slow forgetting, called every hour or so.
proc ::soul::memory::decay {} {
    variable rel
    set now [::soul::rt::now]
    dict for {k r} $rel {
        dict set r aff [expr {[dict get $r aff] * 0.97}]
        if {$now - [dict get $r seen] > 7 * 86400} {
            dict set r fam [expr {[dict get $r fam] * 0.98}]
        }
        if {[dict get $r fam] < 0.01 && abs([dict get $r aff]) < 0.05} {
            dict unset rel $k
        } else {
            dict set rel $k $r
        }
    }
}

proc ::soul::memory::forget {key} {
    variable rel
    dict unset rel $key
}

# --- topics --------------------------------------------------------------------------

proc ::soul::memory::observe_words {chan words lang} {
    variable topics
    variable max_topics
    if {![::soul::rt::cfg soul topics $chan]} { return }
    set c [::soul::rt::irclower $chan]
    # Stopwords of the channel language plus the English master (people mix
    # languages on IRC, and English is the fallback for everything else).
    set stop [dict merge [::soul::grammar::lexicon en stop] [::soul::grammar::lexicon $lang stop]]
    set members [dict create]
    foreach m [chanlist $chan] { dict set members [string tolower $m] 1 }
    set now [::soul::rt::nowms]
    set t [expr {[dict exists $topics $c] ? [dict get $topics $c] : [dict create]}]
    foreach w $words {
        if {[string length $w] < 5 || [string length $w] > 24} { continue }
        if {![regexp {^[[:alpha:]]+$} $w]} { continue }
        if {[dict exists $stop $w] || [dict exists $members $w]} { continue }
        set s [expr {[dict exists $t $w] ? [topic_score [dict get $t $w] $now] : 0.0}]
        dict set t $w [list [expr {$s + 1.0}] $now]
    }
    if {[dict size $t] > $max_topics} {
        set pairs {}
        dict for {w e} $t { lappend pairs [list $w [topic_score $e $now]] }
        set t [dict create]
        foreach p [lrange [lsort -real -decreasing -index 1 $pairs] 0 [expr {$max_topics * 3 / 4}]] {
            dict set t [lindex $p 0] [list [lindex $p 1] $now]
        }
    }
    dict set topics $c $t
}

proc ::soul::memory::topic_score {e now} {
    lassign $e s t
    return [expr {$s * pow(0.5, ($now - $t) / 21600000.0)}]
}

# Top topics of a channel: list of {word score}, best first.
proc ::soul::memory::top_topics {chan {n 5}} {
    variable topics
    set c [::soul::rt::irclower $chan]
    if {![dict exists $topics $c]} { return {} }
    set now [::soul::rt::nowms]
    set pairs {}
    dict for {w e} [dict get $topics $c] {
        set s [topic_score $e $now]
        if {$s >= 2.0} { lappend pairs [list $w [format %.1f $s]] }
    }
    return [lrange [lsort -real -decreasing -index 1 $pairs] 0 [expr {$n - 1}]]
}

proc ::soul::memory::prune_topics {} {
    variable topics
    set now [::soul::rt::nowms]
    dict for {c t} $topics {
        set keep [dict create]
        dict for {w e} $t { if {[topic_score $e $now] >= 0.2} { dict set keep $w $e } }
        if {[dict size $keep]} { dict set topics $c $keep } else { dict unset topics $c }
    }
}

# --- facts --------------------------------------------------------------------------

proc ::soul::memory::fact_key {text} {
    set k [string tolower [string trim $text " \t?!.\u00bf\u00a1"]]
    regsub -all {\s+} $k " " k
    # Leading articles (es, en, fr, it, pt, de) are not part of the subject.
    regsub {^(?:(?:el|la|los|las|un|una|the|a|an|le|les|une|des|du|il|lo|i|gli|o|os|as|um|uma|der|die|das|den|dem|ein|eine)\s+|l')} $k "" k
    return $k
}

# Returns {ok message-symbol}.
proc ::soul::memory::learn {chan key text by} {
    variable facts
    set k [fact_key $key]
    set text [string trim $text " \t."]
    if {$k eq "" || [string length $k] > 60 || $text eq "" || [string length $text] > 200} {
        return [list 0 fact.refused]
    }
    if {[regexp {[\001\r\n]} "$k$text"]} { return [list 0 fact.refused] }
    # No links, adverts or channel invitations.
    if {[::soul::rt::unsafe_text "$k $text"]} { return [list 0 fact.refused] }
    if {![dict exists $facts $k] && [dict size $facts] >= [::soul::rt::cfg soul facts_max]} {
        return [list 0 fact.full]
    }
    dict set facts $k [dict create key [string trim $key] text $text by $by ts [::soul::rt::now]]
    return [list 1 fact.learned]
}

proc ::soul::memory::recall {key} {
    variable facts
    set k [fact_key $key]
    if {[dict exists $facts $k]} { return [dict get $facts $k] }
    return {}
}

proc ::soul::memory::unlearn {key} {
    variable facts
    set k [fact_key $key]
    if {![dict exists $facts $k]} { return 0 }
    dict unset facts $k
    return 1
}

proc ::soul::memory::random_fact {} {
    variable facts
    if {![dict size $facts]} { return {} }
    return [dict get $facts [::soul::rng::pick [dict keys $facts]]]
}

proc ::soul::memory::fact_count {} {
    variable facts
    return [dict size $facts]
}

proc ::soul::memory::fact_list {} {
    variable facts
    return $facts
}

# --- languages ------------------------------------------------------------------

# A person's language preference: each confident detection adds 1 to that
# language and fades the others, so it follows people who switch.
proc ::soul::memory::note_lang {key chan lang} {
    variable rel
    variable chanlang
    if {$lang eq "" || [opted_out $key]} { return }
    if {[dict exists $rel $key]} {
        set r [dict get $rel $key]
        set ls [expr {[dict exists $r lang] ? [dict get $r lang] : {}}]
        set new {}
        dict for {l v} $ls {
            if {$l ne $lang && $v * 0.8 >= 0.1} { dict set new $l [format %.2f [expr {$v * 0.8}]] }
        }
        set cur [expr {[dict exists $ls $lang] ? [dict get $ls $lang] : 0.0}]
        dict set new $lang [format %.2f [expr {min(10.0, $cur + 1.0)}]]
        dict set r lang $new
        dict set rel $key $r
    }
    if {$chan ne ""} {
        set c [::soul::rt::irclower $chan]
        set now [::soul::rt::nowms]
        set e [expr {[dict exists $chanlang $c $lang] ? [dict get $chanlang $c $lang] : {0.0 0}}]
        dict set chanlang $c $lang [list [expr {[decayed $e $now] + 1.0}] $now]
    }
}

proc ::soul::memory::decayed {e now} {
    lassign $e v t
    return [expr {$v * pow(0.5, ($now - $t) / 21600000.0)}]
}

proc ::soul::memory::person_lang {key} {
    set r [get_rel $key]
    if {![dict exists $r lang]} { return "" }
    set best ""
    set bv 1.5
    dict for {l v} [dict get $r lang] { if {$v >= $bv} { set best $l; set bv $v } }
    return $best
}

# The language most of the channel has spoken lately, if there is a clear one.
proc ::soul::memory::channel_lang {chan} {
    variable chanlang
    set c [::soul::rt::irclower $chan]
    if {![dict exists $chanlang $c]} { return "" }
    set now [::soul::rt::nowms]
    set total 0.0
    set best ""
    set bv 0.0
    dict for {l e} [dict get $chanlang $c] {
        set v [decayed $e $now]
        set total [expr {$total + $v}]
        if {$v > $bv} { set best $l; set bv $v }
    }
    if {$total < 3.0 || $bv / $total < 0.5} { return "" }
    return $best
}

proc ::soul::memory::channel_langs {chan} {
    variable chanlang
    set c [::soul::rt::irclower $chan]
    if {![dict exists $chanlang $c]} { return {} }
    set now [::soul::rt::nowms]
    set out {}
    dict for {l e} [dict get $chanlang $c] { lappend out [list $l [format %.1f [decayed $e $now]]] }
    return [lsort -real -decreasing -index 1 $out]
}

# --- anniversaries and milestones ----------------------------------------------

# Whole years between $ts and now if today is the same month and day, else 0.
proc ::soul::memory::same_day {ts tz} {
    set now [::soul::rt::now]
    if {[clock format $ts -format %m%d -timezone $tz] ne [clock format $now -format %m%d -timezone $tz]} { return 0 }
    return [expr {[scan [clock format $now -format %Y -timezone $tz] %d] - [scan [clock format $ts -format %Y -timezone $tz] %d]}]
}

# Years since we met this person, if today is the anniversary and it has
# not been celebrated this year; else 0.
proc ::soul::memory::person_anniversary {key tz} {
    variable rel
    if {![dict exists $rel $key]} { return 0 }
    set r [get_rel $key]
    set years [same_day [dict get $r since] $tz]
    set year [clock format [::soul::rt::now] -format %Y -timezone $tz]
    if {$years < 1 || [dict get $r anniv] == $year} { return 0 }
    dict set r anniv $year
    dict set rel $key $r
    return $years
}

# Interaction milestone just reached (100, 500, ...) or 0.
proc ::soul::memory::milestone {key} {
    variable rel
    variable milestones
    if {![dict exists $rel $key]} { return 0 }
    set r [get_rel $key]
    set n [dict get $r n]
    set hit 0
    foreach m $milestones { if {$n >= $m && [dict get $r ms] < $m} { set hit $m } }
    if {$hit} {
        dict set r ms $hit
        dict set rel $key $r
    }
    return $hit
}

proc ::soul::memory::chan_seen {chan} {
    variable chanmeta
    set c [::soul::rt::irclower $chan]
    if {![dict exists $chanmeta $c]} { dict set chanmeta $c [dict create since [::soul::rt::now] anniv 0] }
}

proc ::soul::memory::channel_anniversary {chan tz} {
    variable chanmeta
    set c [::soul::rt::irclower $chan]
    if {![dict exists $chanmeta $c]} { return 0 }
    set m [dict get $chanmeta $c]
    set years [same_day [dict get $m since] $tz]
    set year [clock format [::soul::rt::now] -format %Y -timezone $tz]
    if {$years < 1 || [dict get $m anniv] == $year} { return 0 }
    dict set chanmeta $c anniv $year
    return $years
}

# --- opinions ----------------------------------------------------------------------

# The bot's opinion of something, -1..1. Without experience it is a stable
# "taste" derived from the word and the seed (same bot, same tastes); the
# channel's sentiment when it talks about the word then shifts it.
proc ::soul::memory::opinion_of {subject} {
    variable opinions
    set k [fact_key $subject]
    if {$k eq ""} { return 0.0 }
    set taste [expr {([zlib crc32 "$k|[::soul::rt::cfg soul seed]"] % 2001) / 1000.0 - 1.0}]
    set base [expr {$taste * 0.6 + ([::soul::rt::cfg soul agreeableness] - 50) / 250.0}]
    if {[dict exists $opinions $k]} { set base [expr {$base + [dict get $opinions $k]}] }
    return [::soul::mind::clamp $base -1.0 1.0]
}

proc ::soul::memory::opinion_class {subject} {
    set o [opinion_of $subject]
    if {$o > 0.25} { return like }
    if {$o < -0.25} { return dislike }
    return neutral
}

proc ::soul::memory::learn_opinion {words sentiment} {
    variable opinions
    variable max_opinions
    if {abs($sentiment) < 0.3} { return }
    foreach w $words {
        set w [fact_key $w]
        if {[string length $w] < 5} { continue }
        set v [expr {[dict exists $opinions $w] ? [dict get $opinions $w] : 0.0}]
        dict set opinions $w [format %.3f [::soul::mind::clamp [expr {$v + 0.08 * $sentiment}] -1.0 1.0]]
    }
    if {[dict size $opinions] > $max_opinions} {
        # Keep the strongest opinions (by magnitude), with their sign.
        set pairs {}
        dict for {w v} $opinions { lappend pairs [list $w $v [expr {abs($v)}]] }
        set opinions [dict create]
        foreach p [lrange [lsort -real -decreasing -index 2 $pairs] 0 [expr {$max_opinions * 3 / 4}]] {
            dict set opinions [lindex $p 0] [lindex $p 1]
        }
    }
}
