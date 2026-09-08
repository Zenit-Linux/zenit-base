require "option_parser"

# wz — nowoczesna alternatywa dla `ln` (Zenit Linux, "wiąż")
#
# STATUS: szkielet+ — linki symboliczne i twarde działają w podstawowym
# zakresie, wraz z obsługą wielu dowiązań na raz do jednego katalogu
# docelowego (-t DIR, jak `ln -t`, oraz forma `wz CEL... KATALOG` gdy
# ostatni argument jest istniejącym katalogiem). Walidacja skrzyżowanych
# systemów plików (co ma znaczenie tylko dla dowiązań twardych) pozostaje
# jako TODO — dziś polegamy na tym, że `File.link` sam zwróci błąd
# systemowy (EXDEV), jeśli cel i dowiązanie leżą na różnych urządzeniach.

VERSION = "0.1.0"

symbolic    = false
force       = false
verbose     = false
target_dir  = nil.as(String?)
args        = [] of String

parser = OptionParser.new do |p|
  p.banner = "wz — nowoczesna alternatywa dla ln (Zenit Linux)\n\nUżycie: wz [opcje] CEL DOWIĄZANIE\n       wz [opcje] CEL... KATALOG\n       wz [opcje] -t KATALOG CEL..."
  p.on("-s", "--symbolic", "utwórz dowiązanie symboliczne zamiast twardego") { symbolic = true }
  p.on("-f", "--force", "usuń istniejące dowiązanie przed utworzeniem nowego") { force = true }
  p.on("-v", "--verbose", "wypisuj tworzone dowiązania") { verbose = true }
  p.on("-t KATALOG", "--target-directory=KATALOG", "utwórz dowiązania dla wszystkich CEL... w podanym katalogu") { |v| target_dir = v }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu wz") { puts "wz #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

# Tworzy pojedyncze dowiązanie `link -> target`, z obsługą -f/-v wspólną
# dla wszystkich trybów wywołania.
def make_link(target : String, link : String, symbolic : Bool, force : Bool, verbose : Bool) : Bool
  if File.exists?(link) || File.symlink?(link)
    unless force
      STDERR.puts "wz: '#{link}' już istnieje — użyj -f, aby nadpisać"
      return false
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
    true
  rescue e
    STDERR.puts "wz: nie można utworzyć dowiązania '#{link}' -> '#{target}': #{e.message}"
    false
  end
end

exit_code = 0

if dir = target_dir
  # -t KATALOG CEL... : każdy CEL dostaje dowiązanie w KATALOG/basename(CEL).
  if args.empty?
    STDERR.puts "wz: wymagany co najmniej jeden argument CEL wraz z -t"
    exit 1
  end
  unless Dir.exists?(dir)
    STDERR.puts "wz: katalog docelowy '#{dir}' nie istnieje"
    exit 1
  end
  args.each do |target|
    link = File.join(dir, File.basename(target))
    exit_code = 1 unless make_link(target, link, symbolic, force, verbose)
  end
elsif args.size == 2 && !Dir.exists?(args[1])
  # Klasyczna forma: wz CEL DOWIĄZANIE (DOWIĄZANIE nie jest katalogiem).
  target, link = args
  exit_code = 1 unless make_link(target, link, symbolic, force, verbose)
elsif args.size >= 2 && Dir.exists?(args.last)
  # Forma z wieloma celami: wz CEL... KATALOG (jak `ln CEL... KATALOG`).
  dir = args.last
  args[0...-1].each do |target|
    link = File.join(dir, File.basename(target))
    exit_code = 1 unless make_link(target, link, symbolic, force, verbose)
  end
else
  STDERR.puts "wz: wymagane argumenty: CEL DOWIĄZANIE, albo CEL... KATALOG"
  exit 1
end

exit exit_code
