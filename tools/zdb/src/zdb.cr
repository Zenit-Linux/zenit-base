require "option_parser"
require "./elf_symbols"
require "./disasm"

# zdb — Zenit Linux Debugger (odpowiednik GNU Debuggera)
#
# STATUS: szkielet+ — interaktywny debugger oparty bezpośrednio na
# ptrace(2), bez zewnętrznych zależności. Obsługuje: uruchomienie i
# śledzenie procesu potomnego, punkty przerwania (int3 / 0xCC) z
# rozwiązywaniem nazw funkcji z tabeli symboli ELF (elf_symbols.cr), krok
# po kroku, podgląd/zmianę rejestrów i pamięci, prosty backtrace przez
# łańcuch RBP (z nazwami symboli), oraz podstawową deasemblację
# (disasm.cr — poprawna długość instrukcji, ale bez pełnych operandów).
# Podłączanie się do już działającego procesu (PTRACE_ATTACH —
# zadeklarowane, ale niepodłączone do żadnej komendy) i demangling C++
# pozostają jako TODO.
#
# Użycie:
#   zdb PROGRAM [ARGUMENTY...]     — uruchamia sesję debugowania od razu
#   zdb                              — wchodzi w tryb interaktywny, gdzie
#                                       polecenie `run` startuje program

VERSION = "0.1.0"

lib LibZdb
  PTRACE_TRACEME    =  0
  PTRACE_PEEKTEXT   =  1
  PTRACE_PEEKDATA   =  2
  PTRACE_POKETEXT   =  4
  PTRACE_POKEDATA   =  5
  PTRACE_CONT       =  7
  PTRACE_KILL       =  8
  PTRACE_SINGLESTEP =  9
  PTRACE_GETREGS    = 12
  PTRACE_SETREGS    = 13
  PTRACE_ATTACH     = 16
  PTRACE_DETACH     = 17

  fun ptrace(request : LibC::Int, pid : LibC::PidT, addr : Void*, data : Void*) : LibC::Long
  fun c_fork = fork : LibC::PidT
  fun execvp(file : LibC::Char*, argv : LibC::Char**) : LibC::Int
  fun waitpid(pid : LibC::PidT, status : LibC::Int*, options : LibC::Int) : LibC::PidT
  fun kill(pid : LibC::PidT, sig : LibC::Int) : LibC::Int

  # struct user_regs_struct z <sys/user.h> na x86_64 — kolejność pól MUSI
  # dokładnie odpowiadać ABI jądra Linuksa, inaczej GETREGS/SETREGS czytają
  # i zapisują nieprawidłowe przesunięcia.
  struct UserRegsStruct
    r15 : LibC::ULong
    r14 : LibC::ULong
    r13 : LibC::ULong
    r12 : LibC::ULong
    rbp : LibC::ULong
    rbx : LibC::ULong
    r11 : LibC::ULong
    r10 : LibC::ULong
    r9  : LibC::ULong
    r8  : LibC::ULong
    rax : LibC::ULong
    rcx : LibC::ULong
    rdx : LibC::ULong
    rsi : LibC::ULong
    rdi : LibC::ULong
    orig_rax : LibC::ULong
    rip : LibC::ULong
    cs  : LibC::ULong
    eflags : LibC::ULong
    rsp : LibC::ULong
    ss  : LibC::ULong
    fs_base : LibC::ULong
    gs_base : LibC::ULong
    ds : LibC::ULong
    es : LibC::ULong
    fs : LibC::ULong
    gs : LibC::ULong
  end
end

SIGTRAP = 5
INT3_OPCODE = 0xCC_u8

