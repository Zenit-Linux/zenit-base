(def stage (os/getenv "ZPM_PACKAGE_STAGE_DIR"))

(defn fail [msg]
  (eprint "recipe.janet: " msg)
  (os/exit 1))

(defn run [cmd]
  # `os/shell` zwraca kod wyjścia polecenia (jak C-owe system()) --
  # zero == sukces.
  (def code (os/shell cmd))
  (unless (zero? code)
    (fail (string "'" cmd "' zakończone kodem " code))))

(defn try-run [cmd]
  # Jak `run`, ale nie przerywa recipe przy niepowodzeniu -- zwraca
  # true/false. Do kroków, które są "najlepszym wysiłkiem".
  (zero? (os/shell cmd)))

(defn have? [tool]
  (zero? (os/shell (string "command -v " tool " >/dev/null 2>&1"))))

(defn root? []
  (zero? (os/shell "test \"$(id -u)\" = 0")))

(defn sudo- []
  (if (root?) "" (if (have? "sudo") "sudo " "")))

(defn ensure-dir [path]
  # `os/mkdir` w Janet nie jest rekurencyjne i zgłasza błąd, jeśli katalog
  # już istnieje -- oba przypadki nieszkodliwe, więc łykamy błąd.
  (try (os/mkdir path) ([_] nil)))

(defn ensure-dir-p [path]
  (var acc "")
  (each part (string/split "/" path)
    (when (> (length part) 0)
      (set acc (string acc "/" part))
      (ensure-dir acc))))

# ---------------------------------------------------------------------
# Auto-instalacja brakujących narzędzi -- wykrywa menedżer pakietów
# (apt/dnf/pacman/zypper/apk/brew), nie tylko apt/Debian. `build.janet`
# samo dba o mingw-w64 (potrzebny tylko dla bootloadera, best-effort) --
# tutaj zapewniamy trzy toolchainy, których `build.janet` NIE instaluje
# samo: `janet` (żeby w ogóle je uruchomić), `nim`/`nimble` (zesh, zsrv,
# zboot) i `crystal`/`shards` (~35 narzędzi CLI w tools/).
# ---------------------------------------------------------------------

(defn detect-pm []
  (cond
    (have? "apt-get") :apt
    (have? "dnf") :dnf
    (have? "pacman") :pacman
    (have? "zypper") :zypper
    (have? "apk") :apk
    (have? "brew") :brew
    :none))

(defn pm-install [pkgs-by-pm]
  (def pm (detect-pm))
  (def pkgs (get pkgs-by-pm pm))
  (if (not pkgs)
    false
    (let [sudo (sudo-)]
      (case pm
        :apt (try-run (string sudo "apt-get update && " sudo "env DEBIAN_FRONTEND=noninteractive apt-get install -y " pkgs))
        :dnf (try-run (string sudo "dnf install -y " pkgs))
        :pacman (try-run (string sudo "pacman -Sy --noconfirm " pkgs))
        :zypper (try-run (string sudo "zypper --non-interactive install " pkgs))
        :apk (try-run (string sudo "apk add --no-cache " pkgs))
        :brew (try-run (string "brew install " pkgs))
        false))))

(defn ensure-git []
  (unless (have? "git")
    (eprint "recipe.janet: brak 'git' -- próbuję zainstalować (" (detect-pm) ")...")
    (pm-install {:apt "git" :dnf "git" :pacman "git" :zypper "git" :apk "git" :brew "git"}))
  (unless (have? "git")
    (fail "nie udało się zapewnić 'git'")))

(defn build-janet-from-source []
  # Oficjalna metoda budowania janet ze źródeł to `git clone` + `make`
  # + `make install` (patrz README janet-lang/janet) -- projekt NIE ma
  # gotowego skryptu instalacyjnego typu curl-do-sh. Jeśli nie mamy
  # roota/sudo, instalujemy do lokalnego prefiksu (~/.local) zamiast
  # /usr/local, żeby nie wymagać uprawnień.
  (ensure-git)
  (def src "/tmp/zpk-janet-src")
  (try-run (string "rm -rf " src))
  (and
    (try-run (string "git clone --depth 1 https://github.com/janet-lang/janet.git " src))
    (try-run (string "cd " src " && make -j\"$(nproc 2>/dev/null || echo 2)\""))
    (if (or (root?) (have? "sudo"))
      (try-run (string "cd " src " && " (sudo-) "make install"))
      (let [prefix (string (os/getenv "HOME") "/.local")]
        (when (try-run (string "cd " src " && make install PREFIX=" prefix))
          (os/setenv "PATH" (string prefix "/bin:" (os/getenv "PATH")))
          true)))))

(defn ensure-janet []
  # `janet` -- brak w domyślnych repozytoriach wielu dystrybucji;
  # próbujemy menedżera pakietów, a jeśli go nie ma, budujemy ze
  # źródeł (`git clone` + `make` + `make install`, tak jak mówi
  # README janet-lang/janet -- działa niezależnie od dystrybucji).
  (unless (have? "janet")
    (eprint "recipe.janet: brak 'janet' -- próbuję zainstalować (" (detect-pm) ")...")
    (unless (pm-install {:apt "janet" :dnf "janet" :pacman "janet" :zypper "janet" :apk "janet" :brew "janet"})
      (eprint "recipe.janet: menedżer pakietów nie ma 'janet' -- buduję ze źródeł (git clone + make install)...")
      (build-janet-from-source)))
  (unless (have? "janet")
    (fail "nie udało się zapewnić 'janet' -- zainstaluj ręcznie (https://janet-lang.org) i uruchom ponownie")))

