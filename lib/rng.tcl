# lib/rng.tcl -- deterministic pseudo-random numbers (xorshift32).
#
# soul never uses Tcl's global rand(): other Eggdrop scripts share it, and a
# private generator with a configurable seed makes the personality fully
# reproducible in tests ("given seed 42, the bot answers X").

namespace eval ::soul::rng {
    variable state 2463534242
}

proc ::soul::rng::seed {s} {
    variable state
    set s [expr {wide($s) & 0xffffffff}]
    if {$s == 0} { set s 2463534242 }
    set state $s
    # Discard the first outputs; xorshift needs a few rounds to mix small seeds.
    for {set i 0} {$i < 8} {incr i} { next }
}

proc ::soul::rng::next {} {
    variable state
    set x $state
    set x [expr {($x ^ ($x << 13)) & 0xffffffff}]
    set x [expr {$x ^ ($x >> 17)}]
    set x [expr {($x ^ ($x << 5)) & 0xffffffff}]
    set state $x
    return $x
}

# Uniform float in [0, 1).
proc ::soul::rng::rand {} {
    return [expr {[next] / 4294967296.0}]
}

proc ::soul::rng::chance {p} {
    return [expr {[rand] < $p}]
}

# Integer in [0, n).
proc ::soul::rng::int {n} {
    if {$n <= 0} { return 0 }
    return [expr {int([rand] * $n)}]
}

proc ::soul::rng::pick {list} {
    if {![llength $list]} { return "" }
    return [lindex $list [int [llength $list]]]
}

# Index chosen with probability proportional to the (non-negative) weights.
# Returns -1 if every weight is zero.
proc ::soul::rng::weighted {weights} {
    set total 0.0
    foreach w $weights { if {$w > 0} { set total [expr {$total + $w}] } }
    if {$total <= 0} { return -1 }
    set r [expr {[rand] * $total}]
    set i 0
    foreach w $weights {
        if {$w > 0} {
            set r [expr {$r - $w}]
            if {$r < 0} { return $i }
        }
        incr i
    }
    return [expr {[llength $weights] - 1}]
}
