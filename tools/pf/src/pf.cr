require "option_parser"

# pf — nowoczesna alternatywa dla `printf` (Zenit Linux)
#
# STATUS: szkielet — obsługuje najczęstsze specyfikatory (%s, %d, %f, %%)
# oraz podstawowe sekwencje ucieczki, z zapętleniem formatu jeśli podano
# więcej argumentów niż specyfikatorów (jak prawdziwe printf(1)).
# Specyfikatory szerokości/precyzji (%5d, %.2f) i %x/%o pozostają jako TODO.

VERSION = "0.1.0"

args = ARGV

if args.empty? || args[0].in?(["-h", "--help"])
  puts "pf — nowoczesna alternatywa dla printf (Zenit Linux)"
  puts "Użycie: pf FORMAT [ARGUMENT...]"
  puts "  %s  -> tekst      %d -> liczba całkowita      %f -> liczba zmiennoprzecinkowa      %% -> znak %"
  exit 0
end

if args[0] == "--version"
  puts "pf #{VERSION}"
  exit 0
end

format = args[0]
values = args[1..]

# TODO: %5d / %-10s (szerokość/wyrównanie), %.2f (precyzja), %x/%o (hex/oct).

def render(format : String, values : Array(String)) : String
  out = String.build do |io|
    value_idx = 0
    i = 0
    while i < format.size
      c = format[i]
      if c == '\\' && i + 1 < format.size
        case format[i + 1]
        when 'n' then io << '\n'
        when 't' then io << '\t'
        when '\\' then io << '\\'
        else io << c << format[i + 1]
        end
        i += 2
      elsif c == '%' && i + 1 < format.size
        spec = format[i + 1]
        case spec
        when '%'
          io << '%'
        when 's'
          io << (values[value_idx]? || "")
          value_idx += 1
        when 'd'
          v = values[value_idx]?
          io << (v.try(&.to_i64?) || 0)
          value_idx += 1
        when 'f'
          v = values[value_idx]?
          io << (v.try(&.to_f64?) || 0.0)
          value_idx += 1
        else
          io << c << spec
        end
        i += 2
      else
        io << c
        i += 1
      end
    end
  end
  out
end

# Jeśli podano więcej argumentów niż specyfikatorów w formacie, printf(1)
# powtarza format aż do wyczerpania argumentów.
specifiers_count = format.scan(/%[sdf%]/).size
if values.empty? || specifiers_count == 0
  print render(format, values)
else
  idx = 0
  while idx < values.size
    chunk = values[idx, specifiers_count]
    print render(format, chunk)
    idx += specifiers_count
  end
end
