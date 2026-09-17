require "process"

# zn — nowoczesna alternatywa dla `find` (Zenit Linux)
#
# STATUS: --exec, filtry --min-size/--max-size/--newer-than, PRAWDZIWE
# predykaty logiczne (-not/-and/-or, z poprawnym pierwszeństwem: -not
# wiąże najmocniej, potem -and, potem -or -- dokładnie jak w GNU find) i
# -L (podążanie za linkami symbolicznymi przy przechodzeniu katalogów, z
# ochroną przed nieskończoną pętlą przy cyklu dowiązań przez śledzenie
# odwiedzonych ścieżek rzeczywistych).
#
# Ponieważ kolejność predykatów i operatorów (-and/-or/-not) ma znaczenie
# (w odróżnieniu od zwykłych, niezależnych od siebie flag), ten plik
# parsuje ARGV RĘCZNIE zamiast przez OptionParser -- OptionParser nie
# zachowuje kolejności wywołań różnych `.on(...)` względem siebie, więc
# nie dałoby się nim zbudować drzewa wyrażenia.

VERSION = "0.1.0"

alias Predicate = Proc(String, String, File::Info, Bool)

enum TokKind
  Pred
  And
  Or
  Not
end

record Tok, kind : TokKind, pred : Predicate?

def make_name_pred(pattern : String) : Predicate
  ->(name : String, full : String, info : File::Info) { File.match?(pattern, name) }
end

def make_type_pred(t : Char) : Predicate
  ->(name : String, full : String, info : File::Info) do
    case t
    when 'f' then !info.directory?
    when 'd' then info.directory?
    else true
    end
  end
end

def make_min_size_pred(n : Int64) : Predicate
  ->(name : String, full : String, info : File::Info) { info.size >= n }
end

def make_max_size_pred(n : Int64) : Predicate
  ->(name : String, full : String, info : File::Info) { info.size <= n }
end

def make_newer_than_pred(minutes : Int32) : Predicate
  cutoff = Time.utc - Time::Span.new(minutes: minutes)
  ->(name : String, full : String, info : File::Info) { info.modification_time >= cutoff }
end

# --- parser wyrażenia predykatów (rekurencyjne zstępowanie) -------------
# Pierwszeństwo (najmocniejsze na dole, jak w GNU find):  -or < -and < -not
# `pos` to indeks przekazywany przez referencję (Array jednoelementowa,
# bo Crystal nie ma `inout`/`ref` dla zmiennych lokalnych w blokach).

def parse_unary(tokens : Array(Tok), pos : Array(Int32)) : Predicate
  if pos[0] >= tokens.size
    return ->(n : String, f : String, i : File::Info) { true }
  end

  tok = tokens[pos[0]]
  case tok.kind
  when TokKind::Not
    pos[0] += 1
    inner = parse_unary(tokens, pos)
    ->(n : String, f : String, i : File::Info) { !inner.call(n, f, i) }
  when TokKind::Pred
    pos[0] += 1
    tok.pred.not_nil!
  else
    ->(n : String, f : String, i : File::Info) { true } # operator w nieoczekiwanym miejscu -- ignoruj
  end
end

def parse_and(tokens : Array(Tok), pos : Array(Int32)) : Predicate
  left = parse_unary(tokens, pos)
  while pos[0] < tokens.size && tokens[pos[0]].kind.in?(TokKind::And, TokKind::Pred, TokKind::Not)
    pos[0] += 1 if tokens[pos[0]].kind == TokKind::And
    right = parse_unary(tokens, pos)
    l = left
    left = ->(n : String, f : String, i : File::Info) { l.call(n, f, i) && right.call(n, f, i) }
  end
  left
end

def parse_or(tokens : Array(Tok), pos : Array(Int32)) : Predicate
  left = parse_and(tokens, pos)
  while pos[0] < tokens.size && tokens[pos[0]].kind == TokKind::Or
    pos[0] += 1
    right = parse_and(tokens, pos)
    l = left
    left = ->(n : String, f : String, i : File::Info) { l.call(n, f, i) || right.call(n, f, i) }
  end
  left
end

# --- parsowanie ARGV -----------------------------------------------------

max_depth          = nil.as(Int32?)
exec_cmd           = nil.as(Array(String)?)
follow_symlinks    = false
roots              = [] of String
tokens             = [] of Tok