class Debuggee
  property pid : Int32 = 0
  property running : Bool = false
  property breakpoints : Hash(UInt64, UInt64) = {} of UInt64 => UInt64 # adres -> oryginalne 8 bajtów
  property symbols : Array(ElfSymbols::Symbol) = [] of ElfSymbols::Symbol
  property program_path : String = ""

  def symbol_for(addr : UInt64) : String?
    ElfSymbols.resolve(symbols, addr)
  end

  def format_addr(addr : UInt64) : String
    sym = symbol_for(addr)
    sym ? "0x#{addr.to_s(16)} <#{sym}>" : "0x#{addr.to_s(16)}"
  end

  def build_argv(args : Array(String)) : Pointer(LibC::Char*)
    ptr = Pointer(LibC::Char*).malloc(args.size + 1)
    args.each_with_index { |a, i| ptr[i] = a.to_unsafe.as(LibC::Char*) }
    ptr[args.size] = Pointer(LibC::Char).null
    ptr
  end

  def start(command : Array(String))
    @program_path = command[0]
    @symbols = ElfSymbols.load(@program_path)
    puts "zdb: wczytano #{@symbols.size} symboli z '#{@program_path}'" unless @symbols.empty?

    pid = LibZdb.c_fork
    if pid == 0
      # Proces potomny: zgłoś się do śledzenia, potem wykonaj docelowy program.
      LibZdb.ptrace(LibZdb::PTRACE_TRACEME, 0, Pointer(Void).null, Pointer(Void).null)
      argv = build_argv(command)
      LibZdb.execvp(command[0].to_unsafe.as(LibC::Char*), argv)
      exit 127 # execvp nie wróciło => się nie powiodło
    end

    @pid = pid
    status = 0
    LibZdb.waitpid(pid, pointerof(status), 0) # czekaj na pierwszy SIGTRAP (po execve)
    @running = true
    puts "zdb: uruchomiono '#{command.join(" ")}' jako pid #{pid} (zatrzymany na wejściu)"
  end

  def peek_word(addr : UInt64) : UInt64
    LibZdb.ptrace(LibZdb::PTRACE_PEEKTEXT, @pid, Pointer(Void).new(addr), Pointer(Void).null).to_u64!
  end

  def poke_word(addr : UInt64, value : UInt64)
    LibZdb.ptrace(LibZdb::PTRACE_POKETEXT, @pid, Pointer(Void).new(addr), Pointer(Void).new(value))
  end

  def read_bytes(addr : UInt64, count : Int32) : Bytes
    ## Odczytuje `count` bajtów z pamięci śledzonego procesu, słowami po
    ## 8 bajtów przez PEEKTEXT — używane przez deasemblację (disasm.cr).
    buf = Bytes.new(count)
    words_needed = (count + 7) // 8
    (0...words_needed).each do |wi|
      w = peek_word(addr + (wi.to_u64 * 8))
      8.times do |bi|
        idx = wi * 8 + bi
        break if idx >= count
        buf[idx] = ((w >> (bi * 8)) & 0xFF).to_u8
      end
    end
    buf
  end

  def set_breakpoint(addr : UInt64)
    return unless @running
    original = peek_word(addr)
    breakpoints[addr] = original
    patched = (original & ~0xFF_u64) | INT3_OPCODE.to_u64
    poke_word(addr, patched)
    puts "zdb: ustawiono punkt przerwania pod #{format_addr(addr)}"
  end

  def get_regs : LibZdb::UserRegsStruct
    regs = LibZdb::UserRegsStruct.new
    LibZdb.ptrace(LibZdb::PTRACE_GETREGS, @pid, Pointer(Void).null, pointerof(regs).as(Void*))
    regs
  end

  def set_regs(regs : LibZdb::UserRegsStruct)
    r = regs
    LibZdb.ptrace(LibZdb::PTRACE_SETREGS, @pid, Pointer(Void).null, pointerof(r).as(Void*))
  end

  def restore_breakpoint_if_hit
    ## Wywoływane tuż po zatrzymaniu na SIGTRAP: jeśli RIP-1 odpowiada
    ## ustawionemu punktowi przerwania, przywraca oryginalny bajt i cofa
    ## RIP o 1, tak aby kontynuacja wykonała oryginalną instrukcję.
    regs = get_regs
    hit_addr = regs.rip - 1
    if breakpoints.has_key?(hit_addr)
      poke_word(hit_addr, breakpoints[hit_addr])
      regs.rip = hit_addr
      set_regs(regs)
      puts "zdb: trafiono punkt przerwania pod #{format_addr(hit_addr)}"
    end
  end

  def cont
    return unless @running
    LibZdb.ptrace(LibZdb::PTRACE_CONT, @pid, Pointer(Void).null, Pointer(Void).null)
    wait_and_report
  end

  def single_step
    return unless @running
    LibZdb.ptrace(LibZdb::PTRACE_SINGLESTEP, @pid, Pointer(Void).null, Pointer(Void).null)
    wait_and_report
  end

  def wait_and_report
    status = 0
    LibZdb.waitpid(@pid, pointerof(status), 0)

    exited = (status & 0x7F) == 0
    if exited
      code = (status >> 8) & 0xFF
      puts "zdb: proces #{@pid} zakończył się kodem #{code}"
      @running = false
      return
    end

    stopped_by_signal = (status & 0xFF) == 0x7F
    if stopped_by_signal
      sig = (status >> 8) & 0xFF
      if sig == SIGTRAP
        restore_breakpoint_if_hit
      else
        puts "zdb: proces zatrzymany sygnałem #{sig}"
      end
    end
  end

  def print_regs
    return puts "zdb: proces nie działa" unless @running
    r = get_regs
    puts "rip=0x#{r.rip.to_s(16)}  rsp=0x#{r.rsp.to_s(16)}  rbp=0x#{r.rbp.to_s(16)}"
    puts "rax=0x#{r.rax.to_s(16)}  rbx=0x#{r.rbx.to_s(16)}  rcx=0x#{r.rcx.to_s(16)}  rdx=0x#{r.rdx.to_s(16)}"
    puts "rsi=0x#{r.rsi.to_s(16)}  rdi=0x#{r.rdi.to_s(16)}"
    puts "r8=0x#{r.r8.to_s(16)}  r9=0x#{r.r9.to_s(16)}  r10=0x#{r.r10.to_s(16)}  r11=0x#{r.r11.to_s(16)}"
    puts "r12=0x#{r.r12.to_s(16)}  r13=0x#{r.r13.to_s(16)}  r14=0x#{r.r14.to_s(16)}  r15=0x#{r.r15.to_s(16)}"
    puts "eflags=0x#{r.eflags.to_s(16)}"
  end

  def dump_memory(addr : UInt64, words : Int32)
    return puts "zdb: proces nie działa" unless @running
    (0...words).each do |i|
      w = peek_word(addr + (i.to_u64 * 8))
      puts "0x#{(addr + i.to_u64 * 8).to_s(16).rjust(16, '0')}: 0x#{w.to_s(16).rjust(16, '0')}"
    end
  end

  def backtrace
    ## Prosty spacer po łańcuchu ramek (frame pointer chain): zakłada, że
    ## program był kompilowany BEZ -fomit-frame-pointer. TODO: fallback
    ## przez odczyt informacji CFI (.eh_frame), gdy ramki są pominięte.
    return puts "zdb: proces nie działa" unless @running
    r = get_regs
    puts "#0  #{format_addr(r.rip)}"

    frame_bp = r.rbp
    depth = 1
    while frame_bp != 0 && depth < 32
      return_addr = peek_word(frame_bp + 8)
      break if return_addr == 0
      puts "##{depth}  #{format_addr(return_addr)}"
      frame_bp = peek_word(frame_bp)
      depth += 1
    end
  end

  def disassemble(addr : UInt64, count : Int32)
    return puts "zdb: proces nie działa" unless @running
    bytes = read_bytes(addr, count * 16) # zapas na dłuższe instrukcje
    insns = Disasm.decode_range(bytes, addr, count)
    insns.each do |insn|
      hex = insn.raw.map { |b| b.to_s(16).rjust(2, '0') }.join(" ")
      sym = symbol_for(insn.addr)
      label = sym ? " <#{sym}>" : ""
      puts "0x#{insn.addr.to_s(16)}#{label}:  #{hex.ljust(24)}  #{insn.mnemonic}"
    end
  end

  def list_symbols
    if symbols.empty?
      puts "zdb: brak wczytanych symboli (uruchom 'run PROGRAM' lub program nie ma .symtab)"
      return
    end
    symbols.each do |s|
      puts "0x#{s.addr.to_s(16).rjust(16, '0')}  #{s.size.to_s.rjust(8)}  #{s.name}"
    end
  end

  def kill_debuggee
    return unless @running
    LibZdb.ptrace(LibZdb::PTRACE_KILL, @pid, Pointer(Void).null, Pointer(Void).null)
    @running = false
  end
