require "option_parser"

VERSION = "0.1.0"

show_all      = false
show_kernel   = false
show_hostname = false
show_release  = false
show_version  = false
show_machine  = false
as_json       = false

parser = OptionParser.new do |p|
  p.banner = "about — nowoczesna alternatywa dla uname (Zenit Linux)\n\nUżycie: about [opcje]"
  p.on("-a", "--all", "pokaż wszystkie informacje") { show_all = true }
  p.on("-s", "--kernel-name", "nazwa jądra") { show_kernel = true }
  p.on("-n", "--nodename", "nazwa hosta") { show_hostname = true }
  p.on("-r", "--kernel-release", "wersja wydania jądra") { show_release = true }
  p.on("-v", "--kernel-version", "wersja jądra") { show_version = true }
  p.on("-m", "--machine", "architektura sprzętu") { show_machine = true }
  p.on("--json", "wypisz wynik jako JSON") { as_json = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu about") { puts "about #{VERSION}"; exit 0 }
end
parser.parse

# Pobranie informacji o systemie przez syscall uname(2).
uts = uninitialized LibC::UtsnameT
LibC.uname(pointerof(uts))

sysname  = String.new(pointerof(uts.sysname))
nodename = String.new(pointerof(uts.nodename))
release  = String.new(pointerof(uts.release))
kversion = String.new(pointerof(uts.version))
machine  = String.new(pointerof(uts.machine))

if !(show_all || show_kernel || show_hostname || show_release || show_version || show_machine)
  show_kernel = true
end

if as_json
  puts %({"sysname":"#{sysname}","nodename":"#{nodename}","release":"#{release}","version":"#{kversion}","machine":"#{machine}"})
else
  parts = [] of String
  parts << sysname  if show_all || show_kernel
  parts << nodename if show_all || show_hostname
  parts << release  if show_all || show_release
  parts << kversion if show_all || show_version
  parts << machine  if show_all || show_machine
  puts parts.join(" ")
end
