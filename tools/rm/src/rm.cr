require "option_parser"
require "file_utils"

VERSION = "0.1.0"

force       = false
interactive = false
verbose     = false
no_clobber  = false
args        = [] of String

parser = OptionParser.new do |p|
  p.banner = "rm — nowoczesna alternatywa dla mv (Zenit Linux)\n\nUżycie: rm [opcje] ŹRÓDŁO... CEL"
  p.on("-f", "--force", "nadpisuj bez pytania") { force = true }
  p.on("-i", "--interactive", "pytaj przed nadpisaniem") { interactive = true }
  p.on("-n", "--no-clobber", "nie nadpisuj istniejących plików") { no_clobber = true }
  p.on("-v", "--verbose", "wypisuj przenoszone pliki") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu rm") { puts "rm #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

if args.size < 2
  STDERR.puts "rm: wymagane argumenty: ŹRÓDŁO... CEL"
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

target  = args.last
sources = args[0..-2]

target_is_dir = Dir.exists?(target)

if sources.size > 1 && !target_is_dir
  STDERR.puts "rm: cel '#{target}' nie jest katalogiem"
  exit 1
end

exit_code = 0

sources.each do |src|
  unless File.exists?(src) || Dir.exists?(src)
    STDERR.puts "rm: nie można przenieść '#{src}': nie istnieje"
    exit_code = 1
    next
  end

  dest = target_is_dir ? File.join(target, File.basename(src.chomp('/'))) : target

  if File.exists?(dest) || Dir.exists?(dest)
    if no_clobber
      next
    elsif interactive && !force
      next unless confirm("rm: nadpisać '#{dest}'?")
    end
  end

  begin
    FileUtils.mv(src, dest)
    puts "rm: '#{src}' -> '#{dest}'" if verbose
  rescue e
    STDERR.puts "rm: błąd przenoszenia '#{src}': #{e.message}"
    exit_code = 1
  end
end

exit exit_code
