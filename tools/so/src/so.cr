require "option_parser"

# so — nowoczesna alternatywa dla `sort` (Zenit Linux)
#
# STATUS: sortowanie leksykograficzne i numeryczne, sortowanie wg
# wybranego pola (-k, jak GNU sort), własny separator pól (-t) oraz -m
# (scalanie WIELU JUŻ POSORTOWANYCH plików bez pełnego resortowania od
# zera — klasyczny krok "merge" z merge sort, uogólniony na k list przez
# kolejne scalanie parami: k-1 scaleń zamiast jednego sortowania całości).

VERSION = "0.1.0"

numeric   = false
reverse   = false
unique    = false
merge_mode = false
key_field = nil.as(Int32?)
separator = " "
files     = [] of String

parser = OptionParser.new do |p|
  p.banner = "so — nowoczesna alternatywa dla sort (Zenit Linux)\n\nUżycie: so [opcje] [PLIK...]"
  p.on("-n", "--numeric", "sortuj numerycznie zamiast leksykograficznie") { numeric = true }
  p.on("-r", "--reverse", "odwróć kolejność sortowania") { reverse = true }
  p.on("-u", "--unique", "usuń zduplikowane linie z wyniku") { unique = true }
  p.on("-m", "--merge", "scal PODANE PLIKI zakładając, że każdy jest już posortowany (bez resortowania całości)") { merge_mode = true }
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

# Wczytuje KAŻDY plik OSOBNO (bez łączenia) -- niezbędne dla -m, gdzie
# scalanie musi znać granice między poszczególnymi już-posortowanymi
# listami wejściowymi.
def read_lines_separately(files : Array(String)) : Array(Array(String))
  if files.empty?
    [STDIN.gets_to_end.split('\n').reject(&.empty?)]
  else
    files.compact_map do |f|
      unless File.exists?(f)
        STDERR.puts "so: nie można otworzyć '#{f}': nie istnieje"
        next nil
      end
      File.read_lines(f)
    end
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

key_field_val = key_field
sort_key = ->(line : String) { key_field_val ? field_of(line, key_field_val, separator) : line }

def key_str(line : String, sort_key : Proc(String, String)) : String
  sort_key.call(line)
end

def key_num(line : String, sort_key : Proc(String, String)) : Float64
  sort_key.call(line).to_f? || 0.0
end

# Scala DWIE już posortowane listy w jedną posortowaną listę, O(n+m),
# bez ponownego porównywania wszystkiego ze wszystkim -- serce -m.
def merge_two_str(a : Array(String), b : Array(String), reverse : Bool, sort_key : Proc(String, String)) : Array(String)
  result = Array(String).new(a.size + b.size)
  i = 0
  j = 0
  while i < a.size && j < b.size
    ka = key_str(a[i], sort_key)
    kb = key_str(b[j], sort_key)
    take_a = reverse ? (ka >= kb) : (ka <= kb)
    if take_a
      result << a[i]; i += 1
    else
      result << b[j]; j += 1
    end
  end
  result.concat(a[i...a.size]) if i < a.size
  result.concat(b[j...b.size]) if j < b.size
  result
end

def merge_two_num(a : Array(String), b : Array(String), reverse : Bool, sort_key : Proc(String, String)) : Array(String)
  result = Array(String).new(a.size + b.size)
  i = 0
  j = 0
  while i < a.size && j < b.size
    ka = key_num(a[i], sort_key)
    kb = key_num(b[j], sort_key)
    take_a = reverse ? (ka >= kb) : (ka <= kb)
    if take_a
      result << a[i]; i += 1
    else
      result << b[j]; j += 1
    end
  end
  result.concat(a[i...a.size]) if i < a.size
  result.concat(b[j...b.size]) if j < b.size
  result
end

sorted = if merge_mode
           lists = read_lines_separately(files)
           if lists.empty?
             [] of String
           else
             lists.reduce do |acc, lst|
               numeric ? merge_two_num(acc, lst, reverse, sort_key) : merge_two_str(acc, lst, reverse, sort_key)
             end
           end
         else
           lines = read_lines(files)
           s = numeric ? lines.sort_by { |l| key_num(l, sort_key) } : lines.sort_by { |l| key_str(l, sort_key) }
           reverse ? s.reverse : s
         end

sorted = sorted.uniq if unique

sorted.each { |l| puts l }