end

def print_help
  puts <<-HELP
  Dostępne polecenia:
    run PROGRAM [ARGI...]   uruchom i zacznij śledzić program
    break ADRES (b)          ustaw punkt przerwania pod adresem szesnastkowym (np. break 0x401020)
    continue (c)              wznów wykonanie do następnego punktu przerwania
    step (s)                    wykonaj jedną instrukcję
    regs (r)                      wypisz rejestry procesora
    mem ADRES LICZBA (m)            zrzuć LICZBA słów (8 B) pamięci od ADRES
    disas ADRES LICZBA               deasembluj LICZBA instrukcji od ADRES (podstawowy)
    sym ADRES                          pokaż najbliższy symbol dla adresu
    symbols                              wypisz wszystkie wczytane symbole
    bt                                     wypisz prosty backtrace (łańcuch RBP)
    kill                                zabij śledzony proces
    help (h)                             pokaż tę pomoc
    quit (q)                              wyjdź z zdb
  HELP
end

def parse_hex(s : String) : UInt64
  s = s.starts_with?("0x") ? s[2..] : s
  s.to_u64(16)
end

VERSION_FLAG = ARGV.includes?("-v") || ARGV.includes?("--version")
if VERSION_FLAG
  puts "zdb #{VERSION}"
  exit 0
