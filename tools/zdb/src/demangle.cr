module Demangle
  BUILTIN_TYPES = {
    'v' => "void", 'w' => "wchar_t", 'b' => "bool", 'c' => "char",
    'a' => "signed char", 'h' => "unsigned char", 's' => "short",
    't' => "unsigned short", 'i' => "int", 'j' => "unsigned int",
    'l' => "long", 'm' => "unsigned long", 'x' => "long long",
    'y' => "unsigned long long", 'n' => "__int128", 'o' => "unsigned __int128",
    'f' => "float", 'd' => "double", 'e' => "long double", 'g' => "__float128",
    'z' => "...",
  }

  # Wyjątek wewnętrzny -- sygnalizuje "trafiliśmy na coś, czego ten
  # uproszczony parser nie obsługuje (albo mangled name jest uszkodzony)".
  # Zawsze łapany na najwyższym poziomie `demangle`, nigdy nie wycieka.
  private class GiveUp < Exception
  end

  private class Parser
    def initialize(@s : String)
      @pos = 0
      # Tabela podstawień: KAŻDY w pełni sparsowany komponent nazwy
      # (prefiks zagnieżdżonej nazwy) i typ (poza gołymi wbudowanymi
      # jednoliterowymi) trafia tu w kolejności napotkania -- `S_`
      # odwołuje się do wpisu 0, `S0_` do wpisu 1, `S1_` do wpisu 2, itd.
      @subs = [] of String
    end

    private def peek : Char?
      @pos < @s.size ? @s[@pos] : nil
    end

    private def advance : Char
      raise GiveUp.new("nieoczekiwany koniec") if @pos >= @s.size
      c = @s[@pos]
      @pos += 1
      c
    end

    private def expect(c : Char)
      raise GiveUp.new("oczekiwano '#{c}'") unless peek == c
      @pos += 1
    end

    private def read_number : Int32
      start = @pos
      while (c = peek) && c.ascii_number?
        @pos += 1
      end
      raise GiveUp.new("oczekiwano liczby") if @pos == start
      @s[start...@pos].to_i
    end

    private def read_source_name : String
      len = read_number
      raise GiveUp.new("identyfikator za krótki") if @pos + len > @s.size
      name = @s[@pos, len]
      @pos += len
      name
    end

    private def add_sub(s : String)
      @subs << s
    end

    private def resolve_substitution : String
      expect('S')
      if peek == '_'
        @pos += 1
        idx = 0
      else
        idx = read_number + 1
        expect('_')
      end
      raise GiveUp.new("nieznane podstawienie S#{idx == 0 ? "" : (idx - 1)}_") if idx >= @subs.size
      @subs[idx]
    end

    # <unqualified-name> w kontekście <prefix> -- zwraca nil dla
    # ctor/dtor (obsługiwane osobno przez wywołującego, bo potrzebują
    # znać nazwę klasy z WCZEŚNIEJSZEGO prefiksu).
    private def read_unqualified_name(class_name : String?) : String
      case peek
      when 'C'
        @pos += 1
        raise GiveUp.new("oczekiwano cyfry ctor") unless peek && peek.not_nil!.ascii_number?
        @pos += 1
        raise GiveUp.new("konstruktor bez znanej klasy") unless class_name
        class_name
      when 'D'
        @pos += 1
        raise GiveUp.new("oczekiwano cyfry dtor") unless peek && peek.not_nil!.ascii_number?
        @pos += 1
        raise GiveUp.new("destruktor bez znanej klasy") unless class_name
        "~#{class_name}"
      else
        if peek && peek.not_nil!.ascii_number?
          read_source_name
        else
          # operator-name, template, lambda itp. -- poza zakresem.
          raise GiveUp.new("nieobsługiwany unqualified-name '#{peek}'")
        end
      end
    end

    # <nested-name> ::= N [<CV-qualifiers>] <prefix> <unqualified-name> E
    # Zwraca w pełni zakwalifikowaną nazwę "a::b::c".
    def read_nested_name : String
      expect('N')
      # Kwalifikatory CV na METODZIE (np. "const" na końcu sygnatury) —
      # rzadkie w praktycznych backtrace'ach z C; pomijamy je świadomie
      # (konsumujemy, ale nie odzwierciedlamy w wyniku) zamiast poddawać
      # się całkowicie.
      while peek == 'K' || peek == 'V' || peek == 'r'
        @pos += 1
      end

      parts = [] of String
      loop do
        break if peek == 'E'
        component =
          if peek == 'S'
            resolve_substitution
          else
            last_class = parts.empty? ? nil : parts.last
            read_unqualified_name(last_class)
          end
        parts << component
        qualified = parts.join("::")
        add_sub(qualified)
        break if peek == 'E'
      end
      expect('E')
      parts.join("::")
    end

    # <name> ::= <nested-name> | <unscoped-name> | <substitution>
    def read_name : String
      case peek
      when 'N'
        read_nested_name
      when 'S'
        resolve_substitution
      else
        # UWAGA: celowo BEZ add_sub tutaj -- zweryfikowane empirycznie
        # przeciwko c++filt (`_Z3fooPiS_` musi dać "foo(int*, int*)", nie
        # "foo(int*, foo)"): gołe, nieszablonowe <unscoped-name> (czyli
        # zwykła, niezagnieżdżona nazwa funkcji na szczycie <encoding>)
        # NIE jest kandydatem do tabeli podstawień w praktyce
        # gcc/clang -- w odróżnieniu od komponentów <nested-name>
        # (dodawanych osobno w read_nested_name) i typów nienazwanych
        # wbudowanie (dodawanych w read_type).
        read_source_name
      end
    end

    # <type> ::= <builtin-type> | P<type> | R<type> | O<type> | K<type>
    #          | V<type> | <name> | <substitution>
    def read_type : String
      case peek
      when 'S'
        return resolve_substitution
      when 'P'
        @pos += 1
        inner = read_type
        result = "#{inner}*"
        add_sub(result)
        return result
      when 'R'
        @pos += 1
        inner = read_type
        result = "#{inner}&"
        add_sub(result)
        return result
      when 'O'
        @pos += 1
        inner = read_type
        result = "#{inner}&&"
        add_sub(result)
        return result
      when 'K'
        @pos += 1
        inner = read_type
        result = "#{inner} const"
        add_sub(result)
        return result
      when 'V'
        @pos += 1
        inner = read_type
        result = "#{inner} volatile"
        add_sub(result)
        return result
      end

      c = peek
      if c && BUILTIN_TYPES.has_key?(c)
        @pos += 1
        return BUILTIN_TYPES[c]
      end

      # Typ nazwany (klasa/struktura/enum) -- <name>, z podstawieniem już
      # zapisanym przez read_name/read_nested_name.
      if c == 'N' || (c && c.ascii_number?)
        return read_name
      end

      raise GiveUp.new("nieobsługiwany kod typu '#{c}'")
    end

    # Lista typów parametrów aż do końca stringa. Pusta lista parametrów
    # jest kodowana jako pojedyncze 'v' (void) -- zgodnie ze specyfikacją,
    # NIE dodajemy wtedy "(void)" tylko "()" (konwencja C++, nie C).
    def read_param_types : Array(String)
      return [] of String if @pos >= @s.size
      if peek == 'v' && @pos == @s.size - 1
        @pos += 1
        return [] of String
      end
      types = [] of String
      while @pos < @s.size
        types << read_type
      end
      types
    end
  end

  # Próbuje zdemanglować `mangled`. Zwraca `mangled` BEZ ZMIAN, jeśli to
  # nie jest nazwa w stylu Itanium C++ (brak prefiksu `_Z`) albo jeśli
  # napotka konstrukcję poza obsługiwanym podzbiorem gramatyki (szablony,
  # operatory, uszkodzony napis) -- nigdy nie zwraca zmyślonego wyniku.
  def self.demangle(mangled : String) : String
    return mangled unless mangled.starts_with?("_Z")

    begin
      p = Parser.new(mangled[2..])
      name = p.read_name
      params = p.read_param_types
      "#{name}(#{params.join(", ")})"
    rescue GiveUp
      mangled
    rescue IndexError | ArgumentError
      # read_number/slicing poza zakresem na uszkodzonym/nietypowym
      # wejściu -- traktujemy identycznie jak GiveUp: bezpieczny fallback.
      mangled
    end
  end
end
