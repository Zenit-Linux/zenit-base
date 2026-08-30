(def nim-tools ["zesh"])
(def nim-system ["zboot" "zsrv"])
(def crystal-tools
  ["about" "cr" "dl" "mk" "ow" "gr" "pm" "rm" "sp" "kp" "wp" "sz" "zn" "lb" "wz" "pr"
   "df" "du" "zb" "fr" "so" "un" "ar" "gdz" "en" "id" "kt" "hn" "ro" "xa" "zdb"
   "echo" "pf" "wm" "up" "ni"])

(defn run
  "Uruchamia polecenie zewnętrzne i przerywa budowę w razie błędu."
  [& args]
  (print "==> " (string/join args " "))
  (def result (os/execute args :p))
  (unless (zero? result)
    (eprint "[Zenit] Polecenie nie powiodło się: " (string/join args " "))
    (os/exit 1)))

(defn run-quiet
  "Jak `run`, ale nie drukuje wywoływanego polecenia ani jego wyjścia --
   do sond wykrywających obecność narzędzi (`which x`), gdzie sam fakt
   nieudanego wywołania nie jest błędem budowy, tylko wynikiem sondy."
  [& args]
  (def devnull (file/open "/dev/null" :w))
  (def result (os/execute args :p {:out devnull :err devnull}))
  (file/close devnull)
  (zero? result))

(defn command-exists?
  [cmd]
  (run-quiet "sh" "-c" (string "command -v " cmd " >/dev/null 2>&1")))

(defn detect-package-manager
  "Zwraca jeden z :apt :dnf :pacman :zypper :apk albo nil (nieznany/
   nieobsługiwany menedżer pakietów -- `ensure-mingw` wtedy tylko ostrzega
   i pozwala kontynuować budowę reszty komponentów zamiast się wywalać)."
  []
  (cond
    (command-exists? "apt-get") :apt
    (command-exists? "dnf") :dnf
    (command-exists? "pacman") :pacman
    (command-exists? "zypper") :zypper
    (command-exists? "apk") :apk
    nil))

(defn running-as-root?
  []
  # `$USER` bywa nieustawione w minimalnych obrazach kontenerowych (nawet
  # gdy proces faktycznie działa jako root) -- pytamy `id -u` bezpośrednio
  # zamiast polegać na zmiennej środowiskowej, która może kłamać/brakować.
  (def buf @"")
  (with [f (file/temp)]
    (os/execute ["id" "-u"] :p {:out f})
    (file/seek f :set 0)
    (buffer/blit buf (:read f :all)))
  (= (string/trim (string buf)) "0"))

(defn maybe-sudo
  "Poprzedza polecenie `sudo`, chyba że już działamy jako root (typowe w
   kontenerach CI/dev, gdzie `sudo` często w ogóle nie jest zainstalowane
   -- wołanie `sudo` na takim obrazie kończy się \"No such file or
   directory\", mimo że instalacja pakietu i tak by się powiodła bez
   niego, bo proces już ma uprawnienia roota)."
  [& args]
  (if (running-as-root?) args (array/concat @["sudo"] args)))

(defn run-allow-fail
  "Jak `run`, ale nie przerywa budowy w razie niepowodzenia -- tylko
   ostrzega. Używane dla `apt-get update`: jeśli chociaż JEDNO ze
   skonfigurowanych repozytoriów systemu jest niedostępne (częsty
   przypadek na maszynach deweloperskich/CI z dodatkowymi, niezwiązanymi
   repozytoriami third-party), `apt-get update` zwraca kod błędu mimo że
   repozytoria potrzebne do zainstalowania mingw-w64 (domyślne
   Ubuntu/Debian) zaktualizowały się poprawnie -- twarde przerwanie
   całej budowy z tego powodu byłoby nieproporcjonalne."
  [& args]
  (print "==> " (string/join args " "))
  (def result (os/execute args :p))
  (unless (zero? result)
    (eprint "[Zenit] Polecenie zakończyło się niezerowym kodem (kontynuuję mimo to): " (string/join args " ")))
  result)

(defn install-mingw-for
  [pkg-manager]
  (case pkg-manager
    :apt (do
           (run-allow-fail ;(maybe-sudo "apt-get" "update"))
           (run ;(maybe-sudo "apt-get" "install" "-y" "gcc-mingw-w64-x86-64")))
    :dnf (run ;(maybe-sudo "dnf" "install" "-y" "mingw64-gcc"))
    :pacman (run ;(maybe-sudo "pacman" "-S" "--noconfirm" "mingw-w64-gcc"))
    :zypper (run ;(maybe-sudo "zypper" "install" "-y" "mingw64-cross-gcc"))
    :apk (run ;(maybe-sudo "apk" "add" "mingw-w64-gcc"))
    (eprint "[Zenit] Nieznany menedżer pakietów -- pomiń automatyczną instalację.")))

