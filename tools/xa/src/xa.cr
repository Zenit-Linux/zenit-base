require "option_parser"
require "process"

# xa — nowoczesna alternatywa dla `xargs` (Zenit Linux)
#
# STATUS: działa. Buduje i uruchamia polecenie z argumentami wczytanymi
# ze stdin (jeden argument na linię). Grupowanie po -n LICZBA, tryb -0
# (separator NUL, jak `find -print0 | xargs -0`), -I ZASTĘPNIK (podmiana
# tokenu, jak `xargs -I{}`) i -P NUM (uruchamianie równoległe, jak
# `xargs -P`) działają.

VERSION = "0.1.0"

max_args_per_call = 0 # 0 = bez limitu (wszystkie argumenty w jednym wywołaniu)
null_separated     = false
verbose            = false
replace_str        = nil
parallel_jobs      = 1 # 1 = sekwencyjnie (jak dotąd); >1 = do tylu naraz; 0 = bez limitu
command_and_args   = [] of String

parser = OptionParser.new do |p|
  p.banner = "xa — nowoczesna alternatywa dla xargs (Zenit Linux)\n\nUżycie: polecenie1 | xa [opcje] POLECENIE [ARGUMENTY...]"
  p.on("-n NUM", "--max-args=NUM", "maksymalna liczba argumentów na jedno wywołanie") { |v| max_args_per_call = v.to_i }
  p.on("-0", "--null", "argumenty na wejściu rozdzielone bajtem NUL zamiast nowej linii") { null_separated = true }
  p.on("-I ZASTEPNIK", "podmień ZASTĘPNIK w argumentach na kolejny wiersz wejścia (jedno wywołanie na wiersz, jak xargs -I)") { |v| replace_str = v }
  p.on("-P NUM", "--max-procs=NUM", "uruchom do NUM wywołań równolegle (0 = bez limitu, 1 = sekwencyjnie -- domyślnie)") { |v| parallel_jobs = v.to_i }
  p.on("-t", "--verbose", "wypisz polecenie przed wykonaniem") { verbose = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu xa") { puts "xa #{VERSION}"; exit 0 }
  p.unknown_args { |args| command_and_args.concat(args) }
end

# UWAGA: Crystal OptionParser domyślnie "przetasowuje" argumenty (jak GNU
# getopt bez POSIXLY_CORRECT) i próbuje interpretować KAŻDY token
# zaczynający się od "-" jako WŁASNĄ opcję `xa`, nawet jeśli pojawia się
# PO nazwie polecenia -- więc `xa echo -n x` czy `xa sh -c '...'` bez
# poniższego ręcznego podziału kończyłoby się błędem "Invalid option: -c"
# zamiast przekazania `-c` do `sh`. xargs z natury MUSI wspierać
# przekazywanie dowolnych flag do polecenia docelowego, więc ręcznie
# wyznaczamy granicę: skanujemy ARGV tylko do momentu napotkania
# PIERWSZEGO "gołego" argumentu (albo separatora `--`) -- to on i
# WSZYSTKO po nim trafia bez zmian do `command_and_args`, z pominięciem
# OptionParsera całkowicie (dokładnie tak, jak robi to GNU xargs).
xa_argv_end = ARGV.size
i = 0
while i < ARGV.size
  arg = ARGV[i]
  case arg
  when "--"
    xa_argv_end = i + 1
    break
  when "-0", "--null", "-t", "--verbose", "-h", "--help", "--version"
    i += 1
  when "-n", "-I", "-P"
    i += 2 # flaga + jej wartość jako OSOBNY token (np. "-n" "5")
  when .starts_with?("--max-args="), .starts_with?("--max-procs=")
    i += 1
  when .starts_with?("-n"), .starts_with?("-I"), .starts_with?("-P")
    i += 1 # sklejona forma z wartością w tym samym tokenie ("-n5", "-I{}")
  when .starts_with?("-")
    i += 1 # nierozpoznana flaga xa -- niech OptionParser.parse zgłosi czytelny błąd
  else
    xa_argv_end = i # pierwszy goły argument = POLECENIE; koniec opcji xa
    break
  end
  xa_argv_end = i
end

xa_argv  = ARGV[0...xa_argv_end]
rest_argv = ARGV[xa_argv_end..]

parser.parse(xa_argv)
command_and_args.concat(rest_argv)

if command_and_args.empty?
  STDERR.puts "xa: brak polecenia do uruchomienia"
  exit 1
end

separator = null_separated ? '\0' : '\n'
raw = STDIN.gets_to_end
items = raw.split(separator).reject(&.empty?)

base_cmd  = command_and_args[0]
base_args = command_and_args[1..]

# Uruchamia listę zadań (domknięć zwracających kod wyjścia procesu) z
# limitem współbieżności `max_parallel` (1 = sekwencyjnie, 0 = bez
# limitu -- wszystkie naraz, >1 = maks. tyle jednocześnie). Zwraca
# ZAGREGOWANY kod wyjścia: ostatni napotkany niezerowy kod (tak samo jak
# poprzednia sekwencyjna pętla) -- przy współbieżności "ostatni" nie ma
# deterministycznego znaczenia czasowego (to samo zachowanie co GNU
# xargs: przy wielu równoległych niepowodzeniach kolejność raportowania
# nie jest gwarantowana), ale każde niezerowe niepowodzenie i tak
# odzwierciedla się w niezerowym kodzie końcowym `xa`.
def run_tasks(tasks : Array(Proc(Int32)), max_parallel : Int32) : Int32
  final_exit = 0

  if max_parallel == 1 || tasks.size <= 1
    tasks.each do |task|
      code = task.call
      final_exit = code if code != 0
    end
    return final_exit
  end

  mutex = Mutex.new
  done  = Channel(Nil).new

  if max_parallel <= 0
    # Bez limitu: odpal wszystkie zadania naraz.
    tasks.each do |task|
      spawn do
        code = task.call
        mutex.synchronize { final_exit = code if code != 0 }
        done.send(nil)
      end
    end
  else
    # Semafor przez zbuforowany kanał: `send` blokuje fiber, gdy bufor
    # jest pełny (czyli już `max_parallel` zadań w locie), co ogranicza
    # rzeczywistą liczbę równocześnie działających podprocesów.
    slots = Channel(Nil).new(max_parallel)
    tasks.each do |task|
      slots.send(nil)
      spawn do
        code = task.call
        mutex.synchronize { final_exit = code if code != 0 }
        slots.receive
        done.send(nil)
      end
    end
  end

  tasks.size.times { done.receive }
  final_exit
end

exit_code =
  if rs = replace_str
    # -I ZASTĘPNIK: jak w GNU xargs, wymusza JEDNO wywołanie na wiersz
    # wejścia (odpowiednik -L 1) niezależnie od -n — grupowanie po kilka
    # argumentów naraz nie miałoby sensu, skoro każdy wiersz podmienia się
    # osobno w konkretnym miejscu szablonu polecenia.
    tasks = items.map do |item|
      Proc(Int32).new do
        full_cmd  = base_cmd.gsub(rs, item)
        full_args = base_args.map(&.gsub(rs, item))
        puts "#{full_cmd} #{full_args.join(" ")}" if verbose

        status = Process.run(full_cmd, args: full_args, output: STDOUT, error: STDERR)
        status.exit_code
      end
    end
    run_tasks(tasks, parallel_jobs)
  else
    groups = if max_args_per_call > 0
               items.each_slice(max_args_per_call).to_a
             else
               [items]
             end

    tasks = groups.reject(&.empty?).map do |group|
      Proc(Int32).new do
        full_args = base_args + group
        puts "#{base_cmd} #{full_args.join(" ")}" if verbose

        status = Process.run(base_cmd, args: full_args, output: STDOUT, error: STDERR)
        status.exit_code
      end
    end
    run_tasks(tasks, parallel_jobs)
  end

exit exit_code
