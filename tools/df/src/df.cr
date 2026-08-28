require "option_parser"

# df — nowoczesna alternatywa dla `df` (Zenit Linux)
#
# STATUS: szkielet — odczytuje statystyki systemu plików przez statvfs(2)
# (bezpośredni binding do libc, bo Crystal nie udostawia tego w stdlib).
# Mapowanie punktu montowania -> urządzenie (parsowanie /proc/mounts)
# pozostaje jako TODO — dziś przyjmujemy podane ścieżki wprost.

VERSION = "0.1.0"

lib LibDf
  struct Statvfs
    f_bsize   : LibC::ULong
    f_frsize  : LibC::ULong
    f_blocks  : LibC::ULongLong
    f_bfree   : LibC::ULongLong
    f_bavail  : LibC::ULongLong
    f_files   : LibC::ULongLong
    f_ffree   : LibC::ULongLong
    f_favail  : LibC::ULongLong
    f_fsid    : LibC::ULong
    f_flag    : LibC::ULong
    f_namemax : LibC::ULong
    spare     : StaticArray(Int32, 6)
  end

  fun statvfs(path : LibC::Char*, buf : Statvfs*) : LibC::Int
end

human_size = false
paths      = [] of String

parser = OptionParser.new do |p|
  p.banner = "df — nowoczesna alternatywa dla df (Zenit Linux)\n\nUżycie: df [opcje] [ŚCIEŻKA...]"
  p.on("-H", "--human", "rozmiary czytelne dla człowieka (KB/MB/GB)") { human_size = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu df") { puts "df #{VERSION}"; exit 0 }
  p.unknown_args { |args| paths.concat(args) }
end
parser.parse

paths = ["/"] if paths.empty?

def human_readable(bytes : UInt64) : String
  units = {"B", "K", "M", "G", "T"}
  size = bytes.to_f
  idx = 0
  while size >= 1024 && idx < units.size - 1
    size /= 1024
    idx += 1
  end
  "#{size.round(1)}#{units[idx]}"
end

# TODO: parsowanie /proc/mounts, aby wypisać rzeczywistą nazwę urządzenia
# i punkt montowania zamiast samej podanej ścieżki.

exit_code = 0
puts "#{"ŚCIEŻKA".ljust(24)} #{"ROZMIAR".rjust(10)} #{"UŻYTE".rjust(10)} #{"WOLNE".rjust(10)} UŻYCIE%"

paths.each do |path|
  buf = LibDf::Statvfs.new
  ret = LibDf.statvfs(path.check_no_null_byte, pointerof(buf))
  if ret != 0
    STDERR.puts "df: nie można odczytać statystyk dla '#{path}'"
    exit_code = 1
    next
  end

  block_size = buf.f_frsize > 0 ? buf.f_frsize : buf.f_bsize
  total = buf.f_blocks.to_u64 * block_size
  free  = buf.f_bfree.to_u64 * block_size
  used  = total - free
  pct   = total > 0 ? (used.to_f / total.to_f * 100).round(1) : 0.0

  total_s = human_size ? human_readable(total) : total.to_s
  used_s  = human_size ? human_readable(used) : used.to_s
  free_s  = human_size ? human_readable(free) : free.to_s

  puts "#{path.ljust(24)} #{total_s.rjust(10)} #{used_s.rjust(10)} #{free_s.rjust(10)} #{pct}%"
end

exit exit_code
