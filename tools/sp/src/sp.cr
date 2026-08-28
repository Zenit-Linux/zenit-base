require "option_parser"

# sp — nowoczesna alternatywa dla `ls` (Zenit Linux)
#
# STATUS: rozbudowany szkielet — dodano kolorowanie wg typu pliku,
# rekurencyjne wypisywanie (-R) i sortowanie po rozmiarze (-S).
# Format długi z właścicielem/grupą (wymaga wywołań LibC getpwuid/getgrgid)
# oraz locale-aware sortowanie nazw pozostają jako TODO.

VERSION = "0.1.0"

show_all    = false
long_format = false
human_size  = false
sort_time   = false
sort_size   = false
reverse     = false
recursive   = false
no_color    = false
paths       = [] of String

parser = OptionParser.new do |p|
  p.banner = "sp — nowoczesna alternatywa dla ls (Zenit Linux)\n\nUżycie: sp [opcje] [ŚCIEŻKA...]"
  p.on("-a", "--all", "pokaż także pliki ukryte") { show_all = true }
  p.on("-l", "--long", "format długi (typ, rozmiar, data)") { long_format = true }
  p.on("-H", "--human", "rozmiary czytelne dla człowieka (KB/MB/GB)") { human_size = true }
  p.on("-t", "--time", "sortuj wg czasu modyfikacji") { sort_time = true }
  p.on("-S", "--size", "sortuj wg rozmiaru (od największego)") { sort_size = true }
  p.on("-r", "--reverse", "odwróć kolejność sortowania") { reverse = true }
  p.on("-R", "--recursive", "wypisz zawartość podkatalogów rekurencyjnie") { recursive = true }
  p.on("--no-color", "wyłącz kolorowanie wyjścia") { no_color = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu sp") { puts "sp #{VERSION}"; exit 0 }
  p.unknown_args { |args| paths.concat(args) }
end
parser.parse

paths = ["."] if paths.empty?
use_color = !no_color && STDOUT.tty?

# TODO: format długi z właścicielem/grupą — wymaga LibC.getpwuid/getgrgid,
# których Crystal nie udostępnia bezpośrednio w stdlib bez własnych bindingów.
# TODO: sortowanie nazw z uwzględnieniem locale (obecnie proste String#<=>).

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

# Kolorowanie wg typu pliku, w stylu klasycznego `ls --color`:
#   katalog = niebieski, link symboliczny = cyan, wykonywalny = zielony.
def colorize(name : String, info : File::Info, use_color : Bool) : String
  return name unless use_color

  if info.symlink?
    "\e[36m#{name}\e[0m"
  elsif info.directory?
    "\e[1;34m#{name}\e[0m"
  elsif (info.permissions.value & 0o111) != 0
    "\e[1;32m#{name}\e[0m"
  else
    name
  end
end

def sorted_entries(path : String, entries : Array(String), show_all : Bool,
                    sort_time : Bool, sort_size : Bool, reverse : Bool) : Array(String)
  entries = entries.select { |e| show_all || !e.starts_with?('.') }

  entries = if sort_time
              entries.sort_by { |e| File.info(File.join(path, e)).modification_time }.reverse
            elsif sort_size
              entries.sort_by { |e| File.info(File.join(path, e)).size }.reverse
            else
              entries.sort
            end

  entries = entries.reverse if reverse
  entries
end

def list_dir(path : String, show_all : Bool, long_format : Bool, human_size : Bool,
             sort_time : Bool, sort_size : Bool, reverse : Bool, recursive : Bool,
             use_color : Bool)
  entries = sorted_entries(path, Dir.children(path), show_all, sort_time, sort_size, reverse)
  subdirs = [] of String

  entries.each do |name|
    full = File.join(path, name)
    info = File.info?(full)
    next unless info

    subdirs << full if recursive && info.directory? && name != "." && name != ".."

    display_name = colorize(name, info, use_color)

    if long_format
      kind = info.directory? ? "d" : (info.symlink? ? "l" : "-")
      size = human_size ? human_readable(info.size.to_i64) : info.size.to_s
      puts "#{kind} #{size.to_s.rjust(8)} #{display_name}"
    else
      puts display_name
    end
  end

  subdirs.each do |subdir|
    puts "\n#{subdir}:"
    list_dir(subdir, show_all, long_format, human_size, sort_time, sort_size, reverse, recursive, use_color)
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
    list_dir(path, show_all, long_format, human_size, sort_time, sort_size, reverse, recursive, use_color)
  else
    puts path
  end
end

exit exit_code
