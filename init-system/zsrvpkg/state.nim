import std/tables
import ./types

var
  services*:      Table[string, ServiceRuntime] = initTable[string, ServiceRuntime]()
  currentTarget*: Target = tgMultiUser
  shuttingDown*:  bool = false
  shutdownDeadline*: float = 0.0 # czas (epochTime) po którym wysyłamy SIGKILL ocalałym usługom
