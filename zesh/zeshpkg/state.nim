import std/tables

var
  localVars*:   Table[string, string] = initTable[string, string]()
  aliases*:     Table[string, string] = initTable[string, string]()
  history*:     seq[string] = @[]
  lastExitCode*: int = 0
