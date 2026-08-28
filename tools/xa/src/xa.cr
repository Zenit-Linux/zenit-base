require "option_parser"
require "process"

# xa — nowoczesna alternatywa dla `xargs` (Zenit Linux)
#
# STATUS: szkielet — buduje i uruchamia polecenie z argumentami wczytanymi
# ze stdin (jeden argument na linię). Grupowanie po -n LICZBA i tryb -0
# (separator NUL, jak `find -print0 | xargs -0`) działają. Uruchamianie
# równoległe (-P) i podmiana {} (jak `xargs -I{}`) pozostają jako TODO.

VERSION = "0.1.0"

max_args_per_call = 0 # 0 = bez limitu (wszystkie argumenty w jednym wywołaniu)
null_separated     = false
verbose            = false
command_and_args   = [] of String

parser = OptionParser.new do |p|
  p.banner = "xa — nowoczesna alternatywa dla xargs (Zenit Linux)\n\nUżycie: polecenie1 | xa [opcje] POLECENIE [ARGUMENTY...]"
  p.on("-n NUM", "--max-args=NUM", "maksymalna liczba argumentów na jedno wywołanie") { |v| max_args_per_call = v.to_i }
  p.on("-0", "--null", "argumenty na wejściu rozdzielone bajtem NUL zamiast nowej linii") { null_separated = true }
  p.on("-t", "--verbose", "wypisz polecenie przed wykonaniem") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu xa") { puts "xa #{VERSION}"; exit 0 }
  p.unknown_args { |args| command_and_args.concat(args) }
end
parser.parse

if command_and_args.empty?
  STDERR.puts "xa: brak polecenia do uruchomienia"
  exit 1
end

# TODO: -I ZASTĘPNIK (podmiana konkretnego tokenu w argumentach zamiast
# doklejania na końcu), -P N (uruchamianie N wywołań równolegle).

separator = null_separated ? '\0' : '\n'
raw = STDIN.gets_to_end
items = raw.split(separator).reject(&.empty?)

base_cmd  = command_and_args[0]
base_args = command_and_args[1..]

groups = if max_args_per_call > 0
           items.each_slice(max_args_per_call).to_a
         else
           [items]
         end

exit_code = 0
groups.each do |group|
  next if group.empty?
  full_args = base_args + group
  puts "#{base_cmd} #{full_args.join(" ")}" if verbose

  status = Process.run(base_cmd, args: full_args, output: STDOUT, error: STDERR)
  unless status.success?
    exit_code = status.exit_code
  end
end

exit exit_code
