require "option_parser"

# pr — nowoczesna alternatywa dla `ps` (Zenit Linux, "procesy")
#
# STATUS: czyta /proc i wypisuje informacje o procesach; filtrowanie po
# użytkowniku (-u), drzewo procesów (--tree, po PPid z /proc/[pid]/status)
# i sortowanie po zużyciu CPU/pamięci (--sort=cpu|mem, z pól utime+stime
# i VmRSS) są zaimplementowane.

VERSION = "0.1.0"

show_all   = false
user_filter = nil.as(String?)
tree_mode  = false
sort_by    = nil.as(String?)

parser = OptionParser.new do |p|
  p.banner = "pr — nowoczesna alternatywa dla ps (Zenit Linux)\n\nUżycie: pr [opcje]"
  p.on("-a", "--all", "pokaż procesy wszystkich użytkowników") { show_all = true }
  p.on("-u UŻYTKOWNIK", "--user=UŻYTKOWNIK", "pokaż tylko procesy danego użytkownika") { |v| user_filter = v }
  p.on("--tree", "pokaż procesy jako drzewo (wg procesu rodzica)") { tree_mode = true }
  p.on("--sort=KLUCZ", "sortuj po 'cpu' albo 'mem' (malejąco) zamiast po PID") { |v| sort_by = v }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu pr") { puts "pr #{VERSION}"; exit 0 }
end
parser.parse

struct ProcInfo
  getter pid : Int32
  getter ppid : Int32
  getter comm : String
  getter state : String
  getter uid : Int32
  getter rss_kb : Int64
  getter cpu_ticks : Int64

  def initialize(@pid : Int32, @ppid : Int32, @comm : String, @state : String,
                 @uid : Int32, @rss_kb : Int64, @cpu_ticks : Int64)
  end
end

def read_uid_map : Hash(String, Int32)
  # Mapa nazwa_użytkownika -> UID, z /etc/passwd (format: name:pass:uid:gid:...).
  result = {} of String => Int32
  return result unless File.exists?("/etc/passwd")
  File.each_line("/etc/passwd") do |line|
    fields = line.split(':')
    next if fields.size < 3
    uid = fields[2].to_i?
    result[fields[0]] = uid if uid
  end
  result
end

def read_status_fields(pid : Int32) : {Int32, Int64}
  # Zwraca (UID rzeczywisty, VmRSS w KiB) z /proc/[pid]/status.
  uid = -1
  rss = 0_i64
  status_path = "/proc/#{pid}/status"
  return {uid, rss} unless File.exists?(status_path)
  File.each_line(status_path) do |line|
    if line.starts_with?("Uid:")
      parts = line.split(/\s+/)
      uid = parts[1].to_i? || -1 if parts.size > 1
    elsif line.starts_with?("VmRSS:")
      parts = line.split(/\s+/)
      rss = parts[1].to_i64? || 0_i64 if parts.size > 1
    end
  end
  {uid, rss}
end

def read_proc_entries : Array(ProcInfo)
  result = [] of ProcInfo
  return result unless Dir.exists?("/proc")

  Dir.children("/proc").each do |entry|
    next unless entry =~ /\A\d+\z/
    pid = entry.to_i
    stat_path = "/proc/#{entry}/stat"
    next unless File.exists?(stat_path)

    begin
      content = File.read(stat_path)
      # Format: PID (COMM) STAN PPID ... UTIME STIME ...  -- COMM może w
      # zasadzie zawierać dowolne znaki (nawet nawiasy), więc szukamy
      # OSTATNIEGO ')' zamiast pierwszego, żeby nie urwać się za wcześnie.
      lparen = content.index('(')
      rparen = content.rindex(')')
      next unless lparen && rparen && rparen > lparen

      comm = content[(lparen + 1)...rparen]
      rest = content[(rparen + 2)..].split(' ')
      next if rest.size < 13

      state = rest[0]
      ppid  = rest[1].to_i? || 0
      utime = rest[11].to_i64? || 0_i64
      stime = rest[12].to_i64? || 0_i64

      uid, rss = read_status_fields(pid)
      result << ProcInfo.new(pid, ppid, comm, state, uid, rss, utime + stime)
    rescue
      next
    end
  end
  result
end

procs = read_proc_entries

if uf = user_filter
  uid_map = read_uid_map
  target_uid = uid_map[uf]? || uf.to_i?
  if target_uid
    procs = procs.select { |pi| pi.uid == target_uid }
  else
    STDERR.puts "pr: nieznany użytkownik '#{uf}'"
    exit 1
  end
end

def print_row(pi : ProcInfo, prefix : String = "")
  puts "#{pi.pid.to_s.rjust(5)} #{pi.state.ljust(5)} #{pi.rss_kb.to_s.rjust(8)}K #{prefix}#{pi.comm}"
end

puts "  PID STAN     RSS  POLECENIE"

if tree_mode
  by_pid = {} of Int32 => ProcInfo
  children = Hash(Int32, Array(Int32)).new { |h, k| h[k] = [] of Int32 }
  procs.each do |pi|
    by_pid[pi.pid] = pi
    children[pi.ppid] << pi.pid
  end

  visited = Set(Int32).new

  print_tree = uninitialized Proc(Int32, Int32, Nil)
  print_tree = ->(pid : Int32, depth : Int32) do
    pi = by_pid[pid]?
    if pi && !visited.includes?(pid)
      visited << pid
      print_row(pi, "  " * depth + (depth > 0 ? "└─ " : ""))
    end
    children[pid].sort!.each { |child_pid| print_tree.call(child_pid, depth + 1) }
  end

  # Korzenie: procesy, których rodzic NIE jest wśród wypisywanych procesów
  # (zwykle PID 1 i "osierocone" poddrzewa po filtrowaniu -u).
  roots = procs.map(&.pid).select { |pid| !by_pid.has_key?(by_pid[pid]?.try(&.ppid) || -1) }.sort!
  roots.each { |pid| print_tree.call(pid, 0) }
  # Wszystko, co z jakiegoś powodu nie zostało odwiedzone (np. cykl albo
  # rodzic spoza /proc w chwili odczytu) -- i tak wypisz, żeby nic nie zniknęło.
  procs.each { |pi| print_row(pi) unless visited.includes?(pi.pid) }
else
  sorted = case sort_by
           when "cpu" then procs.sort_by { |pi| -pi.cpu_ticks }
           when "mem" then procs.sort_by { |pi| -pi.rss_kb }
           else            procs.sort_by(&.pid)
           end
  sorted.each { |pi| print_row(pi) }
end
