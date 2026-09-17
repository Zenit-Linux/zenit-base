module MyersDiff
  # Format zgodny z tym, czego wcześniej dostarczał odtwarzacz (backtrace)
  # tablicy DP w ro.cr: (rodzaj, tekst, indeks_w_a_PRZED, indeks_w_b_PRZED).
  # Dzięki temu reszta programu (grupowanie w hunki, wypisywanie unified
  # diff) nie wymaga ŻADNYCH zmian — jedyna różnica to SPOSÓB wyznaczenia
  # tej listy.
  alias Op = {Char, String, Int32, Int32}

  # Zwraca skrypt edycji przekształcający `a` w `b`.
  def self.diff(a : Array(String), b : Array(String)) : Array(Op)
    n = a.size
    m = b.size
    max = n + m
    return [] of Op if max == 0

    offset = max
    v = Array(Int32).new(2 * max + 1, 0)
    # `trace[d]` to KOPIA tablicy `v` zaraz PO przetworzeniu wszystkich
    # przekątnych dla danego D -- potrzebna do odtworzenia (backtrace)
    # rzeczywistej ścieżki po znalezieniu rozwiązania. To właśnie ta
    # lista kosztuje O(D*(n+m)) zamiast O(n*m): przechowujemy D+1
    # migawek o rozmiarze O(n+m) każda, zamiast jednej tablicy O(n*m).
    trace = [] of Array(Int32)

    d = 0
    while d <= max
      trace << v.dup
      k = -d
      while k <= d
        x = if k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])
              v[k + 1 + offset] # ruch w dół (insercja) -- lepsza przekątna po lewej
            else
              v[k - 1 + offset] + 1 # ruch w prawo (usunięcie)
            end
        y = x - k

        # "Wąż" (snake): ciągnij po przekątnej tak długo, jak linie się
        # zgadzają -- dopasowania nie kosztują nic w D, więc łapczywie
        # konsumujemy ich jak najwięcej od razu.
        while x < n && y < m && a[x] == b[y]
          x += 1
          y += 1
        end

        v[k + offset] = x

        if x >= n && y >= m
          return backtrack(a, b, trace, d)
        end

        k += 2
      end
      d += 1
    end

    # Nieosiągalne dla poprawnych wejść -- pętla D zawsze znajduje
    # rozwiązanie w co najwyżej `max` krokach (najgorszy przypadek: same
    # usunięcia + same insercje, D = n + m). Pusta lista zamiast crasha,
    # gdyby jednak coś było nie tak z powyższą logiką.
    [] of Op
  end

  # Odtwarza rzeczywisty skrypt edycji, idąc WSTECZ od (n, m) do (0, 0)
  # przez zapisane migawki `trace`, jedna warstwa D na raz.
  private def self.backtrack(a : Array(String), b : Array(String), trace : Array(Array(Int32)), final_d : Int32) : Array(Op)
    n = a.size
    m = b.size
    offset = n + m

    x = n
    y = m
    ops = [] of Op

    d = final_d
    while d >= 0
      v = trace[d]
      k = x - y
      prev_k = if k == -d || (k != d && v[k - 1 + offset] < v[k + 1 + offset])
                 k + 1
               else
                 k - 1
               end
      prev_x = v[prev_k + offset]
      prev_y = prev_x - prev_k

      # Cofnij najpierw CAŁY "wąż" (ciąg dopasowań) tej warstwy -- to on
      # odpowiada za linie kontekstowe (' ') w wyniku.
      while x > prev_x && y > prev_y
        ops << {' ', a[x - 1], x - 1, y - 1}
        x -= 1
        y -= 1
      end

      # Po zejściu węża zostaje dokładnie JEDEN elementarny krok (D > 0):
      # albo pionowy (x się nie zmienia -> insercja linii z `b`), albo
      # poziomy (y się nie zmienia -> usunięcie linii z `a`).
      if d > 0
        if x == prev_x
          ops << {'+', b[prev_y], x, prev_y}
        else
          ops << {'-', a[prev_x], prev_x, y}
        end
      end

      x = prev_x
      y = prev_y
      d -= 1
    end

    ops.reverse
  end
end
