require "option_parser"

# ro — nowoczesna alternatywa dla `diff` (Zenit Linux, "różnice")
#
# STATUS: szkielet — prosty algorytm LCS (najdłuższy wspólny podciąg) do
# wykrywania dodanych/usuniętych linii, format wyjścia zbliżony do
# unified diff. Prawdziwy `diff -u` z kontekstem i scalaniem sąsiadujących
# zmian w hunki pozostaje jako TODO — dziś każda różnica to osobna linia.

VERSION = "0.1.0"

no_color = false
files    = [] of String

parser = OptionParser.new do |p|
  p.banner = "ro — nowoczesna alternatywa dla diff (Zenit Linux)\n\nUżycie: ro [opcje] PLIK1 PLIK2"
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

# Tablica LCS (programowanie dynamiczne) — O(n*m) czasu i pamięci,
# wystarczające dla plików tekstowych umiarkowanej wielkości.
# TODO: wersja z ograniczoną pamięcią (Myers diff) dla dużych plików.
dp = Array.new(a.size + 1) { Array.new(b.size + 1, 0) }
(1..a.size).each do |i|
  (1..b.size).each do |j|
    dp[i][j] = if a[i - 1] == b[j - 1]
                 dp[i - 1][j - 1] + 1
               else
                 Math.max(dp[i - 1][j], dp[i][j - 1])
               end
  end
end

ops = [] of {Char, String}
i, j = a.size, b.size
while i > 0 || j > 0
  if i > 0 && j > 0 && a[i - 1] == b[j - 1]
    ops << {' ', a[i - 1]}
    i -= 1
    j -= 1
  elsif j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])
    ops << {'+', b[j - 1]}
    j -= 1
  else
    ops << {'-', a[i - 1]}
    i -= 1
  end
end
ops.reverse!

changed = false
ops.each do |(kind, line)|
  next if kind == ' '
  changed = true
  colored = if !use_color
              "#{kind}#{line}"
            elsif kind == '+'
              "\e[32m+#{line}\e[0m"
            else
              "\e[31m-#{line}\e[0m"
            end
  puts colored
end

exit(changed ? 1 : 0)
