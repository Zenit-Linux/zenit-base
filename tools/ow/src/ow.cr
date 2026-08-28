require "option_parser"

VERSION = "0.1.0"

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
  if pw = LibC.getpwnam(name)
    pw.value.pw_uid
  else
    name.to_i32.to_u32
  end
rescue ArgumentError
  STDERR.puts "ow: nieznany użytkownik '#{name}'"
  exit 1
end

def resolve_gid(name : String) : LibC::GidT
  if gr = LibC.getgrnam(name)
    gr.value.gr_gid
  else
    name.to_i32.to_u32
  end
rescue ArgumentError
  STDERR.puts "ow: nieznana grupa '#{name}'"
  exit 1
end

uid = user_part.empty? ? LibC::UidT.new(-1) : resolve_uid(user_part)
gid = group_part ? resolve_gid(group_part.not_nil!) : LibC::GidT.new(-1)

def chown_path(path : String, uid, gid, recursive : Bool, verbose : Bool)
  if LibC.chown(path, uid, gid) != 0
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
