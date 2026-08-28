require "option_parser"

# pr — nowoczesna alternatywa dla `ps` (Zenit Linux, "procesy")
#
# STATUS: szkielet — czyta /proc i wypisuje podstawowe informacje
# o procesach; filtrowanie i sortowanie zaawansowane to TODO.

VERSION = "0.1.0"

show_all = false

parser = OptionParser.new do |p|
  p.banner = "pr — nowoczesna alternatywa dla ps (Zenit Linux)\n\nUżycie: pr [opcje]"
  p.on("-a", "--all", "pokaż procesy wszystkich użytkowników") { show_all = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu pr") { puts "pr #{VERSION}"; exit 0 }
end
parser.parse

# TODO: filtrowanie po użytkowniku (-u), drzewo procesów (--tree)
# TODO: sortowanie po zużyciu CPU/RAM, gdy dostępne z /proc/[pid]/stat

struct ProcInfo
  getter pid : Int32
  getter comm : String
  getter state : String

  def initialize(@pid : Int32, @comm : String, @state : String)
  end
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
      # Format: pid (comm) state ...
      if m = content.match(/\A\d+\s+\(([^)]*)\)\s+(\S)/)
        result << ProcInfo.new(pid, m[1], m[2])
      end
    rescue
      next
    end
  end
  result
end

procs = read_proc_entries
puts "  PID STAN  POLECENIE"
procs.sort_by(&.pid).each do |proc_info|
  puts "#{proc_info.pid.to_s.rjust(5)} #{proc_info.state.ljust(5)} #{proc_info.comm}"
end
