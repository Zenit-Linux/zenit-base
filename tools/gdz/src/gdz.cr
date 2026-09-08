require "option_parser"

# gdz — nowoczesna alternatywa dla `which` (Zenit Linux, "gdzie")
#
# STATUS: szkielet+ — przeszukuje $PATH i zwraca pierwszą pasującą
# ścieżkę; z -a wypisuje WSZYSTKIE dopasowania w $PATH, jak `which -a`.

VERSION = "0.1.0"

show_all = false
names = [] of String

parser = OptionParser.new do |p|
  p.banner = "gdz — nowoczesna alternatywa dla which (Zenit Linux)\n\nUżycie: gdz [opcje] POLECENIE..."
  p.on("-a", "--all", "wypisz wszystkie dopasowania w $PATH, nie tylko pierwsze") { show_all = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu gdz") { puts "gdz #{VERSION}"; exit 0 }
  p.unknown_args { |args| names.concat(args) }
end
parser.parse

if names.empty?
  STDERR.puts "gdz: brak argumentu — podaj nazwę polecenia"
  exit 1
end

# Zwraca WSZYSTKIE ścieżki wykonywalne o danej nazwie znalezione w
# katalogach z $PATH, w kolejności ich występowania w $PATH.
def find_all(name : String) : Array(String)
  found = [] of String
  path_env = ENV["PATH"]? || ""
  path_env.split(':', remove_empty: true).each do |dir|
    candidate = File.join(dir, name)
    if File.exists?(candidate) && !File.directory?(candidate) && File::Info.executable?(candidate)
      found << candidate
    end
  end
  found
end

exit_code = 0
names.each do |name|
  if show_all
    matches = find_all(name)
    if matches.empty?
      STDERR.puts "gdz: nie znaleziono '#{name}' w $PATH"
      exit_code = 1
    else
      matches.each { |m| puts m }
    end
  else
    path = Process.find_executable(name)
    if path
      puts path
    else
      STDERR.puts "gdz: nie znaleziono '#{name}' w $PATH"
      exit_code = 1
    end
  end
end

exit exit_code
