require "option_parser"

# Binding bezpośrednio do kill(2) — nie polegamy na wysokopoziomowym API
# Process z stdlib, żeby zachować pełną kontrolę nad numerem sygnału i
# jednoznaczną semantykę zgodną z klasycznym `kill(1)`.
lib LibZb
  fun kill(pid : LibC::PidT, sig : LibC::Int) : LibC::Int
end

def pid_exists?(pid : Int32) : Bool
  # sygnał 0 nie jest dostarczany, ale kill(2) wciąż sprawdza czy proces
  # istnieje i czy mamy uprawnienia — standardowa sztuczka do testowania PID.
  LibZb.kill(pid, 0) == 0
end

# zb — nowoczesna alternatywa dla `kill` (Zenit Linux, "zabij")
#
# STATUS: szkielet — wysyłanie sygnałów po PID działa; dopasowanie po
# nazwie procesu (jak `pkill`) i --timeout (SIGTERM potem SIGKILL) to TODO.

VERSION = "0.1.0"

SIGNAL_NAMES = {
  "HUP" => 1, "INT" => 2, "QUIT" => 3, "KILL" => 9,
  "TERM" => 15, "USR1" => 10, "USR2" => 12, "STOP" => 19, "CONT" => 18,
}

signal_num = 15 # SIGTERM domyślnie
list_only  = false
pids       = [] of Int32

args = ARGV.dup
parser = OptionParser.new do |p|
  p.banner = "zb — nowoczesna alternatywa dla kill (Zenit Linux)\n\nUżycie: zb [-SYGNAŁ] PID..."
  p.on("-l", "--list", "wypisz dostępne nazwy sygnałów") { list_only = true }
  p.on("-s SYGNAŁ", "--signal=SYGNAŁ", "sygnał do wysłania (nazwa lub numer)") do |v|
    signal_num = SIGNAL_NAMES[v.upcase]? || v.to_i? || signal_num
  end
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu zb") { puts "zb #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end

# Obsługa skróconej formy `-9`, `-TERM` itp. przed przekazaniem do OptionParser,
# ponieważ OptionParser nie rozpoznaje dynamicznych flag liczbowych.
positional = [] of String
ARGV.each do |a|
  if a.starts_with?('-') && a.size > 1 && a[1..].to_i?
    signal_num = a[1..].to_i
  elsif a.starts_with?('-') && SIGNAL_NAMES.has_key?(a[1..].upcase)
    signal_num = SIGNAL_NAMES[a[1..].upcase]
  else
    positional << a
  end
end

if list_only
  SIGNAL_NAMES.each { |name, num| puts "#{num}\tSIG#{name}" }
  exit 0
end

positional.each do |a|
  if pid = a.to_i?
    pids << pid
  else
    STDERR.puts "zb: nieprawidłowy PID: '#{a}'"
  end
end

if pids.empty?
  STDERR.puts "zb: brak argumentu — podaj co najmniej jeden PID"
  exit 1
end

# TODO: dopasowanie po nazwie procesu przez przeszukanie /proc/[pid]/comm
# (odpowiednik `pkill NAZWA`), oraz --timeout wysyłający najpierw SIGTERM,
# a po limicie czasu SIGKILL, jeśli proces wciąż działa.

exit_code = 0
pids.each do |pid|
  unless pid_exists?(pid)
    STDERR.puts "zb: proces #{pid} nie istnieje"
    exit_code = 1
    next
  end

  ret = LibZb.kill(pid, signal_num)
  if ret != 0
    STDERR.puts "zb: nie można wysłać sygnału #{signal_num} do #{pid}"
    exit_code = 1
  end
end

exit exit_code
