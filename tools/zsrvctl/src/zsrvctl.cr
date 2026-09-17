require "option_parser"
require "socket"

# zsrvctl — narzędzie administracyjne do kontroli `zsrv` (PID 1, Zenit
# Linux) przez gniazdo kontrolne `/run/zenit/control.sock`
# (zsrvpkg/control.nim po stronie zsrv).
#
# Zastępuje ręczny protokół "echo target > /run/zenit/target && kill -HUP 1"
# — dokładnie to narzędzie, które README zapowiadało jako
# `zsrvctl isolate TARGET` (patrz sekcja "zsrv" w README.md głównego
# repozytorium).
#
# Protokół: jedna linia polecenia -> jedna lub więcej linii odpowiedzi,
# ostatnia linia to zawsze "OK ..." albo "ERR ...". Połączenie jest
# zamykane przez zsrv zaraz po wysłaniu odpowiedzi (bez trzymania stanu).

VERSION    = "0.1.0"
SOCK_PATH  = "/run/zenit/control.sock"

def send_command(cmd : String) : String
  socket = UNIXSocket.new(SOCK_PATH)
  socket.puts(cmd)
  response = socket.gets_to_end
  socket.close
  response || ""
rescue ex : Exception
  # Celowo szeroki wyjątek: różne wersje Crystala/libc zgłaszają brak
  # gniazda (ENOENT) albo odmowę połączenia (ECONNREFUSED) pod różnymi
  # klasami wyjątków (Socket::ConnectError, Errno, IO::Error) — dla
  # użytkownika liczy się tylko czytelny komunikat, nie dokładna klasa.
  STDERR.puts "zsrvctl: nie mozna polaczyc sie z #{SOCK_PATH}: #{ex.message}"
  STDERR.puts "zsrvctl: czy zsrv (PID 1) dziala i utworzyl gniazdo kontrolne?"
  exit 1
end

def print_response(response : String)
  lines = response.chomp.split('\n')
  lines.each do |line|
    if line.starts_with?("ERR")
      STDERR.puts line
    else
      puts line unless line == "OK"
    end
  end

  exit 1 if lines.last?.try(&.starts_with?("ERR"))
end

banner = <<-BANNER
zsrvctl — sterowanie systemem init zsrv (Zenit Linux)

Użycie:
  zsrvctl list                lista wszystkich znanych usług i ich stanu
  zsrvctl status NAZWA        szczegóły jednej usługi
  zsrvctl start NAZWA         uruchamia usługę natychmiast
  zsrvctl stop NAZWA          zatrzymuje usługę
  zsrvctl restart NAZWA       zatrzymuje i uruchamia ponownie
  zsrvctl isolate TARGET      przełącza target w locie (rescue | multi-user)
  zsrvctl reload              wczytuje ponownie /etc/zenit/services (bez zrywania dzialajacych uslug)
  zsrvctl logs NAZWA [N]      ostatnie N linii logu usługi (domyślnie 20, maks. 500)
  zsrvctl ping                sprawdza, czy zsrv odpowiada

Opcje:
BANNER

rest = [] of String

parser = OptionParser.new do |p|
  p.banner = banner
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu zsrvctl") { puts "zsrvctl #{VERSION}"; exit 0 }
  p.unknown_args { |args| rest.concat(args) }
end
parser.parse

if rest.empty?
  puts parser
  exit 1
end

command = rest.join(" ")
print_response(send_command(command))
