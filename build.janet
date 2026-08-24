(def nim-tools ["zesh"])
(def nim-system ["zboot" "zsrv"])
(def crystal-tools
  ["about" "cr" "dl" "mk" "ow" "gr" "pm" "rm" "sp" "kp" "wp" "sz" "zn" "lb" "wz" "pr"])

(defn run
  "Uruchamia polecenie zewnętrzne i przerywa budowę w razie błędu."
  [& args]
  (print "==> " (string/join args " "))
  (def result (os/execute args :p))
  (unless (zero? result)
    (eprint "[Zenith] Polecenie nie powiodło się: " (string/join args " "))
    (os/exit 1)))

(defn build-nim-shell
  []
  (print "\n[Zenith] Budowanie powłoki Nim: " (string/join nim-tools ", "))
  (run "nimble" "buildShell"))

(defn build-nim-system
  []
  (print "\n[Zenith] Budowanie komponentów systemowych Nim (szkielety): "
         (string/join nim-system ", "))
  (run "nimble" "buildInit")
  # Bootloader wymaga celu --os:standalone; może zawieść, dopóki linker
  # script i pełna implementacja long mode nie są gotowe — patrz TODO
  # w bootloader/zboot.nim. Nie przerywamy całej budowy w razie błędu.
  (try
    (run "nimble" "buildBootloader")
    ([err]
      (eprint "[Zenith] Bootloader jeszcze nie buduje się w pełni (szkielet): " err))))

(defn build-crystal
  []
  (print "\n[Zenith] Budowanie narzędzi Crystal: " (string/join crystal-tools ", "))
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
  (copy-if-exists "bootloader/zboot" "dist/zboot")
  (each t crystal-tools
    (copy-if-exists (string "bin/" t) (string "dist/" t))))

(defn main
  [&]
  (build-nim-shell)
  (build-nim-system)
  (build-crystal)
  (collect-binaries)
  (print "\n[Zenith] Gotowe. Wszystkie binaria znajdują się w katalogu dist/"))
