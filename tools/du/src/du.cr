require "option_parser"

# du — nowoczesna alternatywa dla `du` (Zenit Linux)
#
# STATUS: rekurencyjne sumowanie rozmiarów, wykrywanie twardych dowiązań
# (żeby nie liczyć tego samego bloku dwukrotnie, śledzone po parze
# urządzenie+inode) i --exclude=WZORZEC (dopasowanie glob, można podać
# wielokrotnie) do pomijania wybranych plików/katalogów.

VERSION = "0.1.0"

summary_only = false
human_size   = false
max_depth    = nil.as(Int32?)
exclude_patterns = [] of String
paths        = [] of String

parser = OptionParser.new do |p|
  p.banner = "du — nowoczesna alternatywa dla du (Zenit Linux)\n\nUżycie: du [opcje] [ŚCIEŻKA...]"
  p.on("-s", "--summary", "pokaż tylko sumę dla każdej podanej ścieżki") { summary_only = true }
  p.on("-H", "--human", "rozmiary czytelne dla człowieka (KB/MB/GB)") { human_size = true }
  p.on("--max-depth N", "maksymalna głębokość wypisywania podkatalogów") { |v| max_depth = v.to_i }
  p.on("--exclude=WZORZEC", "pomiń pliki/katalogi pasujące do wzorca glob (można podać wielokrotnie)") { |v| exclude_patterns << v }
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

def excluded?(path : String, name : String, patterns : Array(String)) : Bool
  patterns.any? { |pat| File.match?(pat, name) || File.match?(pat, path) }
end

# Śledzi (dev, inode) plików o więcej niż jednym twardym dowiązaniu, żeby
# policzyć ich rozmiar TYLKO RAZ -- inaczej `du` zawyżałby wynik dla
# katalogów zawierających wiele twardych dowiązań do tego samego pliku
# (rzeczywisty rozmiar na dysku jest zajęty raz, niezależnie od liczby
# nazw wskazujących na ten sam inode).
seen_inodes = Set(String).new

def dir_size(path : String, depth : Int32, max_depth : Int32?, summary_only : Bool,
             human_size : Bool, exclude_patterns : Array(String), seen_inodes : Set(String)) : Int64
  total = 0_i64

  begin
    Dir.children(path).each do |child|
      full = File.join(path, child)
      next if excluded?(full, child, exclude_patterns)

      info = File.info?(full, follow_symlinks: false)
      next unless info

      if info.directory?
        total += dir_size(full, depth + 1, max_depth, summary_only, human_size, exclude_patterns, seen_inodes)
      elsif LibC.lstat(full.check_no_null_byte, out st) == 0 && st.st_nlink > 1
        key = "#{st.st_dev}:#{st.st_ino}"
        total += info.size unless seen_inodes.includes?(key)
        seen_inodes << key
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
  total = dir_size(path, 0, max_depth, summary_only, human_size, exclude_patterns, seen_inodes)
  if summary_only
    size_s = human_size ? human_readable(total) : total.to_s
    puts "#{size_s.rjust(10)}  #{path}"
  end
end
