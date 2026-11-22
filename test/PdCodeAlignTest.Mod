MODULE PdCodeAlignTest;
(* Tests of PdCodeAlign, the layout of aligned code. Each case lays out
   a piece of code and writes the layout back: lines separated by " / ",
   a blank line as "-"; each segment as "@column", with "#group" for a
   later segment, then ":" and its pieces marked as PdCodeTest marks
   them ([reserved word], {comment}, |string|, plain unmarked); then
   the groups, in their order, as " G<id>@<column>=<lines>", the lines
   numbered from 1. In the code, "$" stands for a newline and "`" for a
   double quote. *)

IMPORT Out, Ropes, PdCode, A := PdCodeAlign;

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

PROCEDURE AppendStr(VAR s: ARRAY OF CHAR; VAR k: INTEGER; t: ARRAY OF CHAR);
  VAR i: INTEGER;
BEGIN
  i := 0; WHILE t[i] # 0X DO Append(s, k, t[i]); INC(i) END
END AppendStr;

PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; VAR k: INTEGER; n: LONGINT);
BEGIN
  IF n >= 10 THEN AppendInt(s, k, n DIV 10) END;
  Append(s, k, CHR(ORD("0") + n MOD 10))
END AppendInt;

PROCEDURE AppendRope(VAR s: ARRAY OF CHAR; VAR k: INTEGER; r: Ropes.Rope);
  VAR i: LONGINT; ch: CHAR;
BEGIN
  FOR i := 0 TO Ropes.Length(r) - 1 DO
    ch := Ropes.Fetch(r, i);
    IF ch = 22X THEN ch := "`" END;
    Append(s, k, ch)
  END
END AppendRope;

(* The line number of l in b, from 1 *)
PROCEDURE LineNo(b: A.Block; l: A.Line): INTEGER;
  VAR p: A.Line; n: INTEGER;
BEGIN
  p := b.lines; n := 1;
  WHILE p # l DO p := p.next; INC(n) END;
  RETURN n
END LineNo;

PROCEDURE Show(b: A.Block; VAR out: ARRAY OF CHAR);
  VAR k: INTEGER; l: A.Line; s: A.Segment; p: A.Piece; g: A.Group; m: A.Member;
    open, close: CHAR;
BEGIN
  k := 0; l := b.lines;
  WHILE l # NIL DO
    IF l # b.lines THEN AppendStr(out, k, " / ") END;
    IF l.segs = NIL THEN Append(out, k, "-") END;
    s := l.segs;
    WHILE s # NIL DO
      IF s # l.segs THEN Append(out, k, " ") END;
      Append(out, k, "@"); AppendInt(out, k, s.col);
      IF s.group # NIL THEN Append(out, k, "#"); AppendInt(out, k, s.group.id) END;
      Append(out, k, ":");
      p := s.pieces;
      WHILE p # NIL DO
        CASE p.kind OF
          PdCode.Plain: open := 0X; close := 0X
        | PdCode.Reserved: open := "["; close := "]"
        | PdCode.Comment: open := "{"; close := "}"
        | PdCode.String: open := "|"; close := "|"
        END;
        IF open # 0X THEN Append(out, k, open) END;
        AppendRope(out, k, p.text);
        IF close # 0X THEN Append(out, k, close) END;
        p := p.next
      END;
      s := s.next
    END;
    l := l.next
  END;
  g := b.groups;
  WHILE g # NIL DO
    AppendStr(out, k, " G"); AppendInt(out, k, g.id);
    Append(out, k, "@"); AppendInt(out, k, g.col); Append(out, k, "=");
    m := g.members;
    WHILE m # NIL DO
      AppendInt(out, k, LineNo(b, m.line));
      IF m.next # NIL THEN Append(out, k, ",") END;
      m := m.next
    END;
    g := g.next
  END;
  out[k] := 0X
END Show;

