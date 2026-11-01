# lib/rt.tcl -- the small runtime soul runs on.
#
# Everything the personality engine needs from its host, in one file and
# without dependencies beyond Tcl 8.6 and Eggdrop's script API:
#
#   text helpers      safe output, word splitting, durations, templates
#   config            INI file validated against declared options
#   store             atomic, checksummed data files
#   rl                token-bucket rate limits
#   perm              named capabilities mapped to Eggdrop flags
#   sched             one 1-second utimer driving every delayed task
#   bind              error-isolating bind wrapper with a circuit breaker
#   cmd               the "soul" command (channel, /msg and partyline)
#   log / journal     messages to Eggdrop's log
#
# Nothing here evaluates user text or configuration as code.

namespace eval ::soul::rt {
    variable version   1.0.1
    variable clock_cmd      ;# test hook: command prefix returning epoch ms
    if {![info exists clock_cmd]} { set clock_cmd "" }
    variable datadir ""
    variable state stopped  ;# stopped | running | broken
    variable binds {}
    variable errors {}      ;# timestamps (ms) of recent handler errors
    variable last_error ""
}

# --- time ------------------------------------------------------------------

proc ::soul::rt::nowms {} {
    variable clock_cmd
    if {$clock_cmd ne ""} { return [{*}$clock_cmd] }
    return [clock milliseconds]
}

proc ::soul::rt::now {} { return [expr {[nowms] / 1000}] }

# "90", "90s", "10m", "2h30m", "1d", "1w" -> seconds; -1 if invalid.
proc ::soul::rt::parse_duration {text} {
    set text [string tolower [string trim $text]]
    if {$text eq ""} { return -1 }
    if {[string is digit -strict $text]} { return [expr {$text}] }
    if {![regexp {^(\d+[smhdw])+$} $text]} { return -1 }
    set total 0
    foreach {- n u} [regexp -all -inline {(\d+)([smhdw])} $text] {
        set n [scan $n %d]
        switch -- $u {
            s { incr total $n }
            m { incr total [expr {$n * 60}] }
            h { incr total [expr {$n * 3600}] }
            d { incr total [expr {$n * 86400}] }
            w { incr total [expr {$n * 604800}] }
        }
    }
    return $total
}

proc ::soul::rt::fmt_duration {secs} {
    set secs [expr {int($secs)}]
    if {$secs <= 0} { return "0s" }
    set out ""
    foreach {unit len} {d 86400 h 3600 m 60 s 1} {
        if {$secs >= $len} {
            append out [expr {$secs / $len}]$unit
            set secs [expr {$secs % $len}]
        }
    }
    return $out
}

# --- text ------------------------------------------------------------------

# Remove characters that could inject extra IRC protocol lines.
proc ::soul::rt::sanitize {text} {
    return [string map {"\r" " " "\n" " " "\0" "" "\001" ""} $text]
}

# Strip mIRC formatting codes.
proc ::soul::rt::strip_codes {text} {
    regsub -all {\003(\d{1,2}(,\d{1,2})?)?} $text "" text
    return [string map {"\002" "" "\017" "" "\026" "" "\037" "" "\035" "" "\036" "" "\021" ""} $text]
}

# Split text into chunks of at most $max bytes (UTF-8), on spaces where
# possible; each line break starts a new chunk. At most $maxlines chunks.
proc ::soul::rt::split_text {text {max 400} {maxlines 10}} {
    set text [string map {"\r\n" "\n" "\r" "\n"} $text]
    if {[string first "\n" $text] >= 0} {
        set out {}
        foreach para [split $text "\n"] {
            if {[string trim $para] eq ""} { continue }
            set room [expr {$maxlines - [llength $out]}]
            if {$room <= 0} { break }
            lappend out {*}[split_text $para $max $room]
        }
        return $out
    }
    set text [sanitize $text]
    set out {}
    while {$text ne "" && [llength $out] < $maxlines} {
        if {[string length [encoding convertto utf-8 $text]] <= $max} {
            lappend out $text
            break
        }
        set lo 1; set hi [string length $text]
        while {$lo < $hi} {
            set mid [expr {($lo + $hi + 1) / 2}]
            if {[string length [encoding convertto utf-8 [string range $text 0 $mid-1]]] <= $max} {
                set lo $mid
            } else {
                set hi [expr {$mid - 1}]
            }
        }
        set cut $lo
        set sp [string last " " [string range $text 0 $cut-1]]
        if {$sp > $cut / 2} { set cut $sp }
        lappend out [string trimright [string range $text 0 $cut-1]]
        set text [string trimleft [string range $text $cut end]]
    }
    return $out
}

