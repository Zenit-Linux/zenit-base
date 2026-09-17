require "option_parser"
require "compress/gzip"
require "./ustar"

# ar — nowoczesna alternatywa dla `tar` (Zenit Linux, "archiwizuj")
#
# STATUS: używa prawdziwego formatu POSIX ustar (ustar.cr), więc archiwa
# utworzone przez `ar -c` da się rozpakować zwykłym `tar -xf` (GNU tar /
# bsdtar) i na odwrót. Ścieżki dłuższe niż mieści klasyczny ustar (>256 B
# łącznie prefix+name) są obsługiwane przez rozszerzenie GNU @LongLink
# (ten sam mechanizm co prawdziwy GNU tar — blok typu 'L' niosący pełną
# ścieżkę przed właściwym nagłówkiem), więc archiwa z bardzo długimi
# ścieżkami są w pełni wymienne z GNU tar/bsdtar w OBIE strony. Obsługuje
# też `-z` (gzip, jak `tar czf`/`tar xzf`) przez wbudowany moduł
# `compress/gzip` z biblioteki standardowej Crystala. Zachowanie
# uprawnień/właściciela poza samym trybem pliku i linki symboliczne
# pozostają jako TODO.

VERSION = "0.1.0"

enum Mode
  Create
  Extract
  List
end

mode    = Mode::List
archive = nil.as(String?)
inputs  = [] of String
verbose = false
gzip    = false

parser = OptionParser.new do |p|
  p.banner = "ar — nowoczesna alternatywa dla tar (Zenit Linux)\n\nUżycie:\n  ar -c[z] -f ARCHIWUM PLIK/KATALOG...   (utwórz)\n  ar -x[z] -f ARCHIWUM                    (rozpakuj do bieżącego katalogu)\n  ar -t[z] -f ARCHIWUM                    (wypisz zawartość)"
  p.on("-c", "--create", "utwórz nowe archiwum") { mode = Mode::Create }
  p.on("-x", "--extract", "rozpakuj archiwum") { mode = Mode::Extract }
  p.on("-t", "--list", "wypisz zawartość archiwum") { mode = Mode::List }
  p.on("-z", "--gzip", "kompresja/dekompresja gzip (jak tar -z)") { gzip = true }
  p.on("-f ARCHIWUM", "--file=ARCHIWUM", "ścieżka pliku archiwum") { |v| archive = v }
  p.on("-v", "--verbose", "wypisuj przetwarzane pliki") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu ar") { puts "ar #{VERSION}"; exit 0 }
  p.unknown_args { |args| inputs.concat(args) }
end
parser.parse

unless archive
  STDERR.puts "ar: brak -f ARCHIWUM"
  exit 1
end
archive_path = archive.not_nil!

# Auto-detekcja -z po rozszerzeniu, tak jak robi to GNU tar dla .tgz/.tar.gz.
gzip ||= archive_path.ends_with?(".gz") || archive_path.ends_with?(".tgz")

def collect_files(path : String) : Array(String)
  result = [] of String
  if File.file?(path)
    result << path
  elsif Dir.exists?(path)
    Dir.glob(File.join(path, "**", "*")).each do |entry|
      result << entry if File.file?(entry)
    end
  end
  result
end

