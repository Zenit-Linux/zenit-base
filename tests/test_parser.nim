import std/[unittest, strutils]
import "../zesh/zeshpkg/parser"
import "../zesh/zeshpkg/lexer"

suite "parser.splitStatements":
  test "pojedyncze polecenie, brak separatora":
    let stmts = splitStatements(tokenize("echo hi"))
    check stmts.len == 1
    check stmts[0].sepAfter == sepNone
    check stmts[0].background == false

  test "potok w jednej instrukcji (| nie dzieli na osobne Statement)":
    let stmts = splitStatements(tokenize("a | b | c"))
    check stmts.len == 1
    check stmts[0].pipeline.len == 3

  test "; dzieli na dwie instrukcje z sepSeq":
    let stmts = splitStatements(tokenize("a; b"))
    check stmts.len == 2
    check stmts[0].sepAfter == sepSeq
    check stmts[1].sepAfter == sepNone

  test "&& daje sepAnd":
    check splitStatements(tokenize("a && b"))[0].sepAfter == sepAnd

  test "|| daje sepOr":
    check splitStatements(tokenize("a || b"))[0].sepAfter == sepOr

  test "& (tło) ustawia background na TEJ instrukcji":
    let stmts = splitStatements(tokenize("sleep 1 &"))
    check stmts.len == 1
    check stmts[0].background == true

suite "parser.splitRawStatements":
  test "linia bez separatorów -- jeden fragment":
    let raw = splitRawStatements("echo hello")
    check raw.len == 1
    check raw[0].text == "echo hello"
    check raw[0].sep == sepNone

  test "; dzieli na surowym tekście, z poprawnym sep":
    let raw = splitRawStatements("false; echo dalej")
    check raw.len == 2
    check raw[0].text.strip() == "false"
    check raw[0].sep == sepSeq
    check raw[1].text.strip() == "echo dalej"
    check raw[1].sep == sepNone

  test "&& i || rozpoznawane osobno":
    let raw1 = splitRawStatements("a && b")
    check raw1.len == 2
    check raw1[0].sep == sepAnd

    let raw2 = splitRawStatements("a || b")
    check raw2.len == 2
    check raw2[0].sep == sepOr

  test "; WEWNĄTRZ podwójnego cudzysłowu NIE dzieli instrukcji":
    let raw = splitRawStatements("echo \"a; b\"; echo koniec")
    check raw.len == 2
    check raw[0].text.strip() == "echo \"a; b\""
    check raw[1].text.strip() == "echo koniec"

  test "; WEWNĄTRZ pojedynczego cudzysłowu NIE dzieli instrukcji":
    let raw = splitRawStatements("echo 'a; b'; echo koniec")
    check raw.len == 2
    check raw[0].text.strip() == "echo 'a; b'"

  test "; WEWNĄTRZ $(...) NIE dzieli instrukcji":
    let raw = splitRawStatements("echo $(a; b); echo koniec")
    check raw.len == 2
    check raw[0].text.strip() == "echo $(a; b)"
    check raw[1].text.strip() == "echo koniec"

  test "pojedynczy | (potok) NIE jest granicą instrukcji":
    let raw = splitRawStatements("a | b; c")
    check raw.len == 2
    check raw[0].text.strip() == "a | b"
    check raw[1].text.strip() == "c"

  test "trzy instrukcje łańcuchowane różnymi separatorami":
    let raw = splitRawStatements("a; b && c || d")
    check raw.len == 4
    check raw[0].sep == sepSeq
    check raw[1].sep == sepAnd
    check raw[2].sep == sepOr
    check raw[3].sep == sepNone

  test "pusta linia daje pustą listę instrukcji":
    check splitRawStatements("").len == 0

  test "kluczowa własność: KAŻDY fragment, po ponownej tokenizacji, daje dokładnie jedną Statement":
    # To jest właściwość, na której polega interpreter.runLine: skoro
    # splitRawStatements już podzieliło linię na granicach ;/&&/||, każdy
    # zwrócony fragment, przepuszczony z osobna przez tokenize+
    # splitStatements, MUSI dać dokładnie jedną instrukcję (bez kolejnego
    # podziału) -- inaczej `interpreter.runLine` niepoprawnie zliczałby
    # `lastExitCode` między iteracjami.
    for line in ["echo a; echo b; echo c", "a && b || c", "sleep 1 & echo x; echo y"]:
      for rawStmt in splitRawStatements(line):
        let again = splitStatements(tokenize(rawStmt.text))
        check again.len == 1

echo "\nWszystkie testy parser.nim (zesh) przeszły pomyślnie."
