module Ustar
  BLOCK_SIZE = 512

  # Przesunięcia pól w 512-bajtowym nagłówku ustar (POSIX.1-1988).
  OFF_NAME     =   0
  OFF_MODE     = 100
  OFF_UID      = 108
  OFF_GID      = 116
  OFF_SIZE     = 124
  OFF_MTIME    = 136
  OFF_CHKSUM   = 148
  OFF_TYPEFLAG = 156
  OFF_LINKNAME = 157
  OFF_MAGIC    = 257
  OFF_VERSION  = 263
  OFF_UNAME    = 265
  OFF_GNAME    = 297
  OFF_PREFIX   = 345

  TYPE_REGULAR   = '0'
  TYPE_DIRECTORY = '5'

  private def self.set_ascii(header : Bytes, offset : Int32, width : Int32, value : String)
    bytes = value.to_slice
    n = Math.min(bytes.size, width)
    n.times { |i| header[offset + i] = bytes[i] }
  end

  private def self.set_octal(header : Bytes, offset : Int32, width : Int32, value : UInt64)
    # Format klasyczny: (width - 1) cyfr ósemkowych wyrównanych do prawej,
    # zerami z lewej, zakończone NUL (ostatni bajt zostaje 0, bo bufor
    # nagłówka jest inicjalizowany zerami).
    digits = value.to_s(8)
    digits = digits.rjust(width - 1, '0')
    set_ascii(header, offset, width - 1, digits)
  end

  private def self.get_ascii(header : Bytes, offset : Int32, width : Int32) : String
    slice = header[offset, width]
    stop = 0
    stop += 1 while stop < slice.size && slice[stop] != 0
    String.new(slice[0, stop])
  end

  private def self.get_octal(header : Bytes, offset : Int32, width : Int32) : UInt64
    str = get_ascii(header, offset, width).strip
    return 0_u64 if str.empty?
    str.to_u64(8)
  end

  # Buduje jeden 512-bajtowy nagłówek ustar dla pliku o podanej
  # (względnej) ścieżce, rozmiarze i uprawnieniach.
  def self.build_header(name : String, size : UInt64, mode : Int32, typeflag : Char) : Bytes
    header = Bytes.new(BLOCK_SIZE, 0_u8)

    if name.bytesize <= 100
      set_ascii(header, OFF_NAME, 100, name)
    else
      # Podział na prefix (<=155) + name (<=100) na '/' tak, by obie
      # części zmieściły się w limitach — standardowe rozwiązanie ustar
      # dla ścieżek do 256 znaków łącznie. Szukamy najdalej wysuniętego
      # w prawo '/', po którym reszta ścieżki mieści się w 100 bajtach.
      split_at = nil.as(Int32?)
      name.size.times do |idx|
        next unless name[idx] == '/'
        after_len = name.bytesize - idx - 1
        split_at = idx if after_len <= 100 && idx <= 155
      end

      if split_at
        s = split_at.not_nil!
        set_ascii(header, OFF_PREFIX, 155, name[0...s])
        set_ascii(header, OFF_NAME, 100, name[(s + 1)..])
      else
        # Ścieżka zbyt długa nawet dla ustar (>256 znaków) — obcinamy z
        # ostrzeżeniem zamiast implementować rozszerzenie GNU @LongLink.
        STDERR.puts "ar: ostrzeżenie — ścieżka '#{name}' jest zbyt długa dla ustar, zostanie obcięta"
        set_ascii(header, OFF_NAME, 100, name[0, 100])
      end
    end

    set_octal(header, OFF_MODE, 8, mode.to_u64)
    set_octal(header, OFF_UID, 8, 0_u64)
    set_octal(header, OFF_GID, 8, 0_u64)
    set_octal(header, OFF_SIZE, 12, size)
    set_octal(header, OFF_MTIME, 12, Time.utc.to_unix.to_u64)
    set_ascii(header, OFF_TYPEFLAG, 1, typeflag.to_s)
    set_ascii(header, OFF_MAGIC, 6, "ustar")
    set_ascii(header, OFF_VERSION, 2, "00")
    set_ascii(header, OFF_UNAME, 32, "zenit")
    set_ascii(header, OFF_GNAME, 32, "zenit")

    # Suma kontrolna liczona z polem chksum wypełnionym spacjami (0x20),
    # zgodnie ze specyfikacją POSIX ustar.
    8.times { |i| header[OFF_CHKSUM + i] = 0x20_u8 }
    sum = 0_u32
    header.each { |b| sum += b }
    chksum_str = sum.to_s(8).rjust(6, '0')
    set_ascii(header, OFF_CHKSUM, 6, chksum_str)
    header[OFF_CHKSUM + 6] = 0_u8
    header[OFF_CHKSUM + 7] = 0x20_u8

    header
  end

  record ParsedHeader, name : String, size : UInt64, mode : Int32, typeflag : Char

  # Parsuje nagłówek 512 B. Zwraca nil dla bloku samych zer (koniec
  # archiwum) albo gdy magic "ustar" się nie zgadza (uszkodzone archiwum).
  def self.parse_header(block : Bytes) : ParsedHeader?
    return nil if block.all? { |b| b == 0 }

    magic = get_ascii(block, OFF_MAGIC, 6)
    return nil unless magic == "ustar"

    prefix = get_ascii(block, OFF_PREFIX, 155)
    name   = get_ascii(block, OFF_NAME, 100)
    full_name = prefix.empty? ? name : "#{prefix}/#{name}"

    size     = get_octal(block, OFF_SIZE, 12)
    mode     = get_octal(block, OFF_MODE, 8).to_i32
    typeflag = get_ascii(block, OFF_TYPEFLAG, 1)
    tf       = typeflag.empty? ? TYPE_REGULAR : typeflag[0]

    ParsedHeader.new(full_name, size, mode, tf)
  end

  # Liczba pełnych bloków 512 B potrzebnych do zmieszczenia `size` bajtów
  # danych (ustar zawsze wyrównuje zawartość plików do wielokrotności 512).
  def self.blocks_for(size : UInt64) : UInt64
    (size + BLOCK_SIZE - 1) // BLOCK_SIZE
  end
end
