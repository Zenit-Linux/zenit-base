require "option_parser"

# ow — nowoczesna alternatywa dla `chown` (Zenit Linux)
#
# NAPRAWIONE: `LibC.getpwnam` (oraz `LibC.getgrnam`, `LibC.chown`) nie
# są zdefiniowane w domyślnie ładowanym module `LibC` w tej instalacji
# Crystal — ten sam rodzaj problemu co wcześniej `LibC::Utsname` w
# `about` (bindingi do <pwd.h>/<grp.h>/<unistd.h> to osobne pliki w
# drzewie stdlib, dociągane tylko przy pewnych innych `require`, z
# których `ow` nie korzysta). Naprawione przez zdefiniowanie WŁASNEGO,
# minimalnego `lib LibOw` z dokładnie potrzebnymi strukturami/funkcjami
# — ten sam sprawdzony wzorzec co w `tools/id/src/id.cr` i
# `tools/kt/src/kt.cr`.
#
# Przy okazji naprawiony też ukryty błąd czasu wykonania:
# `if pw = LibC.getpwnam(name)` traktowało zwrócony wskaźnik jako
# "falsy" gdy null, ale w Crystalu wskaźniki (`Pointer(T)`) są ZAWSZE
# prawdziwe (`truthy`), niezależnie od tego czy są null — trzeba jawnie
# sprawdzić `.null?`. Bez tego program próbowałby odczytać pola spod
# null wskaźnika (`pw.value.pw_uid`) dla nieistniejącego użytkownika
# zamiast przejść do interpretacji jako liczbowe UID, co kończyłoby się
# segfaultem zamiast czytelnego komunikatu błędu.

VERSION = "0.1.0"

lib LibOw
  struct Passwd
    pw_name : LibC::Char*
    pw_passwd : LibC::Char*
    pw_uid : LibC::UidT
    pw_gid : LibC::GidT
    pw_gecos : LibC::Char*
    pw_dir : LibC::Char*
    pw_shell : LibC::Char*
  end

  struct Group
    gr_name : LibC::Char*
    gr_passwd : LibC::Char*
    gr_gid : LibC::GidT
    gr_mem : LibC::Char**
  end

  fun getpwnam(name : LibC::Char*) : Passwd*
  fun getgrnam(name : LibC::Char*) : Group*
  fun chown(path : LibC::Char*, owner : LibC::UidT, group : LibC::GidT) : LibC::Int
end

recursive = false
verbose   = false

parser = OptionParser.new do |p|
  p.banner = "ow — nowoczesna alternatywa dla chown (Zenit Linux)\n\nUżycie: ow [opcje] UŻYTKOWNIK[:GRUPA] ŚCIEŻKA..."
  p.on("-R", "--recursive", "działaj rekurencyjnie na katalogach") { recursive = true }
  p.on("-v", "--verbose", "wypisuj każdą zmianę") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu ow") { puts "ow #{VERSION}"; exit 0 }
end
parser.parse

args = ARGV
if args.size < 2
  STDERR.puts "ow: wymagane argumenty: UŻYTKOWNIK[:GRUPA] ŚCIEŻKA..."
  exit 1
end

owner_spec = args[0]
paths = args[1..]

user_part, _, group_part = owner_spec.partition(':')
group_part = nil if group_part.empty? && !owner_spec.includes?(':')

def resolve_uid(name : String) : LibC::UidT
  pw = LibOw.getpwnam(name)
  return pw.value.pw_uid unless pw.null?

  if n = name.to_i32?
    return n.to_u32
  end

  STDERR.puts "ow: nieznany użytkownik '#{name}'"
  exit 1
end

def resolve_gid(name : String) : LibC::GidT
  gr = LibOw.getgrnam(name)
  return gr.value.gr_gid unless gr.null?

  if n = name.to_i32?
    return n.to_u32
  end

  STDERR.puts "ow: nieznana grupa '#{name}'"
  exit 1
end

uid = user_part.empty? ? LibC::UidT.new(-1) : resolve_uid(user_part)
gid = group_part ? resolve_gid(group_part.not_nil!) : LibC::GidT.new(-1)

def chown_path(path : String, uid, gid, recursive : Bool, verbose : Bool)
  if LibOw.chown(path, uid, gid) != 0
    STDERR.puts "ow: nie można zmienić właściciela '#{path}'"
  elsif verbose
    puts "ow: zmieniono właściciela '#{path}'"
  end

  if recursive && Dir.exists?(path) && !File.symlink?(path)
    Dir.children(path).each do |child|
      chown_path(File.join(path, child), uid, gid, recursive, verbose)
    end
  end
end

paths.each do |path|
  chown_path(path, uid, gid, recursive, verbose)
end
