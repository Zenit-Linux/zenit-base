require "option_parser"

# sp — nowoczesna alternatywa dla `ls` (Zenit Linux)
#
# STATUS: kolorowanie wg typu pliku, rekurencyjne wypisywanie (-R),
# sortowanie po rozmiarze (-S), PRAWDZIWY format długi z właścicielem/
# grupą (LibC.getpwuid/getgrgid — Crystal nie udostępnia tego w stdlib,
# stąd bezpośredni binding) i pełnymi uprawnieniami w stylu `rwxr-xr-x`,
# oraz sortowanie nazw ignorujące wielkość liter (case-insensitive —
# UWAGA: to NIE jest pełna kolacja locale/ICU, tylko praktyczne
# przybliżenie najczęstszej skargi na sortowanie "ASCII-owe", gdzie
# wielkie litery ('Z') sortują się PRZED wszystkimi małymi ('a') —
# prawdziwe reguły locale, np. dla znaków diakrytycznych, wymagałyby
# biblioteki ICU, której Crystal nie ma w stdlib).

VERSION = "0.1.0"

lib LibPw
  struct Passwd
    pw_name   : LibC::Char*
    pw_passwd : LibC::Char*
    pw_uid    : LibC::UidT
    pw_gid    : LibC::GidT
    pw_gecos  : LibC::Char*
    pw_dir    : LibC::Char*
    pw_shell  : LibC::Char*
  end
  fun getpwuid(uid : LibC::UidT) : Passwd*
end

lib LibGr
  struct Group
    gr_name   : LibC::Char*
    gr_passwd : LibC::Char*
    gr_gid    : LibC::GidT
    gr_mem    : LibC::Char**
  end
  fun getgrgid(gid : LibC::GidT) : Group*
end

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
  p.on("-l", "--long", "format długi (uprawnienia, właściciel, grupa, rozmiar, data)") { long_format = true }
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

owner_cache = {} of UInt32 => String
group_cache = {} of UInt32 => String

def owner_name(uid_str : String, cache : Hash(UInt32, String)) : String
  uid = uid_str.to_u32?
  return uid_str unless uid
  cache.fetch(uid) do
    pw = LibPw.getpwuid(uid)
    name = pw.null? ? uid_str : String.new(pw.value.pw_name)
    cache[uid] = name
    name
  end
end

def group_name(gid_str : String, cache : Hash(UInt32, String)) : String
  gid = gid_str.to_u32?
  return gid_str unless gid
  cache.fetch(gid) do
    gr = LibGr.getgrgid(gid)
    name = gr.null? ? gid_str : String.new(gr.value.gr_name)
    cache[gid] = name
    name
  end
end

# Format `rwxr-xr-x` (bez ósemkowego sufiksu, w odróżnieniu od
# File::Permissions#to_s wbudowanego w Crystal) plus litera typu pliku
# na początku -- dokładnie tak, jak pierwsza kolumna `ls -l`.
def mode_string(info : File::Info) : String
  perm = info.permissions
  type_char = info.directory? ? 'd' : (info.symlink? ? 'l' : '-')
  String.build do |s|
    s << type_char
    s << (perm.owner_read? ? 'r' : '-')
    s << (perm.owner_write? ? 'w' : '-')
    s << (perm.owner_execute? ? 'x' : '-')
    s << (perm.group_read? ? 'r' : '-')
    s << (perm.group_write? ? 'w' : '-')
    s << (perm.group_execute? ? 'x' : '-')
    s << (perm.other_read? ? 'r' : '-')
    s << (perm.other_write? ? 'w' : '-')
    s << (perm.other_execute? ? 'x' : '-')
  end
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
              # Sortowanie ignorujące wielkość liter jako klucz PIERWOTNY,
              # z oryginalną nazwą jako rozstrzygnięcie remisu (stabilne,
              # deterministyczne dla np. "Foo" i "foo" współistniejących
              # w tym samym katalogu).
              entries.sort_by { |e| {e.downcase, e} }
            end

  entries = entries.reverse if reverse
  entries
end

def list_dir(path : String, show_all : Bool, long_format : Bool, human_size : Bool,
             sort_time : Bool, sort_size : Bool, reverse : Bool, recursive : Bool,
             use_color : Bool, owner_cache : Hash(UInt32, String), group_cache : Hash(UInt32, String))
  entries = sorted_entries(path, Dir.children(path), show_all, sort_time, sort_size, reverse)
  subdirs = [] of String

  entries.each do |name|
    full = File.join(path, name)
    info = File.info?(full)
    next unless info

    subdirs << full if recursive && info.directory? && name != "." && name != ".."

    display_name = colorize(name, info, use_color)

    if long_format
      size = human_size ? human_readable(info.size.to_i64) : info.size.to_s
      owner = owner_name(info.owner_id, owner_cache)
      group = group_name(info.group_id, group_cache)
      puts "#{mode_string(info)} #{owner.ljust(8)} #{group.ljust(8)} #{size.to_s.rjust(8)} #{display_name}"
    else
      puts display_name
    end
  end

  subdirs.each do |subdir|
    puts "\n#{subdir}:"
    list_dir(subdir, show_all, long_format, human_size, sort_time, sort_size, reverse, recursive, use_color, owner_cache, group_cache)
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
    list_dir(path, show_all, long_format, human_size, sort_time, sort_size, reverse, recursive, use_color, owner_cache, group_cache)
  else
    puts path
  end
end

exit exit_code
