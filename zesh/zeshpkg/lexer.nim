import ./vars

type
  TokenKind* = enum
    tkWord, tkPipe, tkRedirIn, tkRedirOut, tkRedirAppend, tkSeq, tkAnd, tkOr, tkBackground,
    tkRedirErr, tkRedirErrAppend, tkRedirErrToOut
    ## tkRedirErr        = `2>`   (przekierowanie stderr do pliku, obcinając)
    ## tkRedirErrAppend  = `2>>`  (jak wyżej, ale dopisując)
    ## tkRedirErrToOut   = `2>&1` (scalenie stderr ze stdout — bez nazwy pliku po tokenie)

  Token* = object
    kind*: TokenKind
    text*: string

proc tokenize*(line: string): seq[Token] =
  # Jawna zmienna `tokens` zamiast niejawnego `result` — zagnieżdżone
  # proc `flush`/`flushUnquoted` poniżej przechwytują ją jako zmienną
  # domknięcia, a przechwytywanie `result` w zagnieżdżonym proc jest w
  # Nim zabronione ze względów bezpieczeństwa pamięci.
  var tokens: seq[Token] = @[]
  var i = 0
  var current = ""
  var haveCurrent = false
  var unquotedRun = ""

  proc flushUnquoted() =
    if unquotedRun.len > 0:
      current &= expandVars(unquotedRun)
      unquotedRun = ""
      haveCurrent = true

  proc flush() =
    flushUnquoted()
    if haveCurrent:
      tokens.add(Token(kind: tkWord, text: current))
      current = ""
      haveCurrent = false

  while i < line.len:
    let c = line[i]
    case c
    of ' ', '\t':
      flush()
      inc i
    of '\'':
      flushUnquoted()
      haveCurrent = true
      inc i
      while i < line.len and line[i] != '\'':
        current &= line[i]
        inc i
      inc i # zamykający '
    of '"':
      flushUnquoted()
      haveCurrent = true
      inc i
      var raw = ""
      while i < line.len and line[i] != '"':
        raw &= line[i]
        inc i
      inc i # zamykający "
      current &= expandVars(raw)
    of '|':
      flush()
      if i + 1 < line.len and line[i + 1] == '|':
        tokens.add(Token(kind: tkOr, text: "||"))
        i += 2
      else:
        tokens.add(Token(kind: tkPipe, text: "|"))
        inc i
    of '&':
      flush()
      if i + 1 < line.len and line[i + 1] == '&':
        tokens.add(Token(kind: tkAnd, text: "&&"))
        i += 2
      else:
        tokens.add(Token(kind: tkBackground, text: "&"))
        inc i
    of ';':
      flush()
      tokens.add(Token(kind: tkSeq, text: ";"))
      inc i
    of '>':
      flush()
      if i + 1 < line.len and line[i + 1] == '>':
        tokens.add(Token(kind: tkRedirAppend, text: ">>"))
        i += 2
      else:
        tokens.add(Token(kind: tkRedirOut, text: ">"))
        inc i
    of '<':
      flush()
      tokens.add(Token(kind: tkRedirIn, text: "<"))
      inc i
    of '2':
      # `2>`/`2>>`/`2>&1` (przekierowanie stderr) są rozpoznawane TYLKO
      # gdy `2` stoi na początku nowego tokenu (nie jest częścią
      # dłuższego słowa, np. pliku o nazwie zaczynającej się od "2") —
      # dokładnie tak, jak deskryptory plików działają w bashu.
      if unquotedRun.len == 0 and not haveCurrent and
         i + 1 < line.len and line[i + 1] == '>':
        if i + 2 < line.len and line[i + 2] == '>':
          tokens.add(Token(kind: tkRedirErrAppend, text: "2>>"))
          i += 3
        elif i + 3 < line.len and line[i + 2] == '&' and line[i + 3] == '1':
          tokens.add(Token(kind: tkRedirErrToOut, text: "2>&1"))
          i += 4
        else:
          tokens.add(Token(kind: tkRedirErr, text: "2>"))
          i += 2
      else:
        unquotedRun &= c
        inc i
    of '$':
      if i + 1 < line.len and line[i + 1] == '(':
        # Substytucja poleceń $(...) MUSI zostać połknięta w całości tutaj,
        # licząc głębokość nawiasów — inaczej spacja wewnątrz (np. w
        # `$(echo hi)`) zostałaby błędnie potraktowana jako granica słowa
        # przez główną pętlę i rozerwałaby podpolecenie na kilka tokenów.
        # Samo rozwinięcie (uruchomienie podpolecenia) następuje później,
        # w expandVars, wywoływanym z flushUnquoted().
        var depth = 1
        var j = i + 2
        while j < line.len and depth > 0:
          if line[j] == '(': inc depth
          elif line[j] == ')': dec depth
          inc j
        unquotedRun &= line[i ..< j]
        i = j
      else:
        unquotedRun &= c
        inc i
    else:
      unquotedRun &= c
      inc i

  flush()
  tokens
