require "option_parser"

# en — nowoczesna alternatywa dla `env` (Zenit Linux, "środowisko")
#
# STATUS: szkielet+ — obsługuje wypisywanie środowiska,
# `en NAZWA=WARTOSC... polecenie...` (uruchomienie polecenia z dodanymi/
# nadpisanymi zmiennymi), oraz `-i`/`--ignore-environment` (uruchomienie
# z całkowicie czystym środowiskiem — dziedziczone zmienne są ignorowane,
# zostają tylko jawnie podane NAZWA=WARTOSC).

VERSION = "0.1.0"

ignore_environment = false
args = [] of String

parser = OptionParser.new do |p|
  p.banner = "en — nowoczesna alternatywa dla env (Zenit Linux)\n\nUżycie: en [-i] [NAZWA=WARTOSC...] [POLECENIE [ARGUMENTY...]]"
  p.on("-i", "--ignore-environment", "uruchom polecenie z pustym środowiskiem (bez dziedziczenia)") { ignore_environment = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu en") { puts "en #{VERSION}"; exit 0 }
  p.unknown_args { |a| args.concat(a) }
end
parser.parse

assignments = {} of String => String
rest_index = 0

args.each_with_index do |a, idx|
  eq = a.index('=')
  if eq && eq > 0 && a[0...eq].chars.all? { |c| c.alphanumeric? || c == '_' }
    assignments[a[0...eq]] = a[(eq + 1)..]
    rest_index = idx + 1
  else
    break
  end
end

command = args[rest_index..]

if command.empty?
  # Tryb bezargumentowy: wypisz środowisko (z nadpisaniami, jeśli podano).
  assignments.each { |k, v| ENV[k] = v }
  ENV.each { |key, value| puts "#{key}=#{value}" }
else
  begin
    if ignore_environment
      # clear_env: true usuwa CAŁE dziedziczone środowisko procesu
      # potomnego; jedyne zmienne, jakie dostanie, to te z `assignments`.
      Process.exec(command[0], args: command[1..], env: assignments, clear_env: true)
    else
      assignments.each { |k, v| ENV[k] = v }
      Process.exec(command[0], args: command[1..], env: nil, clear_env: false)
    end
  rescue e
    STDERR.puts "en: nie można uruchomić '#{command[0]}': #{e.message}"
    exit 127
  end
end
