module Disasm
  record Insn, addr : UInt64, length : Int32, mnemonic : String, raw : Bytes

  record OpcodeInfo, mnemonic : String, has_modrm : Bool, imm : Int32

  # Tylko najczęstsze opkody jednobajtowe (po ewentualnym prefiksie REX).
  # Klucz 0x50/0x58 obejmuje też warianty push/pop dla rejestrów 1-7 przez
  # maskowanie w decode_one (rejestr koduje się w dolnych 3 bitach opkodu).
  KNOWN_OPCODES = {
    0x50_u8 => OpcodeInfo.new("push", false, 0),
    0x58_u8 => OpcodeInfo.new("pop", false, 0),
    0x90_u8 => OpcodeInfo.new("nop", false, 0),
    0xC3_u8 => OpcodeInfo.new("ret", false, 0),
    0xC9_u8 => OpcodeInfo.new("leave", false, 0),
    0xCC_u8 => OpcodeInfo.new("int3", false, 0),
    0x89_u8 => OpcodeInfo.new("mov", true, 0),
    0x8B_u8 => OpcodeInfo.new("mov", true, 0),
    0x01_u8 => OpcodeInfo.new("add", true, 0),
    0x03_u8 => OpcodeInfo.new("add", true, 0),
    0x29_u8 => OpcodeInfo.new("sub", true, 0),
    0x2B_u8 => OpcodeInfo.new("sub", true, 0),
    0x39_u8 => OpcodeInfo.new("cmp", true, 0),
    0x3B_u8 => OpcodeInfo.new("cmp", true, 0),
    0x85_u8 => OpcodeInfo.new("test", true, 0),
    0x8D_u8 => OpcodeInfo.new("lea", true, 0),
    0x31_u8 => OpcodeInfo.new("xor", true, 0),
    0x21_u8 => OpcodeInfo.new("and", true, 0),
    0x09_u8 => OpcodeInfo.new("or", true, 0),
  }

  # Oblicza dodatkową długość bajtów ModRM (+ SIB + przesunięcie), zgodnie
  # z tabelami kodowania x86: mod=00/rm=101 to RIP-relatywne disp32 na
  # x86-64, mod=01/10 to disp8/disp32, a rm=100 (przy mod != 11) oznacza
  # obecność bajtu SIB.
  private def self.modrm_length(data : Bytes, offset : Int32) : Int32
    return 1 if offset >= data.size
    modrm = data[offset]
    mod = (modrm >> 6) & 0x3_u8
    rm  = modrm & 0x7_u8

    length = 1
    has_sib = mod != 3_u8 && rm == 4_u8
    length += 1 if has_sib

    case mod
    when 0_u8
      if rm == 5_u8
        length += 4 # RIP-relative disp32
      elsif has_sib
        sib_off = offset + 1
        sib = sib_off < data.size ? data[sib_off] : 0_u8
        base = sib & 0x7_u8
        length += 4 if base == 5_u8
      end
    when 1_u8
      length += 1
    when 2_u8
      length += 4
    end

    length
  end

  def self.decode_one(data : Bytes, offset : Int32, addr : UInt64) : Insn
    start = offset
    i = offset

    if i < data.size && (data[i] & 0xF0_u8) == 0x40_u8
      i += 1 # prefiks REX — nie wpływa na długość poza przesunięciem startu opkodu
    end

    if i >= data.size
      return Insn.new(addr, 1, "(koniec danych)", data[start, Math.min(1, data.size - start)])
    end

    opcode = data[i]
    i += 1

    if opcode == 0x0F_u8 && i < data.size
      second = data[i]
      i += 1
      if (second & 0xF0_u8) == 0x80_u8
        i += 4 # jcc rel32
        len = i - start
        return Insn.new(addr, len, "jcc", data[start, Math.min(len, data.size - start)])
      else
        len = i - start
        return Insn.new(addr, len, "??? (0f #{second.to_s(16)})", data[start, Math.min(len, data.size - start)])
      end
    end

    info = KNOWN_OPCODES[opcode & 0xF8_u8]? || KNOWN_OPCODES[opcode]?
    mnemonic = "??? (0x#{opcode.to_s(16)})"

    if info
      mnemonic = info.mnemonic
      i += modrm_length(data, i) if info.has_modrm
      i += info.imm
    elsif opcode == 0xE8_u8
      mnemonic = "call"
      i += 4
    elsif opcode == 0xE9_u8
      mnemonic = "jmp"
      i += 4
    elsif opcode == 0xEB_u8
      mnemonic = "jmp"
      i += 1
    elsif opcode >= 0xB8_u8 && opcode <= 0xBF_u8
      mnemonic = "mov"
      i += 8 # uproszczenie: zakładamy imm64 (poprawne z REX.W, przybliżone bez)
    end

    len = i - start
    len = 1 if len <= 0
    Insn.new(addr, len, mnemonic, data[start, Math.min(len, data.size - start)])
  end

  def self.decode_range(data : Bytes, base_addr : UInt64, count : Int32) : Array(Insn)
    result = [] of Insn
    offset = 0
    count.times do
      break if offset >= data.size
      insn = decode_one(data, offset, base_addr + offset.to_u64)
      result << insn
      offset += insn.length
    end
    result
  end
end
