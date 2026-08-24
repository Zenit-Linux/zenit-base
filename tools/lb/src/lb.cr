require "option_parser"

# lb — nowoczesna alternatywa dla `wc` (Zenith Linux, "liczba")
#
# STATUS: szkielet — liczenie linii/słów/bajtów działa,
# tryb wielobajtowy (znaki UTF-8 vs bajty) to TODO.

VERSION = "1.0.0"

show_lines = false
show_words = false
show_bytes = false
files      = [] of String

parser = OptionParser.new do |p|
  p.banner = "lb — nowoczesna alternatywa dla wc (Zenith Linux)\n\nUżycie: lb [opcje] [PLIK...]"
  p.on("-l", "--lines", "licz tylko linie") { show_lines = true }
  p.on("-w", "--words", "licz tylko słowa") { show_words = true }
  p.on("-c", "--bytes", "licz tylko bajty") { show_bytes = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu lb") { puts "lb #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

show_lines = show_words = show_bytes = true if !show_lines && !show_words && !show_bytes

# TODO: -m (znaki, z uwzględnieniem UTF-8) i -L (najdłuższa linia)

record Counts, lines : Int32, words : Int32, bytes : Int32

def count(io : IO) : Counts
  lines = 0
  words = 0
  bytes = 0
  io.each_line do |line|
    lines += 1
    words += line.split.size
    bytes += line.bytesize + 1
  end
  Counts.new(lines, words, bytes)
end

def format(c : Counts, show_lines : Bool, show_words : Bool, show_bytes : Bool, label : String?)
  parts = [] of String
  parts << c.lines.to_s.rjust(7) if show_lines
  parts << c.words.to_s.rjust(7) if show_words
  parts << c.bytes.to_s.rjust(7) if show_bytes
  line = parts.join(" ")
  line += " #{label}" if label
  puts line
end

total = Counts.new(0, 0, 0)
exit_code = 0

if files.empty?
  c = count(STDIN)
  format(c, show_lines, show_words, show_bytes, nil)
else
  files.each do |f|
    unless File.exists?(f)
      STDERR.puts "lb: nie można otworzyć '#{f}': nie istnieje"
      exit_code = 1
      next
    end
    c = File.open(f) { |io| count(io) }
    total = Counts.new(total.lines + c.lines, total.words + c.words, total.bytes + c.bytes)
    format(c, show_lines, show_words, show_bytes, f)
  end
  format(total, show_lines, show_words, show_bytes, "razem") if files.size > 1
end

exit exit_code
