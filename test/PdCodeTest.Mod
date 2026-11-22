MODULE PdCodeTest;
(* Tests of PdCode, the highlighting scanner. Each case scans a piece of
   code and writes it back with its spans marked: [reserved word],
   {comment}, |string|; plain text unmarked. In the code, "$" stands
   for a newline and "`" for a double quote, which an Oberon string
   cannot hold. The cases include vgrind.md §6.2's mistakes: nested
   comments, comment marks in strings, C's //, Modula-2's case rule. *)

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
PROCEDURE Mark(lang: C.Language; code: ARRAY OF CHAR; VAR out: ARRAY OF CHAR; VAR ok: BOOLEAN);
  VAR t: ARRAY 512 OF CHAR; i, k: INTEGER; p: LONGINT; sp: C.Span; open, close: CHAR;
BEGIN
  i := 0;
  WHILE code[i] # 0X DO
    IF code[i] = "$" THEN t[i] := 0AX
    ELSIF code[i] = "`" THEN t[i] := 22X
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
      IF t[p] = 0AX THEN Append(out, k, "$")
      ELSIF t[p] = 22X THEN Append(out, k, "`")
      ELSE Append(out, k, t[p])
      END
    END;
    IF close # 0X THEN Append(out, k, close) END;
    p := sp.start + sp.len; sp := sp.next
  END;
  IF p # i THEN ok := FALSE END;
  out[k] := 0X
END Mark;

PROCEDURE T(name, langName, code, want: ARRAY OF CHAR);
  VAR got: ARRAY 1024 OF CHAR; lang: C.Language; ok: BOOLEAN;
BEGIN
  lang := C.Find(langName);
  IF lang = NIL THEN Out.String("  no language "); Out.String(langName); Out.Ln; Report(FALSE, name)
  ELSE
    Mark(lang, code, got, ok);
    IF ~ok THEN Out.String("  spans do not cover the text"); Out.Ln END;
    IF got # want THEN
      Out.String("  got  "); Out.String(got); Out.Ln;
      Out.String("  want "); Out.String(want); Out.Ln
    END;
    Report(ok & (got = want), name)
  END
END T;

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
    "#if X$  #  else$#include <stdio.h>$#define N [sizeof]([int])");
  T("c # not at line start", "c", "a # if",
    "a # [if]");
  T("c digit separators", "c", "1'000'000 if 0x1Fu 1e10",
    "1'000'000 [if] 0x1Fu 1e10");
  T("c every word", "c", "alignas alignof auto bool break case char const constexpr continue default do double else enum extern false float for goto if inline int long nullptr register restrict return short signed sizeof static static_assert struct switch thread_local true typedef typeof typeof_unqual union unsigned void volatile while _Alignas _Alignof _Atomic _BitInt _Bool _Complex _Decimal128 _Decimal32 _Decimal64 _Generic _Imaginary _Noreturn _Static_assert _Thread_local",
    "[alignas] [alignof] [auto] [bool] [break] [case] [char] [const] [constexpr] [continue] [default] [do] [double] [else] [enum] [extern] [false] [float] [for] [goto] [if] [inline] [int] [long] [nullptr] [register] [restrict] [return] [short] [signed] [sizeof] [static] [static_assert] [struct] [switch] [thread_local] [true] [typedef] [typeof] [typeof_unqual] [union] [unsigned] [void] [volatile] [while] [_Alignas] [_Alignof] [_Atomic] [_BitInt] [_Bool] [_Complex] [_Decimal128] [_Decimal32] [_Decimal64] [_Generic] [_Imaginary] [_Noreturn] [_Static_assert] [_Thread_local]")
END CLang;

BEGIN
  failures := 0;
  Names;
  Oberon;
  Variants;
  Modula2;
  CLang;
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdCodeTest.
