(def nim-tools ["zesh" "cr" "dl" "mk"])
(def crystal-tools ["about" "ow" "gr" "pm"])

(defn run
  "Uruchamia polecenie zewnętrzne i przerywa budowę w razie błędu."
  [& args]
  (print "==> " (string/join args " "))
  (def result (os/execute args :p))
  (unless (zero? result)
    (eprint "[Zenith] Polecenie nie powiodło się: " (string/join args " "))
    (os/exit 1)))

(defn build-nim
  []
  (print "\n[Zenith] Budowanie narzędzi Nim: " (string/join nim-tools ", "))
  (run "nimble" "build" "-d:release" "-y"))

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
  (each t crystal-tools
    (copy-if-exists (string "bin/" t) (string "dist/" t))))

(defn main
  [&]
  (build-nim)
  (build-crystal)
  (collect-binaries)
  (print "\n[Zenith] Gotowe. Wszystkie binaria znajdują się w katalogu dist/"))
