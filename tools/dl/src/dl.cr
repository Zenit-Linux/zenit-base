require "option_parser"
require "file_utils"

VERSION = "0.1.0"

trash_dir = File.join(ENV["HOME"]? || "/root", ".zenith", "trash")

recursive   = false
force       = false
interactive = false
permanent   = false
verbose     = false
targets     = [] of String

parser = OptionParser.new do |p|
  p.banner = "dl — nowoczesna alternatywa dla rm (Zenit Linux)\n\nUżycie: dl [opcje] PLIK/KATALOG...\n\nDomyślnie pliki trafiają do kosza: #{trash_dir}"
  p.on("-r", "--recursive", "usuwaj katalogi rekurencyjnie") { recursive = true }
  p.on("-f", "--force", "nie pytaj, ignoruj brakujące pliki") { force = true }
  p.on("-i", "--interactive", "pytaj przed każdym usunięciem") { interactive = true }
  p.on("--permanent", "usuń trwale, z pominięciem kosza") { permanent = true }
  p.on("-v", "--verbose", "wypisuj usuwane pliki") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu dl") { puts "dl #{VERSION}"; exit 0 }
  p.unknown_args { |args| targets.concat(args) }
end
parser.parse

if targets.empty?
  STDERR.puts "dl: brak argumentu — podaj plik lub katalog"
  exit 1
end

Dir.mkdir_p(trash_dir) if !permanent && !Dir.exists?(trash_dir)

def confirm(msg : String) : Bool
  print "#{msg} [t/N] "
  STDOUT.flush
  ans = gets
  return false if ans.nil?
  ans = ans.strip.downcase
  ans == "t" || ans == "tak" || ans == "y" || ans == "yes"
end

exit_code = 0

targets.each do |t|
  is_dir  = Dir.exists?(t) && !File.file?(t)
  is_file = File.file?(t)

  unless is_dir || is_file
    unless force
      STDERR.puts "dl: nie można usunąć '#{t}': nie istnieje"
      exit_code = 1
    end
    next
  end

  if is_dir && !recursive
    STDERR.puts "dl: '#{t}' jest katalogiem — użyj -r, aby go usunąć"
    exit_code = 1
    next
  end

  if interactive && !confirm("dl: usunąć '#{t}'?")
    next
  end

  begin
    if permanent
      if is_dir
        FileUtils.rm_rf(t)
      else
        File.delete(t)
      end
      puts "dl: usunięto trwale '#{t}'" if verbose
    else
      stamp = Time.utc.to_unix
      dest  = File.join(trash_dir, "#{File.basename(t.chomp('/'))}_#{stamp}")
      FileUtils.mv(t, dest)
      puts "dl: przeniesiono do kosza '#{t}' -> '#{dest}'" if verbose
    end
  rescue e
    STDERR.puts "dl: błąd usuwania '#{t}': #{e.message}"
    exit_code = 1
  end
end

exit exit_code
