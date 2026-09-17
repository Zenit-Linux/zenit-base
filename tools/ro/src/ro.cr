require "option_parser"
require "./myers_diff"

# ro — nowoczesna alternatywa dla `diff` (Zenit Linux, "różnice")
#
# STATUS: działa. Algorytm Myersa (`myers_diff.cr`, O(D*(n+m)) zamiast
# starej tablicy DP O(n*m) -- patrz komentarz w tym pliku) do wyznaczania
# najkrótszego skryptu edycji, z wynikiem wypisywanym w PRAWDZIWYM
# formacie unified diff (`diff -u`) — nagłówki hunków
# `@@ -start,len +start,len @@`, sąsiadujące zmiany scalone w jeden
# hunk z NUM liniami kontekstu dookoła (domyślnie 3, jak GNU diff).

VERSION = "0.1.0"

no_color = false
context  = 3
files    = [] of String

parser = OptionParser.new do |p|
  p.banner = "ro — nowoczesna alternatywa dla diff (Zenit Linux)\n\nUżycie: ro [opcje] PLIK1 PLIK2"
  p.on("-U NUM", "--unified=NUM", "liczba linii kontekstu wokół zmian (domyślnie 3)") { |v| context = v.to_i }
  p.on("--no-color", "wyłącz kolorowanie wyjścia") { no_color = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu ro") { puts "ro #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

if files.size != 2
  STDERR.puts "ro: wymagane dokładnie dwa argumenty: PLIK1 PLIK2"
  exit 1
end

[files[0], files[1]].each do |f|
  unless File.exists?(f)
    STDERR.puts "ro: nie można otworzyć '#{f}': nie istnieje"
    exit 1
  end
end

use_color = !no_color && STDOUT.tty?
a = File.read_lines(files[0])
b = File.read_lines(files[1])

# Każdy element: (rodzaj, tekst_linii, indeks_w_a_PRZED_konsumpcją, indeks_w_b_PRZED_konsumpcją)
# -- indeksy pozwalają później dokładnie wyliczyć numery linii w nagłówkach hunków.
# Wyznaczone algorytmem Myersa (myers_diff.cr) zamiast poprzedniej
# tablicy DP -- format wyniku identyczny, więc reszta programu (grupowanie
# w hunki, wypisywanie) poniżej nie wymaga żadnych zmian.
ops = MyersDiff.diff(a, b)

if ops.all? { |(kind, _, _, _)| kind == ' ' }
  exit 0 # pliki identyczne -- brak wyjścia, kod 0 (jak `diff`)
end

def colorize(kind : Char, text : String, use_color : Bool) : String
  return text unless use_color
  case kind
  when '+' then "\e[32m#{text}\e[0m"
  when '-' then "\e[31m#{text}\e[0m"
  else          text
  end
end

# --- grupowanie w hunki -------------------------------------------------
# Indeksy (w `ops`) linii ZMIENIONYCH (nie-kontekstowych).
changed_idx = (0...ops.size).select { |k| ops[k][0] != ' ' }

# Klastrowanie: dwie zmiany trafiają do TEGO SAMEGO hunku, jeśli dzieli je
# mniej niż `2*context` linii kontekstu (bo wtedy ich strefy kontekstu i
# tak by się nachodziły) — standardowa reguła scalania hunków z `diff -u`.
hunks = [] of Array(Int32)
changed_idx.each do |idx|
  if hunks.empty? || idx.to_i32 - hunks.last.last > 2 * context
    hunks << [idx.to_i32]
  else
    hunks.last << idx.to_i32
  end
end

puts "--- #{files[0]}"
puts "+++ #{files[1]}"

hunks.each do |group|
  start_op = Math.max(0, group.first - context)
  end_op   = Math.min(ops.size - 1, group.last + context)

  a_start = ops[start_op][2]
  b_start = ops[start_op][3]
  a_count = 0
  b_count = 0
  body = [] of String

  (start_op..end_op).each do |k|
    kind, text, _, _ = ops[k]
    case kind
    when ' '
      a_count += 1
      b_count += 1
    when '-'
      a_count += 1
    when '+'
      b_count += 1
    end
    body << colorize(kind, "#{kind}#{text}", use_color)
  end

  # Konwencja unified diff (GNU diffutils): gdy zakres ma DŁUGOŚĆ ZERO
  # (czysta insercja bez usunięć po stronie A, albo czyste usunięcie bez
  # wstawień po stronie B), numer linii w nagłówku to pozycja PRZED którą
  # następuje zmiana, w indeksowaniu 0-bazowym -- NIE zwykłe "+1" jak przy
  # niepustym zakresie. Bez tego rozróżnienia insercja na samym początku
  # pliku (a_start=0, a_count=0) dawałaby błędny nagłówek "@@ -1,0 ...@@"
  # zamiast poprawnego "@@ -0,0 ...@@", niezgodnego z tym, co generuje i
  # czego oczekuje `patch`/GNU diff.
  a_header_start = a_count == 0 ? a_start : a_start + 1
  b_header_start = b_count == 0 ? b_start : b_start + 1
  header = "@@ -#{a_header_start},#{a_count} +#{b_header_start},#{b_count} @@"
  puts use_color ? "\e[36m#{header}\e[0m" : header
  body.each { |l| puts l }
end

exit 1
