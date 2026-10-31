# lib/grammar.tcl -- phrase packs and the recursive text generator.
#
# PACK FORMAT (UTF-8 text files, *.pack; never evaluated as code)
#
#   # comment
#   @lang es                       language of the following sections
#   [greet.reply]                  a grammar symbol
#   - Hola, {nick}!  ~mood=pos     one alternative per "- " line
#   - buenas {nick}  ~w=2
#   - mm... hola     ~mood=neg ~energy=low
#   - te abraza      ~action       sent as /me
#   - hola || que tal todo?        "||" splits into several messages
#
#   Inside a text:
#     {var}        variable (nick, chan, botnick, topic, fact, randnick, time...)
#     {var|one|many}  plural: "one" when the variable is 1, else "many"
#                  (e.g. "{years} {years|year|years}")
#     <symbol>     expands another symbol (recursion depth limited)
#     (a|b|c)      inline random choice; parentheses without "|" are literal
#
#   Tags at the end of a line (all optional):
#     ~w=N                 weight (default 1)
#     ~mood=pos|neu|neg    valence bucket        ~energy=low|mid|high
#     ~arousal=low|mid|high                       ~rel=friend|known|stranger|foe
#     ~time=morning|afternoon|evening|night       ~action
#     Several values may be given with commas: ~mood=pos,neu
#
#   Special sections:
#     [intent.NAME]   each line is a regular expression (case-insensitive);
#                     capture groups are passed to the behaviour
#     [lexicon.pos] / [lexicon.neg] / [stopwords]   words, space separated
#     [detect]        short, very common words of the language (the, and,
#                     que, und...) used to recognise which language is spoken
#     [detect.chars]  characters typical of the language (\u00f1, \u00df, \u00e3...)
#
# Packs are loaded from packs/ and then <datadir>/soul-packs,
# so administrators can extend or override phrases without touching code.

namespace eval ::soul::grammar {
    variable syms    [dict create]   ;# lang -> symbol -> list of alt dicts
    variable intents [dict create]   ;# lang -> list of {intent regex}
    variable lex     [dict create]   ;# lang -> pos|neg|stop -> dict word 1
    variable diags   {}
    variable condkeys {mood energy arousal rel time}
    variable condvals {
        mood {pos neu neg} energy {low mid high} arousal {low mid high}
        rel {friend known stranger foe} time {morning afternoon evening night}
    }
    variable maxdepth 6
    variable maxlen 400
}

proc ::soul::grammar::reset {} {
    variable syms; variable intents; variable lex; variable diags
    set syms [dict create]; set intents [dict create]; set lex [dict create]; set diags {}
}

proc ::soul::grammar::diag {file line msg} {
    variable diags
    lappend diags "[file tail $file]:$line: $msg"
}

