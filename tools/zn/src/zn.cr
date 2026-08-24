require "option_parser"

# zn — nowoczesna alternatywa dla `find` (Zenith Linux)
#
# STATUS: szkielet — przeszukiwanie po nazwie i typie działa,
# reszta predykatów find(1) to TODO.

VERSION = "1.0.0"

name_pattern = nil.as(String?)
only_type    = nil.as(Char?)
max_depth    = nil.as(Int32?)
roots        = [] of String

parser = OptionParser.new do |p|
  p.banner = "zn — nowoczesna alternatywa dla find (Zenith Linux)\n\nUżycie: zn [ŚCIEŻKA...] [opcje]"
  p.on("--name PATTERN", "dopasuj nazwę pliku (glob, np. '*.txt')") { |v| name_pattern = v }
  p.on("--type TYPE", "f = plik, d = katalog") { |v| only_type = v[0]? }
  p.on("--max-depth N", "maksymalna głębokość przeszukiwania") { |v| max_depth = v.to_i }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu zn") { puts "zn #{VERSION}"; exit 0 }
  p.unknown_args { |args| roots.concat(args) }
end
parser.parse

roots = ["."] if roots.empty?

# TODO: predykaty -mtime/-size/-newer
# TODO: -exec CMD {} \; do uruchamiania poleceń na dopasowaniach
# TODO: podążanie / niepodążanie za linkami symbolicznymi (-L)

def matches?(name : String, full_path : String, name_pattern : String?, only_type : Char?) : Bool
  return false if name_pattern && !File.match?(name_pattern, name)

  if only_type
    is_dir = Dir.exists?(full_path)
    case only_type
    when 'f' then return false if is_dir
    when 'd' then return false unless is_dir
    end
  end

  true
end

def walk(path : String, depth : Int32, max_depth : Int32?, name_pattern : String?, only_type : Char?)
  return if max_depth && depth > max_depth

  Dir.children(path).each do |child|
    full = File.join(path, child)
    puts full if matches?(child, full, name_pattern, only_type)

    if Dir.exists?(full) && !File.symlink?(full)
      walk(full, depth + 1, max_depth, name_pattern, only_type)
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
  puts root if matches?(File.basename(root), root, name_pattern, only_type)
  walk(root, 1, max_depth, name_pattern, only_type) if Dir.exists?(root)
end
