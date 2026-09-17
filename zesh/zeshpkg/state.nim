import std/tables

var
  localVars*:   Table[string, string] = initTable[string, string]()
  aliases*:     Table[string, string] = initTable[string, string]()
  history*:     seq[string] = @[]
  lastExitCode*: int = 0
  scriptName*:  string = "zesh"  ## `$0` -- nazwa programu/skryptu (patrz zesh.nim: `-c` i tryb skryptowy)
  scriptArgs*:  seq[string] = @[] ## `$1`..`$9`/`$@`/`$#` -- argumenty przekazane do `zesh SKRYPT arg1 arg2 ...`
