require "spec"
require "file_utils"

# spec/tools_spec.cr — testy integracyjne dla narzędzi CLI Zenit Linux.
#
# STATUS: szkielet+ — pokrywa reprezentatywną próbkę narzędzi (nie
# wszystkie 31), demonstrując wzorzec testowania: budujemy binaria przez
# `shards build --release`, a testy uruchamiają je jako podprocesy i
# sprawdzają kod wyjścia oraz stdout/stderr. Rozszerzenie o pozostałe
# narzędzia to naturalna kontynuacja tego pliku.
#
# WYMAGANIE: przed uruchomieniem `crystal spec` należy zbudować binaria:
#   shards build --release
#
# Testy dla narzędzi, których binarka nie została zbudowana, zawiodą z
# czytelnym komunikatem błędu (brak pliku) zamiast cichego pominięcia —
# celowo, żeby CI wyraźnie sygnalizowało brakujący krok budowania.

BIN_DIR = File.join(__DIR__, "..", "bin")

private def tool_path(name : String) : String
  File.join(BIN_DIR, name)
end

private def run_tool(name : String, args : Array(String) = [] of String, chdir : String? = nil)
  path = tool_path(name)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run(path, args: args, output: output, error: error, chdir: chdir)
  {status: status, stdout: output.to_s, stderr: error.to_s}
end

private def with_tmp_dir(&)
  dir = File.join(Dir.tempdir, "zenit-spec-#{Random.rand(1_000_000)}")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir) if Dir.exists?(dir)
  end
end

Spec.before_suite do
  unless Dir.exists?(BIN_DIR)
    STDERR.puts "UWAGA: katalog '#{BIN_DIR}' nie istnieje."
    STDERR.puts "Uruchom najpierw: shards build --release"
  end
end

describe "cr (mkdir)" do
  it "tworzy katalog" do
    with_tmp_dir do |dir|
      target = File.join(dir, "nowy")
      result = run_tool("cr", [target])
      result[:status].success?.should be_true
      Dir.exists?(target).should be_true
    end
  end

  it "zwraca błąd, gdy katalog nadrzędny nie istnieje bez -p" do
    with_tmp_dir do |dir|
      target = File.join(dir, "brak", "zagniezdzony")
      result = run_tool("cr", [target])
      result[:status].success?.should be_false
    end
  end

  it "tworzy zagnieżdżoną strukturę z -p" do
    with_tmp_dir do |dir|
      target = File.join(dir, "a", "b", "c")
      result = run_tool("cr", ["-p", target])
      result[:status].success?.should be_true
      Dir.exists?(target).should be_true
    end
  end
end

describe "mk (touch)" do
  it "tworzy pusty plik" do
    with_tmp_dir do |dir|
      target = File.join(dir, "plik.txt")
      run_tool("mk", [target])
      File.exists?(target).should be_true
    end
  end
end

describe "dl (rm z koszem)" do
  it "przenosi plik do kosza zamiast kasować trwale" do
    with_tmp_dir do |dir|
      target = File.join(dir, "do_usuniecia.txt")
      File.write(target, "tresc")
      run_tool("dl", [target])
      File.exists?(target).should be_false
    end
  end

  it "zwraca błąd dla nieistniejącego pliku" do
    with_tmp_dir do |dir|
      result = run_tool("dl", [File.join(dir, "nie_istnieje.txt")])
      result[:status].success?.should be_false
    end
  end
end

describe "wp (cat)" do
  it "wypisuje zawartość pliku bez zmian" do
    with_tmp_dir do |dir|
      f = File.join(dir, "a.txt")
      File.write(f, "linia1\nlinia2\n")
      result = run_tool("wp", [f])
      result[:stdout].should eq("linia1\nlinia2\n")
    end
  end

  it "numeruje linie z -n" do
    with_tmp_dir do |dir|
      f = File.join(dir, "a.txt")
      File.write(f, "x\ny\n")
      result = run_tool("wp", ["-n", f])
      result[:stdout].should contain("1")
      result[:stdout].should contain("2")
    end
  end
end

describe "so (sort)" do
  it "sortuje linie alfabetycznie" do
    with_tmp_dir do |dir|
      input_file = File.join(dir, "input.txt")
      File.write(input_file, "banan\njablko\ncytryna\n")
      result = run_tool("so", [input_file])
      result[:stdout].should eq("banan\ncytryna\njablko\n")
    end
  end

  it "sortuje numerycznie z -n" do
    with_tmp_dir do |dir|
      input_file = File.join(dir, "input.txt")
      File.write(input_file, "10\n2\n1\n")
      result = run_tool("so", ["-n", input_file])
      result[:stdout].should eq("1\n2\n10\n")
    end
  end
end

describe "un (uniq)" do
  it "usuwa sąsiadujące duplikaty" do
    with_tmp_dir do |dir|
      input_file = File.join(dir, "input.txt")
      File.write(input_file, "a\na\nb\nb\nb\nc\n")
      result = run_tool("un", [input_file])
      result[:stdout].should eq("a\nb\nc\n")
    end
  end
end

describe "lb (wc)" do
  it "liczy linie, słowa i bajty" do
    with_tmp_dir do |dir|
      f = File.join(dir, "a.txt")
      File.write(f, "a b c\nd e\n")
      result = run_tool("lb", [f])
      result[:status].success?.should be_true
      result[:stdout].should contain(f)
    end
  end
end

describe "id" do
  it "wypisuje uid i gid bieżącego procesu" do
    result = run_tool("id")
    result[:stdout].should contain("uid=")
    result[:stdout].should contain("gid=")
  end

  it "-u wypisuje tylko liczbę" do
    result = run_tool("id", ["-u"])
    result[:stdout].strip.to_i?.should_not be_nil
  end
end

describe "kt (whoami)" do
  it "wypisuje niepustą nazwę użytkownika" do
    result = run_tool("kt")
    result[:status].success?.should be_true
    result[:stdout].strip.empty?.should be_false
  end
end

describe "echo" do
  it "wypisuje argumenty rozdzielone spacjami z nową linią na końcu" do
    result = run_tool("echo", ["cześć", "świecie"])
    result[:stdout].should eq("cześć świecie\n")
  end

  it "-n pomija końcową nową linię" do
    result = run_tool("echo", ["-n", "test"])
    result[:stdout].should eq("test")
  end
end

describe "ar (tar)" do
  it "tworzy i rozpakowuje archiwum zachowując zawartość pliku" do
    with_tmp_dir do |src_dir|
      with_tmp_dir do |dest_dir|
        source_file = File.join(src_dir, "dane.txt")
        File.write(source_file, "przykladowa tresc\n")
        archive = File.join(src_dir, "test.tar")

        create_result = run_tool("ar", ["-c", "-f", archive, source_file])
        create_result[:status].success?.should be_true
        File.exists?(archive).should be_true

        extract_result = run_tool("ar", ["-x", "-f", archive], chdir: dest_dir)
        extract_result[:status].success?.should be_true

        extracted = File.join(dest_dir, source_file.lchop("/"))
        File.exists?(extracted).should be_true
        File.read(extracted).should eq("przykladowa tresc\n")
      end
    end
  end
end

describe "zn (find)" do
  it "znajduje plik po nazwie" do
    with_tmp_dir do |dir|
      File.write(File.join(dir, "cel.txt"), "")
      File.write(File.join(dir, "inny.log"), "")
      result = run_tool("zn", [dir, "--name", "*.txt"])
      result[:stdout].should contain("cel.txt")
      result[:stdout].should_not contain("inny.log")
    end
  end
end