def write_entries(io : IO, inputs : Array(String), verbose : Bool)
  inputs.each do |input|
    collect_files(input).each do |full_path|
      # Bezpieczeństwo: tak jak prawdziwy tar (domyślnie), usuwamy wiodący
      # '/' ze ścieżki zapisywanej w archiwum — bez tego rozpakowanie
      # archiwum ze ścieżkami bezwzględnymi nadpisywałoby pliki GDZIEKOLWIEK
      # w systemie, ignorując katalog docelowy rozpakowania.
      stored_name = full_path.starts_with?("/") ? full_path[1..] : full_path

      puts "a #{stored_name}" if verbose

      content = File.read(full_path)
      mode = File.info(full_path).permissions.value.to_i32
      header = Ustar.build_entry_headers(stored_name, content.bytesize.to_u64, mode, Ustar::TYPE_REGULAR)

      io.write(header)
      io.write(content.to_slice)

      # Wyrównanie zawartości do wielokrotności 512 B, zgodnie z ustar.
      padding = (Ustar::BLOCK_SIZE - (content.bytesize % Ustar::BLOCK_SIZE)) % Ustar::BLOCK_SIZE
      io.write(Bytes.new(padding, 0_u8)) if padding > 0
    end
  end

  # Archiwum ustar kończy się dwoma pustymi (samymi zerami) blokami 512 B.
  io.write(Bytes.new(Ustar::BLOCK_SIZE * 2, 0_u8))
end

def each_entry(io : IO)
  pending_long_name = nil.as(String?)

  loop do
    block = Bytes.new(Ustar::BLOCK_SIZE)
    read = io.read_fully?(block)
    break if read.nil?

    header = Ustar.parse_header(block)
    break if header.nil? # blok samych zer -> koniec archiwum

    total_blocks = Ustar.blocks_for(header.size)
    raw = Bytes.new((total_blocks * Ustar::BLOCK_SIZE).to_i32)
    io.read_fully(raw)
    content = raw[0, header.size.to_i32]

    if header.typeflag == Ustar::TYPE_GNU_LONGLINK
      # Ten blok NIE jest prawdziwym wpisem — jego "zawartość" to pełna
      # ścieżka (zakończona NUL) dla NASTĘPNEGO nagłówka, który przyjdzie
      # zaraz po nim (patrz Ustar.build_entry_headers po stronie zapisu).
      nul_idx = content.index(0_u8) || content.size
      pending_long_name = String.new(content[0, nul_idx])
      next
    end

    real_name = pending_long_name || header.name
    pending_long_name = nil

    yield Ustar::ParsedHeader.new(real_name, header.size, header.mode, header.typeflag), content
  end
end

case mode
when Mode::Create
  if inputs.empty?
    STDERR.puts "ar: brak plików do zarchiwizowania"
    exit 1
  end

  File.open(archive_path, "w") do |file_io|
    if gzip
      Compress::Gzip::Writer.open(file_io) do |gz|
        write_entries(gz, inputs, verbose)
      end
    else
      write_entries(file_io, inputs, verbose)
    end
  end

when Mode::List, Mode::Extract
  unless File.exists?(archive_path)
    STDERR.puts "ar: nie można otworzyć archiwum '#{archive_path}'"
    exit 1
  end

  File.open(archive_path, "r") do |file_io|
    reader = gzip ? Compress::Gzip::Reader.new(file_io) : file_io

    each_entry(reader) do |header, content|
      if mode == Mode::List
        kind = header.typeflag == Ustar::TYPE_DIRECTORY ? "d" : "-"
        puts "#{kind} #{header.size.to_s.rjust(10)}  #{header.name}"
      else
        # Bezpieczeństwo: odrzucamy wpisy próbujące wyjść poza katalog
        # docelowy przez "../" (path traversal) — tak jak robi to
        # domyślnie GNU tar dla archiwów z niezaufanych źródeł.
        if header.name.starts_with?("/") || header.name.split('/').includes?("..")
          STDERR.puts "ar: pomijam niebezpieczny wpis '#{header.name}' (ścieżka bezwzględna lub '..')"
          next
        end

        puts "x #{header.name}" if verbose
        if header.typeflag == Ustar::TYPE_DIRECTORY
          Dir.mkdir_p(header.name) unless Dir.exists?(header.name)
        else
          dir = File.dirname(header.name)
          Dir.mkdir_p(dir) unless dir.empty? || dir == "." || Dir.exists?(dir)
          File.write(header.name, content)
          File.chmod(header.name, header.mode) if header.mode > 0
        end
      end
    end

    reader.close if gzip
  end
end
