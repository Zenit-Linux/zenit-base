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
  p.on("-E", "--no-escapes", "NIE interpretuj sekwencji ucieczki (domyślne, ale nadpisuje wcześniejsze -e)") { interpret_escapes = false }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu echo") { puts "echo #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

# Zwraca (przetworzony_tekst, zatrzymano_na_backslash_c) -- \c oznacza
# "przerwij wypisywanie tutaj, NIE dodawaj nawet końcowego \n" (konwencja
# POSIX/bash dla `echo -e`), więc wywołujący musi wiedzieć, że natrafiono
# na \c, żeby pominąć końcowe puts/print niezależnie od -n.
def interpret(s : String) : {String, Bool}
  out = String::Builder.new
  i = 0
  while i < s.bytesize
    c = s[i]
    if c == '\\' && i + 1 < s.bytesize
      nxt = s[i + 1]
      case nxt
      when 'n' then out << '\n'; i += 2
      when 't' then out << '\t'; i += 2
      when 'r' then out << '\r'; i += 2
      when '\\' then out << '\\'; i += 2
      when 'a' then out << '\a'; i += 2
      when 'b' then out << '\b'; i += 2
      when 'f' then out << '\f'; i += 2
      when 'v' then out << '\v'; i += 2
      when 'e' then out << '\e'; i += 2
      when 'c' then return {out.to_s, true} # \c: zatrzymaj się tu, całkowicie (bez \n)
      when '0'
        # \0NNN -- do 3 cyfr ÓSEMKOWYCH po "0" (konwencja bash: SAMO "0"
        # jest wymagane przed cyframi, w odróżnieniu od \NNN bez zera).
        j = i + 2
        digits = String::Builder.new
        while digits.bytesize < 3 && j < s.bytesize && s[j].in?('0'..'7')
          digits << s[j]
          j += 1
        end
        if digits.bytesize > 0
          out << (digits.to_s.to_i(8) & 0xFF).chr
          i = j
        else
          out << c; i += 1 # "\0" bez cyfr ósemkowych -- literalnie
        end
      when 'x'
        # \xHH -- do 2 cyfr szesnastkowych.
        j = i + 2
        digits = String::Builder.new
        while digits.bytesize < 2 && j < s.bytesize && s[j].ascii_number? || (digits.bytesize < 2 && j < s.bytesize && s[j].in?('a'..'f', 'A'..'F'))
          digits << s[j]
          j += 1
        end
        if digits.bytesize > 0
          out << (digits.to_s.to_i(16) & 0xFF).chr
          i = j
        else
          out << c; i += 1
        end
      else
        out << c; i += 1 # nieznana sekwencja -- zostaw backslash dosłownie
      end
    else
      out << c
      i += 1
    end
  end
  {out.to_s, false}
end

text = args.join(" ")
stop_output = false
if interpret_escapes
  text, stop_output = interpret(text)
end

if stop_output
  print text
elsif no_newline
  print text
else
  puts text
end
