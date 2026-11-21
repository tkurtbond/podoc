MODULE PdLayoutTest;
(* Tests of PdLayout: each Doc rendered, after a "== name" line and
   followed by "|". The expected output is what doclayout 0.5.0.3
   renders for the same Docs. *)

IMPORT Ropes, PdIO, L := PdLayout;

VAR
  words: ARRAY 64 OF CHAR;

PROCEDURE T(s: ARRAY OF CHAR): L.Doc;
  VAR i, n: LONGINT; t: ARRAY 64 OF CHAR;
BEGIN
  (* "$" stands for a new line *)
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  FOR i := 0 TO n DO
    IF s[i] = "$" THEN t[i] := 0AX ELSE t[i] := s[i] END
  END;
  RETURN L.Text(t)
END T;

(* The words of s, each a Doc, joined by f *)
PROCEDURE Words(s: ARRAY OF CHAR): L.Doc;
  VAR d: L.Doc; i, j: LONGINT;
BEGIN
  d := NIL; i := 0;
  WHILE s[i] # 0X DO
    j := 0;
    WHILE (s[i] # 0X) & (s[i] # " ") DO words[j] := s[i]; INC(i); INC(j) END;
    words[j] := 0X;
    d := L.Hsep(d, L.Text(words));
    IF s[i] = " " THEN INC(i) END
  END;
  RETURN d
END Words;

PROCEDURE Show(name: ARRAY OF CHAR; width: LONGINT; d: L.Doc);
BEGIN
  PdIO.WriteString("== "); PdIO.WriteString(name); PdIO.WriteLn;
  PdIO.WriteRope(L.Render(d, width));
  PdIO.WriteString("|"); PdIO.WriteLn
END Show;

PROCEDURE Num(n: LONGINT);
BEGIN
  IF n >= 10 THEN Num(n DIV 10) END;
  PdIO.WriteChar(CHR(ORD("0") + n MOD 10))
END Num;

PROCEDURE Offsets(name: ARRAY OF CHAR; d: L.Doc);
BEGIN
  PdIO.WriteString("== "); PdIO.WriteString(name); PdIO.WriteLn;
  Num(L.Offset(d)); PdIO.WriteString(" ");
  Num(L.MinOffset(d)); PdIO.WriteString("|"); PdIO.WriteLn
END Offsets;

PROCEDURE Chop(name, s: ARRAY OF CHAR; n: LONGINT);
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO IF s[i] = "$" THEN s[i] := 0AX END; INC(i) END;
  PdIO.WriteString("== "); PdIO.WriteString(name); PdIO.WriteLn;
  PdIO.WriteRope(L.Chop(Ropes.FromString(s), n));
  PdIO.WriteString("|"); PdIO.WriteLn
END Chop;

PROCEDURE Same(r: Ropes.Rope): Ropes.Rope;
BEGIN
  RETURN r
END Same;

PROCEDURE Bool(b: BOOLEAN);
BEGIN
  IF b THEN PdIO.WriteString("TRUE") ELSE PdIO.WriteString("FALSE") END
END Bool;

(* Long spines: n texts "x" and a carriage return, concatenated to the
   right (right) or to the left (~right), which must not overflow the
   stack: the lengths of the text left by Chomp, RemoveFinalNl and
   MapText, and HasNewlines before and after Chomp *)
PROCEDURE Long(name: ARRAY OF CHAR; n: LONGINT; right: BOOLEAN);
  VAR d: L.Doc; i: LONGINT;
BEGIN
  IF right THEN
    d := L.Cr(); FOR i := 1 TO n DO d := L.Cat(T("x"), d) END
  ELSE
    d := NIL; FOR i := 1 TO n DO d := L.Cat(d, T("x")) END; d := L.Cat(d, L.Cr())
  END;
  PdIO.WriteString("== "); PdIO.WriteString(name); PdIO.WriteLn;
  Num(Ropes.Length(L.AllText(L.Chomp(d)))); PdIO.WriteString(" ");
  Num(Ropes.Length(L.AllText(L.RemoveFinalNl(d)))); PdIO.WriteString(" ");
  Num(Ropes.Length(L.AllText(L.MapText(d, Same)))); PdIO.WriteString(" ");
  Bool(L.HasNewlines(d)); PdIO.WriteString(" ");
  Bool(L.HasNewlines(L.Chomp(d))); PdIO.WriteString("|"); PdIO.WriteLn
END Long;

PROCEDURE Vcat(a, b, c, d: L.Doc): L.Doc;
BEGIN
  RETURN L.Above(a, L.Above(b, L.Above(c, d)))
END Vcat;

PROCEDURE Vsep(a, b, c: L.Doc): L.Doc;
BEGIN
  RETURN L.AboveBlank(a, L.AboveBlank(b, c))
END Vsep;

PROCEDURE Run;
  VAR s: ARRAY 32 OF CHAR;
BEGIN
  Show("text", 0, T("hello"));
  Show("literal with new lines", 0, T("a$b$$c"));
  Show("cr after text", 0, L.Cat3(T("a"), L.Cr(), T("b")));
  Show("cr cr", 0, L.Cat(T("a"), L.Cat3(L.Cr(), L.Cr(), T("b"))));
  Show("blankline", 0, L.Cat3(T("a"), L.BlankLine(), T("b")));
  Show("cr blankline", 0,
    L.Cat(T("a"), L.Cat(L.Cr(), L.Cat3(L.BlankLine(), L.Cr(), T("b")))));
  Show("blanklines 2", 0,
    L.Cat(T("a"), L.Cat3(L.BlankLines(2), L.BlankLine(), T("b"))));
  Show("leading blankline", 0, L.Cat(L.BlankLine(), T("a")));
  Show("trailing blankline", 0, L.Cat(T("a"), L.BlankLine()));
  Show("vcat", 0, Vcat(T("a"), T("b"), NIL, T("c")));
  Show("vsep", 0, Vsep(T("a"), T("b"), T("c")));
  Show("hsep", 0, L.Hsep(T("a"), T("b")));
  Show("wrap", 10, Words("the quick brown fox jumps over the lazy dog"));
  Show("no wrap", 0, Words("the quick brown fox jumps over the lazy dog"));
  Show("nest", 0, L.Above(T("x"), L.Above(L.Nest(2, L.Above(T("a"), T("b"))), T("y"))));
  Show("nest blank", 0, L.Nest(2, L.AboveBlank(T("a"), T("b"))));
  Show("prefixed", 0, L.Prefixed("> ", L.AboveBlank(T("a"), T("b"))));
  Show("hang", 0, L.Hang(3, T("- "), L.Above(T("a"), T("b"))));
  Show("hang wrap", 12, L.Hang(2, T("- "), Words("one two three four five six")));
  Show("nest in middle", 0, L.Cat(T("ab"), L.Nest(2, L.Cat3(T("c"), L.Cr(), T("d")))));
  Show("flush", 0, L.Nest(4, L.Above(T("a"), L.Above(L.Flush(T("b")), T("c")))));
  Show("beforeNonBlank", 0,
    L.Above(L.Cat(L.BeforeNonBlank(T("X")), T("a")),
            L.Cat(L.BeforeNonBlank(T("X")), T(" b"))));
  Show("afterBreak", 0,
    L.Above(L.Cat3(T("a"), L.AfterBreak("\&"), T("b")),
            L.Cat(L.AfterBreak("\&"), T(".c"))));
  Show("chomp", 0, L.Cat(L.Chomp(L.Cat3(T("a"), L.BlankLine(), L.Cr())), T("b")));
  Show("nestle", 0, L.Cat(L.Nestle(L.Cat3(L.BlankLine(), L.Cr(), T("a"))), T("b")));
  Show("nowrap", 5, L.NoWrap(Words("aaa bbb ccc")));
  Show("space then cr", 0, L.Cat(T("a"), L.Cat3(L.Space(), L.Cr(), T("b"))));
  Show("wide chars", 6, Words("日本 語の text"));
  s[0] := "e"; s[1] := 0CCX; s[2] := 81X; s[3] := "e"; s[4] := 0CCX; s[5] := 81X;
  s[6] := " "; s[7] := "a"; s[8] := "b"; s[9] := "c"; s[10] := 0X;
  Show("combining", 5, Words(s));
  Show("newline newline", 0, L.Cat(T("a"), L.Cat3(T("$"), T("$"), T("b"))));
  Show("empty", 0, NIL);
  Show("prefix trimmed", 0, L.Prefixed("> ", L.Cat(T("a"), L.Cat3(T("$"), T("$"), T("b")))));
  Show("nested prefixes", 0,
    L.Prefixed("> ", L.AboveBlank(T("a"), L.Prefixed("> ", L.Above(T("b"), T("c"))))));
  Show("no bad wraps", 4, Words("aaa * bbb > c 1. d"));
  Show("avoid bad wraps", 4, L.AvoidBadWraps(Words("aaa * bbb > c 1. d"), NIL));
  Offsets("offsets", Words("aa bbbb c"));
  Offsets("offsets of lines", L.Above(Words("a b c d e"), Words("ffff g")));
  Offsets("offsets of prefixed", L.Cat(T("ab"), L.Prefixed("> ", Words("ccc d"))));
  Chop("chop", "abcdefg", 3);
  Chop("chop lines", "ab$cdefgh$i$", 2);
  Long("long right spine", 1000000, TRUE);
  Long("long left spine", 1000000, FALSE)
END Run;

BEGIN
  Run;
  PdIO.CloseOutput
END PdLayoutTest.
