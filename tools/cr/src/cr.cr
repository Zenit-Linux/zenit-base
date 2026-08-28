require "option_parser"

VERSION = "0.1.0"

parents = false
verbose = false
mode    = ""
dirs    = [] of String

parser = OptionParser.new do |p|
  p.banner = "cr — nowoczesna alternatywa dla mkdir (Zenit Linux)\n\nUżycie: cr [opcje] KATALOG..."
  p.on("-p", "--parents", "twórz katalogi nadrzędne w razie potrzeby") { parents = true }
  p.on("-m MODE", "--mode=MODE", "ustaw uprawnienia (np. 755)") { |v| mode = v }
  p.on("-v", "--verbose", "wypisuj utworzone katalogi") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu cr") { puts "cr #{VERSION}"; exit 0 }
  p.unknown_args { |args| dirs.concat(args) }
end
parser.parse

if dirs.empty?
  STDERR.puts "cr: brak argumentu — podaj nazwę katalogu"
  exit 1
end

exit_code = 0

def create_parents(path : String)
  parent = File.dirname(path)
  return if parent.empty? || parent == "." || Dir.exists?(parent)
  create_parents(parent)
  Dir.mkdir(parent) unless Dir.exists?(parent)
end

dirs.each do |d|
  begin
    parent = File.dirname(d)
    if !parents && !parent.empty? && parent != "." && !Dir.exists?(parent)
      raise "katalog nadrzędny nie istnieje (użyj -p, aby go utworzyć)"
    end

    create_parents(d) if parents
    Dir.mkdir(d) unless Dir.exists?(d)

    unless mode.empty?
      begin
        m = mode.to_i(base: 8)
        File.chmod(d, m)
      rescue ArgumentError
        STDERR.puts "cr: nieprawidłowy tryb uprawnień '#{mode}'"
        exit_code = 1
      end
    end

    puts "cr: utworzono katalog '#{d}'" if verbose
  rescue e
    STDERR.puts "cr: nie można utworzyć katalogu '#{d}': #{e.message}"
    exit_code = 1
  end
end

exit exit_code
