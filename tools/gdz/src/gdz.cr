require "option_parser"

# gdz — nowoczesna alternatywa dla `which` (Zenit Linux, "gdzie")
#
# STATUS: szkielet — przeszukuje $PATH i zwraca pierwszą pasującą ścieżkę.
# Wypisywanie WSZYSTKICH dopasowań (-a, jak `which -a`) pozostaje jako TODO.

VERSION = "0.1.0"

names = [] of String

parser = OptionParser.new do |p|
  p.banner = "gdz — nowoczesna alternatywa dla which (Zenit Linux)\n\nUżycie: gdz POLECENIE..."
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu gdz") { puts "gdz #{VERSION}"; exit 0 }
  p.unknown_args { |args| names.concat(args) }
end
parser.parse

if names.empty?
  STDERR.puts "gdz: brak argumentu — podaj nazwę polecenia"
  exit 1
end

# TODO: -a (wypisz wszystkie dopasowania w $PATH, nie tylko pierwsze).

exit_code = 0
names.each do |name|
  path = Process.find_executable(name)
  if path
    puts path
  else
    STDERR.puts "gdz: nie znaleziono '#{name}' w $PATH"
    exit_code = 1
  end
end

exit exit_code
