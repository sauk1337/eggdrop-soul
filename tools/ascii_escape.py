r"""Rewrite non-ASCII characters in Tcl sources as \uXXXX escapes.

Eggdrop sources scripts using the system encoding, so project sources are
kept pure ASCII. Usage: python tools/ascii_escape.py [--check] files...
"""
import sys

def main(argv):
    check = "--check" in argv
    files = [a for a in argv if a != "--check"]
    bad = 0
    for p in files:
        with open(p, encoding="utf-8") as fh:
            s = fh.read()
        if all(ord(c) < 128 for c in s):
            continue
        bad += 1
        if check:
            print(f"non-ASCII characters in {p}")
            continue
        out = "".join(c if ord(c) < 128 else chr(92) + "u%04x" % ord(c) for c in s)
        with open(p, "w", encoding="ascii", newline="") as fh:
            fh.write(out)
        print(f"escaped {p}")
    return 1 if (check and bad) else 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