# Parse one pack text. $file is only used in diagnostics.
proc ::soul::grammar::load_text {text file} {
    variable syms; variable intents; variable lex; variable condkeys; variable condvals
    set lang en
    set sect ""
    set ln 0
    foreach raw [split [string map {"\r\n" "\n"} $text] "\n"] {
        incr ln
        set line [string trim $raw]
        if {$line eq "" || [string index $line 0] eq "#"} { continue }
        if {[regexp {^@lang\s+([a-z]{2})$} $line -> l]} { set lang $l; continue }
        if {[regexp {^\[([a-z][a-z0-9_.]*)\]$} $line -> s]} { set sect $s; continue }
        if {$sect eq ""} { diag $file $ln "text outside of a section"; continue }
        if {[regexp {^intent\.([a-z0-9_]+)$} $sect -> iname]} {
            if {![regexp {^-\s+(.+)$} $line -> re]} { diag $file $ln "expected '- <regex>'"; continue }
            if {[catch {regexp -nocase -- $re ""} err]} { diag $file $ln "bad regex: $err"; continue }
            dict lappend intents $lang [list $iname $re]
            continue
        }
        if {$sect in {lexicon.pos lexicon.neg stopwords detect}} {
            set kind [dict get {lexicon.pos pos lexicon.neg neg stopwords stop detect detect} $sect]
            foreach w [regexp -all -inline {\S+} [string tolower [string trimleft $line "- "]]] {
                dict set lex $lang $kind $w 1
            }
            continue
        }
        if {$sect eq "detect.chars"} {
            foreach ch [split [string tolower [string trimleft $line "- "]] ""] {
                if {![string is space $ch]} { dict set lex $lang chars $ch 1 }
            }
            continue
        }
        if {![regexp {^-\s+(.*)$} $line -> body]} { diag $file $ln "expected '- <text>'"; continue }
        # Split trailing ~tags from the text.
        set alt [dict create text "" w 1.0 conds {} action 0]
        while {[regexp {^(.*\S)\s+~([a-z]+)(?:=(\S+))?$} $body -> rest k v]} {
            set body $rest
            switch -- $k {
                w {
                    if {![string is double -strict $v] || $v < 0} { diag $file $ln "bad weight '$v'" } else { dict set alt w [expr {double($v)}] }
                }
                action { dict set alt action 1 }
                default {
                    if {$k ni $condkeys} { diag $file $ln "unknown tag ~$k"; continue }
                    set vals [split $v ,]
                    foreach x $vals {
                        if {$x ni [dict get $condvals $k]} { diag $file $ln "bad value '$x' for ~$k" }
                    }
                    dict set alt conds $k $vals
                }
            }
        }
        if {[regexp {^~action$} $body]} { diag $file $ln "empty text"; continue }
        dict set alt text $body
        # Variables this alternative cannot do without (see choose).
        set needs {}
        foreach {- v} [regexp -all -inline {\{([a-z_]+)(?:\|[^|{}]*\|[^|{}]*)?\}} $body] {
            if {$v in {topic randnick fact fact_key fact_by kicker subject years count} && $v ni $needs} { lappend needs $v }
        }
        dict set alt needs $needs
        # dict lappend has no nested form: append to the inner list by hand.
        set cur [expr {[dict exists $syms $lang $sect] ? [dict get $syms $lang $sect] : {}}]
        lappend cur $alt
        dict set syms $lang $sect $cur
    }
}

proc ::soul::grammar::load_file {path} {
    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        set text [read $fh 1048577]
        close $fh
    } err]} {
        diag $path 0 "cannot read: $err"
        return
    }
    if {[string length $text] > 1048576} { diag $path 0 "pack larger than 1 MiB ignored"; return }
    load_text $text $path
}

# Load every pack from the given directories (in order) and check references.
proc ::soul::grammar::load_dirs {dirs} {
    reset
    foreach d $dirs {
        foreach f [lsort [glob -nocomplain -directory $d *.pack]] { load_file $f }
    }
    check_refs
    variable diags
    return $diags
}

proc ::soul::grammar::check_refs {} {
    variable syms
    dict for {lang table} $syms {
        dict for {sym alts} $table {
            foreach a $alts {
                foreach {- ref} [regexp -all -inline {<([a-z][a-z0-9_.]*)>} [dict get $a text]] {
                    if {![dict exists $table $ref]} { diag "$lang:$sym" 0 "reference to undefined symbol <$ref>" }
                }
            }
        }
    }
}

proc ::soul::grammar::has {lang sym} {
    variable syms
    return [expr {[dict exists $syms $lang $sym] || [dict exists $syms en $sym]}]
}

proc ::soul::grammar::symbols {lang} {
    variable syms
    if {![dict exists $syms $lang]} { return {} }
    return [lsort [dict keys [dict get $syms $lang]]]
}

# Languages that have phrases loaded.
proc ::soul::grammar::langs {} {
    variable syms
    return [lsort [dict keys $syms]]
}

# Intents of exactly one language (no fallback).
proc ::soul::grammar::intents_of {lang} {
    variable intents
    if {[dict exists $intents $lang]} { return [dict get $intents $lang] }
    return {}
}

proc ::soul::grammar::intent_list {lang} {
    variable intents
    set out {}
    if {[dict exists $intents $lang]} { set out [dict get $intents $lang] }
    if {$lang ne "en" && [dict exists $intents en]} { lappend out {*}[dict get $intents en] }
    return $out
}

proc ::soul::grammar::lexicon {lang kind} {
    variable lex
    if {[dict exists $lex $lang $kind]} { return [dict get $lex $lang $kind] }
    return {}
}

# Does an alternative's condition set match the context?
proc ::soul::grammar::matches {alt ctx} {
    if {[dict exists $alt needs] && [dict exists $ctx have]} {
        foreach v [dict get $alt needs] { if {$v ni [dict get $ctx have]} { return 0 } }
    }
    dict for {k vals} [dict get $alt conds] {
        if {![dict exists $ctx $k] || [dict get $ctx $k] ni $vals} { return 0 }
    }
    return 1
}

