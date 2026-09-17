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

type
  ArithParser = object
    s:   string
    pos: int

proc skipWs(p: var ArithParser) =
  while p.pos < p.s.len and p.s[p.pos] == ' ':
    inc p.pos

proc arithMatch(p: var ArithParser, tok: string): bool =
  ## Próbuje "skonsumować" operator `tok` (1 lub 2 znaki) w bieżącej
  ## pozycji. Nie myli np. pojedynczego `&` z `&&` ani `=` z `==`, bo
  ## porównuje dokładnie `tok.len` znaków, a wywołujący zawsze próbuje
  ## najpierw dłuższe warianty (patrz kolejność w parseEq/parseAnd/parseOr).
  skipWs(p)
  if p.pos + tok.len <= p.s.len and p.s[p.pos ..< p.pos + tok.len] == tok:
    p.pos += tok.len
    true
  else:
    false

proc parseExpr(p: var ArithParser): int

proc parseNumberOrIdent(p: var ArithParser): int =
  skipWs(p)
  let start = p.pos
  if p.pos < p.s.len and p.s[p.pos].isDigit():
    if p.s[p.pos] == '0' and p.pos + 1 < p.s.len and (p.s[p.pos + 1] == 'x' or p.s[p.pos + 1] == 'X'):
      p.pos += 2
      let hstart = p.pos
      while p.pos < p.s.len and p.s[p.pos] in HexDigits:
        inc p.pos
      return (try: parseHexInt(p.s[hstart ..< p.pos]) except ValueError: 0)
    else:
      while p.pos < p.s.len and p.s[p.pos].isDigit():
        inc p.pos
      return (try: parseInt(p.s[start ..< p.pos]) except ValueError: 0)
  elif p.pos < p.s.len and (p.s[p.pos].isAlphaAscii() or p.s[p.pos] == '_'):
    while p.pos < p.s.len and (p.s[p.pos].isAlphaNumeric() or p.s[p.pos] == '_'):
      inc p.pos
    # Bash pozwala pisać `$((i+1))` zamiast `$(($i+1))` -- goła nazwa
    # wewnątrz wyrażenia arytmetycznego to odwołanie do zmiennej.
    # Niezdefiniowana/nieliczbowa zmienna liczy się jako 0 (tak jak bash).
    let name = p.s[start ..< p.pos]
    return (try: parseInt(lookupVar(name).strip()) except ValueError: 0)
  else:
    # Nieoczekiwany znak (błąd składni w wyrażeniu) -- nie wywalamy
    # powłoki, po prostu przesuwamy się o jeden znak i liczymy jako 0.
    if p.pos < p.s.len: inc p.pos
    return 0

proc parsePrimary(p: var ArithParser): int =
  if arithMatch(p, "("):
    result = parseExpr(p)
    discard arithMatch(p, ")")
  else:
    result = parseNumberOrIdent(p)

proc parseUnary(p: var ArithParser): int =
  if arithMatch(p, "-"):
    result = -parseUnary(p)
  elif arithMatch(p, "+"):
    result = parseUnary(p)
  elif arithMatch(p, "!"):
    result = (if parseUnary(p) == 0: 1 else: 0)
  else:
    result = parsePrimary(p)

proc parseMul(p: var ArithParser): int =
  result = parseUnary(p)
  while true:
    if arithMatch(p, "*"):
      result = result * parseUnary(p)
    elif arithMatch(p, "%"):
      let d = parseUnary(p)
      result = (if d != 0: result mod d else: 0)
    elif arithMatch(p, "/"):
      let d = parseUnary(p)
      result = (if d != 0: result div d else: 0)
    else:
      break

proc parseAdd(p: var ArithParser): int =
  result = parseMul(p)
  while true:
    if arithMatch(p, "+"):
      result = result + parseMul(p)
    elif arithMatch(p, "-"):
      result = result - parseMul(p)
    else:
      break

proc parseRel(p: var ArithParser): int =
  result = parseAdd(p)
  while true:
    if arithMatch(p, "<="):
      result = (if result <= parseAdd(p): 1 else: 0)
    elif arithMatch(p, ">="):
      result = (if result >= parseAdd(p): 1 else: 0)
    elif arithMatch(p, "<"):
      result = (if result < parseAdd(p): 1 else: 0)
    elif arithMatch(p, ">"):
      result = (if result > parseAdd(p): 1 else: 0)
    else:
      break

proc parseEq(p: var ArithParser): int =
  result = parseRel(p)
  while true:
    if arithMatch(p, "=="):
      result = (if result == parseRel(p): 1 else: 0)
    elif arithMatch(p, "!="):
      result = (if result != parseRel(p): 1 else: 0)
    else:
      break

proc parseAnd(p: var ArithParser): int =
  result = parseEq(p)
  while arithMatch(p, "&&"):
    let rhs = parseEq(p)
    result = (if result != 0 and rhs != 0: 1 else: 0)

