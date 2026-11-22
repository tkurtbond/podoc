MODULE PdCodeTest;
(* Tests of PdCode, the highlighting scanner. Each case scans a piece of
   code and writes it back with its spans marked: [reserved word],
   {comment}, |string|; plain text unmarked. In the code, "$" stands
   for a newline and "`" for a double quote, which an Oberon string
   cannot hold. The cases include vgrind.md §6.2's mistakes: nested
   comments, comment marks in strings, C's //, Modula-2's case rule; and
   the corner cases of Pascal's modes, Ada and C++ (study §5.3 to §5.6).
   The shell's cases (study §5.7), with vgrind.md §6.2's sh mistake,
   keywords out of command position, write "$" as itself, a newline as
   "~", a double quote as "`" and a backquote as "^". *)

IMPORT Out, Ropes, C := PdCode;

VAR failures: INTEGER;

PROCEDURE Report(ok: BOOLEAN; name: ARRAY OF CHAR);
BEGIN
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(name); Out.Ln
END Report;

PROCEDURE Append(VAR s: ARRAY OF CHAR; VAR k: INTEGER; ch: CHAR);
BEGIN
  IF k < LEN(s) - 1 THEN s[k] := ch; INC(k) END
END Append;

(* The code's spans marked, with newlines as "$"; FALSE in ok if the
   spans do not cover the text in order *)
PROCEDURE Mark(lang: C.Language; code: ARRAY OF CHAR; shell: BOOLEAN;
    VAR out: ARRAY OF CHAR; VAR ok: BOOLEAN);
  VAR t: ARRAY 1024 OF CHAR; i, k: INTEGER; p: LONGINT; sp: C.Span; open, close, nl: CHAR;
