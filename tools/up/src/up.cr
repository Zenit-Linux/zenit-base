require "option_parser"

# up — nowoczesna alternatywa dla `uptime` (Zenit Linux)
#
# STATUS: szkielet — parsuje /proc/uptime i /proc/loadavg (Linux).
# Liczba zalogowanych użytkowników (jak `uptime` klasyczne, przez utmp)
# pozostaje jako TODO — wymagałoby parsowania /var/run/utmp, binarnego
# formatu bez stabilnego publicznego API w Crystalu.

VERSION = "0.1.0"

parser = OptionParser.new do |p|
  p.banner = "up — nowoczesna alternatywa dla uptime (Zenit Linux)\n\nUżycie: up"
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu up") { puts "up #{VERSION}"; exit 0 }
end
parser.parse

unless File.exists?("/proc/uptime")
  STDERR.puts "up: /proc/uptime niedostępne (nie-Linux albo /proc niezamontowane)"
  exit 1
end

# TODO: liczba zalogowanych użytkowników przez /var/run/utmp.

uptime_seconds = File.read("/proc/uptime").split(' ').first.to_f64
total_seconds = uptime_seconds.to_i64

days    = total_seconds // 86400
hours   = (total_seconds % 86400) // 3600
minutes = (total_seconds % 3600) // 60

parts = [] of String
parts << "#{days} dni" if days > 0
parts << "#{hours} godz" if hours > 0
parts << "#{minutes} min"
uptime_str = parts.join(", ")

load_str = "brak danych"
if File.exists?("/proc/loadavg")
  fields = File.read("/proc/loadavg").split(' ')
  if fields.size >= 3
    load_str = "#{fields[0]}, #{fields[1]}, #{fields[2]}"
  end
end

puts "czas działania: #{uptime_str}, obciążenie (1/5/15 min): #{load_str}"
