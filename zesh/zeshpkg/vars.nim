import std/[os, strutils]
import ./state

proc lookupVar*(name: string): string =
  if name == "?":
    return $lastExitCode
  if localVars.hasKey(name):
    return localVars[name]
  getEnv(name)

proc expandVars*(s: string): string =
  ## Rozwija `$NAME`, `${NAME}` oraz specjalną zmienną `$?` (kod wyjścia
  ## ostatniego polecenia). Nie obsługujemy tu `$(...)` (command
  ## substitution) ani zagnieżdżeń — TODO na kolejny etap.
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '$' and i + 1 < s.len:
      if s[i + 1] == '{':
        let closeIdx = s.find('}', i + 2)
        if closeIdx >= 0:
          let name = s[i + 2 ..< closeIdx]
          result &= lookupVar(name)
          i = closeIdx + 1
          continue
      elif s[i + 1] == '?':
        result &= lookupVar("?")
        i += 2
        continue
      elif s[i + 1].isAlphaAscii() or s[i + 1] == '_':
        var j = i + 1
        while j < s.len and (s[j].isAlphaNumeric() or s[j] == '_'):
          inc j
        result &= lookupVar(s[i + 1 ..< j])
        i = j
        continue
    result &= s[i]
    inc i

proc isAssignment*(word: string): bool =
  let eq = word.find('=')
  if eq <= 0: return false
  for c in word[0 ..< eq]:
    if not (c.isAlphaNumeric() or c == '_'):
      return false
  true
