require "option_parser"

# so — nowoczesna alternatywa dla `sort` (Zenit Linux)
#
# STATUS: szkielet+ — sortowanie leksykograficzne i numeryczne działa,
# wraz z sortowaniem wg wybranego pola (-k, jak GNU sort) i własnym
# separatorem pól (-t). Scalanie już posortowanych plików bez pełnego
# resortowania (-m) pozostaje jako TODO — dziś każde wywołanie sortuje
# całość od nowa, co jest poprawne, ale niepotrzebnie kosztowne dla
# bardzo dużych, już posortowanych wejść.

VERSION = "0.1.0"

numeric   = false
reverse   = false
unique    = false
key_field = nil.as(Int32?)
separator = " "
files     = [] of String

parser = OptionParser.new do |p|
  p.banner = "so — nowoczesna alternatywa dla sort (Zenit Linux)\n\nUżycie: so [opcje] [PLIK...]"
  p.on("-n", "--numeric", "sortuj numerycznie zamiast leksykograficznie") { numeric = true }
  p.on("-r", "--reverse", "odwróć kolejność sortowania") { reverse = true }
  p.on("-u", "--unique", "usuń zduplikowane linie z wyniku") { unique = true }
  p.on("-k POLE", "--key=POLE", "sortuj wg wybranego pola, liczonego od 1 (jak GNU sort -k)") do |v|
    n = v.to_i?
    if n.nil? || n < 1
      STDERR.puts "so: nieprawidłowy numer pola dla -k: '#{v}'"
      exit 1
    end
    key_field = n
  end
  p.on("-t SEPARATOR", "--field-separator=SEPARATOR", "znak oddzielający pola (domyślnie dowolny ciąg spacji)") { |v| separator = v }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu so") { puts "so #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

def read_lines(files : Array(String)) : Array(String)
  if files.empty?
    STDIN.gets_to_end.split('\n').reject(&.empty?)
  else
    lines = [] of String
    files.each do |f|
      unless File.exists?(f)
        STDERR.puts "so: nie można otworzyć '#{f}': nie istnieje"
        next
      end
      lines.concat(File.read_lines(f))
    end
    lines
  end
end

# Wyciąga pole nr `field` (liczone od 1) z linii podzielonej po `sep`.
# Domyślny separator (pojedyncza spacja przekazana jako wartość startowa)
# oznacza podział po dowolnym ciągu białych znaków, tak jak w GNU sort
# bez jawnego -t.
def field_of(line : String, field : Int32, sep : String) : String
  parts = sep == " " ? line.split(' ', remove_empty: true) : line.split(sep)
  idx = field - 1
  idx >= 0 && idx < parts.size ? parts[idx] : ""
end

lines = read_lines(files)

sort_key = ->(line : String) { key_field ? field_of(line, key_field.not_nil!, separator) : line }

sorted = if numeric
           lines.sort_by { |l| sort_key.call(l).to_f? || 0.0 }
         else
           lines.sort_by { |l| sort_key.call(l) }
         end

sorted = sorted.reverse if reverse
sorted = sorted.uniq if unique

sorted.each { |l| puts l }
