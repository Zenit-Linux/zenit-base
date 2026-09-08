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
#
# NAPRAWIONE (2x): pierwsza wersja miała literówkę `LibC::UtsnameT`
# zamiast `LibC::Utsname`. Poprawiona nazwa też jednak nie działała —
# `LibC::Utsname` w ogóle nie istnieje w tej instalacji Crystal, bo
# binding do `struct utsname` z <sys/utsname.h> NIE jest częścią
# domyślnie załadowanego modułu `LibC` (to osobny plik w drzewie stdlib,
# dociągany tylko przez pewne wyższopoziomowe require, których tu nie
# używamy) — stąd "undefined constant LibC::Utsname".
#
# Rozwiązanie: zamiast polegać na tym, czy dana wersja/dystrybucja
# Crystala akurat zdefiniowała ten binding, definiujemy WŁASNY,
# minimalny `lib` z dokładnie tym, czego potrzebujemy. `_UTSNAME_LENGTH`
# (rozmiar każdego pola) to stała 65 w glibc na Linuksie — składnia
# `UInt8[65]` w bloku `lib` to zwykła tablica stałej długości (C-owe
# `char sysname[65]`), niezależna od tego, czy `LibC` ją gdzieś już
# zdefiniował. Sama funkcja `uname` i tak linkuje się do tego samego
# symbolu C `uname` z libc, więc zachowanie jest identyczne.
lib LibAbout
  UTSNAME_LENGTH = 65

  struct Utsname
    sysname : UInt8[65]
    nodename : UInt8[65]
    release : UInt8[65]
    version : UInt8[65]
    machine : UInt8[65]
    domainname : UInt8[65]
  end

  fun uname(buf : Utsname*) : LibC::Int
end

uts = uninitialized LibAbout::Utsname
LibAbout.uname(pointerof(uts))

# Pola są już `UInt8[65]` (StaticArray(UInt8, 65)), więc `.to_unsafe`
# daje wprost `Pointer(UInt8)`, dokładnie tego, czego oczekuje `String.new`
# — bez potrzeby dodatkowego rzutowania `.as(UInt8*)`.
sysname  = String.new(uts.sysname.to_unsafe)
nodename = String.new(uts.nodename.to_unsafe)
release  = String.new(uts.release.to_unsafe)
kversion = String.new(uts.version.to_unsafe)
machine  = String.new(uts.machine.to_unsafe)

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
