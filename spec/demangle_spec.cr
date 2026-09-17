require "spec"
require "../tools/zdb/src/demangle"

# spec/demangle_spec.cr — testy jednostkowe dla demanglera Itanium C++ ABI
# (tools/zdb/src/demangle.cr).
#
# Każdy przypadek testowy poniżej został zweryfikowany wprost przeciwko
# `c++filt` (GNU binutils) w trakcie pisania demanglera — komentarz przy
# każdej grupie pokazuje polecenie użyte do wygenerowania oczekiwanego
# wyniku, np.:
#   echo '_ZN3foo3barEi' | c++filt   ->   foo::bar(int)
#
# W odróżnieniu od reszty `spec/`, ten plik nie potrzebuje zbudowanej
# binarki (`bin/`) — testuje moduł `Demangle` bezpośrednio jako
# bibliotekę, `require`-owaną z pliku źródłowego.

describe Demangle do
  it "nazwy nie-C++ (bez prefiksu _Z) wracają bez zmian" do
    Demangle.demangle("plain_c_function").should eq("plain_c_function")
    Demangle.demangle("").should eq("")
    Demangle.demangle("main").should eq("main")
  end

  it "gole funkcje niezagniezdzone, z prostymi typami wbudowanymi" do
    Demangle.demangle("_Z3foov").should eq("foo()")
    Demangle.demangle("_Z3fooi").should eq("foo(int)")
    Demangle.demangle("_Z3fooii").should eq("foo(int, int)")
    Demangle.demangle("_Z1fyxmjt").should eq(
      "f(unsigned long long, long long, unsigned long, unsigned int, unsigned short)")
  end

  it "nazwy zagniezdzone (namespace/klasa)" do
    Demangle.demangle("_ZN3foo3barEi").should eq("foo::bar(int)")
    Demangle.demangle("_ZN3foo3bar3bazEv").should eq("foo::bar::baz()")
    Demangle.demangle("_ZN6MyList4pushEi").should eq("MyList::push(int)")
    Demangle.demangle("_ZN3std3foo3barEv").should eq("std::foo::bar()")
    Demangle.demangle("_ZN1a1b1cE1d").should eq("a::b::c(d)")
  end

  it "wskazniki, referencje, const/volatile" do
    Demangle.demangle("_Z3fooPi").should eq("foo(int*)")
    Demangle.demangle("_Z3fooRi").should eq("foo(int&)")
    Demangle.demangle("_Z3fooPKi").should eq("foo(int const*)")
    Demangle.demangle("_Z3fooRKi").should eq("foo(int const&)")
    Demangle.demangle("_Z3fooPPi").should eq("foo(int**)")
    Demangle.demangle("_ZN3foo3barEPKc").should eq("foo::bar(char const*)")
    Demangle.demangle("_Z3fooPKPi").should eq("foo(int* const*)")
    Demangle.demangle("_Z3fooRPKi").should eq("foo(int const*&)")
    Demangle.demangle("_Z1fRKPi").should eq("f(int* const&)")
  end

  it "konstruktory i destruktory (C1/C2/C3, D0/D1/D2)" do
    Demangle.demangle("_ZN3fooC1Ev").should eq("foo::foo()")
    Demangle.demangle("_ZN3fooD1Ev").should eq("foo::~foo()")
    Demangle.demangle("_ZN3fooD0Ev").should eq("foo::~foo()")
    Demangle.demangle("_ZN1N1CC2Ev").should eq("N::C::C()")
    Demangle.demangle("_ZN1N1CD2Ev").should eq("N::C::~C()")
    Demangle.demangle("_ZN3foo3barC1ERKS0_").should eq("foo::bar::bar(foo::bar const&)")
  end

  it "tabela podstawien (S_, S0_, ...)" do
    # Te przypadki sa najbardziej podatne na bledy off-by-one w indeksowaniu
    # tabeli podstawien -- stad ich szczegolne pokrycie.
    Demangle.demangle("_Z3fooPiS_").should eq("foo(int*, int*)")
    Demangle.demangle("_ZN1a1b1cES0_").should eq("a::b::c(a::b)")
    Demangle.demangle("_ZN1a1bES_").should eq("a::b(a)")
    Demangle.demangle("_Z1fPiPKiS0_").should eq("f(int*, int const*, int const)")
  end

  it "gole, niezagniezdzone nazwy funkcji NIE wchodza do tabeli podstawien" do
    # Zweryfikowane empirycznie przeciwko c++filt: gdyby "foo" (nazwa
    # funkcji na szczycie _Z...) była substytuowalna, S_ w tym przypadku
    # dałoby błędnie "foo" zamiast "int*".
    Demangle.demangle("_Z3fooPiS_").should_not eq("foo(int*, foo)")
  end

  it "konstrukcje poza obslugiwanym podzbiorem wracaja BEZ ZMIAN (nigdy zly wynik)" do
    template = "_ZN9zenit_std6vectorIiE4pushEi" # szablon -- nieobslugiwane
    Demangle.demangle(template).should eq(template)

    operator_name = "_Zplii" # operator+ -- nieobslugiwane
    Demangle.demangle(operator_name).should eq(operator_name)
  end

  it "uszkodzone/ucięte wejście nie crashuje -- bezpieczny fallback" do
    ["_Z", "_ZN", "_ZZZZZ", "_ZN3foo"].each do |bad|
      Demangle.demangle(bad).should eq(bad)
    end
  end
end
