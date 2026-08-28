require "option_parser"
require "file_utils"

# kp — nowoczesna alternatywa dla `cp` (Zenit Linux)
#
# STATUS: szkielet — podstawowe kopiowanie plików/katalogów działa,
# zaawansowane opcje oznaczone są jako TODO.

VERSION = "0.1.0"

recursive   = false
force       = false
interactive = false
verbose     = false
preserve    = false
args        = [] of String

parser = OptionParser.new do |p|
  p.banner = "kp — nowoczesna alternatywa dla cp (Zenit Linux)\n\nUżycie: kp [opcje] ŹRÓDŁO... CEL"
  p.on("-r", "--recursive", "kopiuj katalogi rekurencyjnie") { recursive = true }
  p.on("-f", "--force", "nadpisuj bez pytania") { force = true }
  p.on("-i", "--interactive", "pytaj przed nadpisaniem") { interactive = true }
  p.on("-p", "--preserve", "zachowaj uprawnienia i znaczniki czasu") { preserve = true }
  p.on("-v", "--verbose", "wypisuj kopiowane pliki") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu kp") { puts "kp #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

if args.size < 2
  STDERR.puts "kp: wymagane argumenty: ŹRÓDŁO... CEL"
  exit 1
end

target        = args.last
sources       = args[0..-2]
target_is_dir = Dir.exists?(target)

if sources.size > 1 && !target_is_dir
  STDERR.puts "kp: cel '#{target}' nie jest katalogiem"
  exit 1
end

# TODO: zachowanie uprawnień/mtime przy -p (File.chmod + File.utime na wyniku)
# TODO: kopiowanie linków symbolicznych bez podążania za nimi (-P / domyślnie w GNU cp)
# TODO: pasek postępu / --progress dla dużych plików

def confirm(msg : String) : Bool
  print "#{msg} [t/N] "
  STDOUT.flush
  ans = gets
  return false if ans.nil?
  ans = ans.strip.downcase
  ans == "t" || ans == "tak" || ans == "y" || ans == "yes"
end

exit_code = 0

sources.each do |src|
  unless File.exists?(src) || Dir.exists?(src)
    STDERR.puts "kp: nie można skopiować '#{src}': nie istnieje"
    exit_code = 1
    next
  end

  dest = target_is_dir ? File.join(target, File.basename(src.chomp('/'))) : target

  if Dir.exists?(src) && !recursive
    STDERR.puts "kp: '#{src}' jest katalogiem — użyj -r, aby go skopiować"
    exit_code = 1
    next
  end

  if (File.exists?(dest) || Dir.exists?(dest)) && interactive && !force
    next unless confirm("kp: nadpisać '#{dest}'?")
  end

  begin
    if Dir.exists?(src)
      FileUtils.cp_r(src, dest)
    else
      FileUtils.cp(src, dest)
    end
    puts "kp: '#{src}' -> '#{dest}'" if verbose
  rescue e
    STDERR.puts "kp: błąd kopiowania '#{src}': #{e.message}"
    exit_code = 1
  end
end

exit exit_code
