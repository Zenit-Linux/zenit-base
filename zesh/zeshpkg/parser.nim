import std/terminal
import ./lexer

type
  Redirect* = object
    stdinFile*:  string
    stdoutFile*: string
    appendOut*:  bool

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
  var current = Command(argv: @[], redirect: Redirect(stdinFile: "", stdoutFile: "", appendOut: false))
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
    of tkPipe:
      result.add(current)
      current = Command(argv: @[], redirect: Redirect(stdinFile: "", stdoutFile: "", appendOut: false))
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