(defn ensure-mingw
  "Sprawdza, czy `x86_64-w64-mingw32-gcc` (krzyżowy kompilator wymagany
   przez `nimble buildBootloader` -- zboot celuje w UEFI/PE32+, patrz
   komentarz w zenit_base.nimble) jest dostępny w PATH, i jeśli nie,
   próbuje go zainstalować przez wykryty menedżer pakietów dystrybucji.

   Celowo NIE przerywa całej budowy, jeśli instalacja się nie powiedzie
   (brak sudo, nieznana dystrybucja, brak internetu, ...) -- bootloader
   i tak jest już opakowany w `try` w `build-nim-system` niżej (obecny
   od czasu, gdy zboot był jeszcze szkieletem, który świadomie mógł nie
   budować się w pełni). Ta funkcja tylko ZWIĘKSZA szansę, że mingw-w64
   będzie już obecny, zanim `nimble buildBootloader` w ogóle spróbuje go
   użyć -- zamiast wymagać ręcznej instalacji przed każdym czystym
   uruchomieniem `janet build.janet` (co było realnym punktem tarcia:
   zgłoszony błąd linkowania zboot był wcześniej niemożliwy do
   zdiagnozowania bez mingw-w64 zainstalowanego ręcznie z zewnątrz)."
  []
  (if (command-exists? "x86_64-w64-mingw32-gcc")
    (print "==> [Zenit] mingw-w64 (x86_64-w64-mingw32-gcc) już dostępny -- pomijam instalację")
    (do
      (print "\n[Zenit] mingw-w64 nie znaleziony w PATH -- wymagany do budowy bootloadera (UEFI/PE32+).")
      (def pm (detect-package-manager))
      (if pm
        (do
          (print "[Zenit] Wykryto menedżer pakietów: " pm " -- instaluję mingw-w64...")
          (try
            (install-mingw-for pm)
            ([err]
              (eprint "[Zenit] Automatyczna instalacja mingw-w64 nie powiodła się: " err)
              (eprint "[Zenit] Zainstaluj ręcznie (np. `apt install gcc-mingw-w64-x86-64`) "
                      "i uruchom ponownie -- reszta budowy (zesh, zsrv, narzędzia Crystal) "
                      "przebiegnie normalnie, tylko bootloader zostanie pominięty.")))
          (unless (command-exists? "x86_64-w64-mingw32-gcc")
            (eprint "[Zenit] mingw-w64 nadal niedostępny po próbie instalacji -- "
                    "`nimble buildBootloader` prawdopodobnie zawiedzie (i zostanie to tylko zalogowane, nie przerwie budowy).")))
        (do
          (eprint "[Zenit] Nie rozpoznano menedżera pakietów tej dystrybucji (sprawdzano: "
                  "apt-get/dnf/pacman/zypper/apk) -- zainstaluj mingw-w64 ręcznie "
                  "(pakiet np. `gcc-mingw-w64-x86-64` na Debian/Ubuntu, `mingw64-gcc` na Fedora).")
          (eprint "[Zenit] Kontynuuję bez niego -- reszta budowy przebiegnie normalnie, "
                  "tylko bootloader zostanie pominięty."))))))

(defn build-nim-shell
  []
  (print "\n[Zenit] Budowanie powłoki Nim: " (string/join nim-tools ", "))
  (run "nimble" "buildShell"))

(defn build-nim-system
  []
  (print "\n[Zenit] Budowanie komponentów systemowych Nim (szkielety): "
         (string/join nim-system ", "))
  (run "nimble" "buildInit")
  # Bootloader (backend UEFI) wymaga krzyżowej kompilacji przez mingw-w64
  # do PE32+ (subsystem EFI_APPLICATION) -- `ensure-mingw` (patrz wyżej)
  # próbuje go zainstalować automatycznie tuż przed tą próbą budowy, żeby
  # nie trzeba było ręcznie przygotowywać toolchaina przed każdym czystym
  # `janet build.janet`. Mimo to nadal opakowane w `try`: instalacja mogła
  # się nie powieść (brak sudo/internetu/nieznana dystrybucja), więc reszta
  # budowy (zesh, narzędzia Crystal) i tak powinna dokończyć się poprawnie.
  (ensure-mingw)
  (try
    (run "nimble" "buildBootloader")
    ([err]
      (eprint "[Zenit] Bootloader nie zbudował się: " err))))

(defn build-crystal
  []
  (print "\n[Zenit] Budowanie narzędzi Crystal: " (string/join crystal-tools ", "))
  (run "shards" "install")
  (run "shards" "build" "--release"))

(defn ensure-dist
  []
  (unless (os/stat "dist")
    (os/mkdir "dist")))

(defn copy-if-exists
  [src dst]
  (when (os/stat src)
    (run "cp" src dst)))

(defn collect-binaries
  []
  (ensure-dist)
  (each t nim-tools
    (copy-if-exists (string t "/" t) (string "dist/" t)))
  (copy-if-exists "init-system/zsrv" "dist/zsrv")
  (copy-if-exists "bootloader/BOOTX64.EFI" "dist/BOOTX64.EFI")
  (each t crystal-tools
    (copy-if-exists (string "bin/" t) (string "dist/" t))))

(defn run-tests
  []
  (print "\n[Zenit] Uruchamianie testów jednostkowych Nim (tests/)...")
  (run "nimble" "test")
  (print "\n[Zenit] Uruchamianie testów integracyjnych Crystal (spec/)...")
  (try
    (run "crystal" "spec")
    ([err]
      (eprint "[Zenit] Testy Crystal nie powiodły się lub `crystal` nie jest zainstalowane: " err))))

(defn install
  []
  (print "\n[Zenit] Instalowanie binariów (patrz scripts/install.sh)...")
  (run "bash" "scripts/install.sh"))

(defn main
  [& args]
  (build-nim-shell)
  (build-nim-system)
  (build-crystal)
  (collect-binaries)
  (print "\n[Zenit] Gotowe. Wszystkie binaria znajdują się w katalogu dist/")

  # Dodatkowe kroki na żądanie: `janet build.janet -- test` / `-- install`.
  (when (find |(= $ "test") args)
    (run-tests))
  (when (find |(= $ "install") args)
    (install)))