args = ARGV.to_a
i = 0
while i < args.size
  a = args[i]
  case a
  when "--name"
    i += 1
    tokens << Tok.new(TokKind::Pred, make_name_pred(args[i]))
  when "--type"
    i += 1
    t = args[i][0]?
    tokens << Tok.new(TokKind::Pred, make_type_pred(t)) if t
  when "--min-size"
    i += 1
    tokens << Tok.new(TokKind::Pred, make_min_size_pred(args[i].to_i64))
  when "--max-size"
    i += 1
    tokens << Tok.new(TokKind::Pred, make_max_size_pred(args[i].to_i64))
  when "--newer-than"
    i += 1
    tokens << Tok.new(TokKind::Pred, make_newer_than_pred(args[i].to_i))
  when "-and", "-a"
    tokens << Tok.new(TokKind::And, nil)
  when "-or", "-o"
    tokens << Tok.new(TokKind::Or, nil)
  when "-not", "!"
    tokens << Tok.new(TokKind::Not, nil)
  when "--max-depth"
    i += 1
    max_depth = args[i].to_i
  when "-L"
    follow_symlinks = true
  when "--exec"
    i += 1
    cmd = [] of String
    while i < args.size && args[i] != ";"
      cmd << args[i]
      i += 1
    end
    exec_cmd = cmd
  when "-h", "--help"
    puts "zn — nowoczesna alternatywa dla find (Zenit Linux)"
    puts
    puts "Użycie: zn [ŚCIEŻKA...] [WYRAŻENIE]"
    puts
    puts "Predykaty: --name WZORZEC, --type f|d, --min-size B, --max-size B, --newer-than MIN"
    puts "Operatory: -and (-a, domyślny między predykatami), -or (-o), -not (!)"
    puts "Inne: --max-depth N, --exec POLECENIE [;], -L (podążaj za linkami symbolicznymi)"
    exit 0
  when "--version"
    puts "zn #{VERSION}"
    exit 0
  else
    roots << a
  end
  i += 1
end

roots = ["."] if roots.empty?

pos = [0]
matcher = tokens.empty? ? ->(n : String, f : String, i : File::Info) { true } : parse_or(tokens, pos)

def run_exec(cmd_template : Array(String), path : String)
  cmd = cmd_template.map { |arg| arg == "{}" ? path : arg }
  return if cmd.empty?
  status = Process.run(cmd[0], args: cmd[1..], output: STDOUT, error: STDERR)
  unless status.success?
    STDERR.puts "zn: polecenie zakończone kodem #{status.exit_code} dla '#{path}'"
  end
end

def visit(name : String, full_path : String, matcher : Predicate, exec_cmd : Array(String)?)
  info = File.info?(full_path, follow_symlinks: false)
  return unless info
  return unless matcher.call(name, full_path, info)

  if exec_cmd
    run_exec(exec_cmd, full_path)
  else
    puts full_path
  end
end

# `visited` śledzi ŚCIEŻKI RZECZYWISTE (po rozwinięciu WSZYSTKICH
# dowiązań, `File.realpath`) katalogów już odwiedzonych -- niezbędne przy
# -L, gdzie cykl dowiązań symbolicznych (np. katalog zawierający
# dowiązanie do samego siebie albo do swojego przodka) inaczej wywołałby
# nieskończoną rekurencję.
def walk(path : String, depth : Int32, max_depth : Int32?, matcher : Predicate,
          exec_cmd : Array(String)?, follow_symlinks : Bool, visited : Set(String))
  return if max_depth && depth > max_depth

  Dir.children(path).each do |child|
    full = File.join(path, child)
    info = File.info?(full, follow_symlinks: false)
    next unless info

    visit(child, full, matcher, exec_cmd)

    is_symlink = info.symlink?
    should_descend = if is_symlink
                        follow_symlinks && Dir.exists?(full) # Dir.exists? podąża za linkiem, sprawdzając CEL
                      else
                        info.directory?
                      end

    if should_descend
      real = (File.realpath(full) rescue full)
      next if visited.includes?(real)
      visited << real
      walk(full, depth + 1, max_depth, matcher, exec_cmd, follow_symlinks, visited)
    end
  end
rescue e
  STDERR.puts "zn: nie można odczytać '#{path}': #{e.message}"
end

roots.each do |root|
  unless Dir.exists?(root) || File.exists?(root)
    STDERR.puts "zn: '#{root}' nie istnieje"
    next
  end
  info = File.info?(root)
  visit(File.basename(root), root, matcher, exec_cmd) if info

  if Dir.exists?(root)
    visited = Set(String).new
    visited << (File.realpath(root) rescue root)
    walk(root, 1, max_depth, matcher, exec_cmd, follow_symlinks, visited)
  end
end
