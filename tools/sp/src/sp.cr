require "option_parser"

# sp — nowoczesna alternatywa dla `ls` (Zenith Linux)
#
# STATUS: szkielet — struktura CLI i podstawowe wypisywanie działają,
# reszta oznaczona jako TODO do dopracowania w kolejnych etapach.

VERSION = "1.0.0"

show_all    = false
long_format = false
human_size  = false
sort_time   = false
reverse     = false
paths       = [] of String

parser = OptionParser.new do |p|
  p.banner = "sp — nowoczesna alternatywa dla ls (Zenith Linux)\n\nUżycie: sp [opcje] [ŚCIEŻKA...]"
  p.on("-a", "--all", "pokaż także pliki ukryte") { show_all = true }
  p.on("-l", "--long", "format długi (uprawnienia, właściciel, rozmiar, data)") { long_format = true }
  p.on("-H", "--human", "rozmiary czytelne dla człowieka (KB/MB/GB)") { human_size = true }
  p.on("-t", "--time", "sortuj wg czasu modyfikacji") { sort_time = true }
  p.on("-r", "--reverse", "odwróć kolejność sortowania") { reverse = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu sp") { puts "sp #{VERSION}"; exit 0 }
  p.unknown_args { |args| paths.concat(args) }
end
parser.parse

paths = ["."] if paths.empty?

# TODO: format długi (-l) — właściciel/grupa/uprawnienia przez LibC.stat
# TODO: kolorowanie wg typu pliku (katalog/plik wykonywalny/link symboliczny)
# TODO: sortowanie po rozmiarze (-S) i wg nazwy z uwzględnieniem locale
# TODO: opcja -R (rekurencyjne wypisywanie podkatalogów)

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

def list_dir(path : String, show_all : Bool, long_format : Bool, human_size : Bool,
             sort_time : Bool, reverse : Bool)
  entries = Dir.children(path)
  entries = entries.select { |e| show_all || !e.starts_with?('.') }

  entries = if sort_time
              entries.sort_by { |e| File.info(File.join(path, e)).modification_time }
            else
              entries.sort
            end
  entries = entries.reverse if reverse

  entries.each do |name|
    full = File.join(path, name)
    info = File.info?(full)
    next unless info

    if long_format
      kind = info.directory? ? "d" : (info.symlink? ? "l" : "-")
      size = human_size ? human_readable(info.size.to_i64) : info.size.to_s
      puts "#{kind} #{size.to_s.rjust(8)} #{name}"
    else
      puts name
    end
  end
end

exit_code = 0
paths.each do |path|
  unless Dir.exists?(path) || File.exists?(path)
    STDERR.puts "sp: nie można uzyskać dostępu do '#{path}': nie istnieje"
    exit_code = 1
    next
  end

  if Dir.exists?(path)
    puts "#{path}:" if paths.size > 1
    list_dir(path, show_all, long_format, human_size, sort_time, reverse)
  else
    puts path
  end
end

exit exit_code
