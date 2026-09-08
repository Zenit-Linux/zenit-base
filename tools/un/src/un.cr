require "option_parser"

# un — nowoczesna alternatywa dla `uniq` (Zenit Linux)
#
# STATUS: szkielet+ — usuwanie sąsiadujących duplikatów (jak klasyczne
# `uniq`) działa, wraz z licznikiem wystąpień (-c) oraz trybami
# --repeated (-d, tylko linie powtórzone) i --unique (-u, tylko linie
# niepowtórzone).

VERSION = "0.1.0"

show_count    = false
ignore_case   = false
only_repeated = false
only_unique   = false
files         = [] of String

parser = OptionParser.new do |p|
  p.banner = "un — nowoczesna alternatywa dla uniq (Zenit Linux)\n\nUżycie: un [opcje] [PLIK...]\n\nUwaga: tak jak klasyczne uniq, usuwa tylko SĄSIADUJĄCE duplikaty — dane wejściowe zwykle warto najpierw posortować (np. przez `so`)."
  p.on("-c", "--count", "poprzedzaj każdą linię liczbą wystąpień") { show_count = true }
  p.on("-i", "--ignore-case", "ignoruj wielkość liter przy porównywaniu") { ignore_case = true }
  p.on("-d", "--repeated", "wypisz tylko linie występujące więcej niż raz") { only_repeated = true }
  p.on("-u", "--unique", "wypisz tylko linie występujące dokładnie raz") { only_unique = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu un") { puts "un #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

if only_repeated && only_unique
  STDERR.puts "un: opcje --repeated i --unique wykluczają się wzajemnie"
  exit 1
end

def normalized(line : String, ignore_case : Bool) : String
  ignore_case ? line.downcase : line
end

def process(io : IO, show_count : Bool, ignore_case : Bool, only_repeated : Bool, only_unique : Bool)
  prev = nil.as(String?)
  count = 0

  emit = ->(line : String, count : Int32) {
    return if only_repeated && count < 2
    return if only_unique && count != 1
    if show_count
      puts "#{count.to_s.rjust(7)} #{line}"
    else
      puts line
    end
  }

  io.each_line do |line|
    key = normalized(line, ignore_case)
    if prev.nil?
      prev = line
      count = 1
    elsif normalized(prev.not_nil!, ignore_case) == key
      count += 1
    else
      emit.call(prev.not_nil!, count)
      prev = line
      count = 1
    end
  end

  emit.call(prev.not_nil!, count) if prev
end

if files.empty?
  process(STDIN, show_count, ignore_case, only_repeated, only_unique)
else
  files.each do |f|
    unless File.exists?(f)
      STDERR.puts "un: nie można otworzyć '#{f}': nie istnieje"
      next
    end
    File.open(f) { |io| process(io, show_count, ignore_case, only_repeated, only_unique) }
  end
end
