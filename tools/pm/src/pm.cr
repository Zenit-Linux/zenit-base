require "option_parser"

VERSION = "1.0.0"

recursive = false
verbose   = false

parser = OptionParser.new do |p|
  p.banner = "pm — nowoczesna alternatywa dla chmod (Zenith Linux)\n\nUżycie: pm [opcje] TRYB ŚCIEŻKA..."
  p.on("-R", "--recursive", "działaj rekurencyjnie na katalogach") { recursive = true }
  p.on("-v", "--verbose", "wypisuj każdą zmianę") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu pm") { puts "pm #{VERSION}"; exit 0 }
end
parser.parse

args = ARGV
if args.size < 2
  STDERR.puts "pm: wymagane argumenty: TRYB ŚCIEŻKA..."
  exit 1
end

mode_spec = args[0]
paths = args[1..]

# Zwraca nowy tryb uprawnień (LibC::ModeT) na podstawie bieżącego trybu i specyfikacji.
def compute_mode(current : Int32, spec : String) : Int32
  if spec =~ /\A[0-7]{3,4}\z/
    return spec.to_i(base: 8)
  end

  mode = current
  spec.split(',').each do |clause|
    clause = clause.strip
    next if clause.empty?

    m = clause.match(/\A([ugoa]*)([+\-=])([rwx]*)\z/)
    unless m
      STDERR.puts "pm: nieprawidłowy tryb symboliczny '#{clause}'"
      exit 1
    end

    who  = m[1].empty? ? "a" : m[1]
    op   = m[2]
    bits = m[3]

    targets = [] of Char
    who.each_char { |c| targets << c }
    targets = ['u', 'g', 'o'] if targets.includes?('a') || targets.empty?

    bitval = 0
    bitval |= 0o4 if bits.includes?('r')
    bitval |= 0o2 if bits.includes?('w')
    bitval |= 0o1 if bits.includes?('x')

    targets.each do |t|
      shift = case t
              when 'u' then 6
              when 'g' then 3
              when 'o' then 0
              else 0
              end
      mask = 0o7 << shift
      value = bitval << shift

      case op
      when "+"
        mode |= value
      when "-"
        mode &= ~value
      when "="
        mode = (mode & ~mask) | value
      end
    end
  end

  mode
end

def chmod_path(path : String, mode_spec : String, recursive : Bool, verbose : Bool)
  unless info = File.info?(path)
    STDERR.puts "pm: nie można uzyskać dostępu do '#{path}'"
    return
  end

  current = info.permissions.value.to_i32
  new_mode = compute_mode(current, mode_spec)

  if LibC.chmod(path, LibC::ModeT.new(new_mode)) != 0
    STDERR.puts "pm: nie można zmienić uprawnień '#{path}'"
  elsif verbose
    puts "pm: zmieniono uprawnienia '#{path}' na #{new_mode.to_s(8)}"
  end

  if recursive && Dir.exists?(path) && !File.symlink?(path)
    Dir.children(path).each do |child|
      chmod_path(File.join(path, child), mode_spec, recursive, verbose)
    end
  end
end

paths.each do |path|
  chmod_path(path, mode_spec, recursive, verbose)
end
