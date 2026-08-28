require "option_parser"

# echo — odpowiednik `echo` (Zenit Linux)
#
# STATUS: działa — brakowało tego narzędzia mimo że dokumentacja i część
# przykładów w repozytorium zakładały jego istnienie (zesh samo w sobie
# nie ma wbudowanego `echo`, deleguje do zewnętrznego programu w $PATH,
# tak jak każda klasyczna powłoka uniksowa). Zachowuje nazwę `echo` bez
# skracania — to jedno z niewielu poleceń na tyle fundamentalnych, że
# skrót łamałby oczekiwania każdego, kto kiedykolwiek pisał skrypt powłoki.

VERSION = "0.1.0"

no_newline = false
interpret_escapes = false
args = [] of String

parser = OptionParser.new do |p|
  p.banner = "echo — wypisuje argumenty na standardowe wyjście (Zenit Linux)\n\nUżycie: echo [opcje] [TEKST...]"
  p.on("-n", "--no-newline", "nie dodawaj znaku nowej linii na końcu") { no_newline = true }
  p.on("-e", "--escapes", "interpretuj sekwencje ucieczki (\\n, \\t, \\\\, ...)") { interpret_escapes = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu echo") { puts "echo #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

# TODO: -E (jawne wyłączenie interpretacji, domyślne i tak, ale przydatne
# do nadpisania -e podanego wcześniej), pełny zestaw sekwencji ucieczki
# POSIX (\a, \b, \f, \v, \0NNN, \xHH) — dziś tylko najczęstsze.

def interpret(s : String) : String
  s.gsub("\\n", "\n")
   .gsub("\\t", "\t")
   .gsub("\\r", "\r")
   .gsub("\\\\", "\\")
end

text = args.join(" ")
text = interpret(text) if interpret_escapes

if no_newline
  print text
else
  puts text
end
