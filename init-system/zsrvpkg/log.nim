import std/[os, times, strutils]

const
  LogPath    = "/var/log/zsrv.log"
  MaxLogSize = 4 * 1024 * 1024 # 4 MiB — próg rotacji

proc rotateIfNeeded() =
  try:
    if fileExists(LogPath) and getFileSize(LogPath) > MaxLogSize:
      let rotated = LogPath & ".1"
      if fileExists(rotated):
        removeFile(rotated)
      moveFile(LogPath, rotated)
  except OSError:
    discard

proc log*(msg: string) =
  let line = "[" & $now() & "] " & msg
  echo line
  try:
    rotateIfNeeded()
    let f = open(LogPath, fmAppend)
    defer: f.close()
    f.writeLine(line)
  except IOError:
    discard # /var/log może nie być jeszcze zamontowane na wczesnym etapie

proc logService*(serviceName: string, msg: string) =
  log("[" & serviceName & "] " & msg)
