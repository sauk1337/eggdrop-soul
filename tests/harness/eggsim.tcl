# tests/harness/eggsim.tcl -- in-process simulator of the Eggdrop Tcl API.
#
# Implements the subset of Eggdrop commands used by soul, with
# the argument conventions documented in Eggdrop's doc/tcl-commands.doc
# (1.9 series), plus helpers to inject IRC events and inspect the bot's
# output. Time is virtual: timers fire only when a test calls sim::advance.
#
# This is a test double, not a full Eggdrop: it does not speak IRC, does not
# implement server queues' flood delays, and only models channel state that
# the tests need. Behaviour verified here must still be confirmed on a real
# Eggdrop (see docs/TESTING.md).

namespace eval ::sim {
    variable now_ms 1767225600000   ;# 2026-01-01 00:00:00 UTC
    variable binds {}
    variable out {}
    variable logs {}
    variable dccout {}
    variable timers [dict create]
    variable timerseq 0
    variable users [dict create]
    variable chans [dict create]
    variable isupport [dict create CHANMODES b,k,l,imnpstrDducCNMT PREFIX (ov)@+ NETWORK QuakeNet]
}

proc ::sim::nowms {} { variable now_ms; return $now_ms }

proc ::sim::reset {} {
    variable binds {}
    variable out {}
    variable logs {}
    variable dccout {}
    variable timers [dict create]
    variable users [dict create]
    variable chans [dict create]
    variable banlog {}
    variable calls {}
    variable bcast {}
    variable fail_hosts {}
    variable connseq 100
    variable conns
    variable netout
    array unset conns
    array unset netout
    array set conns {}
    array set netout {}
    set ::botnick Meepo
    set ::nick Meepo
    set ::botname "Meepo!bot@meepo.users.quakenet.org"
    set ::server "irc.quakenet.org:6667"
    set ::server-online [expr {[nowms] / 1000 - 600}]
    set ::uptime [expr {[nowms] / 1000 - 3600}]
    set ::version "1.9.5 1090500"
    set ::numversion 1090500
}

# --- time & timers ------------------------------------------------------------

proc ::unixtime {} { return [expr {[::sim::nowms] / 1000}] }
proc ::strftime {fmt {t ""}} {
    if {$t eq ""} { set t [unixtime] }
    return [clock format $t -format $fmt]
}
proc ::duration {s} { return [::soul::rt::fmt_duration $s] }

proc ::utimer {secs cmd {count 1} {name ""}} {
    variable ::sim::timers
    variable ::sim::timerseq
    set id "timer[incr timerseq]"
    dict set timers $id [list [expr {[::sim::nowms] + $secs * 1000}] $cmd]
    return $id
}
proc ::timer {mins cmd {count 1} {name ""}} { return [utimer [expr {$mins * 60}] $cmd] }
proc ::killutimer {id} {
    variable ::sim::timers
    if {![dict exists $timers $id]} { error "invalid timerID" }
    dict unset timers $id
}
proc ::killtimer {id} { killutimer $id }
proc ::utimers {} {
    variable ::sim::timers
    set out {}
    dict for {id t} $timers {
        lappend out [list [expr {([lindex $t 0] - [::sim::nowms]) / 1000}] [lindex $t 1] $id]
    }
    return $out
}
proc ::timers {} { return {} }

