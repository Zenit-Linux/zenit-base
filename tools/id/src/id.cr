require "option_parser"

# id — nowoczesna alternatywa dla `id` (Zenit Linux)
#
# STATUS: szkielet+ — wypisuje UID/GID przez getuid/getgid/geteuid/getegid,
# rozwiązuje je na nazwy przez getpwuid(3)/getgrgid(3), oraz wypisuje
# listę grup dodatkowych przez getgroups(2) (-G, opcjonalnie z -n dla nazw), tak jak prawdziwe
# `id` (domyślny wiersz zawiera teraz też `groups=...`).

VERSION = "0.1.0"

lib LibId
  fun getuid : LibC::UidT
  fun getgid : LibC::GidT
  fun geteuid : LibC::UidT
  fun getegid : LibC::GidT
  fun getgroups(size : LibC::Int, list : LibC::GidT*) : LibC::Int

  struct Passwd
    pw_name : LibC::Char*
    pw_passwd : LibC::Char*
    pw_uid : LibC::UidT
    pw_gid : LibC::GidT
    pw_gecos : LibC::Char*
    pw_dir : LibC::Char*
    pw_shell : LibC::Char*
  end

  struct Group
    gr_name : LibC::Char*
    gr_passwd : LibC::Char*
    gr_gid : LibC::GidT
    gr_mem : LibC::Char**
  end

  fun getpwuid(uid : LibC::UidT) : Passwd*
  fun getgrgid(gid : LibC::GidT) : Group*
end

show_user_only   = false
show_group_only  = false
show_name_only   = false
show_groups_only = false

parser = OptionParser.new do |p|
  p.banner = "id — nowoczesna alternatywa dla id (Zenit Linux)\n\nUżycie: id [opcje]"
  p.on("-u", "--user", "pokaż tylko efektywny UID") { show_user_only = true }
  p.on("-g", "--group", "pokaż tylko efektywny GID") { show_group_only = true }
  p.on("-G", "--groups", "pokaż wszystkie ID grup (podstawową i dodatkowe)") { show_groups_only = true }
  p.on("-n", "--name", "z -u/-g/-G: pokaż nazwę/nazwy zamiast liczb") { show_name_only = true }
  p.on("-h", "--help", "pokaż tę pomoc") { puts p; exit 0 }
  p.on("--version", "pokaż wersję programu id") { puts "id #{VERSION}"; exit 0 }
end
parser.parse

def user_name(uid : LibC::UidT) : String?
  pw = LibId.getpwuid(uid)
  return nil if pw.null?
  String.new(pw.value.pw_name)
end

def group_name(gid : LibC::GidT) : String?
  gr = LibId.getgrgid(gid)
  return nil if gr.null?
  String.new(gr.value.gr_name)
end

def format_user(uid : LibC::UidT) : String
  name = user_name(uid)
  name ? "#{uid}(#{name})" : uid.to_s
end

def format_group(gid : LibC::GidT) : String
  name = group_name(gid)
  name ? "#{gid}(#{name})" : gid.to_s
end

# Grupy dodatkowe procesu przez getgroups(2): najpierw wywołanie z
# rozmiarem 0 zwraca liczbę grup (bez dotykania bufora), potem właściwe
# wywołanie wypełnia bufor o tej długości — standardowy dwuetapowy
# wzorzec syscalli, które same nie znają rozmiaru z góry.
def supplementary_groups : Array(LibC::GidT)
  n = LibId.getgroups(0, Pointer(LibC::GidT).null)
  return [] of LibC::GidT if n <= 0
  buf = Pointer(LibC::GidT).malloc(n)
  got = LibId.getgroups(n, buf)
  return [] of LibC::GidT if got < 0
  Array(LibC::GidT).new(got) { |i| buf[i] }
end

if show_groups_only
  gid = LibId.getgid
  gids = ([gid] + supplementary_groups).uniq
  if show_name_only
    puts gids.map { |g| group_name(g) || g.to_s }.join(" ")
  else
    puts gids.map(&.to_s).join(" ")
  end
elsif show_user_only
  euid = LibId.geteuid
  puts show_name_only ? (user_name(euid) || euid.to_s) : euid.to_s
elsif show_group_only
  egid = LibId.getegid
  puts show_name_only ? (group_name(egid) || egid.to_s) : egid.to_s
else
  uid, gid, euid, egid = LibId.getuid, LibId.getgid, LibId.geteuid, LibId.getegid
  all_groups = ([gid] + supplementary_groups).uniq
  line = "uid=#{format_user(uid)} gid=#{format_group(gid)}"
  line += " euid=#{format_user(euid)}" if euid != uid
  line += " egid=#{format_group(egid)}" if egid != gid
  line += " groups=#{all_groups.map { |g| format_group(g) }.join(",")}"
  puts line
end
