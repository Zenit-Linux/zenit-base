require "option_parser"

# wp — nowoczesna alternatywa dla `cat` (Zenit Linux)
#
# STATUS: szkielet — wypisywanie plików i stdin działa,
# numerowanie linii i ściskanie pustych linii to TODO.

VERSION = "0.1.0"

number_lines  = false
squeeze_blank = false
files         = [] of String

parser = OptionParser.new do |p|
  p.banner = "wp — nowoczesna alternatywa dla cat (Zenit Linux)\n\nUżycie: wp [opcje] [PLIK...]"
  p.on("-n", "--number", "numeruj wszystkie linie wyjściowe") { number_lines = true }
  p.on("-s", "--squeeze-blank", "zwijaj powtarzające się puste linie") { squeeze_blank = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu wp") { puts "wp #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

# TODO: obsługa -A/-e/-t (widoczne znaki niedrukowalne, taby jako ^I)
# TODO: strumieniowe czytanie dużych plików zamiast wczytywania całości do pamięci

def emit(io : IO, number_lines : Bool, squeeze_blank : Bool)
  line_no = 0
  prev_blank = false
  io.each_line do |line|
    is_blank = line.strip.empty?
    next if squeeze_blank && is_blank && prev_blank
    prev_blank = is_blank

    if number_lines
      line_no += 1
      puts "#{line_no.to_s.rjust(6)}  #{line}"
    else
      puts line
    end
  end
end

exit_code = 0

if files.empty?
  emit(STDIN, number_lines, squeeze_blank)
else
  files.each do |f|
    if f == "-"
      emit(STDIN, number_lines, squeeze_blank)
      next
    end
    unless File.exists?(f)
      STDERR.puts "wp: nie można otworzyć '#{f}': nie istnieje"
      exit_code = 1
      next
    end
    File.open(f) do |io|
      emit(io, number_lines, squeeze_blank)
    end
  end
end

exit exit_code
