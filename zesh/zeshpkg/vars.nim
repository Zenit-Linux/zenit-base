import std/[os, strutils, tables]
import ./state

var commandSubstitutionHook*: proc(cmd: string): string {.closure.} = nil
  ## Ustawiane przez zeshpkg/interpreter.setupCommandSubstitution() przy
  ## starcie zesh. Jeśli pozostanie nil (np. w testach jednostkowych
  ## uruchamiających sam lexer/vars bez pełnego interpretera), $(...)
  ## rozwija się do pustego tekstu zamiast się wywalać.

proc lookupVar*(name: string): string =
  if name == "?":
    return $lastExitCode
  if localVars.hasKey(name):
    return localVars[name]
  getEnv(name)

proc expandVars*(s: string): string =
  ## Rozwija `$NAME`, `${NAME}`, `$?` (kod wyjścia ostatniego polecenia)
  ## oraz `$(polecenie)` (substytucja poleceń — wynik podpolecenia,
  ## z usuniętymi końcowymi znakami nowej linii, tak jak w POSIX).
  ## Zagnieżdżone `$(...)` wewnątrz `$(...)` są obsługiwane przez liczenie
  ## głębokości nawiasów. Nie obsługujemy tu zagnieżdżonych `${...}` ani
  ## rozwijania arytmetycznego `$((...))` — TODO na kolejny etap.
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '$' and i + 1 < s.len:
      if s[i + 1] == '(':
        var depth = 1
        var j = i + 2
        while j < s.len and depth > 0:
          if s[j] == '(': inc depth
          elif s[j] == ')': dec depth
          if depth > 0: inc j
        if depth == 0:
          let innerCmd = s[i + 2 ..< j]
          if commandSubstitutionHook != nil:
            result &= commandSubstitutionHook(innerCmd)
          i = j + 1
          continue
      elif s[i + 1] == '{':
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
