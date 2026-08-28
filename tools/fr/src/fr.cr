require "option_parser"

# fr — nowoczesna alternatywa dla `head`/`tail` (Zenit Linux, "fragment")
#
# STATUS: szkielet — tryb head (domyślny) i tryb tail (-t) działają na
# całym pliku wczytanym do pamięci. `-f`/`--follow` (jak `tail -f`) jest
# zaimplementowane w prostej wersji (polling), a wydajne inotify to TODO.

VERSION = "0.1.0"

mode_tail = false
num_lines = 10
follow    = false
files     = [] of String

parser = OptionParser.new do |p|
  p.banner = "fr — nowoczesna alternatywa dla head/tail (Zenit Linux)\n\nUżycie: fr [opcje] [PLIK...]"
  p.on("-t", "--tail", "pokaż koniec pliku zamiast początku") { mode_tail = true }
  p.on("-n NUM", "--lines=NUM", "liczba linii do pokazania (domyślnie 10)") { |v| num_lines = v.to_i }
  p.on("-f", "--follow", "śledź dopisywane linie (jak tail -f), wymaga -t") { follow = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu fr") { puts "fr #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

# TODO: --follow oparty o inotify (IN_MODIFY) zamiast pollingu co interwał;
# TODO: obsługa wielu plików na raz z nagłówkami "==> plik <==" jak w GNU coreutils.

def show_head(lines : Array(String), num : Int32)
  lines.first(num).each { |l| puts l }
end

def show_tail(lines : Array(String), num : Int32)
  start = Math.max(0, lines.size - num)
  lines[start..].each { |l| puts l }
end

def follow_file(path : String, num : Int32)
  lines = File.read_lines(path)
  show_tail(lines, num)

  last_size = File.size(path)
  loop do
    sleep 0.5.seconds
    current_size = File.size(path)
    next if current_size <= last_size

    File.open(path) do |io|
      io.seek(last_size)
      io.each_line { |l| puts l }
    end
    last_size = current_size
  end
end

exit_code = 0

if files.empty?
  content = STDIN.gets_to_end.split('\n')
  content.pop if content.last? == ""
  if mode_tail
    show_tail(content, num_lines)
  else
    show_head(content, num_lines)
  end
else
  files.each do |f|
    unless File.exists?(f)
      STDERR.puts "fr: nie można otworzyć '#{f}': nie istnieje"
      exit_code = 1
      next
    end

    puts "==> #{f} <==" if files.size > 1

    if follow && mode_tail
      follow_file(f, num_lines) # nie wraca (pętla nieskończona)
    else
      lines = File.read_lines(f)
      if mode_tail
        show_tail(lines, num_lines)
      else
        show_head(lines, num_lines)
      end
    end
  end
end

exit exit_code
