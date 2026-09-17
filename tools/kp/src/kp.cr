require "option_parser"
require "file_utils"

# kp — nowoczesna alternatywa dla `cp` (Zenit Linux)
#
# STATUS: kopiowanie plików/katalogów, `-p` (zachowanie uprawnień i mtime
# przez File.chmod/File.utime -- UWAGA: Crystal nie udostępnia publicznie
# czasu ostatniego dostępu w File::Info, więc atime jest ustawiany na tę
# samą wartość co mtime, w odróżnieniu od prawdziwego `cp -p`), `-P`
# (kopiowanie linków symbolicznych JAKO linki, bez podążania za nimi —
# domyślne zachowanie w GNU cp) i `--progress` (pasek postępu dla dużych
# plików, oparty o kopiowanie ręczne po kawałku zamiast FileUtils.cp).

VERSION = "0.1.0"

PROGRESS_THRESHOLD = 10 * 1024 * 1024 # pasek postępu tylko dla plików >10 MiB

recursive     = false
force         = false
interactive   = false
verbose       = false
preserve      = false
no_dereference = false
show_progress = false
args          = [] of String

parser = OptionParser.new do |p|
  p.banner = "kp — nowoczesna alternatywa dla cp (Zenit Linux)\n\nUżycie: kp [opcje] ŹRÓDŁO... CEL"
  p.on("-r", "--recursive", "kopiuj katalogi rekurencyjnie") { recursive = true }
  p.on("-f", "--force", "nadpisuj bez pytania") { force = true }
  p.on("-i", "--interactive", "pytaj przed nadpisaniem") { interactive = true }
  p.on("-p", "--preserve", "zachowaj uprawnienia i znaczniki czasu") { preserve = true }
  p.on("-P", "--no-dereference", "kopiuj linki symboliczne JAKO linki, nie podążaj za nimi") { no_dereference = true }
  p.on("--progress", "pokaż pasek postępu dla dużych plików (>10 MiB)") { show_progress = true }
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

def confirm(msg : String) : Bool
  print "#{msg} [t/N] "
  STDOUT.flush
  ans = gets
  return false if ans.nil?
  ans = ans.strip.downcase
  ans == "t" || ans == "tak" || ans == "y" || ans == "yes"
end

def preserve_metadata(src : String, dest : String)
  info = File.info(src, follow_symlinks: false)
  return if info.symlink? # nie ma sensu ustawiać uprawnień na samym dowiązaniu
  File.chmod(dest, info.permissions)
  File.utime(info.modification_time, info.modification_time, dest)
rescue e
  STDERR.puts "kp: nie udało się zachować metadanych dla '#{dest}': #{e.message}"
end

def copy_with_progress(src : String, dest : String, label : String)
  total = File.size(src)
  copied = 0_i64
  File.open(src, "rb") do |input|
    File.open(dest, "wb") do |output|
      buf = Bytes.new(1024 * 1024)
      loop do
        n = input.read(buf)
        break if n == 0
        output.write(buf[0, n])
        copied += n
        pct = total > 0 ? (copied * 100 // total) : 100
        bar_width = 30
        filled = (bar_width * pct // 100)
        bar = ("=" * filled) + (">" * (filled < bar_width ? 1 : 0)) + (" " * Math.max(0, bar_width - filled - 1))
        STDERR.print "\r#{label} [#{bar}] #{pct}%"
        STDERR.flush
      end
    end
  end
  STDERR.print "\n"
end

# Zastępuje proste FileUtils.cp/cp_r własną, rekurencyjną kopią —
# potrzebne, żeby poprawnie obsłużyć -P (linki symboliczne JAKO linki,
# na każdym poziomie drzewa, nie tylko na argumencie najwyższego poziomu)
# i --progress (pasek postępu tylko ma sens przy ręcznym kopiowaniu po
# kawałku, nie przy FileUtils.cp, które kopiuje całość za jednym razem).
def copy_entry(src : String, dest : String, recursive : Bool, no_dereference : Bool,
               preserve : Bool, verbose : Bool, show_progress : Bool)
  info = File.info(src, follow_symlinks: false)

  if info.symlink? && no_dereference
    target_path = File.readlink(src)
    File.delete(dest) if File.exists?(dest) || File.symlink?(dest)
    File.symlink(target_path, dest)
    puts "kp: '#{src}' -> '#{dest}' (link -> #{target_path})" if verbose
    return
  end

  if Dir.exists?(src)
    Dir.mkdir_p(dest) unless Dir.exists?(dest)
    preserve_metadata(src, dest) if preserve
    puts "kp: '#{src}' -> '#{dest}'" if verbose
    Dir.children(src).each do |child|
      copy_entry(File.join(src, child), File.join(dest, child), recursive, no_dereference, preserve, verbose, show_progress)
    end
  else
    if show_progress && File.size(src) > PROGRESS_THRESHOLD
      copy_with_progress(src, dest, File.basename(src))
    else
      FileUtils.cp(src, dest)
    end
    preserve_metadata(src, dest) if preserve
    puts "kp: '#{src}' -> '#{dest}'" if verbose
  end
end

exit_code = 0

sources.each do |src|
  unless File.exists?(src) || Dir.exists?(src) || File.symlink?(src)
    STDERR.puts "kp: nie można skopiować '#{src}': nie istnieje"
    exit_code = 1
    next
  end

  dest = target_is_dir ? File.join(target, File.basename(src.chomp('/'))) : target

  if Dir.exists?(src) && !File.symlink?(src) && !recursive
    STDERR.puts "kp: '#{src}' jest katalogiem — użyj -r, aby go skopiować"
    exit_code = 1
    next
  end

  if (File.exists?(dest) || Dir.exists?(dest)) && interactive && !force
    next unless confirm("kp: nadpisać '#{dest}'?")
  end

  begin
    copy_entry(src, dest, recursive, no_dereference, preserve, verbose, show_progress)
  rescue e
    STDERR.puts "kp: błąd kopiowania '#{src}': #{e.message}"
    exit_code = 1
  end
end

exit exit_code
