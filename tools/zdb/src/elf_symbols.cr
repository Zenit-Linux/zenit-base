module ElfSymbols
  record Symbol, name : String, addr : UInt64, size : UInt64

  private def self.u16(b : Bytes, off : Int32) : UInt16
    IO::ByteFormat::LittleEndian.decode(UInt16, b[off, 2])
  end

  private def self.u32(b : Bytes, off : Int32) : UInt32
    IO::ByteFormat::LittleEndian.decode(UInt32, b[off, 4])
  end

  private def self.u64(b : Bytes, off : Int32) : UInt64
    IO::ByteFormat::LittleEndian.decode(UInt64, b[off, 8])
  end

  private def self.read_cstring(data : Bytes, offset : Int32) : String
    return "" if offset < 0 || offset >= data.size
    stop = offset
    stop += 1 while stop < data.size && data[stop] != 0
    String.new(data[offset, stop - offset])
  end

  # Wczytuje i parsuje symbole funkcji/obiektów ze statycznej tabeli
  # symboli pliku ELF64. Zwraca pustą tablicę (zamiast wyjątku), jeśli
  # plik nie jest ELF64, jest stripowany, albo nie ma sekcji .symtab —
  # zdb wtedy po prostu działa bez rozwiązywania nazw.
  def self.load(path : String) : Array(Symbol)
    return [] of Symbol unless File.exists?(path)

    data = File.read(path).to_slice
    return [] of Symbol if data.size < 64
    return [] of Symbol unless data[0]?.try(&.to_i32) == 0x7F &&
                                data[1]?.try(&.to_i32) == 'E'.ord &&
                                data[2]?.try(&.to_i32) == 'L'.ord &&
                                data[3]?.try(&.to_i32) == 'F'.ord
    return [] of Symbol unless data[4] == 2_u8 # EI_CLASS == ELFCLASS64

    shoff     = u64(data, 0x28)
    shentsize = u16(data, 0x3A).to_i32
    shnum     = u16(data, 0x3C).to_i32
    return [] of Symbol if shoff == 0 || shnum == 0 || shentsize == 0

    section_offset = ->(idx : Int32) { shoff.to_i32 + idx * shentsize }

    symtab_off     = 0_u64
    symtab_size    = 0_u64
    symtab_entsize = 24_u64
    strtab_idx     = 0
    sht_symtab     = 2_u32

    (0...shnum).each do |i|
      base = section_offset.call(i)
      next if base + 64 > data.size
      sh_type = u32(data, base + 4)
      if sh_type == sht_symtab
        symtab_off     = u64(data, base + 24)
        symtab_size    = u64(data, base + 32)
        symtab_entsize = u64(data, base + 56)
        symtab_entsize = 24_u64 if symtab_entsize == 0
        strtab_idx     = u32(data, base + 40).to_i32 # sh_link -> indeks .strtab
      end
    end

    return [] of Symbol if symtab_off == 0

    strtab_base = section_offset.call(strtab_idx)
    return [] of Symbol if strtab_base + 64 > data.size
    strtab_off = u64(data, strtab_base + 24)

    symbols = [] of Symbol
    count = (symtab_size // symtab_entsize).to_i32

    (0...count).each do |i|
      entry_off = symtab_off.to_i32 + i * symtab_entsize.to_i32
      next if entry_off + 24 > data.size

      st_name  = u32(data, entry_off)
      st_info  = data[entry_off + 4]
      st_value = u64(data, entry_off + 8)
      st_size  = u64(data, entry_off + 16)

      kind = st_info & 0xF_u8 # STT_* w dolnych 4 bitach st_info
      next unless kind == 2_u8 || kind == 1_u8 # STT_FUNC=2, STT_OBJECT=1
      next if st_value == 0

      name = read_cstring(data, (strtab_off + st_name).to_i32)
      next if name.empty?

      symbols << Symbol.new(name, st_value, st_size)
    end

    symbols.sort_by(&.addr)
  end

  # Znajduje symbol "obejmujący" dany adres (największy adres <= addr) i
  # zwraca "nazwa" albo "nazwa+0xPRZESUNIĘCIE", jeśli adres nie trafia
  # dokładnie w początek symbolu. Zwraca nil, gdy nic nie pasuje (np.
  # program bez tabeli symboli).
  def self.resolve(symbols : Array(Symbol), addr : UInt64) : String?
    best = nil.as(Symbol?)
    symbols.each do |sym|
      next if sym.addr > addr
      current_best = best
      if current_best.nil? || sym.addr > current_best.addr
        best = sym
      end
    end
    return nil unless best
    b = best.not_nil!
    offset = addr - b.addr
    offset == 0 ? b.name : "#{b.name}+0x#{offset.to_s(16)}"
  end
end
