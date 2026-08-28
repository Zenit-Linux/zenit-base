require "option_parser"

# sz — nowoczesna alternatywa dla `grep` (Zenit Linux)
#
# STATUS: rozbudowany szkielet — dodano kontekst (-A/-B/-C) i kolorowanie
# dopasowanego fragmentu. -l/-L (tylko nazwy plików) pozostaje jako TODO.

VERSION = "0.1.0"

ignore_case  = false
invert       = false
line_number  = false
count_only   = false
recursive    = false
fixed_string = false
no_color     = false
context_before = 0
context_after  = 0
args         = [] of String

parser = OptionParser.new do |p|
  p.banner = "sz — nowoczesna alternatywa dla grep (Zenit Linux)\n\nUżycie: sz [opcje] WZORZEC [PLIK...]"
  p.on("-i", "--ignore-case", "ignoruj wielkość liter") { ignore_case = true }
  p.on("-v", "--invert-match", "wypisz linie NIE pasujące do wzorca") { invert = true }
  p.on("-n", "--line-number", "poprzedzaj dopasowania numerem linii") { line_number = true }
  p.on("-c", "--count", "wypisz tylko liczbę dopasowań") { count_only = true }
  p.on("-r", "--recursive", "przeszukuj katalogi rekurencyjnie") { recursive = true }
  p.on("-F", "--fixed-strings", "traktuj wzorzec jako zwykły tekst, nie regex") { fixed_string = true }
  p.on("-A NUM", "--after-context=NUM", "pokaż NUM linii po dopasowaniu") { |v| context_after = v.to_i }
  p.on("-B NUM", "--before-context=NUM", "pokaż NUM linii przed dopasowaniem") { |v| context_before = v.to_i }
  p.on("-C NUM", "--context=NUM", "pokaż NUM linii przed i po dopasowaniu") { |v| context_before = context_after = v.to_i }
  p.on("--no-color", "wyłącz kolorowanie dopasowań") { no_color = true }
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
use_color   = !no_color && STDOUT.tty? && !count_only

# TODO: obsługa -l/-L (tylko nazwy plików z/bez dopasowań)
# TODO: rekurencyjne przeszukiwanie katalogów, gdy -r i argument to katalog

regex = if fixed_string
          Regex.new(Regex.escape(pattern_str), ignore_case ? Regex::Options::IGNORE_CASE : Regex::Options::None)
        else
          Regex.new(pattern_str, ignore_case ? Regex::Options::IGNORE_CASE : Regex::Options::None)
        end

def highlight(line : String, regex : Regex, use_color : Bool) : String
  return line unless use_color
  line.gsub(regex) { |m| "\e[1;31m#{m}\e[0m" }
end

def search_io(io : IO, label : String?, regex : Regex, invert : Bool,
              line_number : Bool, count_only : Bool, context_before : Int32,
              context_after : Int32, use_color : Bool) : Int32
  matches = 0
  lines = io.each_line.to_a
  matched_indices = [] of Int32

  lines.each_with_index do |line, idx|
    is_match = !!(line =~ regex)
    is_match = !is_match if invert
    if is_match
      matches += 1
      matched_indices << idx.to_i32
    end
  end

  return matches if count_only

  # Zbiór indeksów do wypisania: dopasowania + kontekst przed/po.
  to_print = Set(Int32).new
  matched_indices.each do |idx|
    start_idx = Math.max(0, idx - context_before)
    end_idx   = Math.min(lines.size - 1, idx + context_after)
    (start_idx..end_idx).each { |i| to_print << i.to_i32 }
  end

  prev_printed = -2
  to_print.to_a.sort.each do |idx|
    puts "--" if context_before + context_after > 0 && idx > prev_printed + 1
    prev_printed = idx

    line = lines[idx]
    is_matched_line = matched_indices.includes?(idx)

    prefix = label ? "#{label}:" : ""
    prefix += "#{idx + 1}:" if line_number

    text = is_matched_line ? highlight(line, regex, use_color) : line
    puts "#{prefix}#{text}"
  end

  matches
end

total_matches = 0

if files.empty?
  total_matches += search_io(STDIN, nil, regex, invert, line_number, count_only,
                              context_before, context_after, use_color)
else
  files.each do |f|
    unless File.exists?(f)
      STDERR.puts "sz: nie można otworzyć '#{f}': nie istnieje"
      next
    end
    label = files.size > 1 ? f : nil
    File.open(f) do |io|
      total_matches += search_io(io, label, regex, invert, line_number, count_only,
                                  context_before, context_after, use_color)
    end
  end
end

puts total_matches if count_only
exit(total_matches > 0 ? 0 : 1)
