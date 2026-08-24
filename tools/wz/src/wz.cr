require "option_parser"

# wz — nowoczesna alternatywa dla `ln` (Zenith Linux, "wiąż")
#
# STATUS: szkielet — linki symboliczne i twarde działają w podstawowym
# zakresie, walidacja skrzyżowanych systemów plików to TODO.

VERSION = "1.0.0"

symbolic = false
force    = false
verbose  = false
args     = [] of String

parser = OptionParser.new do |p|
  p.banner = "wz — nowoczesna alternatywa dla ln (Zenith Linux)\n\nUżycie: wz [opcje] CEL DOWIĄZANIE"
  p.on("-s", "--symbolic", "utwórz dowiązanie symboliczne zamiast twardego") { symbolic = true }
  p.on("-f", "--force", "usuń istniejące dowiązanie przed utworzeniem nowego") { force = true }
  p.on("-v", "--verbose", "wypisuj tworzone dowiązania") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu wz") { puts "wz #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

if args.size != 2
  STDERR.puts "wz: wymagane argumenty: CEL DOWIĄZANIE"
  exit 1
end

target, link = args

# TODO: obsługa wielu dowiązań na raz do jednego katalogu docelowego (jak ln -t)

if File.exists?(link) || File.symlink?(link)
  unless force
    STDERR.puts "wz: '#{link}' już istnieje — użyj -f, aby nadpisać"
    exit 1
  end
  File.delete(link)
end

begin
  if symbolic
    File.symlink(target, link)
  else
    File.link(target, link)
  end
  puts "wz: #{symbolic ? "symboliczne" : "twarde"} '#{link}' -> '#{target}'" if verbose
rescue e
  STDERR.puts "wz: nie można utworzyć dowiązania: #{e.message}"
  exit 1
end