# Pick an alternative of $sym. Alternatives whose conditions match are
# preferred; unconditional ones are always eligible. If the context lists
# the non-empty variables ("have"), alternatives that need a missing one
# (e.g. {topic} before the channel has topics) are skipped.
proc ::soul::grammar::choose {lang sym ctx} {
    variable syms
    set alts {}
    if {[dict exists $syms $lang $sym]} {
        set alts [dict get $syms $lang $sym]
    } elseif {[dict exists $syms en $sym]} {
        set alts [dict get $syms en $sym]
    }
    if {![llength $alts]} { return {} }
    set ok {}
    set weights {}
    foreach a $alts {
        if {[matches $a $ctx]} {
            lappend ok $a
            # Conditional alternatives that match are more specific: boost them.
            lappend weights [expr {[dict get $a w] * ([dict size [dict get $a conds]] ? 2.0 : 1.0)}]
        }
    }
    set i [::soul::rng::weighted $weights]
    if {$i < 0} { return {} }
    return [lindex $ok $i]
}

# Expand a symbol. Returns {text action}. Variables ({nick} ...) are NOT
# substituted here; see render.
proc ::soul::grammar::expand {lang sym ctx {depth 0}} {
    variable maxdepth
    if {$depth > $maxdepth} { return [list "" 0] }
    set alt [choose $lang $sym $ctx]
    if {$alt eq ""} { return [list "" 0] }
    set text [dict get $alt text]

    # Inline choices: only parentheses that contain "|" (so "(risas)" stays).
    set guard 0
    while {[regexp -indices {\(([^()|]*\|[^()]*)\)} $text whole inner] && [incr guard] < 50} {
        set opts [split [string range $text {*}$inner] |]
        set text [string replace $text {*}$whole [::soul::rng::pick $opts]]
    }
    # Symbol references, expanded left to right by position (never by regsub
    # with substitution, so the text is not interpreted in any way).
    set out ""
    set pos 0
    while {[regexp -indices -start $pos {<([a-z][a-z0-9_.]*)>} $text whole name]} {
        append out [string range $text $pos [expr {[lindex $whole 0] - 1}]]
        set sub [lindex [expand $lang [string range $text {*}$name] $ctx [expr {$depth + 1}]] 0]
        append out $sub
        set pos [expr {[lindex $whole 1] + 1}]
    }
    append out [string range $text $pos end]
    return [list $out [dict get $alt action]]
}

# Substitute variables, normalise spacing and enforce the length limit.
# Values come from IRC and are stripped of control characters, including
# \001 so nothing can smuggle a CTCP into an action.
proc ::soul::grammar::render {text vars} {
    variable maxlen
    set clean [dict create]
    dict for {k v} $vars {
        dict set clean $k [string map {"\001" "" "\r" " " "\n" " " "\0" ""} $v]
    }
    # Plurals: {years|year|years} -> "year" when years is 1, else "years".
    # Scanned by position; the chosen word is pack text, never user data.
    set out ""
    set pos 0
    while {[regexp -indices -start $pos {\{([a-z_]+)\|([^|{}]*)\|([^|{}]*)\}} $text whole vi si pi]} {
        append out [string range $text $pos [expr {[lindex $whole 0] - 1}]]
        set name [string range $text {*}$vi]
        set n [expr {[dict exists $clean $name] ? [dict get $clean $name] : ""}]
        append out [string range $text {*}[expr {$n eq "1" ? $si : $pi}]]
        set pos [expr {[lindex $whole 1] + 1}]
    }
    set text "$out[string range $text $pos end]"
    set text [::soul::rt::template $text $clean]
    # Unknown placeholders must not leak as "{foo}".
    regsub -all {\{[a-z_]+\}} $text "" text
    regsub -all {[ \t]{2,}} $text " " text
    set text [string map {"\001" ""} [string trim $text]]
    return [::soul::rt::truncate $text $maxlen]
}

proc ::soul::grammar::stats {} {
    variable syms; variable intents
    set out {}
    dict for {lang table} $syms {
        set n 0
        dict for {s alts} $table { incr n [llength $alts] }
        set ni [expr {[dict exists $intents $lang] ? [llength [dict get $intents $lang]] : 0}]
        lappend out "$lang: [dict size $table] symbols, $n phrases, $ni intent patterns"
    }
    return $out
}