# Advance virtual time, firing due timers in order (1 s resolution).
proc ::sim::advance {secs} {
    variable now_ms
    variable timers
    set end [expr {$now_ms + $secs * 1000}]
    while {1} {
        set next ""
        dict for {id t} $timers {
            if {[lindex $t 0] <= $end && ($next eq "" || [lindex $t 0] < [lindex $next 1])} {
                set next [list $id [lindex $t 0] [lindex $t 1]]
            }
        }
        if {$next eq ""} break
        lassign $next id due cmd
        dict unset timers $id
        if {$due > $now_ms} { set now_ms $due }
        if {[catch {uplevel #0 $cmd} err]} { lappend ::sim::logs "TIMER ERROR: $err" }
    }
    set now_ms $end
}

# Advance time without firing timers (e.g. to space out messages).
proc ::sim::sleep_ms {ms} { variable now_ms; incr now_ms $ms }

# --- binds --------------------------------------------------------------------

proc ::bind {type flags mask cmd} {
    variable ::sim::binds
    set b [list $type $flags $mask $cmd]
    if {$b ni $binds} { lappend binds $b }
    return $mask
}
proc ::unbind {type flags mask cmd} {
    variable ::sim::binds
    set i [lsearch -exact $binds [list $type $flags $mask $cmd]]
    if {$i < 0} { error "no such binding" }
    set binds [lreplace $binds $i $i]
    return $mask
}
proc ::binds {{type ""}} {
    variable ::sim::binds
    set out {}
    foreach b $binds {
        if {$type eq "" || [lindex $b 0] eq $type} { lappend out [list {*}$b 0] }
    }
    return $out
}

proc ::sim::flags_ok {flags hand chan} {
    if {$flags in {- * -|- *|* ""}} { return 1 }
    if {$hand eq "*"} { return 0 }
    return [matchattr $hand $flags $chan]
}

# Fire binds of $type whose mask matches $matchtext. Returns the list of
# callback results.
proc ::sim::fire {type matchtext hand chan args} {
    variable binds
    set res {}
    foreach b $binds {
        lassign $b btype flags mask cmd
        if {$btype ne $type} { continue }
        switch -- $type {
            pub - msg - dcc { set hit [string equal -nocase $mask $matchtext] }
            evnt { set hit [string match $mask $matchtext] }
            default { set hit [string match -nocase $mask $matchtext] }
        }
        if {!$hit || ![flags_ok $flags $hand $chan]} { continue }
        if {[catch {uplevel #0 [list {*}$cmd {*}$args]} r]} {
            lappend ::sim::logs "Tcl error \[$cmd\]: $r"
            lappend res ERROR
        } else {
            lappend res $r
        }
    }
    return $res
}

# --- output -------------------------------------------------------------------

proc ::putserv {text args} { lappend ::sim::out [list serv $text [::sim::nowms]] }
proc ::puthelp {text args} { lappend ::sim::out [list help $text [::sim::nowms]] }
proc ::putquick {text args} { lappend ::sim::out [list quick $text [::sim::nowms]] }
proc ::putnow {text args} { lappend ::sim::out [list now $text [::sim::nowms]] }
proc ::putlog {text} { lappend ::sim::logs $text }
proc ::putloglev {lev chan text} { lappend ::sim::logs $text }
proc ::putcmdlog {text} { lappend ::sim::logs $text }
proc ::putdcc {idx text} {
    if {[info exists ::sim::conns($idx)]} { lappend ::sim::netout($idx) $text; return }
    lappend ::sim::dccout $text
}
proc ::dccbroadcast {text} { lappend ::sim::bcast $text }

# Script-controlled connections (Eggdrop: connect / control / killdcc).
proc ::connect {host port} {
    if {$host in $::sim::fail_hosts} { error "connection refused" }
    set idx [incr ::sim::connseq]
    set ::sim::conns($idx) [dict create host $host port $port proc ""]
    set ::sim::netout($idx) {}
    lappend ::sim::calls [list connect $host $port $idx]
    return $idx
}
proc ::control {idx cmd} {
    if {![info exists ::sim::conns($idx)]} { error "invalid idx" }
    dict set ::sim::conns($idx) proc $cmd
}
proc ::valididx {idx} { return [expr {$idx == 1 || [info exists ::sim::conns($idx)]}] }
proc ::killdcc {idx} {
    if {![info exists ::sim::conns($idx)]} { error "invalid idx" }
    unset ::sim::conns($idx)
}
# A line arrives from the remote server.
proc ::sim::netin {idx line} {
    set cmd [dict get $::sim::conns($idx) proc]
    uplevel #0 [list {*}$cmd $idx $line]
}
# The remote side closes the connection.
proc ::sim::netclose {idx} {
    set cmd [dict get $::sim::conns($idx) proc]
    unset ::sim::conns($idx)
    uplevel #0 [list {*}$cmd $idx ""]
}
proc ::sim::netout {idx} {
    if {![info exists ::sim::netout($idx)]} { return {} }
    set r $::sim::netout($idx)
    set ::sim::netout($idx) {}
    return $r
}

# Process / server control: recorded, not executed.
foreach ::sim::c {save savechannels rehash restart die jump} {
    proc ::$::sim::c {args} "lappend ::sim::calls \[list $::sim::c {*}\$args\]"
}
unset ::sim::c
proc ::putkick {chan nicks {reason ""}} {
    foreach n [split $nicks ,] {
        lappend ::sim::out [list serv "KICK $chan $n :$reason"]
        ::sim::remove_member $chan $n
    }
}
proc ::pushmode {chan mode {arg ""}} {
    lappend ::sim::out [list mode [string trim "MODE $chan $mode $arg"]]
    ::sim::apply_mode $chan $mode $arg
}
proc ::flushmode {chan} {}

# Return captured server output lines (texts) and clear the buffer.
proc ::sim::out {} {
    variable out
    set r [lmap o $out {lindex $o 1}]
    set out {}
    return $r
}
# Like sim::out, but each element is {epoch-seconds text}.
proc ::sim::out_timed {} {
    variable out
    set r [lmap o $out {list [expr {[lindex $o 2] eq "" ? [unixtime] : [lindex $o 2] / 1000}] [lindex $o 1]}]
    set out {}
    return $r
}

proc ::sim::dcc {} {
    variable dccout
    set r $dccout
    set dccout {}
    return $r
}

# --- users --------------------------------------------------------------------

proc ::sim::adduser {hand mask {flags ""} {chanflags {}}} {
    variable users
    dict set users [string tolower $hand] [dict create hand $hand hosts [list $mask] flags $flags chan $chanflags]
}

proc ::validuser {hand} {
    return [dict exists $::sim::users [string tolower $hand]]
}

proc ::sim::userflags {hand chan} {
    set u [dict get $::sim::users [string tolower $hand]]
    set g [dict get $u flags]
    set c ""
    if {$chan ne "" && [dict exists $u chan [string tolower $chan]]} { set c [dict get $u chan [string tolower $chan]] }
    return [list $g $c]
}

proc ::sim::has_any {have want} {
    if {$want in {"" -}} { return 1 }
    foreach ch [split $want ""] {
        if {[string first $ch $have] >= 0} { return 1 }
        # Eggdrop: n implies m implies o ... (owner/master/op hierarchy)
        if {$ch eq "o" && [regexp {[mn]} $have]} { return 1 }
        if {$ch eq "m" && [string first n $have] >= 0} { return 1 }
        if {$ch eq "v" && [regexp {[omn]} $have]} { return 1 }
    }
    return 0
}

proc ::matchattr {hand flags {chan ""}} {
    if {![validuser $hand]} { return 0 }
    lassign [::sim::userflags $hand $chan] g c
    if {[regexp {^([^|&]*)([|&])(.*)$} $flags -> gf op cf]} {
        set gok [expr {$gf in {"" -} ? ($op eq "&") : [::sim::has_any $g $gf]}]
        set cok [expr {$cf in {"" -} ? ($op eq "&") : [::sim::has_any $c $cf]}]
        if {$op eq "|"} { return [expr {$gok || $cok}] }
        return [expr {$gok && $cok}]
    }
    return [::sim::has_any $g $flags]
}

proc ::finduser {nuh} {
    dict for {k u} $::sim::users {
        foreach m [dict get $u hosts] {
            if {[string match -nocase $m $nuh]} { return [dict get $u hand] }
        }
    }
    return "*"
}

proc ::nick2hand {nick {chan ""}} {
    foreach ch [dict keys $::sim::chans] {
        if {[dict exists $::sim::chans $ch members [string tolower $nick]]} {
            set m [dict get $::sim::chans $ch members [string tolower $nick]]
            return [finduser "[dict get $m nick]![dict get $m uhost]"]
        }
    }
    return ""
}

proc ::hand2nick {hand {chan ""}} {
    foreach ch [dict keys $::sim::chans] {
        dict for {k m} [dict get $::sim::chans $ch members] {
            if {[string equal -nocase [finduser "[dict get $m nick]![dict get $m uhost]"] $hand]} { return [dict get $m nick] }
        }
    }
    return ""
}

# --- channels -----------------------------------------------------------------

proc ::sim::addchan {chan {botop 1}} {
    variable chans
    set lc [string tolower $chan]
    dict set chans $lc [dict create name $chan members [dict create] bans {} modes "nt" settings [dict create]]
    member_add $chan $::botnick "bot@meepo.users.quakenet.org" $botop 0
}

proc ::sim::member_add {chan nick uhost {op 0} {voice 0}} {
    variable chans
    dict set chans [string tolower $chan] members [string tolower $nick] \
        [dict create nick $nick uhost $uhost op $op voice $voice join [unixtime]]
}

proc ::sim::remove_member {chan nick} {
    variable chans
    set lc [string tolower $chan]
    if {[dict exists $chans $lc members [string tolower $nick]]} {
        dict unset chans $lc members [string tolower $nick]
    }
}

proc ::sim::apply_mode {chan mode arg} {
    variable chans
    set lc [string tolower $chan]
    if {![dict exists $chans $lc]} return
    set sign [string index $mode 0]; set m [string index $mode 1]
    if {$m in {o v} && $arg ne ""} {
        set key [string tolower $arg]
        if {[dict exists $chans $lc members $key]} {
            dict set chans $lc members $key [expr {$m eq "o" ? "op" : "voice"}] [expr {$sign eq "+"}]
        }
    } elseif {$m eq "b"} {
        set bans [dict get $chans $lc bans]
        if {$sign eq "+"} { lappend bans $arg } else { set bans [lsearch -all -inline -not -exact $bans $arg] }
        dict set chans $lc bans $bans
    } elseif {$arg eq ""} {
        set modes [dict get $chans $lc modes]
        if {$sign eq "+"} { if {[string first $m $modes] < 0} { append modes $m } } else { set modes [string map [list $m ""] $modes] }
        dict set chans $lc modes $modes
    }
}

proc ::sim::member {nick chan} {
    set lc [string tolower $chan]
    if {![dict exists $::sim::chans $lc members [string tolower $nick]]} { return {} }
    return [dict get $::sim::chans $lc members [string tolower $nick]]
}

proc ::validchan {chan} { return [dict exists $::sim::chans [string tolower $chan]] }
proc ::channels {} { return [lmap c [dict values $::sim::chans] {dict get $c name}] }
proc ::botonchan {{chan ""}} { return [expr {[::sim::member $::botnick $chan] ne ""}] }
proc ::onchan {nick {chan ""}} {
    if {$chan eq ""} {
        foreach c [dict keys $::sim::chans] { if {[::sim::member $nick $c] ne ""} { return 1 } }
        return 0
    }
    return [expr {[::sim::member $nick $chan] ne ""}]
}
proc ::isop {nick {chan ""}} { set m [::sim::member $nick $chan]; expr {$m ne "" && [dict get $m op]} }
proc ::ishalfop {nick {chan ""}} { return 0 }
proc ::isvoice {nick {chan ""}} { set m [::sim::member $nick $chan]; expr {$m ne "" && [dict get $m voice]} }
proc ::botisop {{chan ""}} { return [isop $::botnick $chan] }
proc ::botishalfop {{chan ""}} { return 0 }
proc ::botisvoice {{chan ""}} { return [isvoice $::botnick $chan] }
proc ::isbotnick {nick} { return [string equal -nocase $nick $::botnick] }
proc ::chanlist {chan {flags ""}} {
    set lc [string tolower $chan]
    if {![dict exists $::sim::chans $lc]} { return {} }
    return [lmap m [dict values [dict get $::sim::chans $lc members]] {dict get $m nick}]
}
proc ::getchanhost {nick {chan ""}} {
    foreach c [expr {$chan eq "" ? [dict keys $::sim::chans] : [list $chan]}] {
        set m [::sim::member $nick $c]
        if {$m ne ""} { return [dict get $m uhost] }
    }
    return ""
}
proc ::getchanjoin {nick chan} {
    set m [::sim::member $nick $chan]
    if {$m eq ""} { error "$nick is not on $chan" }
    return [dict get $m join]
}
proc ::getchanmode {chan} { return "+[dict get $::sim::chans [string tolower $chan] modes]" }
proc ::channel {sub chan args} {
    set lc [string tolower $chan]
    switch -- $sub {
        get {
            set s [lindex $args 0]
            if {[dict exists $::sim::chans $lc settings $s]} { return [dict get $::sim::chans $lc settings $s] }
            return 0
        }
        set { dict set ::sim::chans $lc settings [lindex $args 0] [lindex $args 1] }
        add { if {![dict exists $::sim::chans $lc]} { ::sim::addchan $chan 0; ::sim::remove_member $chan $::botnick } }
        remove { dict unset ::sim::chans $lc }
        info { return {} }
        default { error "unsupported channel subcommand $sub" }
    }
}
proc ::setudef {type name} {}

proc ::newchanban {chan ban creator comment {lifetime ""} {opts ""}} {
    set lc [string tolower $chan]
    set bans [dict get $::sim::chans $lc bans]
    if {$ban ni $bans} { lappend bans $ban }
    dict set ::sim::chans $lc bans $bans
    lappend ::sim::out [list mode "MODE $chan +b $ban"]
    lappend ::sim::banlog [list $chan $ban $creator $comment $lifetime]
}
proc ::killchanban {chan ban} {
    set lc [string tolower $chan]
    set bans [dict get $::sim::chans $lc bans]
    if {$ban ni $bans} { return 0 }
    dict set ::sim::chans $lc bans [lsearch -all -inline -not -exact $bans $ban]
    lappend ::sim::out [list mode "MODE $chan -b $ban"]
    return 1
}
proc ::ischanban {ban chan} { return [expr {$ban in [dict get $::sim::chans [string tolower $chan] bans]}] }
proc ::isban {ban {chan ""}} { if {$chan eq ""} { return 0 }; return [ischanban $ban $chan] }

proc ::isupport {sub args} {
    switch -- $sub {
        get {
            if {![llength $args]} { return $::sim::isupport }
            set k [lindex $args 0]
            if {[dict exists $::sim::isupport $k]} { return [dict get $::sim::isupport $k] }
            error "no such key $k"
        }
        isset { return [dict exists $::sim::isupport [lindex $args 0]] }
    }
}

proc ::maskhost {nuh {type 3}} {
    set host [lindex [split $nuh @] end]
    return "*!*@$host"
}
proc ::matchaddr {mask addr} { return [string match -nocase $mask $addr] }

# --- event injection ----------------------------------------------------------

proc ::sim::hand_of {nick uhost} { return [finduser "$nick!$uhost"] }

proc ::sim::enter {nick uhost chan {op 0} {voice 0}} {
    member_add $chan $nick $uhost $op $voice
    fire join "$chan $nick!$uhost" [hand_of $nick $uhost] $chan $nick $uhost [hand_of $nick $uhost] $chan
}

proc ::sim::pub {nick chan text} {
    set m [member $nick $chan]
    set uhost [expr {$m ne "" ? [dict get $m uhost] : "unknown@unknown"}]
    set hand [hand_of $nick $uhost]
    fire pub [lindex [regexp -inline {\S+} $text] 0] $hand $chan $nick $uhost $hand $chan [::sim::rest $text 1]
    fire pubm "$chan $text" $hand $chan $nick $uhost $hand $chan $text
}

proc ::sim::action {nick chan text} {
    set uhost [dict get [member $nick $chan] uhost]
    set hand [hand_of $nick $uhost]
    fire ctcp ACTION $hand $chan $nick $uhost $hand $chan ACTION $text
}

proc ::sim::chnotice {nick chan text} {
    set uhost [dict get [member $nick $chan] uhost]
    set hand [hand_of $nick $uhost]
    fire notc $text $hand $chan $nick $uhost $hand $text $chan
}

proc ::sim::msg {nick uhost text} {
    set hand [hand_of $nick $uhost]
    fire msg [lindex [regexp -inline {\S+} $text] 0] $hand "" $nick $uhost $hand [::sim::rest $text 1]
    fire msgm $text $hand "" $nick $uhost $hand $text
}

proc ::sim::part {nick chan {msg ""}} {
    set uhost [dict get [member $nick $chan] uhost]
    set hand [hand_of $nick $uhost]
    fire part "$chan $nick!$uhost" $hand $chan $nick $uhost $hand $chan $msg
    remove_member $chan $nick
}

proc ::sim::quit {nick {reason ""}} {
    foreach c [dict keys $::sim::chans] {
        set m [member $nick $c]
        if {$m eq ""} { continue }
        set uhost [dict get $m uhost]
        set hand [hand_of $nick $uhost]
        fire sign "[dict get $::sim::chans $c name] $nick!$uhost" $hand $c $nick $uhost $hand [dict get $::sim::chans $c name] $reason
        remove_member $c $nick
    }
}

proc ::sim::nick {old new} {
    foreach c [dict keys $::sim::chans] {
        set m [member $old $c]
        if {$m eq ""} { continue }
        set uhost [dict get $m uhost]
        set hand [hand_of $old $uhost]
        remove_member $c $old
        dict set m nick $new
        dict set ::sim::chans $c members [string tolower $new] $m
        fire nick "[dict get $::sim::chans $c name] $new" $hand $c $old $uhost $hand [dict get $::sim::chans $c name] $new
    }
}

proc ::sim::kick {kicker chan target {reason ""}} {
    set m [member $kicker $chan]
    set uhost [expr {$m ne "" ? [dict get $m uhost] : "unknown@unknown"}]
    set hand [hand_of $kicker $uhost]
    fire kick "$chan $target" $hand $chan $kicker $uhost $hand $chan $target $reason
    remove_member $chan $target
}

proc ::sim::topic {nick chan topic} {
    set m [member $nick $chan]
    set uhost [expr {$m ne "" ? [dict get $m uhost] : "unknown@unknown"}]
    set hand [hand_of $nick $uhost]
    fire topc "$chan $topic" $hand $chan $nick $uhost $hand $chan $topic
}

proc ::sim::dcccmd {hand text} {
    set cmd [lindex [regexp -inline {\S+} $text] 0]
    fire dcc $cmd $hand "" $hand 1 [::sim::rest $text 1]
    return [dcc]
}

proc ::sim::evnt {type} { fire evnt $type "" "" $type }

::sim::reset
proc ::sim::rest {text n} {
    set text [string trimleft $text]
    for {set i 0} {$i < $n} {incr i} {
        if {![regexp {^\S+\s*(.*)$} $text -> text]} { return "" }
    }
    return $text
}

namespace eval ::soul::rt { variable clock_cmd ::sim::nowms }
