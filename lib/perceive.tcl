# lib/perceive.tcl -- turn an IRC line into a percept.
#
# A percept is a dict:
#   addressed  0 | prefix ("soul: hola") | mention ("hola soul") | private
#   body       the text with the leading address removed
#   intent     first matching intent from the packs ("" if none)
#   groups     regex capture groups of that intent
#   sentiment  -1..1 from the lexicons, emoticons and simple negation
#   laugh      1 if the line laughs (jaja, lol, xD...)
#   question   1 if it asks something
#   words      normalised words (for topics)
#
# Intent patterns are matched case-insensitively against the raw text first
# (so captured facts keep their accents) and then against the normalised
# text (so look-alike tricks and missing accents still match).

namespace eval ::soul::perceive {
    variable negators {no not never nunca ni tampoco jamas nope}
}

proc ::soul::perceive::re_escape {s} {
    return [regsub -all {[][{}()*+?.\\^$|]} $s {\\&}]
}

proc ::soul::perceive::names {} {
    set names [list $::botnick]
    foreach a [::soul::rt::cfg soul names] { if {$a ni $names} { lappend names $a } }
    return $names
}

proc ::soul::perceive::normalize {text} {
    return [string tolower [::soul::rt::strip_codes $text]]
}

# Returns {mode body}.
proc ::soul::perceive::addressing {text} {
    set alt [join [lmap n [names] {re_escape $n}] |]
    if {[regexp -nocase "^\\s*@?(?:$alt)\\s*\[:,>\]+\\s*(.*)\$" $text -> body]} {
        return [list prefix $body]
    }
    if {[regexp -nocase "^\\s*@?(?:$alt)\\s+(\\S.*)\$" $text -> body]} {
        return [list prefix $body]
    }
    if {[regexp -nocase "^(.*?)\[\\s,\]+@?(?:$alt)\\s*(\[?!.\]*)\\s*\$" $text -> body punct]} {
        return [list mention "$body$punct"]
    }
    if {[regexp -nocase "(^|\[^\[:alnum:\]_\])(?:$alt)(\$|\[^\[:alnum:\]_\])" $text]} {
        return [list mention $text]
    }
    return [list 0 $text]
}

proc ::soul::perceive::sentiment {words lang} {
    variable negators
    set pos [::soul::grammar::lexicon $lang pos]
    set neg [::soul::grammar::lexicon $lang neg]
    set score 0.0
    set prev ""
    foreach w $words {
        set v 0
        if {[dict exists $pos $w]} { set v 1 } elseif {[dict exists $neg $w]} { set v -1 }
        if {$v != 0 && $prev in $negators} { set v [expr {-$v}] }
        set score [expr {$score + $v}]
        set prev $w
    }
    return $score
}

# Which language is this? Every loaded pack contributes its [detect] words
# (short function words) and [detect.chars]. Returns {lang confidence};
# lang is "" when the evidence is too weak or ambiguous (e.g. "ok", "lol").
proc ::soul::perceive::detect {text} {
    set low [string tolower [::soul::rt::strip_codes $text]]
    set toks [regexp -all -inline {[[:alpha:]']+} [normalize $text]]
    set scores {}
    foreach lang [::soul::grammar::langs] {
        set d [::soul::grammar::lexicon $lang detect]
        set c [::soul::grammar::lexicon $lang chars]
        set sc 0.0
        foreach t $toks { if {[dict exists $d $t]} { set sc [expr {$sc + 1.0}] } }
        if {[dict size $c]} {
            foreach ch [split $low ""] { if {[dict exists $c $ch]} { set sc [expr {$sc + 1.5}] } }
        }
        lappend scores [list $lang $sc]
    }
    set scores [lsort -real -decreasing -index 1 $scores]
    lassign [lindex $scores 0] best bs
    set second [expr {[llength $scores] > 1 ? [lindex $scores 1 1] : 0.0}]
    if {$bs < 1.0} { return [list "" 0.0] }
    set conf [expr {($bs - $second) / $bs}]
    if {$conf < 0.3} { return [list "" $conf] }
    return [list $best [format %.2f $conf]]
}

# Intents are tried language by language: the detected language first, then
# the order the caller suggests (person, channel, configured, English, rest).
proc ::soul::perceive::lang_order {detected order} {
    set out {}
    foreach l [concat [list $detected] $order [::soul::grammar::langs]] {
        if {$l ne "" && $l ni $out} { lappend out $l }
    }
    return $out
}

proc ::soul::perceive::match_intent {langs body norm actions} {
    foreach lang $langs {
        foreach pair [::soul::grammar::intents_of $lang] {
            lassign $pair name re
            if {$actions != [string match act_* $name]} { continue }
            set m [regexp -nocase -inline -- $re $body]
            if {![llength $m]} { set m [regexp -nocase -inline -- $re $norm] }
            if {[llength $m]} {
                return [list $name [lmap g [lrange $m 1 end] {string trim $g}] $lang]
            }
        }
    }
    return [list "" {} ""]
}

# $order: suggested language order (see lang_order).
proc ::soul::perceive::line {order text {private 0}} {
    set text [::soul::rt::strip_codes $text]
    if {$private} {
        set mode private
        set body [lindex [addressing $text] 1]
    } else {
        lassign [addressing $text] mode body
    }
    # A leading inverted mark (Spanish) must not hide an anchored intent.
    set ibody [string trimleft $body " \t\u00bf\u00a1"]
    set norm [normalize $ibody]
    set words [regexp -all -inline {[[:alpha:]]+} $norm]
    lassign [detect $body] detected conf
    set langs [lang_order $detected $order]
    lassign [match_intent $langs $ibody $norm 0] intent groups ilang
    # The language of the line: where an intent matched, else the detection.
    set lang [expr {$ilang ne "" ? $ilang : $detected}]
    set slang [expr {$lang ne "" ? $lang : [lindex $langs 0]}]

    set s [sentiment $words $slang]
    if {[regexp {(:-?\)|:-?D|<3|\^\^|:3|;-?\))} $body]} { set s [expr {$s + 1}] }
    if {[regexp {(:-?\(|D:|:'\(|>:\()} $body]} { set s [expr {$s - 1}] }
    set s [expr {max(-1.0, min(1.0, $s / max(1.0, sqrt([llength $words] / 2.0))))}]

    set laugh [regexp -nocase {(^|[^[:alpha:]])((j[aeiou]){2,}|(j[sk]){2,}|(ha){2,}|(he){2,}|lol|lmao|rofl|x+d+|mdr|kkk+|rsrs+)([^[:alpha:]]|$)|:d\M} $body]
    set question [regexp {\?\s*$|^\s*\u00bf} $body]

    return [dict create addressed $mode body $body intent $intent groups $groups                 sentiment $s laugh $laugh question $question words $words                 lang $lang detected $detected conf $conf]
}

# Actions (/me) aimed at the bot: "/me hugs soul".
proc ::soul::perceive::action {order text} {
    set p [line $order $text]
    # In an action, a mention anywhere means "done to the bot".
    if {[dict get $p addressed] eq "0"} { return $p }
    dict set p addressed action
    set langs [lang_order [dict get $p detected] $order]
    lassign [match_intent $langs $text [normalize $text] 1] intent groups ilang
    dict set p intent $intent
    dict set p groups $groups
    if {$ilang ne ""} { dict set p lang $ilang }
    return $p
}
