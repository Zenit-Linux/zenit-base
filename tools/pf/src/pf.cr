require "option_parser"

# pf — nowoczesna alternatywa dla `printf` (Zenit Linux)
#
# STATUS: szkielet+ — obsługuje najczęstsze specyfikatory (%s, %d, %f,
# %x, %o, %%), podstawowe sekwencje ucieczki, szerokość/wyrównanie
# (%5d, %-10s), zero-padding (%05d) i precyzję (%.2f, %.3s), z
# zapętleniem formatu, jeśli podano więcej argumentów niż specyfikatorów
# (jak prawdziwe printf(1)). Faktyczne formatowanie liczb/tekstu deleguje
# do wbudowanego w Crystal `sprintf`, żeby nie duplikować logiki C printf.

VERSION = "0.1.0"

args = ARGV

if args.empty? || args[0].in?(["-h", "--help"])
  puts "pf — nowoczesna alternatywa dla printf (Zenit Linux)"
  puts "Użycie: pf FORMAT [ARGUMENT...]"
  puts "  %s  -> tekst                    %d -> liczba całkowita"
  puts "  %f  -> liczba zmiennoprzecinkowa %x -> liczba szesnastkowa"
  puts "  %o  -> liczba ósemkowa           %% -> znak %"
  puts "  Modyfikatory: szerokość (%5d), wyrównanie do lewej (%-5d),"
  puts "  zero-padding (%05d), precyzja (%.2f, %.3s)."
  exit 0
end

if args[0] == "--version"
  puts "pf #{VERSION}"
  exit 0
end

format = args[0]
values = args[1..]

# Parsuje pojedynczy specyfikator zaczynający się na `%` (bez samego %%)
# i zwraca sformatowany tekst plus indeks znaku TUŻ ZA specyfikatorem.
# Deleguje właściwe formatowanie do wbudowanego `sprintf`, obsługując
# tylko konwersję typu argumentu (String -> Int64/Float64 wedle potrzeby).
def render_spec(format : String, start : Int32, value : String?) : {String, Int32}
  j = start + 1
  while j < format.size && "-+0 #".includes?(format[j])
    j += 1
  end
  while j < format.size && format[j].ascii_number?
    j += 1
  end
  if j < format.size && format[j] == '.'
    j += 1
    while j < format.size && format[j].ascii_number?
      j += 1
    end
  end

  if j >= format.size
    # Niekompletny specyfikator na końcu formatu — wypisz dosłownie.
    return {format[start..], format.size}
  end

  conv = format[j]
  spec_str = format[start..j]

  text = case conv
         when 's'
           sprintf(spec_str, value || "")
         when 'd'
           sprintf(spec_str, value.try(&.to_i64?) || 0_i64)
         when 'f'
           sprintf(spec_str, value.try(&.to_f64?) || 0.0)
         when 'x', 'o'
           sprintf(spec_str, value.try(&.to_i64?) || 0_i64)
         else
           spec_str
         end

  {text, j + 1}
end

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
      elsif c == '%' && i + 1 < format.size && format[i + 1] == '%'
        io << '%'
        i += 2
      elsif c == '%' && i + 1 < format.size
        text, next_i = render_spec(format, i, values[value_idx]?)
        io << text
        value_idx += 1
        i = next_i
      else
        io << c
        i += 1
      end
    end
  end
  out
end

# Jeśli podano więcej argumentów niż specyfikatorów w formacie, printf(1)
# powtarza format aż do wyczerpania argumentów. %% nie liczy się jako
# specyfikator, bo nie konsumuje argumentu.
specifiers_count = format.scan(/%[-+0 #]*\d*(\.\d*)?[sdfxo]/).size
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
