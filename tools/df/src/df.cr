require "option_parser"

# df — nowoczesna alternatywa dla `df` (Zenit Linux)
#
# STATUS: odczytuje statystyki systemu plików przez statvfs(2) (bezpośredni
# binding do libc, bo Crystal nie udostawia tego w stdlib) ORAZ parsuje
# /proc/mounts, żeby wypisać rzeczywiste urządzenie i punkt montowania —
# zarówno dla podanych ścieżek (dopasowanie do najdłuższego pasującego
# punktu montowania), jak i (bez argumentów) dla WSZYSTKICH zamontowanych
# systemów plików, tak jak klasyczne `df`.

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

record MountEntry, device : String, mountpoint : String, fstype : String

# /proc/mounts koduje spacje/taby/backslashe w ścieżkach jako sekwencje
# ósemkowe (`\040` dla spacji itd.) -- bez tego odkodowania punkty
# montowania ze spacją w nazwie (rzadkie, ale legalne) pokazywałyby się
# ucięte na pierwszej spacji.
def unescape_mount_field(s : String) : String
  s.gsub(/\\([0-7]{3})/) { |_, m| m[1].to_i(8).chr.to_s }
end

def read_mounts : Array(MountEntry)
  result = [] of MountEntry
  return result unless File.exists?("/proc/mounts")
  File.each_line("/proc/mounts") do |line|
    fields = line.split(' ')
    next if fields.size < 3
    result << MountEntry.new(
      device: unescape_mount_field(fields[0]),
      mountpoint: unescape_mount_field(fields[1]),
      fstype: fields[2],
    )
  end
  result
end

# Zwraca wpis montowania OBEJMUJĄCY daną ścieżkę -- czyli ten o
# NAJDŁUŻSZYM punkcie montowania będącym prefiksem ścieżki (dokładnie
# tak samo jak jądro rozstrzyga zagnieżdżone montowania, np. /var/log
# zamontowane osobno wewnątrz /var).
def mount_for(path : String, mounts : Array(MountEntry)) : MountEntry?
  real = File.expand_path(path)
  best : MountEntry? = nil
  mounts.each do |m|
    next unless real == m.mountpoint || real.starts_with?(m.mountpoint.rstrip('/') + "/") || m.mountpoint == "/"
    if best.nil? || m.mountpoint.size > best.not_nil!.mountpoint.size
      best = m
    end
  end
  best
end

mounts = read_mounts

rows = if paths.empty?
         # Bez argumentów: WSZYSTKIE zamontowane systemy plików (klasyczne
         # zachowanie `df`), w kolejności z /proc/mounts.
         mounts.map { |m| {m.device, m.mountpoint} }
       else
         paths.map do |path|
           if m = mount_for(path, mounts)
             {m.device, m.mountpoint}
           else
             {path, path} # /proc/mounts niedostępne albo brak dopasowania -- pokaż ścieżkę wprost
           end
         end
       end

exit_code = 0
puts "#{"URZĄDZENIE".ljust(20)} #{"ZAMONTOWANE NA".ljust(22)} #{"ROZMIAR".rjust(10)} #{"UŻYTE".rjust(10)} #{"WOLNE".rjust(10)} UŻYCIE%"

rows.each do |(device, mountpoint)|
  buf = LibDf::Statvfs.new
  ret = LibDf.statvfs(mountpoint.check_no_null_byte, pointerof(buf))
  if ret != 0
    STDERR.puts "df: nie można odczytać statystyk dla '#{mountpoint}'"
    exit_code = 1
    next
  end

  block_size = buf.f_frsize > 0 ? buf.f_frsize : buf.f_bsize
  total = buf.f_blocks.to_u64 * block_size
  free  = buf.f_bfree.to_u64 * block_size
  used  = total - free
  pct   = total > 0 ? (used.to_f / total.to_f * 100).round(1) : 0.0

  # Systemy plików bez realnego miejsca na dysku (proc, sysfs, cgroup, ...)
  # mają total=0 -- w listowaniu "wszystkich" (bez argumentów) pomijamy je,
  # tak jak klasyczne `df`, żeby nie zaśmiecać wyniku dziesiątkami wpisów
  # 0/0/0. Jawnie podaną ścieżkę pokazujemy zawsze, nawet jeśli total=0.
  next if paths.empty? && total == 0

  total_s = human_size ? human_readable(total) : total.to_s
  used_s  = human_size ? human_readable(used) : used.to_s
  free_s  = human_size ? human_readable(free) : free.to_s

  puts "#{device.ljust(20)} #{mountpoint.ljust(22)} #{total_s.rjust(10)} #{used_s.rjust(10)} #{free_s.rjust(10)} #{pct}%"
end

exit exit_code
