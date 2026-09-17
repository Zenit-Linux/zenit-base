require "option_parser"

# ni — nowoczesna alternatywa dla `nice`/`renice` (Zenit Linux)
#
# STATUS: uruchamia polecenie ze zmienionym priorytetem przez bezpośredni
# binding do setpriority(2), analogicznie do wcześniejszych narzędzi (zb,
# df) korzystających z LibC zamiast wysokopoziomowego API. `-p PID`
# (odpowiednik `renice`) zmienia priorytet JUŻ działającego procesu
# zamiast uruchamiać nowe polecenie.

VERSION = "0.1.0"

lib LibNi
  PRIO_PROCESS = 0
  fun setpriority(which : LibC::Int, who : LibC::Int, prio : LibC::Int) : LibC::Int
  fun getpriority(which : LibC::Int, who : LibC::Int) : LibC::Int
end

adjustment = 10 # domyślne zwiększenie "nice" o 10, tak jak klasyczne `nice`
renice_pid = nil.as(Int32?)
command = [] of String

# Obsługa `-N` (np. -5, -10) i `-p PID` przed przekazaniem reszty do
# OptionParser, analogicznie do sztuczki zastosowanej wcześniej w zb.cr
# dla `-SYGNAŁ`.
positional = [] of String
skip_next = false
ARGV.each_with_index do |a, idx|
  if skip_next
    skip_next = false
    next
  end
  if a == "-n" && idx + 1 < ARGV.size
    adjustment = ARGV[idx + 1].to_i
    skip_next = true
  elsif a == "-p" && idx + 1 < ARGV.size
    renice_pid = ARGV[idx + 1].to_i
    skip_next = true
  elsif a.starts_with?("-p") && a.size > 2 && a[2..].to_i?
    renice_pid = a[2..].to_i
  elsif a.starts_with?('-') && a.size > 1 && a[1..].to_i?
    adjustment = a[1..].to_i
  elsif a.in?(["-h", "--help"])
    puts "ni — nowoczesna alternatywa dla nice/renice (Zenit Linux)"
    puts "Użycie: ni [-N | -n N] POLECENIE [ARGUMENTY...]   (jak nice)"
    puts "        ni [-N | -n N] -p PID                     (jak renice -- zmienia priorytet istniejącego procesu)"
    exit 0
  elsif a == "--version"
    puts "ni #{VERSION}"
    exit 0
  else
    positional << a
  end
end

command = positional

if pid = renice_pid
  # Tryb renice: ustawia priorytet BEZWZGLĘDNY (nie relatywny do
  # bieżącego procesu ni, tak jak przy uruchamianiu nowego polecenia) na
  # wartość adjustment — dokładnie tak samo jak `renice N -p PID`
  # (w odróżnieniu od `nice -n N polecenie`, gdzie N jest DODAWANE do
  # bieżącego priorytetu powłoki wywołującej).
  ret = LibNi.setpriority(LibNi::PRIO_PROCESS, pid, adjustment)
  if ret != 0
    STDERR.puts "ni: nie można ustawić priorytetu #{adjustment} dla PID #{pid} " \
                "(proces nie istnieje albo brak uprawnień dla wartości ujemnych)"
    exit 1
  end
  puts "ni: priorytet PID #{pid} ustawiony na #{adjustment}"
  exit 0
end

if command.empty?
  STDERR.puts "ni: brak polecenia do uruchomienia (albo -p PID do zmiany priorytetu istniejącego procesu)"
  exit 1
end

current = LibNi.getpriority(LibNi::PRIO_PROCESS, 0)
target = current + adjustment
ret = LibNi.setpriority(LibNi::PRIO_PROCESS, 0, target)
if ret != 0
  STDERR.puts "ni: nie można ustawić priorytetu na #{target} (wymaga uprawnień dla wartości ujemnych)"
end

begin
  Process.exec(command[0], args: command[1..])
rescue e
  STDERR.puts "ni: nie można uruchomić '#{command[0]}': #{e.message}"
  exit 127
end
