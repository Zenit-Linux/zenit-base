require "option_parser"

# hn — nowoczesna alternatywa dla `hostname` (Zenit Linux)
#
# STATUS: szkielet — odczyt przez gethostname(2) działa; ustawianie nazwy
# hosta (sethostname, wymaga CAP_SYS_ADMIN) pozostaje jako TODO.

VERSION = "0.1.0"

lib LibHn
  fun gethostname(name : LibC::Char*, len : LibC::SizeT) : LibC::Int
end

parser = OptionParser.new do |p|
  p.banner = "hn — nowoczesna alternatywa dla hostname (Zenit Linux)\n\nUżycie: hn"
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu hn") { puts "hn #{VERSION}"; exit 0 }
end
parser.parse

# TODO: `hn NOWA_NAZWA` -> sethostname(2), wymaga uprawnień roota.

buf = Bytes.new(256)
ret = LibHn.gethostname(buf.to_unsafe.as(LibC::Char*), buf.size)
if ret != 0
  STDERR.puts "hn: nie można odczytać nazwy hosta"
  exit 1
end

name = String.new(buf.to_unsafe)
puts name