(defn ensure-nim []
  # nim/nimble -- pakiet dystrybucyjny, w ostateczności choosenim
  # (oficjalny instalator, nie wymaga roota).
  (unless (have? "nimble")
    (eprint "recipe.janet: brak 'nimble' (Nim) -- próbuję zainstalować (" (detect-pm) ")...")
    (unless (pm-install {:apt "nim" :dnf "nim" :pacman "nim" :zypper "nim" :apk "nim" :brew "nim"})
      (eprint "recipe.janet: menedżer pakietów nie ma 'nim' -- próbuję choosenim (oficjalny instalator)...")
      (try-run "curl https://nim-lang.org/choosenim/init.sh -sSf | sh -s -- -y")
      (def nim-bin-dir (string (os/getenv "HOME") "/.nimble/bin"))
      (when (os/stat (string nim-bin-dir "/nimble") :mode)
        (os/setenv "PATH" (string nim-bin-dir ":" (os/getenv "PATH"))))))
  (unless (have? "nimble")
    (fail "nie udało się zapewnić 'nimble' (Nim >= 2.0.0) -- zainstaluj ręcznie (https://nim-lang.org/install.html) i uruchom ponownie")))

(defn ensure-crystal []
  # crystal/shards -- pakiet dystrybucyjny, w ostateczności oficjalny
  # skrypt instalacyjny Crystala (sam wykrywa dystrybucję i dobiera
  # metodę -- apt/yum/pacman/curl+tar -- patrz crystal-lang.org/install).
  (unless (have? "shards")
    (eprint "recipe.janet: brak 'shards' (Crystal) -- próbuję zainstalować (" (detect-pm) ")...")
    (unless (pm-install {:apt "crystal" :dnf "crystal" :pacman "crystal" :zypper "crystal" :apk "crystal" :brew "crystal"})
      (eprint "recipe.janet: menedżer pakietów nie ma 'crystal' -- próbuję oficjalnego skryptu instalacyjnego...")
      (when (try-run "curl -fsSL https://crystal-lang.org/install.sh -o /tmp/zpk-crystal-install.sh && chmod +x /tmp/zpk-crystal-install.sh")
        (try-run (string (sudo-) "bash /tmp/zpk-crystal-install.sh")))))
  (unless (have? "shards")
    (fail "nie udało się zapewnić 'shards'/'crystal' (>= 1.10.0) -- zainstaluj ręcznie (https://crystal-lang.org/install) i uruchom ponownie")))

# packaging/recipe.janet leży w <repo>/packaging -- korzeń repo to
# katalog wyżej, niezależnie od tego, skąd faktycznie wywołano `zpk
# build` (zpk zawsze ustawia cwd recipe na katalog z zpk.build).
(def repo-root (string (os/cwd) "/.."))
(def dist (string repo-root "/dist"))

(def prebuilt-dist (os/getenv "ZPK_PACKAGING_PREBUILT_DIST"))

(def dist-dir
  (if (and prebuilt-dist (> (length prebuilt-dist) 0))
    # CI/operator już zbudował Zenit Base wcześniej w tym samym biegu
    # (np. osobny krok `janet build.janet` przed wywołaniem `zpk
    # build`) -- nie buduj drugi raz, użyj gotowego katalogu dist/.
    # Pomijamy też poniższą logikę instalowania janet/nim/crystal.
    prebuilt-dist
    (do
      (ensure-janet)
      (ensure-nim)
      (ensure-crystal)
      # `janet build.janet` samo: buduje zesh (`nimble buildShell`),
      # zsrv (`nimble buildInit`), próbuje zbudować zboot (UEFI,
      # `nimble buildBootloader` -- best-effort, wymaga mingw-w64,
      # który `ensure-mingw` wewnątrz build.janet stara się
      # zainstalować samo; brak bootloadera NIE przerywa reszty
      # budowy), oraz wszystkie narzędzia Crystal z tools/
      # (`shards install && shards build --release`) -- i na końcu
      # kopiuje wszystko do dist/ (patrz `collect-binaries`).
      (run (string "cd " repo-root " && janet build.janet"))
      dist)))

(unless (os/stat dist-dir :mode)
  (fail (string "katalog dist/ nie istnieje: " dist-dir " -- `janet build.janet` prawdopodobnie zawiodło wcześniej")))

(def bin-dir (string stage "/usr/bin"))
(ensure-dir stage)
(ensure-dir (string stage "/usr"))
(ensure-dir bin-dir)

# Wszystko w dist/ poza BOOTX64.EFI to zwykła binarka CLI (zesh, zsrv,
# ~35 narzędzi Crystal) -- ląduje w usr/bin/. BOOTX64.EFI to obraz
# UEFI, nie binarka do uruchomienia z powłoki -- ląduje osobno, w
# miejscu specyficznym dla pakietu (patrz komentarz niżej), nie
# bezpośrednio w /boot/efi (żaden pakiet nie powinien milcząco pisać
# do ESP -- to zadanie instalatora/administratora systemu).
(def bootloader-name "BOOTX64.EFI")
(var staged-count 0)

(each entry (os/dir dist-dir)
  (unless (= entry bootloader-name)
    (def src (string dist-dir "/" entry))
    (when (= (os/stat src :mode) :file)
      (def dest (string bin-dir "/" entry))
      (spit dest (slurp src))
      (run (string "chmod +x " dest))
      (++ staged-count))))

(when (zero? staged-count)
  (fail (string "w " dist-dir " nie znaleziono ani jednej binarki do zapakowania")))

(def bootloader-src (string dist-dir "/" bootloader-name))
(when (os/stat bootloader-src :mode)
  (def boot-dir (string stage "/usr/lib/zenit-base/boot"))
  (ensure-dir-p boot-dir)
  (spit (string boot-dir "/" bootloader-name) (slurp bootloader-src)))
