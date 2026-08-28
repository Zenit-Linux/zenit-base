require "option_parser"

# so — nowoczesna alternatywa dla `sort` (Zenit Linux)
#
# STATUS: szkielet — sortowanie leksykograficzne i numeryczne działa.
# Sortowanie wg konkretnej kolumny (-k) i scalanie posortowanych plików
# (-m) pozostają jako TODO.

VERSION = "0.1.0"

numeric = false
reverse = false
unique  = false
files   = [] of String

parser = OptionParser.new do |p|
  p.banner = "so — nowoczesna alternatywa dla sort (Zenit Linux)\n\nUżycie: so [opcje] [PLIK...]"
  p.on("-n", "--numeric", "sortuj numerycznie zamiast leksykograficznie") { numeric = true }
  p.on("-r", "--reverse", "odwróć kolejność sortowania") { reverse = true }
  p.on("-u", "--unique", "usuń zduplikowane linie z wyniku") { unique = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu so") { puts "so #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

# TODO: -k KOLUMNA (sortowanie wg wybranego pola), -t SEPARATOR,
# TODO: -m (scalanie już posortowanych plików bez pełnego resortowania).

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

lines = read_lines(files)

sorted = if numeric
           lines.sort_by { |l| l.to_f? || 0.0 }
         else
           lines.sort
         end

sorted = sorted.reverse if reverse
sorted = sorted.uniq if unique

sorted.each { |l| puts l }