BEGIN
  IF shell THEN nl := "~" ELSE nl := "$" END;
  i := 0;
  WHILE code[i] # 0X DO
    IF code[i] = nl THEN t[i] := 0AX
    ELSIF code[i] = "`" THEN t[i] := 22X
    ELSIF shell & (code[i] = "^") THEN t[i] := 60X
    ELSE t[i] := code[i]
    END;
    INC(i)
  END;
  t[i] := 0X;
  sp := C.Scan(lang, Ropes.FromString(t));
  k := 0; p := 0; ok := TRUE;
  WHILE sp # NIL DO
    IF (sp.start # p) OR (sp.len <= 0) THEN ok := FALSE END;
    CASE sp.kind OF
      C.Plain: open := 0X; close := 0X
    | C.Reserved: open := "["; close := "]"
    | C.Comment: open := "{"; close := "}"
    | C.String: open := "|"; close := "|"
    END;
    IF open # 0X THEN Append(out, k, open) END;
    FOR p := sp.start TO sp.start + sp.len - 1 DO
      IF t[p] = 0AX THEN Append(out, k, nl)
      ELSIF t[p] = 22X THEN Append(out, k, "`")
      ELSIF t[p] = 60X THEN Append(out, k, "^")
      ELSE Append(out, k, t[p])
      END
    END;
    IF close # 0X THEN Append(out, k, close) END;
    p := sp.start + sp.len; sp := sp.next
  END;
  IF p # i THEN ok := FALSE END;
  out[k] := 0X
END Mark;

PROCEDURE Check(name, langName, code, want: ARRAY OF CHAR; shell: BOOLEAN);
  VAR got: ARRAY 2048 OF CHAR; lang: C.Language; ok: BOOLEAN;
BEGIN
  lang := C.Find(langName);
  IF lang = NIL THEN Out.String("  no language "); Out.String(langName); Out.Ln; Report(FALSE, name)
  ELSE
    Mark(lang, code, shell, got, ok);
    IF ~ok THEN Out.String("  spans do not cover the text"); Out.Ln END;
    IF got # want THEN
      Out.String("  got  "); Out.String(got); Out.Ln;
      Out.String("  want "); Out.String(want); Out.Ln
    END;
    Report(ok & (got = want), name)
  END
END Check;

PROCEDURE T(name, langName, code, want: ARRAY OF CHAR);
BEGIN Check(name, langName, code, want, FALSE)
END T;

(* A shell case: "~" a newline, "^" a backquote *)
PROCEDURE TS(name, langName, code, want: ARRAY OF CHAR);
BEGIN Check(name, langName, code, want, TRUE)
END TS;

PROCEDURE Names;
BEGIN
  Report((C.Find("oberon") # NIL) & (C.Find("oberon") = C.Find("oberon2")), "oberon is oberon2");
  Report((C.Find("oberon1") # NIL) & (C.Find("oberon1") = C.Find("oberon87")), "oberon1 is oberon87");
  Report((C.Find("cp") # NIL) & (C.Find("cp") = C.Find("componentpascal")), "cp is componentpascal");
  Report((C.Find("oberon07") # NIL) & (C.Find("modula2") # NIL) & (C.Find("c") # NIL), "oberon07, modula2, c");
  Report(C.Count(C.Find("oberon")) = 34, "oberon2: 34 words");
  Report(C.Count(C.Find("oberon1")) = 32, "oberon1: 32 words");
  Report(C.Count(C.Find("oberon07")) = 33, "oberon07: 33 words");
  Report(C.Count(C.Find("cp")) = 40, "cp: 40 words");
  Report(C.Count(C.Find("modula2")) = 46, "modula2: 46 words");
  Report(C.Count(C.Find("c")) = 59, "c: 59 words");
  Report((C.Find("pascal") # NIL) & (C.Find("pascal") = C.Find("fpc")), "pascal is fpc");
  Report(C.Count(C.Find("fpc")) = 59, "fpc: 59 words");
  Report(C.Count(C.Find("objfpc")) = 67, "objfpc: 67 words");
  Report(C.Count(C.Find("delphi")) = 65, "delphi: 65 words");
  Report(C.Count(C.Find("tp")) = 54, "tp: 54 words");
  Report(C.Count(C.Find("macpas")) = 56, "macpas: 56 words");
  Report(C.Count(C.Find("iso")) = 36, "iso: 36 words");
  Report(C.Count(C.Find("ada")) = 74, "ada: 74 words");
  Report(C.Count(C.Find("cpp")) = 92, "cpp: 92 words");
  Report(C.Count(C.Find("sh")) = 16, "sh: 16 words");
  Report(C.Count(C.Find("bash")) = 22, "bash: 22 words");
  Report(C.Find("haskell") = NIL, "unknown class");
  Report(C.Find("Oberon") = NIL, "classes are case sensitive");
  Report(C.Scan(C.Find("c"), Ropes.FromString("")) = NIL, "empty text")
END Names;

PROCEDURE Oberon;
BEGIN
  T("oberon words", "oberon", "MODULE M; VAR x: INTEGER; END M.",
    "[MODULE] M; [VAR] x: INTEGER; [END] M.");
  T("oberon lower case is a name", "oberon", "begin := end",
    "begin := end");
  T("oberon word in a name", "oberon", "ENDING := BEGIN_; xEND",
    "ENDING := BEGIN_; xEND");
  T("oberon comment", "oberon", "IF x (* IF *) THEN",
    "[IF] x {(* IF *)} [THEN]");
  T("oberon nested comment", "oberon", "(* a (* IF *) b *) END",
    "{(* a (* IF *) b *)} [END]");
  T("oberon unclosed comment", "oberon", "x (* a (* b *) END",
    "x {(* a (* b *) END}");
  T("oberon strings", "oberon", "s := `(* IF *)`; t := 'END'",
    "s := |`(* IF *)`|; t := |'END'|");
  T("oberon unclosed string", "oberon", "s := `IF$END",
    "s := |`IF|$[END]");
  T("oberon numbers", "oberon", "0FFH 0AX 1.5E10 1..END",
    "0FFH 0AX 1.5E10 1..[END]");
  T("oberon predeclared not reserved", "oberon", "NEW(p); TRUE; ABS(x)",
    "NEW(p); TRUE; ABS(x)");
  T("oberon2 FOR BY", "oberon2", "FOR i := 0 TO 9 BY 2 DO",
    "[FOR] i := 0 [TO] 9 [BY] 2 [DO]");
  T("oberon utf-8 joined", "oberon", "äEND ENDé",
    "äEND ENDé");
  T("comment across lines", "oberon", "(* a$b *)$END",
    "{(* a$b *)}$[END]")
END Oberon;

PROCEDURE Variants;
BEGIN
  T("oberon1 has no FOR", "oberon1", "FOR LOOP WITH EXIT",
    "FOR [LOOP] [WITH] [EXIT]");
  T("oberon07 TRUE FALSE", "oberon07", "TRUE FALSE FOR BY LOOP WITH EXIT",
    "[TRUE] [FALSE] [FOR] [BY] LOOP WITH EXIT");
  T("cp words", "cp", "PROCEDURE (VAR a: T) P*, NEW, ABSTRACT; OUT EMPTY LIMITED EXTENSIBLE CLOSE",
    "[PROCEDURE] ([VAR] a: T) P*, NEW, [ABSTRACT]; [OUT] [EMPTY] [LIMITED] [EXTENSIBLE] [CLOSE]")
END Variants;

PROCEDURE Modula2;
BEGIN
  T("modula2 words", "modula2", "FROM InOut IMPORT WriteString; NOT x AND y",
    "[FROM] InOut [IMPORT] WriteString; [NOT] x [AND] y");
  T("modula2 case rule", "modula2", "from import Begin END",
    "from import Begin [END]");
  T("modula2 iso words", "modula2", "EXCEPT FINALLY RETRY REM",
    "[EXCEPT] [FINALLY] [RETRY] [REM]");
  T("modula2 pragma", "modula2", "<* ASSIGN END *> BEGIN",
    "{<* ASSIGN END *>} [BEGIN]");
  T("modula2 nested comment", "modula2", "(* (* *) END *) END",
    "{(* (* *) END *)} [END]")
END Modula2;

PROCEDURE CLang;
BEGIN
  T("c words", "c", "static int f(void) { return 0; }",
    "[static] [int] f([void]) { [return] 0; }");
  T("c case matters", "c", "INT Int int",
    "INT Int [int]");
  T("c underscore words", "c", "_Bool _Static_assert __int",
    "[_Bool] [_Static_assert] __int");
  T("c line comment", "c", "x; // if else$return",
    "x; {// if else}$[return]");
  T("c line comment continued", "c", "// a \$if$if",
    "{// a \$if}$[if]");
  T("c block comment does not nest", "c", "/* a /* b */ if */",
    "{/* a /* b */} [if] */");
  T("c comment marks in strings", "c", "s = `/* if */`; t = `//`;",
    "s = |`/* if */`|; t = |`//`|;");
  T("c escaped quote", "c", "s = `a\`if`; else",
    "s = |`a\`if`|; [else]");
  T("c braces in strings", "c", "if (c == '{') { x = `}`; }",
    "[if] (c == |'{'|) { x = |`}`|; }");
  T("c char escape", "c", "c = '\''; if",
    "c = |'\''|; [if]");
  T("c prefixes", "c", "u8`x` L'y'",
    "u8|`x`| L|'y'|");
  T("c directive", "c", "#if X$  #  else$#include <stdio.h>$#define N sizeof(int)",
    "#if X$  #  else$#include |<stdio.h>|$#define N [sizeof]([int])");
  T("c header names", "c", "#include<if.h>$# include_next <a$#import <x>$#if a<b && c>d",
    "#include|<if.h>|$# include_next |<a|$#import |<x>|$#if a<b && c>d");
  T("c # not at line start", "c", "a # if",
    "a # [if]");
  T("c digit separators", "c", "1'000'000 if 0x1Fu 1e10",
    "1'000'000 [if] 0x1Fu 1e10");
  T("c every word", "c", "alignas alignof auto bool break case char const constexpr continue default do double else enum extern false float for goto if inline int long nullptr register restrict return short signed sizeof static static_assert struct switch thread_local true typedef typeof typeof_unqual union unsigned void volatile while _Alignas _Alignof _Atomic _BitInt _Bool _Complex _Decimal128 _Decimal32 _Decimal64 _Generic _Imaginary _Noreturn _Static_assert _Thread_local",
    "[alignas] [alignof] [auto] [bool] [break] [case] [char] [const] [constexpr] [continue] [default] [do] [double] [else] [enum] [extern] [false] [float] [for] [goto] [if] [inline] [int] [long] [nullptr] [register] [restrict] [return] [short] [signed] [sizeof] [static] [static_assert] [struct] [switch] [thread_local] [true] [typedef] [typeof] [typeof_unqual] [union] [unsigned] [void] [volatile] [while] [_Alignas] [_Alignof] [_Atomic] [_BitInt] [_Bool] [_Complex] [_Decimal128] [_Decimal32] [_Decimal64] [_Generic] [_Imaginary] [_Noreturn] [_Static_assert] [_Thread_local]")
END CLang;

PROCEDURE Pascal;
BEGIN
  T("pascal case ignored", "pascal", "BEGIN Begin begin",
    "[BEGIN] [Begin] [begin]");
  T("pascal comments", "pascal", "{ if } x (* then *) // else$end",
    "{{ if }} x {(* then *)} {// else}$[end]");
  T("fpc nested comments", "fpc", "{ a { b } end } end (* (* *) end *) end",
    "{{ a { b } end }} [end] {(* (* *) end *)} [end]");
  T("fpc kinds nest apart", "fpc", "{ (* } end",
    "{{ (* }} [end]");
  T("delphi comments do not nest", "delphi", "{ a { b } end } end",
    "{{ a { b }} [end] } [end]");
  T("iso comments close each other", "iso", "{ a *) end (* b } end",
    "{{ a *)} [end] {(* b }} [end]");
  T("iso no nesting", "iso", "(* a (* b *) end *)",
    "{(* a (* b *)} [end] *)");
  T("pascal doubled quote", "pascal", "s := 'it''s end'; end",
    "s := |'it''s end'|; [end]");
  T("pascal no double quotes", "pascal", "s := `end`",
    "s := `[end]`");
  T("pascal unclosed string", "pascal", "s := 'end$end",
    "s := |'end|$[end]");
  T("pascal directives", "pascal", "{$mode objfpc}{$H+}$unit",
    "{{$mode objfpc}}{{$H+}}$[unit]");
  T("pascal ampersand", "pascal", "&begin := &17; begin &End",
    "&begin := &17; [begin] &End");
  T("pascal character codes", "pascal", "#13#10 #$0D $FF end",
    "#13#10 #$0D $FF [end]");
  T("fpc every word", "fpc", "and array asm begin bitpacked case const constructor cppclass destructor div do downto else end exports file finalization for function goto if implementation in inherited initialization interface label library mod nil not object of operator or otherwise packed procedure program property record repeat resourcestring set shl shr string then threadvar to type unit until uses var while with xor",
    "[and] [array] [asm] [begin] [bitpacked] [case] [const] [constructor] [cppclass] [destructor] [div] [do] [downto] [else] [end] [exports] [file] [finalization] [for] [function] [goto] [if] [implementation] [in] [inherited] [initialization] [interface] [label] [library] [mod] [nil] [not] [object] [of] [operator] [or] [otherwise] [packed] [procedure] [program] [property] [record] [repeat] [resourcestring] [set] [shl] [shr] [string] [then] [threadvar] [to] [type] [unit] [until] [uses] [var] [while] [with] [xor]");
  T("fpc others are names", "fpc", "as class dispinterface except finally inline is raise return try univ",
    "as class dispinterface except finally inline is raise return try univ");
  T("objfpc every word", "objfpc", "and array as asm begin bitpacked case class const constructor cppclass destructor dispinterface div do downto else end except exports file finalization finally for function goto if implementation in inherited initialization interface is label library mod nil not object of operator or otherwise packed procedure program property raise record repeat resourcestring set shl shr string then threadvar to try type unit until uses var while with xor",
    "[and] [array] [as] [asm] [begin] [bitpacked] [case] [class] [const] [constructor] [cppclass] [destructor] [dispinterface] [div] [do] [downto] [else] [end] [except] [exports] [file] [finalization] [finally] [for] [function] [goto] [if] [implementation] [in] [inherited] [initialization] [interface] [is] [label] [library] [mod] [nil] [not] [object] [of] [operator] [or] [otherwise] [packed] [procedure] [program] [property] [raise] [record] [repeat] [resourcestring] [set] [shl] [shr] [string] [then] [threadvar] [to] [try] [type] [unit] [until] [uses] [var] [while] [with] [xor]");
  T("objfpc others are names", "objfpc", "inline return univ",
    "inline return univ");
  T("delphi every word", "delphi", "and array as asm begin bitpacked case class const constructor destructor dispinterface div do downto else end except exports file finalization finally for function goto if implementation in inherited initialization interface is label library mod nil not object of or otherwise packed procedure program property raise record repeat resourcestring set shl shr string then threadvar to try type unit until uses var while with xor",
    "[and] [array] [as] [asm] [begin] [bitpacked] [case] [class] [const] [constructor] [destructor] [dispinterface] [div] [do] [downto] [else] [end] [except] [exports] [file] [finalization] [finally] [for] [function] [goto] [if] [implementation] [in] [inherited] [initialization] [interface] [is] [label] [library] [mod] [nil] [not] [object] [of] [or] [otherwise] [packed] [procedure] [program] [property] [raise] [record] [repeat] [resourcestring] [set] [shl] [shr] [string] [then] [threadvar] [to] [try] [type] [unit] [until] [uses] [var] [while] [with] [xor]");
  T("delphi others are names", "delphi", "cppclass inline operator return univ",
    "cppclass inline operator return univ");
  T("tp every word", "tp", "and array asm begin bitpacked case const constructor destructor div do downto else end exports file for function goto if implementation in inherited interface label library mod nil not object of or otherwise packed procedure program record repeat resourcestring set shl shr string then threadvar to type unit until uses var while with xor",
    "[and] [array] [asm] [begin] [bitpacked] [case] [const] [constructor] [destructor] [div] [do] [downto] [else] [end] [exports] [file] [for] [function] [goto] [if] [implementation] [in] [inherited] [interface] [label] [library] [mod] [nil] [not] [object] [of] [or] [otherwise] [packed] [procedure] [program] [record] [repeat] [resourcestring] [set] [shl] [shr] [string] [then] [threadvar] [to] [type] [unit] [until] [uses] [var] [while] [with] [xor]");
  T("tp others are names", "tp", "as class cppclass dispinterface except finalization finally initialization inline is operator property raise return try univ",
    "as class cppclass dispinterface except finalization finally initialization inline is operator property raise return try univ");
  T("macpas every word", "macpas", "and array asm begin bitpacked case const constructor destructor div do downto else end exports file for function goto if implementation in inherited interface label library mod nil not object of or otherwise packed procedure program record repeat resourcestring return set shl shr string then threadvar to type unit univ until uses var while with xor",
    "[and] [array] [asm] [begin] [bitpacked] [case] [const] [constructor] [destructor] [div] [do] [downto] [else] [end] [exports] [file] [for] [function] [goto] [if] [implementation] [in] [inherited] [interface] [label] [library] [mod] [nil] [not] [object] [of] [or] [otherwise] [packed] [procedure] [program] [record] [repeat] [resourcestring] [return] [set] [shl] [shr] [string] [then] [threadvar] [to] [type] [unit] [univ] [until] [uses] [var] [while] [with] [xor]");
  T("macpas others are names", "macpas", "as class cppclass dispinterface except finalization finally initialization inline is operator property raise try",
    "as class cppclass dispinterface except finalization finally initialization inline is operator property raise try");
  T("iso every word", "iso", "and array begin case const div do downto else end file for function goto if in label mod nil not of or packed procedure program record repeat set then to type until var while with xor",
    "[and] [array] [begin] [case] [const] [div] [do] [downto] [else] [end] [file] [for] [function] [goto] [if] [in] [label] [mod] [nil] [not] [of] [or] [packed] [procedure] [program] [record] [repeat] [set] [then] [to] [type] [until] [var] [while] [with] [xor]");
  T("iso others are names", "iso", "as asm bitpacked class constructor cppclass destructor dispinterface except exports finalization finally implementation inherited initialization inline interface is library object operator otherwise property raise resourcestring return shl shr string threadvar try unit univ uses",
    "as asm bitpacked class constructor cppclass destructor dispinterface except exports finalization finally implementation inherited initialization inline interface is library object operator otherwise property raise resourcestring return shl shr string threadvar try unit univ uses");
  T("pascal is fpc", "pascal", "class try operator cppclass property",
    "class try [operator] [cppclass] [property]")
END Pascal;

PROCEDURE Ada;
BEGIN
  T("ada every word", "ada", "abort abs abstract accept access aliased all and array at begin body case constant declare delay delta digits do else elsif end entry exception exit for function generic goto if in interface is limited loop mod new not null of or others out overriding package parallel pragma private procedure protected raise range record rem renames requeue return reverse select separate some subtype synchronized tagged task terminate then type until use when while with xor",
    "[abort] [abs] [abstract] [accept] [access] [aliased] [all] [and] [array] [at] [begin] [body] [case] [constant] [declare] [delay] [delta] [digits] [do] [else] [elsif] [end] [entry] [exception] [exit] [for] [function] [generic] [goto] [if] [in] [interface] [is] [limited] [loop] [mod] [new] [not] [null] [of] [or] [others] [out] [overriding] [package] [parallel] [pragma] [private] [procedure] [protected] [raise] [range] [record] [rem] [renames] [requeue] [return] [reverse] [select] [separate] [some] [subtype] [synchronized] [tagged] [task] [terminate] [then] [type] [until] [use] [when] [while] [with] [xor]");
  T("ada case ignored", "ada", "BEGIN Begin begin",
    "[BEGIN] [Begin] [begin]");
  T("ada comment", "ada", "x := 1; -- if$end",
    "x := 1; {-- if}$[end]");
  T("ada doubled quote", "ada", "S := `a``b end`; end",
    "S := |`a``b end`|; [end]");
  T("ada attributes", "ada", "X'First A'Range P'Access T'Delta T'Digits M'Mod",
    "X'First A'Range P'Access T'Delta T'Digits M'Mod");
  T("ada character literals", "ada", "C := 'a'; if C = ''' then",
    "C := |'a'|; [if] C = |'''| [then]");
  T("ada qualified expression", "ada", "Character'('a') and T'(others => 'x')",
    "Character'(|'a'|) [and] T'([others] => |'x'|)");
  T("ada tick after a parenthesis", "ada", "F(X)'Img",
    "F(X)'Img");
  T("ada tick after all", "ada", "X.all'Access",
    "X.[all]'Access");
  T("ada literal after a word", "ada", "when 'x' => null;",
    "[when] |'x'| => [null];");
  T("ada utf-8 literal", "ada", "C := 'é';",
    "C := |'é'|;");
  T("ada lone quote", "ada", "x := 'ab end",
    "x := 'ab [end]")
END Ada;

PROCEDURE CPlusPlus;
BEGIN
  T("cpp every word", "cpp", "alignas alignof auto bool break case char const constexpr continue default do double else enum extern false float for goto if inline int long nullptr register return short signed sizeof static static_assert struct switch thread_local true typedef union unsigned void volatile while and and_eq asm bitand bitor catch char8_t char16_t char32_t class compl concept consteval constinit const_cast co_await co_return co_yield decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not not_eq operator or or_eq private protected public reinterpret_cast requires static_cast template this throw try typeid typename using virtual wchar_t xor xor_eq",
    "[alignas] [alignof] [auto] [bool] [break] [case] [char] [const] [constexpr] [continue] [default] [do] [double] [else] [enum] [extern] [false] [float] [for] [goto] [if] [inline] [int] [long] [nullptr] [register] [return] [short] [signed] [sizeof] [static] [static_assert] [struct] [switch] [thread_local] [true] [typedef] [union] [unsigned] [void] [volatile] [while] [and] [and_eq] [asm] [bitand] [bitor] [catch] [char8_t] [char16_t] [char32_t] [class] [compl] [concept] [consteval] [constinit] [const_cast] [co_await] [co_return] [co_yield] [decltype] [delete] [dynamic_cast] [explicit] [export] [friend] [mutable] [namespace] [new] [noexcept] [not] [not_eq] [operator] [or] [or_eq] [private] [protected] [public] [reinterpret_cast] [requires] [static_cast] [template] [this] [throw] [try] [typeid] [typename] [using] [virtual] [wchar_t] [xor] [xor_eq]");
  T("cpp contextual words are names", "cpp", "final override import module restrict _Bool",
    "final override import module restrict _Bool");
  T("cpp raw string", "cpp", "R`(a `if` b)` if",
    "|R`(a `if` b)`| [if]");
  T("cpp raw string with a delimiter", "cpp", "R`x(a )` if$)x` if",
    "|R`x(a )` if$)x`| [if]");
  T("cpp raw string prefixes", "cpp", "u8R`(if)` LR`(x)` uR`()` UR`()`",
    "|u8R`(if)`| |LR`(x)`| |uR`()`| |UR`()`|");
  T("cpp not raw strings", "cpp", "R `if` Rx`y` u8`z`",
    "R |`if`| Rx|`y`| u8|`z`|");
  T("cpp unclosed raw string", "cpp", "R`(if$if",
    "|R`(if$if|");
  T("cpp digit separators", "cpp", "1'000 if 'x'",
    "1'000 [if] |'x'|");
  T("cpp comments and directives", "cpp", "#include <new>$class C; // if",
    "#include |<new>|$[class] C; {// if}")
END CPlusPlus;

PROCEDURE Shell;
BEGIN
  TS("sh if", "sh", "if a; then b; elif c; then d; else e; fi",
    "[if] a; [then] b; [elif] c; [then] d; [else] e; [fi]");
  TS("sh loops", "sh", "while a; do b; done; until c~do d~done",
    "[while] a; [do] b; [done]; [until] c~[do] d~[done]");
  TS("sh ! and braces", "sh", "! a; { b; }", "[!] a; [{] b; [}]");
  TS("sh keywords out of command position", "sh", "echo if then done fi in esac { }",
    "echo if then done fi in esac { }");
  TS("sh after a pipe, a list or &", "sh", "a | if b; then c; fi || while d; do e; done & until f; do :; done && ! g",
    "a | [if] b; [then] c; [fi] || [while] d; [do] e; [done] & [until] f; [do] :; [done] && [!] g");
  TS("sh builtins are names", "sh", "cd /; export x; return; set -e",
    "cd /; export x; return; set -e");
  TS("sh after an assignment or a redirection", "sh", "x=1 if; >f then; 2>&1 done",
    "x=1 if; >f then; 2>&1 done");
  TS("sh a brace in a word", "sh", "{a,b} {echo x; }", "{a,b} {echo x; [}]");
  TS("sh escaped and quoted words", "sh", "\if 'if' i\f `if`",
    "\if |'if'| i\f |`if`|");
  TS("sh for", "sh", "for x in a done; do echo $x; done",
    "[for] x [in] a done; [do] echo $x; [done]");
  TS("sh for without in", "sh", "for x do :; done; for y; do :; done",
    "[for] x [do] :; [done]; [for] y; [do] :; [done]");
  TS("sh for, in on the next line", "sh", "for x~in a~do b~done",
    "[for] x~[in] a~[do] b~[done]");
  TS("sh case", "sh", "case $x in~  a|b) echo in;;~  (c) if d; then :; fi ;;~  *) done=1~esac",
    "[case] $x [in]~  a|b) echo in;;~  (c) [if] d; [then] :; [fi] ;;~  *) done=1~[esac]");
  TS("sh case on reserved words", "sh", "case done in done) echo done;; esac",
    "[case] done [in] done) echo done;; [esac]");
  TS("sh esac as a pattern", "sh", "case x in a|esac) :;; (esac) :;; esac",
    "[case] x [in] a|esac) :;; (esac) :;; [esac]");
  TS("sh empty case, in on the next line", "sh", "case x~in esac; if",
    "[case] x~[in] [esac]; [if]");
  TS("sh nested case", "sh", "case a in x) case b in y) z;; esac;& w) v;;& esac; fi",
    "[case] a [in] x) [case] b [in] y) z;; [esac];& w) v;;& [esac]; [fi]");
  TS("sh comments", "sh", "echo a#b ${#x} # c~# d~a;#e~if",
    "echo a#b ${#x} {# c}~{# d}~a;{#e}~[if]");
  TS("sh strings", "sh", "echo 'it''s' `a $(b `c`) \` ^d^` $'x\'y' $`z` if",
    "echo |'it'||'s'| |`a $(b `c`) \` ^d^`| |$'x\'y'| |$`z`| if");
  TS("sh strings across lines", "sh", "echo 'a~if' `b~if`; if",
    "echo |'a~if'| |`b~if`|; [if]");
  TS("sh unclosed string", "sh", "echo 'a~if", "echo |'a~if|");
  TS("sh command substitution", "sh", "x=$(if a; then b; fi) y=^while c; do :; done^ $(echo done)",
    "x=$([if] a; [then] b; [fi]) y=^[while] c; [do] :; [done]^ $(echo done)");
  TS("sh words around substitutions", "sh", "done$(x) $(x)done ^x^done; ${x:-done} $((if))",
    "done$(x) $(x)done ^x^done; ${x:-done} $((if))");
  TS("sh subshell", "sh", "(if a; then b; fi) done; (cd x; done)",
    "([if] a; [then] b; [fi]) done; (cd x; [done])");
  TS("sh here-document", "sh", "cat <<EOF; if x~if then~ EOF~EOF~if y",
    "cat <<EOF; [if] x~if then~ EOF~EOF~[if] y");
  TS("sh here-documents, quoted, two on a line", "sh", "cat <<'A' <<`B`; done~if~A~fi~B~fi",
    "cat <<|'A'| <<|`B`|; [done]~if~A~fi~B~[fi]");
  TS("sh here-document, <<- and escaped", "sh", "cat <<-\E~if~E~if",
    "cat <<-\E~if~E~[if]");
  TS("sh here-document, <<- strips tabs", "sh", "cat <<-E~	if~	E~if",
    "cat <<-E~	if~	E~[if]");
  TS("sh here-document in a substitution", "sh", "x=$(cat <<E~if~E~); if",
    "x=$(cat <<E~if~E~); [if]");
  TS("sh unclosed here-document", "sh", "cat <<E~if~fi", "cat <<E~if~fi");
  TS("sh function", "sh", "f() { if a; then :; fi; }~g () (done)",
    "f() [{] [if] a; [then] :; [fi]; [}]~g () ([done])");
  TS("sh has no bash words", "sh", "function f { :; }; select x in a; time b; coproc c; [[ d ]]",
    "function f { :; [}]; select x in a; time b; coproc c; [[ d ]]");
  TS("bash every word", "bash", "[[ a ]]; ! b; { c; }; time d; coproc e; function f { :; }",
    "[[[] a []]]; [!] b; [{] c; [}]; [time] d; [coproc] e; [function] f [{] :; [}]");
  TS("bash [[ ]]", "bash", "[[ -f done && (x || ! y) ]] && if",
    "[[[] -f done && (x || ! y) []]] && [if]");
  TS("bash select", "bash", "select x in a b; do break; done",
    "[select] x [in] a b; [do] break; [done]");
  TS("bash function with parentheses", "bash", "function f() { :; }~function g~{ done; }",
    "[function] f() [{] :; [}]~[function] g~[{] [done]; [}]");
  TS("bash arithmetic", "bash", "((done)) && x=$((if)); for ((i=0; i<2; i++)); do :; done",
    "((done)) && x=$((if)); [for] ((i=0; i<2; i++)); [do] :; [done]");
  TS("bash arrays and extended patterns", "bash", "a=(if done) b+=(fi); echo @(if|done) !(x)",
    "a=(if done) b+=(fi); echo @(if|done) !(x)");
  TS("bash process substitution", "bash", "diff <(if a; then :; fi) >(done)",
    "diff <([if] a; [then] :; [fi]) >([done])");
  TS("bash here-string", "bash", "cat <<<done; if x", "cat <<<done; [if] x");
  TS("bash &> and |&", "bash", "a &>f done |& if", "a &>f done |& [if]")
END Shell;

BEGIN
  failures := 0;
  Names;
  Oberon;
  Variants;
  Modula2;
  CLang;
  Pascal;
  Ada;
  CPlusPlus;
  Shell;
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdCodeTest.
