require "option_parser"
require "process"

# zn — nowoczesna alternatywa dla `find` (Zenith Linux)
#
# STATUS: rozbudowany szkielet — dodano --exec, filtry --min-size/--max-size
# oraz --newer-than (w minutach). Podążanie za linkami symbolicznymi (-L)
# oraz predykaty logiczne (-and/-or/-not) pozostają jako TODO.

VERSION = "1.0.0"

name_pattern = nil.as(String?)
only_type    = nil.as(Char?)
max_depth    = nil.as(Int32?)
min_size     = nil.as(Int64?)
max_size     = nil.as(Int64?)
newer_than_minutes = nil.as(Int32?)
exec_cmd     = nil.as(Array(String)?)
roots        = [] of String

parser = OptionParser.new do |p|
  p.banner = "zn — nowoczesna alternatywa dla find (Zenith Linux)\n\nUżycie: zn [ŚCIEŻKA...] [opcje]"
  p.on("--name PATTERN", "dopasuj nazwę pliku (glob, np. '*.txt')") { |v| name_pattern = v }
  p.on("--type TYPE", "f = plik, d = katalog") { |v| only_type = v[0]? }
  p.on("--max-depth N", "maksymalna głębokość przeszukiwania") { |v| max_depth = v.to_i }
  p.on("--min-size BYTES", "tylko pliki >= podanego rozmiaru w bajtach") { |v| min_size = v.to_i64 }
  p.on("--max-size BYTES", "tylko pliki <= podanego rozmiaru w bajtach") { |v| max_size = v.to_i64 }
  p.on("--newer-than MIN", "tylko pliki zmodyfikowane w ciągu ostatnich MIN minut") { |v| newer_than_minutes = v.to_i }
  p.on("--exec CMD", "wykonaj polecenie dla każdego dopasowania ({} = ścieżka)") do |v|
    exec_cmd = v.split(' ')
  end
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu zn") { puts "zn #{VERSION}"; exit 0 }
  p.unknown_args { |args| roots.concat(args) }
end
parser.parse

roots = ["."] if roots.empty?

# TODO: prawdziwa składnia `-exec CMD {} \;` (z osobnymi argumentami) zamiast
# pojedynczego stringa dzielonego spacjami — obecne rozwiązanie nie obsługuje
# argumentów zawierających spacje.
# TODO: -L (podążanie za linkami symbolicznymi), -and/-or/-not do łączenia predykatów.

def matches?(name : String, full_path : String, info : File::Info, name_pattern : String?,
             only_type : Char?, min_size : Int64?, max_size : Int64?,
             newer_than_minutes : Int32?) : Bool
  return false if name_pattern && !File.match?(name_pattern, name)

  if only_type
    case only_type
    when 'f' then return false if info.directory?
    when 'd' then return false unless info.directory?
    end
  end

  return false if min_size && info.size < min_size
  return false if max_size && info.size > max_size

  if newer_than_minutes
    cutoff = Time.utc - Time::Span.new(minutes: newer_than_minutes)
    return false if info.modification_time < cutoff
  end

  true
end

def run_exec(cmd_template : Array(String), path : String)
  cmd = cmd_template.map { |arg| arg == "{}" ? path : arg }
  return if cmd.empty?
  status = Process.run(cmd[0], args: cmd[1..], output: STDOUT, error: STDERR)
  unless status.success?
    STDERR.puts "zn: polecenie zakończone kodem #{status.exit_code} dla '#{path}'"
  end
end

def visit(name : String, full_path : String, name_pattern : String?, only_type : Char?,
          min_size : Int64?, max_size : Int64?, newer_than_minutes : Int32?,
          exec_cmd : Array(String)?)
  info = File.info?(full_path)
  return unless info
  return unless matches?(name, full_path, info, name_pattern, only_type, min_size, max_size, newer_than_minutes)

  if exec_cmd
    run_exec(exec_cmd, full_path)
  else
    puts full_path
  end
end

def walk(path : String, depth : Int32, max_depth : Int32?, name_pattern : String?, only_type : Char?,
          min_size : Int64?, max_size : Int64?, newer_than_minutes : Int32?, exec_cmd : Array(String)?)
  return if max_depth && depth > max_depth

  Dir.children(path).each do |child|
    full = File.join(path, child)
    visit(child, full, name_pattern, only_type, min_size, max_size, newer_than_minutes, exec_cmd)

    if Dir.exists?(full) && !File.symlink?(full)
      walk(full, depth + 1, max_depth, name_pattern, only_type, min_size, max_size, newer_than_minutes, exec_cmd)
    end
  end
rescue e
  STDERR.puts "zn: nie można odczytać '#{path}': #{e.message}"
end

roots.each do |root|
  unless Dir.exists?(root) || File.exists?(root)
    STDERR.puts "zn: '#{root}' nie istnieje"
    next
  end
  info = File.info?(root)
  if info
    visit(File.basename(root), root, name_pattern, only_type, min_size, max_size, newer_than_minutes, exec_cmd)
  end
  walk(root, 1, max_depth, name_pattern, only_type, min_size, max_size, newer_than_minutes, exec_cmd) if Dir.exists?(root)
end
