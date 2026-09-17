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

proc expandHistoryRefs*(line: string): (string, bool) =
  ## Obsługa odwołań do historii: `!!` (ostatnie polecenie), `!n`
  ## (polecenie numer n) i `!prefix` (ostatnie polecenie zaczynające się
  ## od `prefix`, przeszukiwane WSTECZ -- jak w bashu). Zwraca
  ## (rozwinięta_linia, powiodło_się) -- przy nieudanym `!n`/`!prefix`
  ## drugi element jest `false` i zesh.nim NIE powinno ani uruchamiać, ani
  ## dopisywać wyniku do historii (dokładnie jak bash z "event not found").
  if line == "!!":
    if history.len > 0: return (history[^1], true)
    stderr.writeLine("zesh: !!: brak zdarzenia (historia jest pusta)")
    return (line, false)

  if line.len > 1 and line[0] == '!' and line[1..^1].allCharsInSet(Digits):
    let idx = parseInt(line[1..^1]) - 1
    if idx >= 0 and idx < history.len:
      return (history[idx], true)
    stderr.writeLine("zesh: " & line & ": brak zdarzenia o tym numerze")
    return (line, false)

  if line.len > 1 and line[0] == '!' and line[1] != '!':
    # `!prefix`: ostatnie polecenie w historii zaczynające się od
    # `prefix`, szukane od NAJNOWSZEGO wpisu wstecz (jak `history -p`/
    # rozwijanie `!` w bashu). Sama historia NIE zawiera jeszcze bieżącej
    # linii (dopisywana jest dopiero po tym rozwinięciu w zesh.nim), więc
    # `!e` po `echo a` trafi w `echo a`, nie w samo siebie.
    let prefix = line[1..^1]
    for i in countdown(history.len - 1, 0):
      if history[i].startsWith(prefix):
        return (history[i], true)
    stderr.writeLine("zesh: " & line & ": brak zdarzenia pasującego do prefiksu '" & prefix & "'")
    return (line, false)

  (line, true)