proc ::soul::rt::truncate {text max} {
    if {[string length $text] <= $max} { return $text }
    return "[string range $text 0 [expr {$max - 4}]]..."
}

# Words of user input, WITHOUT Tcl list parsing (braces and quotes in user
# text are just characters).
proc ::soul::rt::words {text} {
    return [regexp -all -inline {\S+} $text]
}

# The text after the first $n words, inner spacing preserved.
proc ::soul::rt::rest {text n} {
    set text [string trimleft $text]
    for {set i 0} {$i < $n} {incr i} {
        if {![regexp {^\S+\s*(.*)$} $text -> text]} { return "" }
    }
    return $text
}

# Only literal {name} placeholders listed in $vars are replaced.
proc ::soul::rt::template {tpl vars} {
    set map {}
    dict for {k v} $vars { lappend map "\{$k\}" [sanitize $v] }
    return [string map $map $tpl]
}

proc ::soul::rt::valid_chan {chan} {
    return [regexp {^[#&][^\s,\x07]{1,49}$} $chan]
}

proc ::soul::rt::valid_ident {name} {
    return [regexp {^[a-z][a-z0-9_.-]{0,47}$} $name]
}

# Resolve $name under $base and refuse anything escaping it.
proc ::soul::rt::safe_path {base name} {
    if {![regexp {^[A-Za-z0-9_][A-Za-z0-9_.-]*$} $name] || [string match *..* $name]} {
        error "unsafe file name: $name"
    }
    set full [file normalize [file join $base $name]]
    if {[string first "[file normalize $base]/" $full] != 0} { error "path escapes base directory: $name" }
    return $full
}

# IRC case-insensitive lower (rfc1459 mapping).
proc ::soul::rt::irclower {s} {
    return [string map {[ \{ ] \} \\ | ~ ^} [string tolower $s]]
}

# "user@host" -> "*!*@host": tracks a person across nick changes.
proc ::soul::rt::hostkey {uhost} {
    return "*!*@[string tolower [lindex [split $uhost @] end]]"
}

proc ::soul::rt::bool {v} {
    switch -nocase -- [string trim $v] {
        1 - yes - on - true - enabled { return 1 }
        0 - no - off - false - disabled { return 0 }
    }
    error "not a boolean: $v"
}

# Text that must never be taught as a fact: links, adverts, channel
# invitations and protocol tricks.
proc ::soul::rt::unsafe_text {text} {
    set t [string tolower [strip_codes $text]]
    if {[regexp {[\001\r\n]} $text]} { return 1 }
    if {[regexp {https?://|www\.|\m[a-z0-9-]+\.(com|net|org|io|xyz|ru|tk|ly|gg|me|tv)\M} $t]} { return 1 }
    if {[regexp {(^|\s)[#&][^\s,]{2,}} $t] || [regexp {\m(join|/j)\s+#} $t]} { return 1 }
    return 0
}

# --- output ------------------------------------------------------------------

proc ::soul::rt::say {target text {queue help}} {
    foreach line [split_text $text] {
        switch -- $queue {
            quick { putquick "PRIVMSG $target :$line" }
            serv  { putserv "PRIVMSG $target :$line" }
            default { puthelp "PRIVMSG $target :$line" }
        }
    }
}

proc ::soul::rt::notice {target text} {
    foreach line [split_text $text] { puthelp "NOTICE $target :$line" }
}

# Reply where a command came from (channel, /msg or partyline).
proc ::soul::rt::reply {ctx text} {
    switch -- [dict get $ctx where] {
        dcc { foreach line [split_text $text 450 50] { putdcc [dict get $ctx idx] $line } }
        pub { foreach line [split_text $text 400 [cfg soul max_pub_lines]] { say [dict get $ctx chan] $line } }
        default { foreach line [split_text $text 400 20] { notice [dict get $ctx nick] $line } }
    }
}

# Private reply: NOTICE on IRC, the partyline for dcc.
proc ::soul::rt::reply_private {ctx text} {
    if {[dict get $ctx where] eq "dcc"} { reply $ctx $text; return }
    foreach line [split_text $text 400 20] { notice [dict get $ctx nick] $line }
}

# --- log -------------------------------------------------------------------------

namespace eval ::soul::rt { variable levels {debug info warn error} }

# log <level> <category> <message> ?security?
proc ::soul::rt::log {level cat msg args} {
    variable levels
    set min [expr {[catch {cfg soul log_level} l] ? "info" : $l}]
    if {[lsearch $levels $level] < [lsearch $levels $min]} { return }
    putlog "soul: [expr {$level in {warn error} ? "[string toupper $level] " : ""}]\[$cat\] [truncate [sanitize $msg] 400]"
}

# Admin and security events go to the log too (kept as a separate call so
# a host can route them elsewhere).
namespace eval ::soul::rt::journal { variable seq 0 }
proc ::soul::rt::journal::add {module sev cat msg {data {}}} {
    variable seq
    ::soul::rt::log [expr {$sev in {warn error critical} ? "warn" : "info"}] $cat $msg
    return [incr seq]
}

# --- config ------------------------------------------------------------------------
#
#   [soul]              option = value
#   [channel #name]     option = value   (or soul.option = value)
#   [permissions]       soul.view = m
#   [ratelimit]         soul.talk = 8/5m
#
# Unknown keys, bad values and out-of-range numbers are reported with their
# line number and the default is kept. Nothing is ever evaluated.

namespace eval ::soul::rt::config {
    variable schema [dict create]   ;# module,key -> option dict
    variable gval                   ;# array module,key -> value
    variable cval                   ;# array chan,module,key -> value
    variable diags {}
    variable path ""
    array set gval {}
    array set cval {}
}

proc ::soul::rt::config::declare {module key args} {
    variable schema
    set o [dict merge {-type str -default "" -scope global -doc "" -min "" -max "" -values {} -maxlen 400} $args]
    if {![dict exists $schema $module,$key]} {
        lassign [check $o [dict get $o -default]] ok v
        if {!$ok} { error "bad default for $module.$key: $v" }
        dict set o value $v
    } else {
        dict set o value [dict get $schema $module,$key value]
    }
    dict set schema $module,$key $o
}

# Validate one value against an option. Returns {1 normalised} or {0 reason}.
proc ::soul::rt::config::check {o raw} {
    set raw [string trim $raw]
    switch -- [dict get $o -type] {
        bool {
            if {[catch {::soul::rt::bool $raw} v]} { return [list 0 "expected yes or no"] }
            return [list 1 $v]
        }
        int {
            if {![string is integer -strict $raw]} { return [list 0 "expected a whole number"] }
            set v [scan $raw %lld]
            if {[dict get $o -min] ne "" && $v < [dict get $o -min]} { return [list 0 "minimum is [dict get $o -min]"] }
            if {[dict get $o -max] ne "" && $v > [dict get $o -max]} { return [list 0 "maximum is [dict get $o -max]"] }
            return [list 1 $v]
        }
        duration {
            set v [::soul::rt::parse_duration $raw]
            if {$v < 0} { return [list 0 "expected a duration such as 90s, 20m or 2h"] }
            if {[dict get $o -min] ne "" && $v < [dict get $o -min]} { return [list 0 "minimum is [::soul::rt::fmt_duration [dict get $o -min]]"] }
            if {[dict get $o -max] ne "" && $v > [dict get $o -max]} { return [list 0 "maximum is [::soul::rt::fmt_duration [dict get $o -max]]"] }
            return [list 1 $v]
        }
        enum {
            set v [string tolower $raw]
            if {$v ni [dict get $o -values]} { return [list 0 "expected one of: [join [dict get $o -values] {, }]"] }
            return [list 1 $v]
        }
        list {
            set v [regexp -all -inline {[^\s,]+} $raw]
            if {[llength [dict get $o -values]]} {
                foreach x $v {
                    if {[string tolower $x] ni [dict get $o -values]} { return [list 0 "'$x' is not one of: [join [dict get $o -values] {, }]"] }
                }
                set v [lmap x $v { string tolower $x }]
            }
            return [list 1 $v]
        }
        rate {
            if {![regexp {^(\d+)/(\S+)$} $raw -> n per] || $n < 1 || [set p [::soul::rt::parse_duration $per]] < 1} {
                return [list 0 "expected N/period, e.g. 8/5m"]
            }
            return [list 1 [list $n $p]]
        }
        flags {
            if {![regexp {^(-|[a-zA-Z]*(\|[a-zA-Z]*)?)$} $raw]} { return [list 0 "expected Eggdrop flags such as o, m or -|o"] }
            return [list 1 $raw]
        }
        default {
            if {[string length $raw] > [dict get $o -maxlen]} { return [list 0 "longer than [dict get $o -maxlen] characters"] }
            if {[regexp {[\r\n\0]} $raw]} { return [list 0 "control characters are not allowed"] }
            return [list 1 $raw]
        }
    }
}

proc ::soul::rt::config::diag {sev line msg} {
    variable diags
    lappend diags [dict create sev $sev line $line msg $msg]
}

# Parse and apply INI text. Returns the list of diagnostics.
proc ::soul::rt::config::apply_text {text} {
    variable schema
    variable gval
    variable cval
    variable diags
    set diags {}
    array unset gval
    array unset cval
    set sect ""
    set lineno 0
    foreach line [split $text \n] {
        incr lineno
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] in {# ;}} { continue }
        if {[regexp {^\[\s*([^\]]+?)\s*\]$} $line -> head]} {
            set w [::soul::rt::words $head]
            if {[llength $w] == 2 && [lindex $w 0] eq "channel" && [::soul::rt::valid_chan [lindex $w 1]]} {
                set sect [list channel [::soul::rt::irclower [lindex $w 1]]]
            } elseif {[llength $w] == 1 && [lindex $w 0] in {soul permissions ratelimit}} {
                set sect [list [lindex $w 0] ""]
            } else {
                diag error $lineno "unknown section \[$head\] (use \[soul\], \[channel #name\], \[permissions\] or \[ratelimit\])"
                set sect [list skip ""]
            }
            continue
        }
        if {![regexp {^([A-Za-z0-9_.]+)\s*=\s*(.*)$} $line -> key raw]} {
            diag error $lineno "expected 'option = value'"
            continue
        }
        lassign $sect kind chan
        if {$kind eq ""} { diag error $lineno "'$key' is outside of any section"; continue }
        if {$kind eq "skip"} { continue }
        set key [string tolower $key]
        switch -- $kind {
            permissions { set module perm }
            ratelimit   { set module ratelimit }
            default {
                set module soul
                if {[string match soul.* $key]} { set key [string range $key 5 end] }
            }
        }
        if {![dict exists $schema $module,$key]} {
            diag warning $lineno "unknown option '$key'"
            continue
        }
        set o [dict get $schema $module,$key]
        if {$kind eq "channel" && "channel" ni [dict get $o -scope]} {
            diag warning $lineno "'$key' cannot be set per channel; put it under \[soul\]"
            continue
        }
        lassign [check $o $raw] ok v
        if {!$ok} {
            diag error $lineno "$key: $v (keeping [string trim [dict get $o -default]])"
            continue
        }
        if {$kind eq "channel"} { set cval($chan,$module,$key) $v } else { set gval($module,$key) $v }
    }
    return $diags
}

proc ::soul::rt::config::load {p} {
    variable path
    variable diags
    set path $p
    if {$p eq "" || ![file exists $p]} {
        apply_text ""
        set diags [list [dict create sev info line 0 msg "no configuration file at '$p'; using defaults"]]
        return $diags
    }
    if {[catch {
        set fh [open $p r]
        fconfigure $fh -encoding utf-8
        set text [read $fh 262145]
        close $fh
    } err]} {
        set diags [list [dict create sev error line 0 msg "cannot read '$p': $err"]]
        return $diags
    }
    return [apply_text $text]
}

proc ::soul::rt::config::get {module key {chan ""}} {
    variable schema
    variable gval
    variable cval
    if {$chan ne ""} {
        set lc [::soul::rt::irclower $chan]
        if {[info exists cval($lc,$module,$key)]} { return $cval($lc,$module,$key) }
    }
    if {[info exists gval($module,$key)]} { return $gval($module,$key) }
    if {![dict exists $schema $module,$key]} { error "unknown option $module.$key" }
    return [dict get $schema $module,$key value]
}

# Where a value comes from: "channel", "file" or "default".
proc ::soul::rt::config::source_of {module key {chan ""}} {
    variable gval
    variable cval
    if {$chan ne "" && [info exists cval([::soul::rt::irclower $chan],$module,$key)]} { return channel }
    if {[info exists gval($module,$key)]} { return file }
    return default
}

# Documented example configuration, generated from the declarations.
proc ::soul::rt::config::example {} {
    variable schema
    set out "# soul.conf -- generated by tools/example.tcl. Every option is optional.\n\n\[soul\]\n"
    foreach k [lsort [dict keys $schema soul,*]] {
        set o [dict get $schema $k]
        set scope [expr {"channel" in [dict get $o -scope] ? ", per channel" : ""}]
        set type [dict get $o -type]
        if {$type eq "enum"} { set type "[join [dict get $o -values] |]" }
        set d [dict get $o -default]
        if {[dict get $o -type] eq "bool"} { set d [expr {$d ? "yes" : "no"}] }
        append out "# [dict get $o -doc] ($type$scope)\n#[lindex [split $k ,] 1] = $d\n"
    }
    append out "\n# Per-channel values override the ones above:\n#\[channel #mychannel\]\n#active = yes\n#lang = es\n"
    append out "\n\[permissions\]\n"
    foreach k [lsort [dict keys $schema perm,*]] {
        set o [dict get $schema $k]
        append out "# [dict get $o -doc]\n#[lindex [split $k ,] 1] = [dict get $o -default]\n"
    }
    append out "\n\[ratelimit\]\n"
    foreach k [lsort [dict keys $schema ratelimit,*]] {
        set o [dict get $schema $k]
        append out "# [dict get $o -doc]\n#[lindex [split $k ,] 1] = [dict get $o -default]\n"
    }
    return $out
}

proc ::soul::rt::cfg {module key {chan ""}} {
    return [config::get $module $key $chan]
}

# --- store ---------------------------------------------------------------------------
#
# <datadir>/<name>.db:  "SOULSTORE 1 <crc32> <bytes>\n" + a Tcl dict (never
# evaluated). Atomic writes; a corrupt file is moved aside, never half-loaded.

namespace eval ::soul::rt::store {
    variable pending
    array set pending {}
}

proc ::soul::rt::store::path {name} {
    if {$::soul::rt::datadir eq ""} { error "data directory not set" }
    if {![::soul::rt::valid_ident $name]} { error "invalid store name: $name" }
    return [::soul::rt::safe_path $::soul::rt::datadir $name.db]
}

proc ::soul::rt::store::decode {bytes} {
    set nl [string first "\n" $bytes]
    if {$nl < 0} { return [list 0 "missing header"] }
    if {![regexp {^SOULSTORE 1 (\d+) (\d+)$} [string range $bytes 0 $nl-1] -> crc len]} { return [list 0 "bad header"] }
    set payload [string range $bytes $nl+1 end]
    if {[string length $payload] != $len} { return [list 0 "length mismatch (truncated write?)"] }
    if {[zlib crc32 $payload] != $crc} { return [list 0 "checksum mismatch"] }
    set value [encoding convertfrom utf-8 $payload]
    if {[catch {dict size $value}]} { return [list 0 "payload is not a dictionary"] }
    return [list 1 $value]
}

proc ::soul::rt::store::load {name {default {}}} {
    set p [path $name]
    if {![file exists $p]} { return $default }
    if {[catch {
        set fh [open $p rb]
        set bytes [read $fh]
        close $fh
    } err]} {
        ::soul::rt::log error store "cannot read $name: $err"
        return $default
    }
    lassign [decode $bytes] ok value
    if {!$ok} {
        set q "$p.corrupt-[::soul::rt::now]"
        catch {file rename -force $p $q}
        ::soul::rt::log error store "'$name' is corrupt ($value); moved to [file tail $q], starting from scratch"
        return $default
    }
    return $value
}

proc ::soul::rt::store::save {name value} {
    set p [path $name]
    set payload [encoding convertto utf-8 $value]
    set fh [open $p.tmp wb]
    if {[catch {
        puts -nonewline $fh "SOULSTORE 1 [zlib crc32 $payload] [string length $payload]\n$payload"
        close $fh
    } err]} {
        catch {close $fh}
        catch {file delete $p.tmp}
        error "cannot write $name: $err"
    }
    file rename -force $p.tmp $p
    catch {file attributes $p -permissions 0600}
}

# Deferred save, flushed every second and on save/rehash/restart/die.
proc ::soul::rt::store::mark {name value} {
    variable pending
    set pending($name) $value
}

proc ::soul::rt::store::flush {} {
    variable pending
    set failed 0
    foreach name [array names pending] {
        if {[catch {save $name $pending($name)} err]} {
            ::soul::rt::log error store $err
            incr failed
            continue
        }
        unset pending($name)
    }
    return $failed
}

# --- rate limits -----------------------------------------------------------------------

namespace eval ::soul::rt::rl {
    variable buckets
    variable max_buckets 20000
    array set buckets {}
}

proc ::soul::rt::rl::declare {cat default doc} {
    ::soul::rt::config::declare ratelimit $cat -type rate -default $default -doc $doc
}

proc ::soul::rt::rl::allow {cat key {chan ""} {cost 1}} {
    variable buckets
    variable max_buckets
    lassign [::soul::rt::cfg ratelimit $cat] cap period
    set now [::soul::rt::nowms]
    set id "$cat|[string tolower $chan]|$key"
    if {[info exists buckets($id)]} {
        lassign $buckets($id) tokens last
        set tokens [expr {min(double($cap), $tokens + ($now - $last) * $cap / ($period * 1000.0))}]
    } else {
        if {[array size buckets] >= $max_buckets} { gc }
        set tokens [expr {double($cap)}]
    }
    if {$tokens >= $cost} {
        set buckets($id) [list [expr {$tokens - $cost}] $now]
        return 1
    }
    set buckets($id) [list $tokens $now]
    return 0
}

# Drop buckets idle for over an hour (they are full again by then).
proc ::soul::rt::rl::gc {} {
    variable buckets
    set now [::soul::rt::nowms]
    foreach id [array names buckets] {
        if {$now - [lindex $buckets($id) 1] > 3600000} { unset buckets($id) }
    }
}

proc ::soul::rt::rl::reset {} {
    variable buckets
    array unset buckets
}

# --- permissions -------------------------------------------------------------------------

namespace eval ::soul::rt::perm {}
proc ::soul::rt::perm::declare {cap flags doc} {
    ::soul::rt::config::declare perm $cap -type flags -default $flags -doc $doc
}

proc ::soul::rt::perm::allowed {hand cap {chan ""}} {
    if {$cap eq "-"} { return 1 }
    set flags [::soul::rt::cfg perm $cap]
    if {$flags eq "-"} { return 1 }
    if {$hand in {"" "*"} || ![validuser $hand]} { return 0 }
    if {$chan ne "" && [validchan $chan]} { return [matchattr $hand $flags $chan] }
    # Outside a channel, channel flags (|o) cannot apply: use the global part.
    set global [lindex [split $flags |] 0]
    if {$global eq ""} { return 0 }
    return [matchattr $hand $global]
}

# --- scheduler -----------------------------------------------------------------------------

namespace eval ::soul::rt::sched {
    variable tasks [dict create]
    variable handlers [dict create]
    variable seq 0
    variable timer ""
}

proc ::soul::rt::sched::handler {module name procname} {
    variable handlers
    dict set handlers $name $procname
}

# add -handler h ?-args list? ?-in secs? ?-every secs? ?-name unique?
proc ::soul::rt::sched::add {args} {
    variable tasks
    variable seq
    variable handlers
    set o [dict merge {-module soul -handler "" -args {} -in 0 -every 0 -name ""} $args]
    if {![dict exists $handlers [dict get $o -handler]]} { error "unknown scheduler handler [dict get $o -handler]" }
    if {[dict get $o -name] ne ""} {
        dict for {id t} $tasks { if {[dict get $t name] eq [dict get $o -name]} { dict unset tasks $id } }
    }
    set id [incr seq]
    dict set tasks $id [dict create handler [dict get $o -handler] args [dict get $o -args] \
        due [expr {[::soul::rt::now] + max(0, [dict get $o -in])}] every [dict get $o -every] name [dict get $o -name]]
    return $id
}

proc ::soul::rt::sched::get {id} {
    variable tasks
    return [expr {[dict exists $tasks $id] ? [dict get $tasks $id] : {}}]
}

proc ::soul::rt::sched::cancel {id} {
    variable tasks
    if {![dict exists $tasks $id]} { return 0 }
    dict unset tasks $id
    return 1
}

proc ::soul::rt::sched::start {} {
    variable timer
    stop
    set timer [utimer 1 ::soul::rt::sched::tick]
}

proc ::soul::rt::sched::stop {} {
    variable timer
    if {$timer ne ""} { catch {killutimer $timer}; set timer "" }
}

proc ::soul::rt::sched::tick {} {
    variable timer
    set timer [utimer 1 ::soul::rt::sched::tick]
    if {[catch {run_due} err]} { ::soul::rt::log error sched "tick failed: $err" }
    if {[catch {::soul::rt::store::flush} err]} { ::soul::rt::log error store "flush failed: $err" }
}

proc ::soul::rt::sched::run_due {} {
    variable tasks
    variable handlers
    if {$::soul::rt::state ne "running"} { return }
    set now [::soul::rt::now]
    set due {}
    dict for {id t} $tasks { if {[dict get $t due] <= $now} { lappend due [list $id [dict get $t due]] } }
    foreach item [lrange [lsort -integer -index 1 $due] 0 49] {
        set id [lindex $item 0]
        if {![dict exists $tasks $id]} { continue }
        set t [dict get $tasks $id]
        if {[catch {{*}[dict get $handlers [dict get $t handler]] {*}[dict get $t args]} err]} {
            ::soul::rt::record_error "task [dict get $t handler]: $err"
        }
        if {![dict exists $tasks $id]} { continue }
        if {[dict get $t every] > 0} {
            dict set tasks $id due [expr {$now + [dict get $t every]}]
        } else {
            dict unset tasks $id
        }
    }
}

# --- binds and the circuit breaker --------------------------------------------------------

proc ::soul::rt::bind {module type flags mask cmd} {
    variable binds
    set full [list ::soul::rt::tramp $cmd]
    ::bind $type $flags $mask $full
    lappend binds [list $type $flags $mask $full]
    return $full
}

proc ::soul::rt::unbind_all {} {
    variable binds
    foreach b $binds { catch {::unbind {*}$b} }
    set binds {}
}

# Every event goes through here: a bug never reaches Eggdrop, and too many
# errors in a short time switch soul off instead of flooding the log.
proc ::soul::rt::tramp {cmd args} {
    variable state
    if {$state ne "running"} { return 0 }
    if {[catch {uplevel #0 [list {*}$cmd {*}$args]} res]} {
        record_error "[lindex $cmd 0]: $res"
        return 0
    }
    return $res
}

proc ::soul::rt::record_error {msg} {
    variable errors
    variable last_error
    variable state
    set now [nowms]
    set last_error "[clock format [now] -format {%Y-%m-%d %H:%M:%S}] $msg"
    lappend errors $now
    set errors [lmap t $errors { expr {$now - $t < 300000 ? $t : [continue]} }]
    log error soul $msg
    if {[llength $errors] >= 20 && $state eq "running"} {
        log error soul "too many errors in 5 minutes: soul switched itself off (fix the cause, then .rehash)"
        stop broken
    }
}

# --- commands ----------------------------------------------------------------------------

namespace eval ::soul::rt::cmd {
    variable spec [dict create]
}

proc ::soul::rt::cmd::register {module name args} {
    variable spec
    set spec [dict merge {-proc "" -where {pub msg dcc} -desc "" -subs {}} $args]
    dict set spec name $name
}

proc ::soul::rt::cmd::bind_all {} {
    variable spec
    set prefix [::soul::rt::cfg soul prefix]
    set name [dict get $spec name]
    if {$prefix ne ""} { ::soul::rt::bind soul pub - $prefix$name [list ::soul::rt::cmd::on_pub] }
    ::soul::rt::bind soul msg - $name [list ::soul::rt::cmd::on_msg]
    ::soul::rt::bind soul dcc - $name [list ::soul::rt::cmd::on_dcc]
}

proc ::soul::rt::cmd::on_pub {nick uhost hand chan text} {
    dispatch [dict create nick $nick uhost $uhost hand $hand chan $chan where pub idx -1] [::soul::rt::strip_codes $text]
    return 0
}

proc ::soul::rt::cmd::on_msg {nick uhost hand text} {
    dispatch [dict create nick $nick uhost $uhost hand $hand chan "" where msg idx -1] [::soul::rt::strip_codes $text]
    return 0
}

proc ::soul::rt::cmd::on_dcc {hand idx text} {
    dispatch [dict create nick $hand uhost "" hand $hand chan "" where dcc idx $idx] $text
    return 0
}

# "<sub> args..." -> the subcommand's proc with a context dict:
#   nick uhost hand chan where idx  +  cmdsub argv text
proc ::soul::rt::cmd::dispatch {ctx body} {
    variable spec
    set where [dict get $ctx where]
    if {$where ne "dcc"} {
        set key [::soul::rt::hostkey [dict get $ctx uhost]]
        if {![::soul::rt::rl::allow soul.cmd $key]} { return }
    }
    set name [dict get $spec name]
    set subs [dict get $spec -subs]
    set argv [::soul::rt::words $body]
    set sub [string tolower [lindex $argv 0]]
    if {$sub eq "" || $sub eq "help" || ![dict exists $subs $sub]} {
        set lines [list "$name -- [dict get $spec -desc]"]
        dict for {s def} $subs {
            lassign $def p perm syn desc
            if {![::soul::rt::perm::allowed [dict get $ctx hand] $perm [dict get $ctx chan]]} { continue }
            lappend lines "  $name $s $syn -- $desc"
        }
        ::soul::rt::reply_private $ctx [join $lines \n]
        return
    }
    lassign [dict get $subs $sub] procname perm syntax
    set argv [lrange $argv 1 end]
    # Outside channels a leading #channel scopes the permission check.
    set permchan [dict get $ctx chan]
    if {$permchan eq "" && [::soul::rt::valid_chan [lindex $argv 0]] && [validchan [lindex $argv 0]]} {
        set permchan [lindex $argv 0]
    }
    if {![::soul::rt::perm::allowed [dict get $ctx hand] $perm $permchan]} {
        ::soul::rt::reply_private $ctx "Permission denied ($perm)."
        if {$where ne "pub"} { ::soul::rt::log info security "denied $name $sub to [dict get $ctx hand]/[dict get $ctx nick] (needs $perm)" }
        return
    }
    dict set ctx cmd $name
    dict set ctx cmdsub $sub
    dict set ctx argv $argv
    dict set ctx text [::soul::rt::rest $body 1]
    dict set ctx syntax "$name $sub $syntax"
    if {[catch {{*}$procname $ctx} err]} {
        ::soul::rt::record_error "command $name $sub: $err"
        ::soul::rt::reply_private $ctx "Internal error; details are in the bot's log."
    }
}

# Is this the first word of a soul command (used to keep chat away from it)?
proc ::soul::rt::cmd::lookup {word} {
    variable spec
    return [expr {[dict exists $spec name] && [string equal -nocase $word [dict get $spec name]] ? $spec : ""}]
}

# --- runtime options -----------------------------------------------------------------------

proc ::soul::rt::declare_core {} {
    set D ::soul::rt::config::declare
    $D soul enabled -type bool -default yes -doc "Run soul at all (no = loaded but asleep, no binds)"
    $D soul prefix -type str -default "!" -maxlen 3 -doc "Prefix of the channel command (!soul); empty = no channel command"
    $D soul max_pub_lines -type int -default 4 -min 1 -max 20 -doc "Most lines a command answer may put in a channel"
    $D soul log_level -type enum -values {debug info warn error} -default info -doc "Lowest level written to Eggdrop's log"
    ::soul::rt::rl::declare soul.cmd 6/30s "soul commands per person"
}

# --- lifecycle ----------------------------------------------------------------------------

proc ::soul::rt::state {} { variable state; return $state }

proc ::soul::rt::stop {{why stopped}} {
    variable state
    if {$state eq "running"} { catch {::soul::stop} }
    unbind_all
    set state $why
    catch {store::flush}
}
