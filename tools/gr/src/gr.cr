require "option_parser"

# gr — nowoczesna alternatywa dla `chgrp` (Zenit Linux)
#
# NAPRAWIONE: tak samo jak w `tools/ow/src/ow.cr` — `LibC.getgrnam` i
# `LibC.chown` nie są zdefiniowane w domyślnie ładowanym module `LibC`
# w tej instalacji Crystal. Naprawione przez własny, minimalny
# `lib LibGr` z dokładnie potrzebnymi strukturą i funkcjami, plus
# poprawny `.null?` zamiast traktowania wskaźnika jako "falsy" (w
# Crystalu `Pointer(T)` jest zawsze prawdziwy, nawet gdy null).

VERSION = "0.1.0"

lib LibGr
  struct Group
    gr_name : LibC::Char*
    gr_passwd : LibC::Char*
    gr_gid : LibC::GidT
    gr_mem : LibC::Char**
  end

  fun getgrnam(name : LibC::Char*) : Group*
  fun chown(path : LibC::Char*, owner : LibC::UidT, group : LibC::GidT) : LibC::Int
end

recursive = false
verbose   = false

parser = OptionParser.new do |p|
  p.banner = "gr — nowoczesna alternatywa dla chgrp (Zenit Linux)\n\nUżycie: gr [opcje] GRUPA ŚCIEŻKA..."
  p.on("-R", "--recursive", "działaj rekurencyjnie na katalogach") { recursive = true }
  p.on("-v", "--verbose", "wypisuj każdą zmianę") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu gr") { puts "gr #{VERSION}"; exit 0 }
end
parser.parse

args = ARGV
if args.size < 2
  STDERR.puts "gr: wymagane argumenty: GRUPA ŚCIEŻKA..."
  exit 1
end

group_name = args[0]
paths = args[1..]

def resolve_gid(name : String) : LibC::GidT
  gr = LibGr.getgrnam(name)
  return gr.value.gr_gid unless gr.null?

  if n = name.to_i32?
    return n.to_u32
  end

  STDERR.puts "gr: nieznana grupa '#{name}'"
  exit 1
end

gid = resolve_gid(group_name)

def chgrp_path(path : String, gid, recursive : Bool, verbose : Bool)
  # -1 jako uid oznacza „nie zmieniaj właściciela”
  if LibGr.chown(path, LibC::UidT.new(-1), gid) != 0
    STDERR.puts "gr: nie można zmienić grupy '#{path}'"
  elsif verbose
    puts "gr: zmieniono grupę '#{path}'"
  end

  if recursive && Dir.exists?(path) && !File.symlink?(path)
    Dir.children(path).each do |child|
      chgrp_path(File.join(path, child), gid, recursive, verbose)
    end
  end
end

paths.each do |path|
  chgrp_path(path, gid, recursive, verbose)
end
