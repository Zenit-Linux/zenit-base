require "option_parser"

VERSION = "1.0.0"

recursive = false
verbose   = false

parser = OptionParser.new do |p|
  p.banner = "gr — nowoczesna alternatywa dla chgrp (Zenith Linux)\n\nUżycie: gr [opcje] GRUPA ŚCIEŻKA..."
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
  if gr = LibC.getgrnam(name)
    gr.value.gr_gid
  else
    name.to_i32.to_u32
  end
rescue ArgumentError
  STDERR.puts "gr: nieznana grupa '#{name}'"
  exit 1
end

gid = resolve_gid(group_name)

def chgrp_path(path : String, gid, recursive : Bool, verbose : Bool)
  # -1 jako uid oznacza „nie zmieniaj właściciela”
  if LibC.chown(path, LibC::UidT.new(-1), gid) != 0
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
