require "option_parser"

# wm — nowoczesna alternatywa dla `free` (Zenit Linux, "wolna pamięć")
#
# STATUS: szkielet — parsuje /proc/meminfo (Linux) i wypisuje
# RAM/swap w stylu `free`. Odświeżanie ciągłe (jak `free -s N`) pozostaje
# jako TODO.

VERSION = "0.1.0"

human_size = false

parser = OptionParser.new do |p|
  p.banner = "wm — nowoczesna alternatywa dla free (Zenit Linux)\n\nUżycie: wm [opcje]"
  p.on("-H", "--human", "rozmiary czytelne dla człowieka (KB/MB/GB)") { human_size = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu wm") { puts "wm #{VERSION}"; exit 0 }
end
parser.parse

unless File.exists?("/proc/meminfo")
  STDERR.puts "wm: /proc/meminfo niedostępne (nie-Linux albo /proc niezamontowane)"
  exit 1
end

# TODO: -s SEKUNDY (ciągłe odświeżanie), -c LICZBA (limit powtórzeń).

def human_readable(kib : Int64) : String
  units = {"K", "M", "G", "T"}
  size = kib.to_f
  idx = 0
  while size >= 1024 && idx < units.size - 1
    size /= 1024
    idx += 1
  end
  "#{size.round(1)}#{units[idx]}"
end

fields = {} of String => Int64
File.each_line("/proc/meminfo") do |line|
  parts = line.split(':', 2)
  next unless parts.size == 2
  key = parts[0].strip
  value_str = parts[1].strip.split(' ').first? || "0"
  fields[key] = value_str.to_i64? || 0_i64
end

total     = fields["MemTotal"]? || 0_i64
free_mem  = fields["MemFree"]? || 0_i64
available = fields["MemAvailable"]? || free_mem
buffers   = fields["Buffers"]? || 0_i64
cached    = fields["Cached"]? || 0_i64
used      = total - free_mem - buffers - cached

swap_total = fields["SwapTotal"]? || 0_i64
swap_free  = fields["SwapFree"]? || 0_i64
swap_used  = swap_total - swap_free

def fmt(v : Int64, human : Bool) : String
  human ? human_readable(v) : v.to_s
end

puts "#{"".ljust(8)} #{"RAZEM".rjust(10)} #{"UŻYTE".rjust(10)} #{"WOLNE".rjust(10)} #{"BUFOR/CACHE".rjust(12)} #{"DOSTĘPNE".rjust(10)}"
puts "Pamięć:  #{fmt(total, human_size).rjust(10)} #{fmt(used, human_size).rjust(10)} #{fmt(free_mem, human_size).rjust(10)} " \
     "#{fmt(buffers + cached, human_size).rjust(12)} #{fmt(available, human_size).rjust(10)}"
puts "Swap:    #{fmt(swap_total, human_size).rjust(10)} #{fmt(swap_used, human_size).rjust(10)} #{fmt(swap_free, human_size).rjust(10)}"
