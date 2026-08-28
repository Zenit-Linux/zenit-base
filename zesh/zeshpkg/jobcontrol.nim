import std/[tables, posix, terminal]

type
  JobState* = enum
    jsRunning, jsDone

  Job* = object
    id*:      int
    pids*:    seq[Pid]
    command*: string
    state*:   JobState

var
  jobs*:   Table[int, Job] = initTable[int, Job]()
  nextJobId = 1

proc addJob*(pids: seq[Pid], command: string): int =
  let id = nextJobId
  inc nextJobId
  jobs[id] = Job(id: id, pids: pids, command: command, state: jsRunning)
  echo "[" & $id & "] " & $pids[^1]
  id

proc refreshJobStatuses*() =
  ## Sprawdza (nieblokująco) czy któreś z zadań w tle się zakończyło i
  ## informuje o tym użytkownika — wywoływane przed każdym nowym promptem.
  for id, job in jobs.mpairs:
    if job.state == jsDone: continue

    var allDone = true
    for pid in job.pids:
      var status: cint
      let r = waitpid(pid, status, WNOHANG)
      if r == 0:
        allDone = false # ten proces w potoku wciąż działa

    if allDone:
      job.state = jsDone
      stdout.styledWriteLine(fgGreen, "[" & $id & "]+  Done", fgDefault, "    " & job.command)

proc listJobs*() =
  for id, job in jobs:
    let marker = if job.state == jsRunning: "Running" else: "Done"
    echo "[" & $id & "]  " & marker & "\t" & job.command

proc waitForJob*(id: int) =
  ## `fg %N`: czeka blokująco na zakończenie WSZYSTKICH procesów zadania.
  ## TODO: rzeczywiste oddanie terminala procesowi (tcsetpgrp) i obsługa
  ## zatrzymania przez Ctrl+Z zamiast tylko czekania na zakończenie.
  if id notin jobs:
    stderr.writeLine("zesh: fg: brak zadania %" & $id)
    return

  var job = jobs[id]
  for pid in job.pids:
    var status: cint
    discard waitpid(pid, status, 0)
  job.state = jsDone
  jobs[id] = job
