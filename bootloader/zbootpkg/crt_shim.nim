{.push stackTrace: off, checks: off.}

proc initCrtShim*() =
  ## Nic nie robi w praktyce (wszystkie symbole niżej są `{.exportc.}`,
  ## więc trafiają do linkowanego obiektu niezależnie od tego, czy ktoś
  ## jawnie wywołuje coś z tego modułu) -- istnieje wyłącznie po to, żeby
  ## `import zbootpkg/crt_shim` w zboot.nim miało jawne, udokumentowane
  ## miejsce użycia zamiast ostrzeżenia kompilatora "imported and not
  ## used" (moduł JEST używany -- przez linker, nie przez wywołanie Nim).
  discard

# ---- 1. funkcjonalne -------------------------------------------------------

proc zenitMemcpy(dest, src: pointer, n: csize_t): pointer {.exportc: "memcpy", cdecl.} =
  var d = cast[ptr UncheckedArray[uint8]](dest)
  var s = cast[ptr UncheckedArray[uint8]](src)
  for i in 0 ..< int(n):
    d[i] = s[i]
  dest

proc zenitMemmove(dest, src: pointer, n: csize_t): pointer {.exportc: "memmove", cdecl.} =
  # W przeciwieństwie do memcpy musi poprawnie obsłużyć nakładające się
  # zakresy -- kopiujemy od tyłu, gdy dest > src (klasyczna technika).
  var d = cast[ptr UncheckedArray[uint8]](dest)
  var s = cast[ptr UncheckedArray[uint8]](src)
  if cast[uint](dest) > cast[uint](src):
    for i in countdown(int(n) - 1, 0):
      d[i] = s[i]
  else:
    for i in 0 ..< int(n):
      d[i] = s[i]
  dest

proc zenitMemset(dest: pointer, value: cint, n: csize_t): pointer {.exportc: "memset", cdecl.} =
  var d = cast[ptr UncheckedArray[uint8]](dest)
  let b = uint8(value and 0xFF)
  for i in 0 ..< int(n):
    d[i] = b
  dest

proc zenitStrlen(s: cstring): csize_t {.exportc: "strlen", cdecl.} =
  var i = 0
  while s[i] != '\0':
    inc i
  csize_t(i)

proc zenitCalloc(nmemb, size: csize_t): pointer {.exportc: "calloc", cdecl.} =
  ## `calloc` = `malloc` (dostarczone w allocator.nim, ten sam symbol C
  ## `malloc`, więc odwołujemy się do niego przez FFI, nie przez import
  ## Nim-do-Nim -- allocator.nim nie eksportuje nazwy Nim, tylko symbol C)
  ## + wyzerowanie pamięci.
  proc mallocC(size: csize_t): pointer {.importc: "malloc", cdecl.}
  let total = csize_t(uint(nmemb) * uint(size))
  let p = mallocC(total)
  if p != nil and total > 0:
    discard zenitMemset(p, 0, total)
  p

# ---- 2. stuby (ścieżki nigdy nieosiągane w normalnym działaniu) -----------

proc zenitSignal(sig: cint, handler: pointer): pointer {.exportc: "signal", cdecl.} =
  ## No-op -- nie ma czym "sygnalizować" w środowisku bez systemu
  ## operacyjnego/procesów. Zwraca nil zamiast poprzedniego handlera
  ## (nikt w tym kodzie nie sprawdza wartości zwracanej).
  nil

proc zenitExit(code: cint) {.exportc: "exit", cdecl, noreturn.} =
  ## Wołane wyłącznie przez domyślną ścieżkę Nima dla nieobsłużonego
  ## wyjątku/asercji -- nie ma dokąd "wyjść" w bootloaderze bez systemu
  ## operacyjnego pod spodem, więc zatrzymujemy procesor w pętli
  ## (odpowiednik "halt", bezpieczniejszy niż cokolwiek niezdefiniowane).
  while true:
    discard

proc zenitFflush(stream: pointer): cint {.exportc: "fflush", cdecl.} =
  0 # sukces -- nie mamy buforowanego stdio do zrzucenia

proc zenitFwrite(buf: pointer, size, count: csize_t, stream: pointer): csize_t {.exportc: "fwrite", cdecl.} =
  ## No-op zwracający `count` (tyle, ile "zapisano") -- Nim wywołuje to
  ## tylko przy formatowaniu komunikatu nieobsłużonego wyjątku na
  ## (nieistniejące tu) stderr; prawdziwe wyjście tekstowe zboot idzie
  ## zawsze przez zbootpkg/console.efiPrint (UEFI Simple Text Output),
  ## nie przez stdio.
  count

var gDummyFileHandle: array[8, uint8] # placeholder FILE* -- treść nigdy nie jest czytana

proc zenitAcrtIobFunc(index: cuint): pointer {.exportc: "__acrt_iob_func", cdecl.} =
  ## mingw-w64: pośrednik zwracający FILE* dla stdin/stdout/stderr wg
  ## indeksu. Zwracamy adres nieużywanego bufora -- wystarczy, żeby
  ## symbol istniał i wskaźnik był nie-null (fwrite/fflush powyżej i tak
  ## ignorują jego zawartość).
  addr gDummyFileHandle

# mingw-w64 generuje wywołania `__acrt_iob_func` jako pośredni import z
# DLL (konwencja `__imp_<symbol>` = zmienna globalna zawierająca adres
# funkcji, wołana przez `call [__imp_<symbol>]`, nie bezpośrednie `call
# <symbol>`) -- normalnie rozwiązywana przez linkowanie z ucrtbase.dll.
# Linkujemy `-nostdlib` (brak jakiegokolwiek .dll), więc musimy sami
# dostarczyć TĘ zmienną wskaźnikową, nie tylko samą funkcję pod jej
# "zwykłą" nazwą -- inaczej linker zgłasza "undefined reference to
# '__imp___acrt_iob_func'" mimo że `__acrt_iob_func` powyżej już istnieje.
var zenitAcrtIobFuncImp {.exportc: "__imp___acrt_iob_func".}: pointer = cast[pointer](zenitAcrtIobFunc)

proc zenitCrtMain() {.exportc: "__main", cdecl.} =
  ## GCC/mingw wstawia wywołanie `__main()` na początku funkcji `main`-
  ## podobnych, żeby uruchomić konstruktory globalnych obiektów C++/
  ## sekcji `.ctors`. Nim nie generuje takich konstruktorów dla tego
  ## kodu (freestanding, bez C++), więc pusta implementacja jest
  ## poprawna -- symbol musi tylko ISTNIEĆ, żeby linker się nie
  ## wywalił.
  discard

{.pop.}
