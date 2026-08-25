import std/[os, strutils]

proc promptPath*(): string =
  let cwd = getCurrentDir()
  let home = getHomeDir()
  if cwd == home:
    result = "~"
  elif cwd.startsWith(home & "/"):
    result = "~" & cwd[home.len .. ^1]
  else:
    result = cwd

proc promptMarker*(lastExitCode: int): string =
  if lastExitCode == 0: " ❯ " else: " ✗ "
