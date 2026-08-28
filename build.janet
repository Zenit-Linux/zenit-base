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
  # do PE32+ (subsystem EFI_APPLICATION); może zawieść, dopóki toolchain
  # nie jest zainstalowany lub dopóki parsowanie ELF/handoff do jądra nie
  # są dokończone — patrz TODO w bootloader/zboot.nim. Nie przerywamy
  # całej budowy w razie błędu.
  (try
    (run "nimble" "buildBootloader")
    ([err]
      (eprint "[Zenit] Bootloader jeszcze nie buduje się w pełni (szkielet): " err))))

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
