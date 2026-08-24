require "option_parser"

# sz — nowoczesna alternatywa dla `grep` (Zenith Linux)
#
# STATUS: szkielet — dopasowywanie proste i wyrażeniami regularnymi działa,
# reszta klasycznych opcji grep to TODO.

VERSION = "1.0.0"

ignore_case  = false
invert       = false
line_number  = false
count_only   = false
recursive    = false
fixed_string = false
args         = [] of String

parser = OptionParser.new do |p|
  p.banner = "sz — nowoczesna alternatywa dla grep (Zenith Linux)\n\nUżycie: sz [opcje] WZORZEC [PLIK...]"
  p.on("-i", "--ignore-case", "ignoruj wielkość liter") { ignore_case = true }
  p.on("-v", "--invert-match", "wypisz linie NIE pasujące do wzorca") { invert = true }
  p.on("-n", "--line-number", "poprzedzaj dopasowania numerem linii") { line_number = true }
  p.on("-c", "--count", "wypisz tylko liczbę dopasowań") { count_only = true }
  p.on("-r", "--recursive", "przeszukuj katalogi rekurencyjnie") { recursive = true }
  p.on("-F", "--fixed-strings", "traktuj wzorzec jako zwykły tekst, nie regex") { fixed_string = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu sz") { puts "sz #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

if args.empty?
  STDERR.puts "sz: brak wzorca do wyszukania"
  exit 1
end

pattern_str = args.shift
files       = args

# TODO: obsługa -l/-L (tylko nazwy plików z/bez dopasowań)
# TODO: kolorowanie dopasowanego fragmentu (--color)
# TODO: kontekst -A/-B/-C (linie przed/po dopasowaniu)

regex = if fixed_string
          Regex.new(Regex.escape(pattern_str), ignore_case ? Regex::Options::IGNORE_CASE : Regex::Options::None)
        else
          Regex.new(pattern_str, ignore_case ? Regex::Options::IGNORE_CASE : Regex::Options::None)
        end

def search_io(io : IO, label : String?, regex : Regex, invert : Bool,
              line_number : Bool, count_only : Bool) : Int32
  matches = 0
  io.each_line.with_index(1) do |line, idx|
    is_match = !!(line =~ regex)
    is_match = !is_match if invert
    next unless is_match

    matches += 1
    next if count_only

    prefix = label ? "#{label}:" : ""
    prefix += "#{idx}:" if line_number
    puts "#{prefix}#{line}"
  end
  matches
end

total_matches = 0
exit_code     = 1

if files.empty?
  total_matches += search_io(STDIN, nil, regex, invert, line_number, count_only)
else
  files.each do |f|
    unless File.exists?(f)
      STDERR.puts "sz: nie można otworzyć '#{f}': nie istnieje"
      next
    end
    label = files.size > 1 ? f : nil
    File.open(f) do |io|
      total_matches += search_io(io, label, regex, invert, line_number, count_only)
    end
  end
end

puts total_matches if count_only
exit_code = total_matches > 0 ? 0 : 1
exit exit_code
