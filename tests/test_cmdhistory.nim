import std/unittest
import "../zesh/zeshpkg/cmdhistory"
import "../zesh/zeshpkg/state"

suite "cmdhistory.expandHistoryRefs":
  setup:
    history = @["echo pierwsze", "ls -la", "echo drugie"]

  test "!! rozwija się do ostatniego polecenia":
    let (line, ok) = expandHistoryRefs("!!")
    check ok == true
    check line == "echo drugie"

  test "!! z pustą historią zwraca błąd (nie wykonuje niczego)":
    history = @[]
    let (_, ok) = expandHistoryRefs("!!")
    check ok == false

  test "!n rozwija się do polecenia o numerze n (1-indeksowane)":
    let (line, ok) = expandHistoryRefs("!2")
    check ok == true
    check line == "ls -la"

  test "!n poza zakresem zwraca błąd":
    let (_, ok) = expandHistoryRefs("!99")
    check ok == false

  test "!prefix zwraca NAJNOWSZE pasujące polecenie (szukane wstecz)":
    let (line, ok) = expandHistoryRefs("!echo")
    check ok == true
    check line == "echo drugie" # nie "echo pierwsze" -- najnowsze wygrywa

  test "!prefix bez dopasowania zwraca błąd":
    let (_, ok) = expandHistoryRefs("!zzz")
    check ok == false

  test "linia bez '!' na początku przechodzi bez zmian":
    let (line, ok) = expandHistoryRefs("echo trzecie")
    check ok == true
    check line == "echo trzecie"

  test "'!' pojedynczy znak na końcu linii nie jest odwołaniem do historii":
    let (line, ok) = expandHistoryRefs("echo !")
    check ok == true
    check line == "echo !"

echo "\nWszystkie testy cmdhistory.nim przeszły pomyślnie."
