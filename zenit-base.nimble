version       = "0.1.0"
author        = "Zenith Linux Developers"
description   = "Rdzenne narzędzia systemowe Zenith Linux napisane w Nim"
license       = "Apache-2.0"

bin           = @["zesh/zesh", "cr/cr", "dl/dl", "mk/mk"]
srcDir        = "."

requires "nim >= 2.0.0"

task buildAll, "Buduje wszystkie narzędzia Nim w trybie release":
  exec "nimble build -d:release -y"

task test, "Uruchamia podstawowe testy dymne narzędzi":
  exec "nim c -r zesh/zesh.nim --version"
  exec "nim c -r cr/cr.nim --version"
  exec "nim c -r dl/dl.nim --version"
  exec "nim c -r mk/mk.nim --version"
