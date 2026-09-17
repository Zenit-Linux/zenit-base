require "option_parser"

# fr — nowoczesna alternatywa dla `head`/`tail` (Zenit Linux, "fragment")
#
# STATUS: tryb head (domyślny) i tryb tail (-t) działają na całym pliku
# wczytanym do pamięci; obsługa wielu plików na raz z nagłówkami
# "==> plik <==" (jak w GNU coreutils). `-f`/`--follow` (jak `tail -f`)
# oparte jest o inotify(7) (IN_MODIFY, budzi proces TYLKO gdy plik
# faktycznie się zmieni, bez pollingu co interwał) i wspiera śledzenie
# WIELU plików naraz jednocześnie (jeden deskryptor inotify, wiele
# watchy — dopisek do dowolnego z nich budzi pętlę i wypisuje tylko
# nowe bajty z WŁAŚCIWEGO pliku, z nagłówkiem przy zmianie źródła).

VERSION = "0.1.0"

lib LibInotify
  fun inotify_init1(flags : LibC::Int) : LibC::Int
  fun inotify_add_watch(fd : LibC::Int, path : LibC::Char*, mask : LibC::UInt) : LibC::Int
end

IN_MODIFY = 0x00000002_u32
# Nagłówek struktury inotify_event to: wd(4) + mask(4) + cookie(4) + len(4),
# po czym następuje `len` bajtów nazwy (dopełnionej zerami) -- patrz inotify(7).
INOTIFY_EVENT_HEADER_SIZE = 16

mode_tail = false
num_lines = 10
follow    = false
files     = [] of String

parser = OptionParser.new do |p|
  p.banner = "fr — nowoczesna alternatywa dla head/tail (Zenit Linux)\n\nUżycie: fr [opcje] [PLIK...]"
  p.on("-t", "--tail", "pokaż koniec pliku zamiast początku") { mode_tail = true }
  p.on("-n NUM", "--lines=NUM", "liczba linii do pokazania (domyślnie 10)") { |v| num_lines = v.to_i }
  p.on("-f", "--follow", "śledź dopisywane linie przez inotify (jak tail -f), wymaga -t") { follow = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu fr") { puts "fr #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

def show_head(lines : Array(String), num : Int32)
  lines.first(num).each { |l| puts l }
end

def show_tail(lines : Array(String), num : Int32)
  start = Math.max(0, lines.size - num)
  lines[start..].each { |l| puts l }
end

def follow_files(paths : Array(String))
  inotify_fd = LibInotify.inotify_init1(0)
  if inotify_fd < 0
    STDERR.puts "fr: inotify_init1 nie powiodło się -- jądro bez wsparcia inotify?"
    exit 1
  end

  wd_to_path = {} of Int32 => String
  last_size  = {} of String => Int64

  paths.each do |path|
    wd = LibInotify.inotify_add_watch(inotify_fd, path.check_no_null_byte, IN_MODIFY)
    if wd < 0
      STDERR.puts "fr: nie można śledzić '#{path}' przez inotify"
      next
    end
    wd_to_path[wd] = path
    last_size[path] = File.size(path)
  end

  if wd_to_path.empty?
    STDERR.puts "fr: żaden plik nie jest śledzony -- kończę"
    exit 1
  end

  last_printed_path = paths.size == 1 ? paths.first : nil
  fd_io = IO::FileDescriptor.new(inotify_fd, blocking: true)
  buf = Bytes.new(4096)

  loop do
    n = fd_io.read(buf)
    break if n == 0
    offset = 0
    while offset + INOTIFY_EVENT_HEADER_SIZE <= n
      wd     = IO::ByteFormat::SystemEndian.decode(Int32, buf[offset, 4])
      len    = IO::ByteFormat::SystemEndian.decode(UInt32, buf[offset + 12, 4])
      offset += INOTIFY_EVENT_HEADER_SIZE + len.to_i32

      path = wd_to_path[wd]?
      next unless path

      current_size = File.size(path)
      prev_size = last_size[path]? || 0_i64
      next if current_size <= prev_size

      if paths.size > 1 && last_printed_path != path
        puts "\n==> #{path} <=="
        last_printed_path = path
      end

      File.open(path) do |io|
        io.seek(prev_size)
        io.each_line { |l| puts l }
      end
      last_size[path] = current_size
    end
  end
end

exit_code = 0

if files.empty?
  content = STDIN.gets_to_end.split('\n')
  content.pop if content.last? == ""
  if mode_tail
    show_tail(content, num_lines)
  else
    show_head(content, num_lines)
  end
elsif follow && mode_tail
  existing = files.select do |f|
    exists = File.exists?(f)
    unless exists
      STDERR.puts "fr: nie można otworzyć '#{f}': nie istnieje"
      exit_code = 1
    end
    exists
  end
  existing.each do |f|
    puts "==> #{f} <==" if existing.size > 1
    show_tail(File.read_lines(f), num_lines)
  end
  follow_files(existing) unless existing.empty? # nie wraca (pętla nieskończona)
else
  files.each do |f|
    unless File.exists?(f)
      STDERR.puts "fr: nie można otworzyć '#{f}': nie istnieje"
      exit_code = 1
      next
    end

    puts "==> #{f} <==" if files.size > 1

    lines = File.read_lines(f)
    if mode_tail
      show_tail(lines, num_lines)
    else
      show_head(lines, num_lines)
    end
  end
end

exit exit_code