PROCEDURE T(name, langName, code, want: ARRAY OF CHAR);
  VAR got: ARRAY 1024 OF CHAR; t: ARRAY 512 OF CHAR; i: INTEGER;
    lang: PdCode.Language; text: Ropes.Rope; sp: PdCode.Span;
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
  text := Ropes.FromString(t);
  IF langName = "" THEN sp := NIL
  ELSE lang := PdCode.Find(langName); sp := PdCode.Scan(lang, text)
  END;
  Show(A.Layout(text, sp), got);
  IF got # want THEN
    Out.String("  got  "); Out.String(got); Out.Ln;
    Out.String("  want "); Out.String(want); Out.Ln
  END;
  Report(got = want, name)
END T;

PROCEDURE Cutting;
BEGIN
  T("one line", "", "x := 1", "@0:x := 1");
  T("indentation", "", "    x := 1", "@4:x := 1");
  T("two spaces cut", "", "a  b", "@0:a @3#1:b G1@3=1");
  T("single spaces stay", "", "a b c", "@0:a b c");
  T("trailing spaces dropped", "", "a b   ", "@0:a b");
  T("blank lines", "", "a$$   $b", "@0:a / - / - / @0:b");
  T("empty text", "", "", "-");
  T("final newline", "", "a$", "@0:a / -");
  T("utf-8 columns", "", "äöü  x$abc  y", "@0:äöü @5#1:x / @0:abc @5#1:y G1@5=1,2");
  T("tab is text", "", "a	  b", "@0:a	 @4#1:b G1@4=1")
END Cutting;

PROCEDURE Kinds;
BEGIN
  T("pieces by kind", "oberon", "  IF x THEN (* c *)",
    "@2:[IF] x [THEN] {(* c *)}");
  T("comment cut by spaces", "oberon", "x;  (* a  b *)",
    "@0:x; @4#1:{(* a} @10#2:{b *)} G1@4=1 G2@10=1");
  T("comment across lines", "oberon", "(* a$   b *) END",
    "@0:{(* a} / @3:{b *)} [END]");
  T("string kept whole", "oberon", "s :=  `a  b`  (* c *)",
    "@0:s := @6#1:|`a  b`| @14#2:{(* c *)} G1@6=1 G2@14=1");
  T("space between kinds", "c", "int  x; /* c */",
    "@0:[int] @5#1:x; {/* c */} G1@5=1")
END Kinds;

PROCEDURE Groups;
BEGIN
  T("group of consecutive lines", "",
    "a  x$bb  x$c   x", "@0:a @3#1:x / @0:bb @4#2:x / @0:c @4#2:x G1@3=1 G2@4=2,3");
  T("blank line splits a group", "",
    "a   x$$b   x", "@0:a @4#1:x / - / @0:b @4#2:x G1@4=1 G2@4=3");
  T("groups in column order", "",
    "a  b  c$d  e  f", "@0:a @3#1:b @6#2:c / @0:d @3#1:e @6#2:f G1@3=1,2 G2@6=1,2");
  T("a group skips a line without it", "",
    "a     x$b  y  x$c     x",
    "@0:a @6#2:x / @0:b @3#1:y @6#2:x / @0:c @6#2:x G1@3=2 G2@6=1,2,3");
  T("a line without the column ends it", "",
    "a     x$b$c     x", "@0:a @6#1:x / @0:b / @0:c @6#2:x G1@6=1 G2@6=3");
  T("indentation is not grouped", "",
    "  a$  b  x$  c  x", "@2:a / @2:b @5#1:x / @2:c @5#1:x G1@5=2,3")
END Groups;

PROCEDURE Names;
BEGIN
  Report((A.AlignOf("none") = A.None) & (A.AlignOf("fixed") = A.Fixed)
    & (A.AlignOf("elastic") = A.Elastic) & (A.AlignOf("hybrid") = A.Hybrid), "alignment names");
  Report((A.AlignOf("Hybrid") = -1) & (A.AlignOf("") = -1), "unknown alignment")
END Names;

BEGIN
  failures := 0;
  Cutting;
  Kinds;
  Groups;
  Names;
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdCodeAlignTest.
