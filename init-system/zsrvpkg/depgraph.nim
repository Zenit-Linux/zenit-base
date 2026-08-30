import std/[tables, sequtils, algorithm, strutils]
import ./state
import ./logger

proc topologicalStartOrder*(names: seq[string]): seq[string] =
  ## Zwraca nazwy usług w kolejności bezpiecznej do startu (zależności
  ## z `After=` przed usługami, które ich potrzebują). W razie cyklu
  ## zależności dołącza pozostałe usługi na końcu i loguje ostrzeżenie,
  ## zamiast się zawieszać.
  var inDegree = initTable[string, int]()
  var dependents = initTable[string, seq[string]]() # dep -> [usługi zależne od dep]

  for n in names:
    inDegree[n] = 0

  for n in names:
    for dep in services[n].def.after:
      if dep notin inDegree:
        continue # zależność spoza aktywnego zestawu usług — pomijamy
      inDegree[n] = inDegree[n] + 1
      dependents.mgetOrPut(dep, @[]).add(n)

  var queue = names.filterIt(inDegree[it] == 0)
  queue.sort() # deterministyczna kolejność wśród usług bez zależności
  result = @[]

  while queue.len > 0:
    let n = queue[0]
    queue.delete(0)
    result.add(n)
    for dependent in dependents.getOrDefault(n, @[]):
      inDegree[dependent] = inDegree[dependent] - 1
      if inDegree[dependent] == 0:
        queue.add(dependent)
    queue.sort()

  if result.len < names.len:
    let remaining = names.filterIt(it notin result)
    log("zsrv: wykryto cykl zależności wśród usług: " & remaining.join(", ") &
        " — dodaję je na końcu kolejności startu")
    result.add(remaining)
