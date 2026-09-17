require "option_parser"

# up — nowoczesna alternatywa dla `uptime` (Zenit Linux)
#
# STATUS: parsuje /proc/uptime i /proc/loadavg (Linux) ORAZ liczbę
# zalogowanych użytkowników przez bezpośrednie parsowanie binarnego
# /var/run/utmp (struct utmp z <utmp.h> — Crystal nie ma stabilnego
# publicznego API do utmp w stdlib, stąd ręczne odwzorowanie układu
# struktury C jako `lib` w Crystalu, licząc wpisy typu USER_PROCESS).

VERSION = "0.1.0"

lib LibUtmp
  UT_LINESIZE  =  32
  UT_NAMESIZE  =  32
  UT_HOSTSIZE  = 256
  USER_PROCESS = 7_i16

  struct ExitStatus
    e_termination : Int16
    e_exit        : Int16
  end

  # Układ pól MUSI odpowiadać `struct utmp` z glibc <bits/utmpx.h> na
  # Linuksie x86_64 (rozmiar całości: 384 B) -- Crystal `lib struct`
  # stosuje te same reguły wyrównania co C, więc kolejność/typy pól
  # wystarczą, bez ręcznego dopełniania bajtami.
  struct Utmp
    ut_type    : Int16
    ut_pid     : Int32
    ut_line    : UInt8[32]
    ut_id      : UInt8[4]
    ut_user    : UInt8[32]
    ut_host    : UInt8[256]
    ut_exit    : ExitStatus
    ut_session : Int32
    ut_tv_sec  : Int32
    ut_tv_usec : Int32
    ut_addr_v6 : Int32[4]
    unused     : UInt8[20]
  end
end

def bytes_to_string(bytes) : String
  arr = Bytes.new(bytes.size) { |i| bytes[i] }
  nul = arr.index(0_u8) || arr.size
  String.new(arr[0, nul])
end

def logged_in_user_count : Int32?
  path = ["/var/run/utmp", "/run/utmp"].find { |p| File.exists?(p) }
  return nil unless path

  entry_size = sizeof(LibUtmp::Utmp)
  count = 0
  seen_users = Set(String).new

  File.open(path, "rb") do |io|
    buf = Bytes.new(entry_size)
    loop do
      n = io.read_fully?(buf)
      break unless n
      entry = buf.to_unsafe.as(LibUtmp::Utmp*).value
      if entry.ut_type == LibUtmp::USER_PROCESS
        user = bytes_to_string(entry.ut_user)
        line = bytes_to_string(entry.ut_line)
        seen_users << "#{user}:#{line}" # unikalne po (użytkownik, terminal) -- jak `who`
      end
    end
  end
  seen_users.size
rescue
  nil
end

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

users = logged_in_user_count
users_str = users ? "#{users}" : "brak danych (/var/run/utmp niedostępny)"

puts "czas działania: #{uptime_str}, użytkownicy: #{users_str}, obciążenie (1/5/15 min): #{load_str}"
