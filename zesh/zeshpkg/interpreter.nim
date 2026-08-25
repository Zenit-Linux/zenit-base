import ./lexer
import ./parser
import ./exec
import ./state

proc runLine*(line: string): int =
  let tokens = tokenize(line)
  let statements = splitStatements(tokens)

  var code = 0
  var skipDueToShortCircuit = false

  for stmt in statements:
    if skipDueToShortCircuit:
      skipDueToShortCircuit = false
      continue

    code = runPipeline(stmt)
    lastExitCode = code

    case stmt.sepAfter
    of sepAnd:
      # `&&`: następna instrukcja wykonuje się tylko, gdy ta się powiodła.
      skipDueToShortCircuit = (code != 0)
    of sepOr:
      # `||`: następna instrukcja wykonuje się tylko, gdy ta zawiodła.
      skipDueToShortCircuit = (code == 0)
    of sepSeq, sepNone:
      discard

  code
