import std/unittest
import "../zesh/zeshpkg/vars"
import "../zesh/zeshpkg/state"

suite "vars.expandVars - parametry pozycyjne":
  setup:
    scriptName = "zesh"
    scriptArgs = @[]

  test "$0 to nazwa skryptu":
    scriptName = "moj_skrypt.sh"
    check expandVars("nazwa=$0") == "nazwa=moj_skrypt.sh"

  test "$1 i $2 to kolejne argumenty":
    scriptArgs = @["pierwszy", "drugi"]
    check expandVars("$1 $2") == "pierwszy drugi"

  test "$9 poza zakresem rozwija sie do pustego tekstu":
    scriptArgs = @["a"]
    check expandVars("[$9]") == "[]"

  test "$@ laczy wszystkie argumenty spacja":
    scriptArgs = @["a", "b", "c"]
    check expandVars("$@") == "a b c"

  test "$# to liczba argumentow":
    scriptArgs = @["a", "b", "c"]
    check expandVars("$#") == "3"

  test "brak argumentow: $# = 0, $@ = pusty tekst, $1 = pusty tekst":
    check expandVars("$#") == "0"
    check expandVars("[$@]") == "[]"
    check expandVars("[$1]") == "[]"

  test "$10 to $1 nastepowany przez literalne '0' (tak jak w POSIX)":
    scriptArgs = @["ARG"]
    check expandVars("$10") == "ARG0"
