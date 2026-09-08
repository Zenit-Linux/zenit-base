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
# STATUS: szkielet+ — wysyłanie sygnałów po PID działa, wraz z
# --timeout (najpierw SIGTERM, a po limicie czasu SIGKILL, jeśli proces
# wciąż działa). Dopasowanie po nazwie procesu (jak `pkill`) pozostaje
# jako TODO.
#
# NAPRAWIONE (2x):
#
# 1. Pierwotna wersja budowała `parser` (OptionParser), ale nigdy nie
#    wołała `parser.parse` — flagi -l/-s/-h/--version nie działały wcale.
#
# 2. Naiwna naprawa (wywołanie `parser.parse` na całym ARGV, z nadzieją
#    że `-9`/`-TERM` trafią do `unknown_args`) też nie działała —
#    zweryfikowane realną kompilacją i uruchomieniem: Crystalowy
#    `OptionParser` rzuca wyjątek `OptionParser::InvalidOption` dla
#    KAŻDEJ nierozpoznanej flagi zaczynającej się od `-` (np. `-9`)
#    ZANIM w ogóle dotrze do `unknown_args` — ten callback łapie tylko
#    argumenty pozycyjne (bez `-` na początku), nie nieznane flagi.
#    Właściwa naprawa: rozpoznajemy `-9`/`-TERM` RĘCZNIE i USUWAMY je z
#    listy argumentów PRZED przekazaniem reszty do `parser.parse(args)`
#    — dzięki temu OptionParser nigdy nie widzi tokenów, których i tak
#    by nie zrozumiał, a PID-y i rozpoznane flagi trafiają do niego
#    normalnie.

VERSION = "0.1.0"

SIGNAL_NAMES = {
  "HUP" => 1, "INT" => 2, "QUIT" => 3, "KILL" => 9,
  "TERM" => 15, "USR1" => 10, "USR2" => 12, "STOP" => 19, "CONT" => 18,
}

signal_num = 15 # SIGTERM domyślnie

# Wyciąga z ARGV wszystkie tokeny w stylu `-9` / `-TERM` / `-SIGTERM`,
# aktualizując `signal_num` na ostatni znaleziony, i zwraca resztę
# argumentów (te, które OptionParser faktycznie rozumie: `-l`, `-s`,
# `-h`, `--version`, oraz zwykłe pozycyjne PID-y).
def extract_signal_shortcuts(args : Array(String), signal_names : Hash(String, Int32)) : {Array(String), Int32?}
  remaining = [] of String
  found = nil.as(Int32?)

  args.each do |a|
    name = a.starts_with?("-SIG") ? a[4..] : a[1..]
    if a.starts_with?('-') && a.size > 1 && (n = name.to_i?)
      found = n
    elsif a.starts_with?('-') && a.size > 1 && signal_names.has_key?(name.upcase)
      found = signal_names[name.upcase]
    else
      remaining << a
    end
  end

  {remaining, found}
end

pre_args, shortcut_signal = extract_signal_shortcuts(ARGV.to_a, SIGNAL_NAMES)
signal_num = shortcut_signal if shortcut_signal

list_only    = false
timeout_secs = nil.as(Int32?)
positional   = [] of String

parser = OptionParser.new do |p|
  p.banner = "zb — nowoczesna alternatywa dla kill (Zenit Linux)\n\nUżycie: zb [-SYGNAŁ] [--timeout SEKUNDY] PID..."
  p.on("-l", "--list", "wypisz dostępne nazwy sygnałów") { list_only = true }
  p.on("-s SYGNAŁ", "--signal=SYGNAŁ", "sygnał do wysłania (nazwa lub numer)") do |v|
    signal_num = SIGNAL_NAMES[v.upcase]? || v.to_i? || signal_num
  end
  p.on("--timeout SEKUNDY", "wyślij najpierw TERM, a po SEKUNDY (jeśli proces wciąż działa) KILL") do |v|
    n = v.to_i?
    if n.nil? || n < 0
      STDERR.puts "zb: nieprawidłowa wartość --timeout: '#{v}'"
      exit 1
    end
    timeout_secs = n
  end
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu zb") { puts "zb #{VERSION}"; exit 0 }
  p.unknown_args { |a| positional.concat(a) }
end
parser.parse(pre_args)

if list_only
  SIGNAL_NAMES.each { |name, num| puts "#{num}\tSIG#{name}" }
  exit 0
end

pids = [] of Int32
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
# (odpowiednik `pkill NAZWA`).

exit_code = 0

if ts = timeout_secs
  pids.each do |pid|
    unless pid_exists?(pid)
      STDERR.puts "zb: proces #{pid} nie istnieje"
      exit_code = 1
      next
    end

    if LibZb.kill(pid, SIGNAL_NAMES["TERM"]) != 0
      STDERR.puts "zb: nie można wysłać sygnału TERM do #{pid}"
      exit_code = 1
      next
    end

    still_alive = true
    ts.times do
      sleep 1.seconds
      unless pid_exists?(pid)
        still_alive = false
        break
      end
    end

    if still_alive && pid_exists?(pid)
      if LibZb.kill(pid, SIGNAL_NAMES["KILL"]) != 0
        STDERR.puts "zb: nie można wysłać sygnału KILL do #{pid}"
        exit_code = 1
      end
    end
  end
else
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
end

exit exit_code