proc parseOr(p: var ArithParser): int =
  result = parseAnd(p)
  while arithMatch(p, "||"):
    let rhs = parseAnd(p)
    result = (if result != 0 or rhs != 0: 1 else: 0)

proc parseExpr(p: var ArithParser): int =
  parseOr(p)

proc evalArithmetic*(expr: string): int =
  ## Ewaluator wyrażeń `$((...))` (rozwijanie arytmetyczne) -- wspiera
  ## liczby dziesiętne i szesnastkowe (`0x...`), zmienne (gołe nazwy,
  ## odczytywane przez `lookupVar`), nawiasy, jednoargumentowe `+ - !`,
  ## dwuargumentowe `* / % + -`, porównania `== != < <= > >=` (dające 1/0)
  ## oraz logiczne `&& ||`. Celowo NIE wspiera operatorów bitowych
  ## (`& | ^ ~ << >>`) ani przypisań wewnątrz wyrażenia (`$((i++))` itp.)
  ## -- pokrywają one zdecydowaną większość realnego użycia w skryptach
  ## powłoki (liczniki pętli, warunki), a ich pominięcie upraszcza
  ## parser i unika dwuznaczności `&` vs `&&` / `=` vs `==`.
  var p = ArithParser(s: expr, pos: 0)
  parseExpr(p)

proc expandVars*(s: string): string =
  ## Rozwija `$NAME`, `${NAME}`, `$?` (kod wyjścia ostatniego polecenia),
  ## `$(polecenie)` (substytucja poleceń — wynik podpolecenia, z
  ## usuniętymi końcowymi znakami nowej linii, tak jak w POSIX) oraz
  ## `$((wyrażenie))` (rozwijanie arytmetyczne, patrz `evalArithmetic`).
  ## Zagnieżdżone `$(...)`/`$((...))` wewnątrz innych `$(...)` są
  ## obsługiwane przez liczenie głębokości nawiasów. Nie obsługujemy tu
  ## zagnieżdżonych `${...}`.
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '$' and i + 1 < s.len:
      if s[i + 1] == '(' and i + 2 < s.len and s[i + 2] == '(':
        # $((wyrażenie)) -- rozwijanie arytmetyczne. Śledzimy głębokość
        # WSZYSTKICH nawiasów od `$(` (włącznie z drugim otwierającym),
        # licząc, że wyrażenie kończy się dopiero, gdy trafimy na ')'
        # domykający na głębokości 0 -- a to jest poprawne domknięcie
        # `$((...))` tylko wtedy, gdy zaraz po nim jest DRUGI ')'.
        var depth = 0
        var j = i + 3
        var closeAt = -1
        while j < s.len:
          if s[j] == '(':
            inc depth
          elif s[j] == ')':
            if depth == 0:
              if j + 1 < s.len and s[j + 1] == ')':
                closeAt = j
              break
            else:
              dec depth
          inc j
        if closeAt >= 0:
          let expr = s[i + 3 ..< closeAt]
          result &= $evalArithmetic(expr)
          i = closeAt + 2
          continue
        # brak poprawnego domknięcia `))` -- spadamy do zwykłej ścieżki
        # $(...) niżej (potraktuje to jako (niepoprawną) substytucję
        # poleceń, zamiast ciszej pomyłki).
      elif s[i + 1] == '(':
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
      elif s[i + 1] == '@':
        # `$@` -- wszystkie argumenty skryptu, rozdzielone spacją. (Bez
        # osobnego zachowania wewnątrz cudzysłowów, jak w prawdziwym
        # POSIX `"$@"` rozdzielające na osobne słowa — expandVars działa
        # na już połączonym tekście linii, więc to uproszczenie.)
        result &= scriptArgs.join(" ")
        i += 2
        continue
      elif s[i + 1] == '#':
        # `$#` -- liczba argumentów skryptu.
        result &= $scriptArgs.len
        i += 2
        continue
      elif s[i + 1].isDigit():
        # `$0` (nazwa skryptu) / `$1`..`$9` (argumenty pozycyjne wg
        # indeksu). Tylko POJEDYNCZA cyfra, tak jak w prawdziwym POSIX —
        # `$10` to `$1` + literalne `0`; dla dwucyfrowych indeksów trzeba
        # by `${10}`, czego (podobnie jak reszty ${...}) nie wspieramy.
        let idx = ord(s[i + 1]) - ord('0')
        if idx == 0:
          result &= scriptName
        elif idx >= 1 and idx <= scriptArgs.len:
          result &= scriptArgs[idx - 1]
        # spoza zakresu (np. $5, gdy podano tylko 2 argumenty) -> pusty
        # tekst, tak jak niezdefiniowana zmienna zwykła.
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
