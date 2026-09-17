import std/[unittest, tables, strutils]
import "../zesh/zeshpkg/lexer"
import "../zesh/zeshpkg/vars"
import "../zesh/zeshpkg/state"

proc words(toks: seq[Token]): seq[string] =
  for t in toks:
    if t.kind == tkWord: result.add(t.text)

suite "lexer.tokenize - słowa i cudzysłowy":
  test "proste słowa rozdzielone spacjami":
    check tokenize("echo hello world").words() == @["echo", "hello", "world"]

  test "wielokrotne spacje/taby nie tworzą pustych słów":
    check tokenize("echo   a\tb").words() == @["echo", "a", "b"]

  test "pojedynczy cudzysłów -- bez rozwijania zmiennych":
    localVars["X"] = "sekret"
    check tokenize("echo '$X'").words() == @["echo", "$X"]
    localVars.del("X")

  test "podwójny cudzysłów -- ZE rozwijaniem zmiennych":
    localVars["X"] = "wartosc"
    check tokenize("""echo "$X"""").words() == @["echo", "wartosc"]
    localVars.del("X")

  test "słowo złożone z fragmentów cudzysłowionych i nie":
    localVars["X"] = "B"
    check tokenize("""echo A"$X"C""").words() == @["echo", "ABC"]
    localVars.del("X")

suite "lexer.tokenize - operatory":
  test "potok |":
    let toks = tokenize("a | b")
    check toks.len == 3
    check toks[1].kind == tkPipe

  test "|| jest ODRÓŻNIANE od pojedynczego | (nie dwa tokeny tkPipe)":
    let toks = tokenize("a || b")
    check toks.len == 3
    check toks[1].kind == tkOr

  test "&& jest odróżniane od tła (&)":
    let toks = tokenize("a && b")
    check toks[1].kind == tkAnd

  test "pojedynczy & to tkBackground, nie tkAnd":
    let toks = tokenize("a &")
    check toks[^1].kind == tkBackground

  test "; to tkSeq":
    check tokenize("a; b")[1].kind == tkSeq

  test "przekierowania > >> <":
    let toks = tokenize("a > b >> c < d")
    check toks[1].kind == tkRedirOut
    check toks[3].kind == tkRedirAppend
    check toks[5].kind == tkRedirIn

  test "przekierowania stderr 2> 2>> 2>&1":
    let toks = tokenize("a 2> b 2>> c 2>&1")
    check toks[1].kind == tkRedirErr
    check toks[3].kind == tkRedirErrAppend
    check toks[5].kind == tkRedirErrToOut

  test "'2' w SRODKU slowa nie jest mylone z przekierowaniem stderr":
    # Przekierowanie `2>` jest rozpoznawane TYLKO gdy '2' stoi na
    # POCZATKU nowego tokenu (tak jak deskryptory plików w bashu) --
    # '2' będące częścią dłuższej nazwy pliku (np. "plik2") musi zostać
    # zwykłym fragmentem słowa.
    let toks = tokenize("plik2>x")
    check toks[0].kind == tkWord
    check toks[0].text == "plik2"
    check toks[1].kind == tkRedirOut

suite "lexer.tokenize - zmienne i substytucja poleceń":
  test "$VAR rozwijane POZA cudzysłowem":
    localVars["FOO"] = "bar"
    check tokenize("echo $FOO").words() == @["echo", "bar"]
    localVars.del("FOO")

  test "${VAR} z nawiasami klamrowymi":
    localVars["FOO"] = "bar"
    check tokenize("echo ${FOO}baz").words() == @["echo", "barbaz"]
    localVars.del("FOO")

  test "$? rozwija się do lastExitCode":
    lastExitCode = 42
    check tokenize("echo $?").words() == @["echo", "42"]
    lastExitCode = 0

  test "niezdefiniowana zmienna rozwija się do pustego tekstu":
    check tokenize("echo [$NIEISTNIEJACA_ZMIENNA_XYZ]").words() == @["echo", "[]"]

  test "$(polecenie) ze spacją w środku NIE rozrywa się na wiele tokenów":
    commandSubstitutionHook = proc(cmd: string): string = "WYNIK:" & cmd
    check tokenize("echo $(polecenie z argumentami)").words() ==
      @["echo", "WYNIK:polecenie z argumentami"]
    commandSubstitutionHook = nil

  test "zagnieżdżone $(...) wewnątrz $(...) -- wewnętrzne pozostaje NIEROZWINIĘTE aż do hooka":
    # Lexer sam NIE rozwija zagnieżdżonych $(...) rekurencyjnie -- tylko
    # poprawnie znajduje granicę zewnętrznego $(...) licząc głębokość
    # nawiasów, i przekazuje CAŁY surowy środek (wraz z nierozwiniętym
    # `$(b)`) do hooka. To hook (w prawdziwym zesh: interpreter.
    # captureCommandOutput, przez pełny `runLine`) odpowiada za dalsze,
    # rekurencyjne rozwinięcie -- co tu symulujemy wprost przez wywołanie
    # `tokenize` na środku w samym hooku, zamiast zakładać, że lexer
    # zrobiłby to sam.
    commandSubstitutionHook = (proc(cmd: string): string =
      if cmd == "b": return "B"
      "[" & tokenize(cmd).words().join(" ") & "]")
    check tokenize("echo $(a $(b) c)").words() == @["echo", "[a B c]"]
    commandSubstitutionHook = nil

suite "lexer.tokenize - rozwijanie arytmetyczne $((...))":
  test "podstawowe działania":
    check tokenize("echo $((1+2*3))").words() == @["echo", "7"]

  test "nawiasy grupujące wewnątrz wyrażenia":
    check tokenize("echo $(((1+2)*3))").words() == @["echo", "9"]

  test "zmienna w wyrażeniu arytmetycznym (bez $)":
    localVars["N"] = "5"
    check tokenize("echo $((N+1))").words() == @["echo", "6"]
    localVars.del("N")

  test "porównania dają 1/0":
    check tokenize("echo $((5>3)) $((5<3))").words() == @["echo", "1", "0"]

echo "\nWszystkie testy lexer.nim przeszły pomyślnie."
