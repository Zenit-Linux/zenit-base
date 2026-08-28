require "option_parser"

# du — nowoczesna alternatywa dla `du` (Zenit Linux)
#
# STATUS: szkielet — rekurencyjne sumowanie rozmiarów działa; wykrywanie
# twardych dowiązań (aby nie liczyć tego samego bloku dwukrotnie) i
# wykluczenia wg wzorca (--exclude) to TODO.

VERSION = "0.1.0"

summary_only = false
human_size   = false
max_depth    = nil.as(Int32?)
paths        = [] of String

parser = OptionParser.new do |p|
  p.banner = "du — nowoczesna alternatywa dla du (Zenit Linux)\n\nUżycie: du [opcje] [ŚCIEŻKA...]"
  p.on("-s", "--summary", "pokaż tylko sumę dla każdej podanej ścieżki") { summary_only = true }
  p.on("-H", "--human", "rozmiary czytelne dla człowieka (KB/MB/GB)") { human_size = true }
  p.on("--max-depth N", "maksymalna głębokość wypisywania podkatalogów") { |v| max_depth = v.to_i }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu du") { puts "du #{VERSION}"; exit 0 }
  p.unknown_args { |args| paths.concat(args) }
end
parser.parse

paths = ["."] if paths.empty?

def human_readable(bytes : Int64) : String
  units = {"B", "K", "M", "G", "T"}
  size = bytes.to_f
  idx = 0
  while size >= 1024 && idx < units.size - 1
    size /= 1024
    idx += 1
  end
  "#{size.round(1)}#{units[idx]}"
end

# TODO: pomijanie twardych dowiązań już policzonych (śledzenie inode),
# TODO: --exclude=WZORZEC do pomijania wybranych plików/katalogów.

def dir_size(path : String, depth : Int32, max_depth : Int32?, summary_only : Bool,
             human_size : Bool) : Int64
  total = 0_i64

  begin
    Dir.children(path).each do |child|
      full = File.join(path, child)
      info = File.info?(full, follow_symlinks: false)
      next unless info

      if info.directory?
        total += dir_size(full, depth + 1, max_depth, summary_only, human_size)
      else
        total += info.size
      end
    end
  rescue e
    STDERR.puts "du: nie można odczytać '#{path}': #{e.message}"
  end

  unless summary_only
    if max_depth.nil? || depth <= max_depth
      size_s = human_size ? human_readable(total) : total.to_s
      puts "#{size_s.rjust(10)}  #{path}"
    end
  end

  total
end

paths.each do |path|
  unless Dir.exists?(path)
    STDERR.puts "du: '#{path}' nie jest katalogiem"
    next
  end
  total = dir_size(path, 0, max_depth, summary_only, human_size)
  if summary_only
    size_s = human_size ? human_readable(total) : total.to_s
    puts "#{size_s.rjust(10)}  #{path}"
  end
end
