require "option_parser"

# hn — nowoczesna alternatywa dla `hostname` (Zenit Linux)
#
# `hn` (bez argumentów) odczytuje nazwę hosta przez gethostname(2).
# `hn NOWA_NAZWA` ustawia ją przez sethostname(2) — wymaga uprawnień
# roota (a ściślej CAP_SYS_ADMIN); zmiana obowiązuje tylko do najbliższego
# restartu, chyba że coś (np. usługa zsrv przy rozruchu) na stałe
# zapisze ją np. do /etc/hostname i przywróci przy starcie systemu.

VERSION = "0.1.0"

lib LibHn
  fun gethostname(name : LibC::Char*, len : LibC::SizeT) : LibC::Int
  fun sethostname(name : LibC::Char*, len : LibC::SizeT) : LibC::Int
end

new_name = nil

parser = OptionParser.new do |p|
  p.banner = "hn — nowoczesna alternatywa dla hostname (Zenit Linux)\n\n" \
             "Użycie: hn [NOWA_NAZWA]\n\n" \
             "Bez argumentów wypisuje bieżącą nazwę hosta. Z argumentem\n" \
             "ustawia nową nazwę (wymaga uprawnień roota)."
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu hn") { puts "hn #{VERSION}"; exit 0 }
  p.unknown_args { |args| new_name = args.first? }
end
parser.parse

if new_name
  name = new_name.not_nil!
  if name.bytesize > 63
    # Limit historyczny HOST_NAME_MAX na Linuksie (patrz `man sethostname`)
    # -- nazwy dłuższe jądro i tak by odrzuciło z ENAMETOOLONG, ale
    # sprawdzenie tutaj daje czytelniejszy komunikat błędu.
    STDERR.puts "hn: nazwa hosta zbyt długa (maks. 63 znaki, HOST_NAME_MAX)"
    exit 1
  end
  ret = LibHn.sethostname(name.to_unsafe, LibC::SizeT.new(name.bytesize))
  if ret != 0
    errno = Errno.value
    STDERR.puts "hn: nie można ustawić nazwy hosta na '#{name}': #{errno} " \
                "(zwykle wymagane uprawnienia roota)"
    exit 1
  end
  exit 0
end

buf = Bytes.new(256)
ret = LibHn.gethostname(buf.to_unsafe.as(LibC::Char*), buf.size)
if ret != 0
  STDERR.puts "hn: nie można odczytać nazwy hosta"
  exit 1
end

name = String.new(buf.to_unsafe)
puts name
