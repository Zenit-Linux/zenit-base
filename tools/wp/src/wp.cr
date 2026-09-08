require "option_parser"

# wp — nowoczesna alternatywa dla `cat` (Zenit Linux)
#
# STATUS: szkielet+ — wypisywanie plików i stdin, numerowanie linii,
# ściskanie pustych linii oraz widoczne znaki niedrukowalne (-A/-e/-t)
# działają. Strumieniowe czytanie bardzo dużych plików (linia po linii
# przez IO, bez wczytywania całości do pamięci) pozostaje jako TODO —
# `io.each_line` już działa strumieniowo, ale samo `File.open` wciąż
# trzyma cały bufor odczytu w pamięci systemu plików, nie w Crystalu.

VERSION = "0.1.0"

number_lines      = false
squeeze_blank     = false
show_ends         = false
show_tabs         = false
show_nonprinting  = false
files             = [] of String

parser = OptionParser.new do |p|
  p.banner = "wp — nowoczesna alternatywa dla cat (Zenit Linux)\n\nUżycie: wp [opcje] [PLIK...]"
  p.on("-n", "--number", "numeruj wszystkie linie wyjściowe") { number_lines = true }
  p.on("-s", "--squeeze-blank", "zwijaj powtarzające się puste linie") { squeeze_blank = true }
  p.on("-A", "--show-all", "jak -vET (znaki niedrukowalne + $ + ^I)") { show_ends = true; show_tabs = true; show_nonprinting = true }
  p.on("-e", "jak -vE (znaki niedrukowalne + $ na końcu linii)") { show_ends = true; show_nonprinting = true }
  p.on("-t", "jak -vT (znaki niedrukowalne + taby jako ^I)") { show_tabs = true; show_nonprinting = true }
  p.on("-E", "--show-ends", "wypisz $ na końcu każdej linii") { show_ends = true }
  p.on("-T", "--show-tabs", "wypisz taby jako ^I") { show_tabs = true }
  p.on("-v", "--show-nonprinting", "wypisz znaki niedrukowalne w notacji ^X") { show_nonprinting = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu wp") { puts "wp #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

# Zamienia linię na wersję z widocznymi znakami niedrukowalnymi (jak
# `cat -v`): sterujące ASCII (< 32, poza tabem) jako ^X, DEL (127) jako
# ^?, tab jako ^I (jeśli show_tabs), $ na końcu (jeśli show_ends).
def visualize(line : String, show_ends : Bool, show_tabs : Bool, show_nonprinting : Bool) : String
  return line unless show_ends || show_tabs || show_nonprinting

  body = String.build do |sb|
    line.each_char do |c|
      if c == '\t'
        show_tabs ? (sb << "^I") : (sb << c)
      elsif show_nonprinting && c.ord < 32
        sb << '^' << (c.ord + 64).chr
      elsif show_nonprinting && c.ord == 127
        sb << "^?"
      else
        sb << c
      end
    end
  end
  show_ends ? "#{body}$" : body
end

def emit(io : IO, number_lines : Bool, squeeze_blank : Bool, show_ends : Bool, show_tabs : Bool, show_nonprinting : Bool)
  line_no = 0
  prev_blank = false
  io.each_line do |line|
    is_blank = line.strip.empty?
    next if squeeze_blank && is_blank && prev_blank
    prev_blank = is_blank

    rendered = visualize(line, show_ends, show_tabs, show_nonprinting)

    if number_lines
      line_no += 1
      puts "#{line_no.to_s.rjust(6)}  #{rendered}"
    else
      puts rendered
    end
  end
end

exit_code = 0

if files.empty?
  emit(STDIN, number_lines, squeeze_blank, show_ends, show_tabs, show_nonprinting)
else
  files.each do |f|
    if f == "-"
      emit(STDIN, number_lines, squeeze_blank, show_ends, show_tabs, show_nonprinting)
      next
    end
    unless File.exists?(f)
      STDERR.puts "wp: nie można otworzyć '#{f}': nie istnieje"
      exit_code = 1
      next
    end
    File.open(f) do |io|
      emit(io, number_lines, squeeze_blank, show_ends, show_tabs, show_nonprinting)
    end
  end
end

exit exit_code
