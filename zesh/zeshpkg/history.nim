import std/[os, strutils]
import ./state

const
  HistoryFile = ".zesh_history"
  MaxHistory  = 1000

proc historyPath(): string =
  getHomeDir() / HistoryFile

proc loadHistory*() =
  let path = historyPath()
  if fileExists(path):
    for line in lines(path):
      if line.len > 0:
        history.add(line)

proc saveHistory*() =
  try:
    let start = max(0, history.len - MaxHistory)
    writeFile(historyPath(), history[start ..< history.len].join("\n") & "\n")
  except IOError:
    discard

proc expandHistoryRefs*(line: string): string =
  ## Obsługa prostych odwołań do historii: `!!` (ostatnie polecenie) i
  ## `!n` (polecenie numer n). TODO: `!prefix` (ostatnie pasujące polecenie).
  if line == "!!":
    if history.len > 0: return history[^1]
    return ""
  if line.len > 1 and line[0] == '!' and line[1..^1].allCharsInSet(Digits):
    let idx = parseInt(line[1..^1]) - 1
    if idx >= 0 and idx < history.len:
      return history[idx]
  line
