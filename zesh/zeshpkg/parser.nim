import std/[terminal, strutils]
import ./lexer

type
  Redirect* = object
    stdinFile*:  string
    stdoutFile*: string
    appendOut*:  bool
    stderrFile*: string # przekierowanie stderr (2>/2>>), puste = brak
    appendErr*:  bool
    mergeErrToOut*: bool # `2>&1` — stderr ma trafić tam, gdzie aktualnie stdout

  Command* = object
    argv*:     seq[string]
    redirect*: Redirect

  Pipeline* = seq[Command]

  StmtSep* = enum
    sepNone, sepSeq, sepAnd, sepOr

  Statement* = object
    pipeline*:   Pipeline
    sepAfter*:   StmtSep # łącznik do NASTĘPNEJ instrukcji
    background*: bool    # instrukcja zakończona samodzielnym `&`

proc parsePipelineTokens*(tokens: seq[Token]): Pipeline =
  ## Parsuje tokeny jednej instrukcji (bez ;/&&/||) na potok poleceń
  ## rozdzielonych `|`, z przekierowaniami dla każdego segmentu.
  result = @[]
  var current = Command(argv: @[], redirect: Redirect())
  var i = 0

  while i < tokens.len:
    let t = tokens[i]
    case t.kind
    of tkWord:
      current.argv.add(t.text)
      inc i
    of tkRedirOut, tkRedirAppend:
      if i + 1 >= tokens.len:
        stderr.styledWriteLine(fgRed, "zesh: brak nazwy pliku po '", t.text, "'")
        return @[]
      current.redirect.stdoutFile = tokens[i + 1].text
      current.redirect.appendOut = (t.kind == tkRedirAppend)
      i += 2
    of tkRedirIn:
      if i + 1 >= tokens.len:
        stderr.styledWriteLine(fgRed, "zesh: brak nazwy pliku po '<'")
        return @[]
      current.redirect.stdinFile = tokens[i + 1].text
      i += 2
    of tkRedirErr, tkRedirErrAppend:
      if i + 1 >= tokens.len:
        stderr.styledWriteLine(fgRed, "zesh: brak nazwy pliku po '", t.text, "'")
        return @[]
      current.redirect.stderrFile = tokens[i + 1].text
      current.redirect.appendErr = (t.kind == tkRedirErrAppend)
      i += 2
    of tkRedirErrToOut:
      # `2>&1` nie ma nazwy pliku po sobie — samodzielny token.
      current.redirect.mergeErrToOut = true
      inc i
    of tkPipe:
      result.add(current)
      current = Command(argv: @[], redirect: Redirect())
      inc i
    of tkSeq, tkAnd, tkOr, tkBackground:
      # Nie powinno się zdarzyć — te tokeny są konsumowane przez splitStatements.
      inc i

  result.add(current)

proc splitStatements*(tokens: seq[Token]): seq[Statement] =
  # Jawna zmienna `statements` zamiast `result` — patrz wyjaśnienie w
  # zeshpkg/lexer.tokenize (zagnieżdżony proc nie może przechwytywać `result`).
  var statements: seq[Statement] = @[]
  var current: seq[Token] = @[]
  var pendingBackground = false

  proc flushStatement(sep: StmtSep) =
    statements.add(Statement(
      pipeline: parsePipelineTokens(current),
      sepAfter: sep,
      background: pendingBackground,
    ))
    current = @[]
    pendingBackground = false

  for t in tokens:
    case t.kind
    of tkSeq:
      flushStatement(sepSeq)
    of tkAnd:
      flushStatement(sepAnd)
    of tkOr:
      flushStatement(sepOr)
    of tkBackground:
      pendingBackground = true
    else:
      current.add(t)

  if current.len > 0 or pendingBackground:
    flushStatement(sepNone)

  statements

type
  RawStatement* = tuple[text: string, sep: StmtSep]

proc splitRawStatements*(line: string): seq[RawStatement] =
  ## Dzieli CAŁĄ linię na surowe fragmenty tekstu przy top-levelowych
  ## (czyli poza cudzysłowami i poza `$(...)`) wystąpieniach `;`, `&&`,
  ## `||` — ZANIM cokolwiek zostanie stokenizowane czy rozwinięte
  ## (`$VAR`/`$?`/`$(...)`). To jest kluczowe: `tokenize()` rozwija
  ## zmienne w trakcie tokenizacji, więc gdyby cała linia `cmd1; echo $?`
  ## trafiła do `tokenize()` jednym rzutem (tak jak wcześniej), `$?`
  ## zostałby rozwinięty na kod wyjścia SPRZED całej linii, zanim `cmd1`
  ## w ogóle by się wykonał — zamiast na kod wyjścia `cmd1`, jak wymaga
  ## tego POSIX. `interpreter.runLine` tokenizuje (i tym samym rozwija)
  ## każdy fragment zwrócony stąd OSOBNO, tuż przed jego wykonaniem.
  ##
  ## Śledzenie cudzysłowów/`$(...)` jest tu celowo minimalne — lustrzane
  ## odbicie tego, co i tak już robi `tokenize()` niżej w tym samym
  ## potoku, tylko na poziomie surowego tekstu zamiast tokenów.
  var stmts: seq[RawStatement] = @[]
  var start = 0
  var i = 0

  proc emit(endIdx: int, sep: StmtSep) =
    let text = line[start ..< endIdx]
    if text.strip().len > 0:
      stmts.add((text: text, sep: sep))

  while i < line.len:
    case line[i]
    of '\'':
      inc i
      while i < line.len and line[i] != '\'': inc i
      if i < line.len: inc i
    of '"':
      inc i
      while i < line.len and line[i] != '"': inc i
      if i < line.len: inc i
    of '$':
      if i + 1 < line.len and line[i + 1] == '(':
        var depth = 1
        i += 2
        while i < line.len and depth > 0:
          if line[i] == '(': inc depth
          elif line[i] == ')': dec depth
          inc i
      else:
        inc i
    of ';':
      emit(i, sepSeq)
      inc i
      start = i
    of '&':
      if i + 1 < line.len and line[i + 1] == '&':
        emit(i, sepAnd)
        i += 2
        start = i
      else:
        # Pojedynczy `&` (tło) NIE jest tu granicą instrukcji -- dokładnie
        # tak samo jak w splitStatements powyżej (tkBackground samo w
        # sobie nie robi flushStatement), więc zostawiamy go w tekście:
        # `tokenize()` wywołane później na tym fragmencie sam go znowu
        # rozpozna jako tkBackground i poprawnie ustawi `background`.
        inc i
    of '|':
      if i + 1 < line.len and line[i + 1] == '|':
        emit(i, sepOr)
        i += 2
        start = i
      else:
        inc i # pojedynczy `|` to potok WEWNĄTRZ instrukcji, nie jej granica
    else:
      inc i

  if start < line.len:
    emit(line.len, sepNone)

  stmts
