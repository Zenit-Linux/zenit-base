require "option_parser"

VERSION = "1.0.0"

no_create = false
verbose   = false
files     = [] of String

parser = OptionParser.new do |p|
  p.banner = "mk — nowoczesna alternatywa dla touch (Zenith Linux)\n\nUżycie: mk [opcje] PLIK..."
  p.on("-c", "--no-create", "nie twórz pliku, jeśli nie istnieje") { no_create = true }
  p.on("-v", "--verbose", "wypisuj utworzone/zaktualizowane pliki") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu mk") { puts "mk #{VERSION}"; exit 0 }
  p.unknown_args { |args| files.concat(args) }
end
parser.parse

if files.empty?
  STDERR.puts "mk: brak argumentu — podaj nazwę pliku"
  exit 1
end

exit_code = 0
now = Time.utc

files.each do |f|
  just_created = false

  unless File.exists?(f)
    next if no_create
    begin
      File.write(f, "")
      just_created = true
    rescue e
      STDERR.puts "mk: nie można utworzyć '#{f}': #{e.message}"
      exit_code = 1
      next
    end
  end

  begin
    File.utime(now, now, f)
    if verbose
      if just_created
        puts "mk: utworzono plik '#{f}'"
      else
        puts "mk: zaktualizowano znacznik czasu '#{f}'"
      end
    end
  rescue e
    STDERR.puts "mk: błąd aktualizacji czasu '#{f}': #{e.message}"
    exit_code = 1
  end
end

exit exit_code
