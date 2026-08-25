import ./vars

type
  TokenKind* = enum
    tkWord, tkPipe, tkRedirIn, tkRedirOut, tkRedirAppend, tkSeq, tkAnd, tkOr, tkBackground

  Token* = object
    kind*: TokenKind
    text*: string

proc tokenize*(line: string): seq[Token] =
  result = @[]
  var i = 0
  var current = ""
  var haveCurrent = false

  proc flush() =
    if haveCurrent:
      result.add(Token(kind: tkWord, text: current))
      current = ""
      haveCurrent = false

  while i < line.len:
    let c = line[i]
    case c
    of ' ', '\t':
      flush()
      inc i
    of '\'':
      haveCurrent = true
      inc i
      while i < line.len and line[i] != '\'':
        current &= line[i]
        inc i
      inc i # zamykający '
    of '"':
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
        result.add(Token(kind: tkOr, text: "||"))
        i += 2
      else:
        result.add(Token(kind: tkPipe, text: "|"))
        inc i
    of '&':
      flush()
      if i + 1 < line.len and line[i + 1] == '&':
        result.add(Token(kind: tkAnd, text: "&&"))
        i += 2
      else:
        result.add(Token(kind: tkBackground, text: "&"))
        inc i
    of ';':
      flush()
      result.add(Token(kind: tkSeq, text: ";"))
      inc i
    of '>':
      flush()
      if i + 1 < line.len and line[i + 1] == '>':
        result.add(Token(kind: tkRedirAppend, text: ">>"))
        i += 2
      else:
        result.add(Token(kind: tkRedirOut, text: ">"))
        inc i
    of '<':
      flush()
      result.add(Token(kind: tkRedirIn, text: "<"))
      inc i
    else:
      haveCurrent = true
      current &= expandVars($c)
      inc i

  flush()
