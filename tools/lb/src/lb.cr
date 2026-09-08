require "option_parser"

# lb — nowoczesna alternatywa dla `wc` (Zenit Linux, "liczba")
#
# STATUS: szkielet+ — liczenie linii/słów/bajtów działa, wraz z trybem
# znakowym z uwzględnieniem UTF-8 (-m, przez `String#size`, który liczy
# punkty kodowe, nie bajty) i długością najdłuższej linii (-L).

VERSION = "0.1.0"

show_lines   = false
show_words   = false
show_bytes   = false
show_chars   = false
show_longest = false
files        = [] of String

parser = OptionParser.new do |p|
  p.banner = "lb — nowoczesna alternatywa dla wc (Zenit Linux)\n\nUżycie: lb [opcje] [PLIK...]"
  p.on("-l", "--lines", "licz tylko linie") { show_lines = true }
  p.on("-w", "--words", "licz tylko słowa") { show_words = true }
  p.on("-c", "--bytes", "licz tylko bajty") { show_bytes = true }
  p.on("-m", "--chars", "licz tylko znaki (UTF-8, punkty kodowe, nie bajty)") { show_chars = true }
  p.on("-L", "--max-line-length", "wypisz długość najdłuższej linii (w znakach)") { show_longest = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu lb") { puts "lb #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

if !show_lines && !show_words && !show_bytes && !show_chars && !show_longest
  show_lines = show_words = show_bytes = true
end

record Counts, lines : Int32, words : Int32, bytes : Int32, chars : Int32, longest : Int32

def count(io : IO) : Counts
  lines = 0
  words = 0
  bytes = 0
  chars = 0
  longest = 0
  io.each_line do |line|
    lines += 1
    words += line.split.size
    bytes += line.bytesize + 1
    # `String#size` liczy punkty kodowe Unicode (znaki), nie bajty —
    # dzięki temu wielobajtowe znaki UTF-8 (np. polskie „ł”, „ż”) liczą
    # się jako jeden znak, tak jak w GNU wc -m.
    line_chars = line.size
    chars += line_chars + 1
    longest = line_chars if line_chars > longest
  end
  Counts.new(lines, words, bytes, chars, longest)
end

def format(c : Counts, show_lines : Bool, show_words : Bool, show_bytes : Bool, show_chars : Bool, show_longest : Bool, label : String?)
  parts = [] of String
  parts << c.lines.to_s.rjust(7) if show_lines
  parts << c.words.to_s.rjust(7) if show_words
  parts << c.bytes.to_s.rjust(7) if show_bytes
  parts << c.chars.to_s.rjust(7) if show_chars
  parts << c.longest.to_s.rjust(7) if show_longest
  line = parts.join(" ")
  line += " #{label}" if label
  puts line
end

total = Counts.new(0, 0, 0, 0, 0)
exit_code = 0

if files.empty?
  c = count(STDIN)
  format(c, show_lines, show_words, show_bytes, show_chars, show_longest, nil)
else
  files.each do |f|
    unless File.exists?(f)
      STDERR.puts "lb: nie można otworzyć '#{f}': nie istnieje"
      exit_code = 1
      next
    end
    c = File.open(f) { |io| count(io) }
    total = Counts.new(
      total.lines + c.lines,
      total.words + c.words,
      total.bytes + c.bytes,
      total.chars + c.chars,
      Math.max(total.longest, c.longest),
    )
    format(c, show_lines, show_words, show_bytes, show_chars, show_longest, f)
  end
  format(total, show_lines, show_words, show_bytes, show_chars, show_longest, "razem") if files.size > 1
end

exit exit_code