end

debuggee = Debuggee.new

if ARGV.size > 0 && !ARGV[0].starts_with?("-")
  debuggee.start(ARGV)
end

puts "zdb #{VERSION} — Zenit Linux Debugger (odpowiednik gdb)"
puts "Wpisz 'help' po listę poleceń."

loop do
  print "(zdb) "
  STDOUT.flush
  line = gets
  break if line.nil?
  parts = line.strip.split(/\s+/).reject(&.empty?)
  next if parts.empty?

  case parts[0]
  when "run"
    if parts.size < 2
      puts "zdb: użycie: run PROGRAM [ARGI...]"
    else
      debuggee.start(parts[1..])
    end
  when "break", "b"
    if parts.size < 2
      puts "zdb: użycie: break ADRES"
    else
      debuggee.set_breakpoint(parse_hex(parts[1]))
    end
  when "continue", "c"
    debuggee.cont
  when "step", "s"
    debuggee.single_step
  when "regs", "r"
    debuggee.print_regs
  when "mem", "m"
    if parts.size < 3
      puts "zdb: użycie: mem ADRES LICZBA_SLOW"
    else
      debuggee.dump_memory(parse_hex(parts[1]), parts[2].to_i)
    end
  when "bt"
    debuggee.backtrace
  when "disas"
    if parts.size < 3
      puts "zdb: użycie: disas ADRES LICZBA_INSTRUKCJI"
    else
      debuggee.disassemble(parse_hex(parts[1]), parts[2].to_i)
    end
  when "sym"
    if parts.size < 2
      puts "zdb: użycie: sym ADRES"
    else
      addr = parse_hex(parts[1])
      resolved = debuggee.symbol_for(addr)
      puts resolved ? "0x#{addr.to_s(16)} <#{resolved}>" : "zdb: brak symbolu dla 0x#{addr.to_s(16)}"
    end
  when "symbols"
    debuggee.list_symbols
  when "kill"
    debuggee.kill_debuggee
  when "help", "h"
    print_help
  when "quit", "q"
    debuggee.kill_debuggee
    break
  else
    puts "zdb: nieznane polecenie '#{parts[0]}' (wpisz 'help')"
  end
end
