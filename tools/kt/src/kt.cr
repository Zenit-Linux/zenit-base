require "option_parser"

# kt — nowoczesna alternatywa dla `whoami` (Zenit Linux, "kto")
#
# STATUS: szkielet+ — odczytuje nazwę użytkownika przez
# getpwuid(getuid()), tak jak prawdziwe `whoami` — poprawne nawet gdy
# zmienne środowiskowe USER/LOGNAME są puste albo celowo sfałszowane
# (proces może ustawić sobie dowolne zmienne środowiskowe, ale nie może
# zmienić tego, co zwraca jądro dla jego prawdziwego UID).

VERSION = "0.1.0"

lib LibKt
  fun getuid : LibC::UidT

  struct Passwd
    pw_name : LibC::Char*
    pw_passwd : LibC::Char*
    pw_uid : LibC::UidT
    pw_gid : LibC::GidT
    pw_gecos : LibC::Char*
    pw_dir : LibC::Char*
    pw_shell : LibC::Char*
  end

  fun getpwuid(uid : LibC::UidT) : Passwd*
end

parser = OptionParser.new do |p|
  p.banner = "kt — nowoczesna alternatywa dla whoami (Zenit Linux)\n\nUżycie: kt"
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu kt") { puts "kt #{VERSION}"; exit 0 }
end
parser.parse

pw = LibKt.getpwuid(LibKt.getuid)
if pw.null?
  # Bardzo rzadki przypadek: UID bez wpisu w /etc/passwd (np. kontener bez
  # NSS skonfigurowanego poprawnie) — awaryjnie spróbuj zmiennych
  # środowiskowych zamiast twardego błędu.
  name = ENV["USER"]? || ENV["LOGNAME"]?
  if name
    puts name
  else
    STDERR.puts "kt: brak wpisu w /etc/passwd dla bieżącego UID i brak USER/LOGNAME"
    exit 1
  end
else
  puts String.new(pw.value.pw_name)
end
