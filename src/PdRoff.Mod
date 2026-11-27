MODULE PdRoff;
(* PdRoff: what the roff writers share, the ms writer (PdMs) and the
   mom writer: roff's escapes (pandoc's Text.Pandoc.Writers.Roff and
   RoffChar), small caps, PDF anchors and strings, the font state, the
   plain text of inlines for PDF bookmarks, and tbl tables. *)

IMPORT Ropes, Strings, Utf8, Unicode, A := PdAst, L := PdLayout, Sh := PdShared, PdAscii, PdCode, PdCodeAlign;

TYPE
  Rope = Ropes.Rope;
  Buf = POINTER TO ARRAY OF CHAR;

  (* The font features on: italic, bold, code (constant width) and
     the one pandoc calls V *)
  Fonts* = RECORD
    i*, b*, c*, v*: BOOLEAN
  END;

  (* A writer's blockListTo, for the cells of a table *)
  BlocksProc* = PROCEDURE (b: A.Block): L.Doc;

  (* a list of Docs *)
  Docs = POINTER TO DocsDesc;
  DocsDesc = RECORD
    d: L.Doc;
    next: Docs
  END;

(* Ropes *)

PROCEDURE R(s: ARRAY OF CHAR): Rope;
BEGIN
  RETURN Ropes.FromString(s)
END R;

PROCEDURE Cat(a, b: Rope): Rope;
BEGIN
  RETURN Ropes.Cat(a, b)
END Cat;

PROCEDURE CatS(a: Rope; s: ARRAY OF CHAR): Rope;
BEGIN
  RETURN Ropes.Cat(a, Ropes.FromString(s))
END CatS;

PROCEDURE CatC(a: Rope; ch: CHAR): Rope;
BEGIN
  RETURN Ropes.Cat(a, Ropes.FromChar(ch))
END CatC;

PROCEDURE Len(r: Rope): LONGINT;
BEGIN
  RETURN Ropes.Length(r)
END Len;

PROCEDURE Eq(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN Ropes.EqualString(r, s)
END Eq;

(* The text of r in a new buffer, 0X after it *)
PROCEDURE ToBuf(r: Rope): Buf;
  VAR b: Buf; n: LONGINT;
BEGIN
  n := Len(r); NEW(b, n + 1);
  IF n > 0 THEN Ropes.Blit(r, 0, b^, 0, n) END;
  b[n] := 0X;
  RETURN b
END ToBuf;

(* The rune ru, encoded *)
PROCEDURE RuneRope(ru: Utf8.Rune): Rope;
  VAR s: ARRAY 8 OF CHAR; k: LONGINT;
BEGIN
  k := 0;
  IF Utf8.Encode(ru, s, k) THEN RETURN Ropes.FromSubchars(s, 0, k) END;
  RETURN NIL
END RuneRope;

(* r with each rune mapped to upper case (up) or lower case *)
PROCEDURE MapCase*(r: Rope; up: BOOLEAN): Rope;
  VAR b: Buf; n, i, q: LONGINT; out: Rope; ru: Utf8.Rune;
BEGIN
  n := Len(r); b := ToBuf(r); out := NIL; i := 0;
  WHILE i < n DO
    q := i;
    IF Utf8.Decode(b^, q, ru) & (q > i) THEN
      IF up THEN ru := Unicode.ToUpper(ru) ELSE ru := Unicode.ToLower(ru) END;
      out := Cat(out, RuneRope(ru))
    ELSE out := CatC(out, b[i]); q := i + 1
    END;
    i := q
  END;
  RETURN out
END MapCase;

(* Escapes *)

(* pandoc's escapeString False AllowUTF8: roff's special characters
   as escapes, and \& before a period that starts a line *)
PROCEDURE EscapeStr*(r: Rope): Rope;
  VAR b: Buf; n, i, start, k: LONGINT; out: Rope; rep: ARRAY 8 OF CHAR;
BEGIN
  n := Len(r);
  IF n = 0 THEN RETURN NIL END;
  b := ToBuf(r);
  out := NIL; start := 0; i := 0;
  WHILE i < n DO
    rep[0] := 0X; k := 1;
    CASE b[i] OF
      0AX:
      IF (i + 1 < n) & (b[i + 1] = ".") THEN
        rep[0] := 0AX; rep[1] := "\"; rep[2] := "&"; rep[3] := "."; rep[4] := 0X; k := 2
      END
    | "'": rep := "\(aq"
    | 22X: rep := "\(dq"
    | "`": rep := "\(ga"
    | "^": rep := "\(ha"
    | "~": rep := "\(ti"
    | "\": rep := "\(rs"
    | "@": rep := "\(at"
    | 0C2X:
      IF (i + 1 < n) & (b[i + 1] = 0A0X) THEN rep := "\ "; k := 2 END
    | 0E2X:
      IF (i + 2 < n) & (b[i + 1] = 80X) THEN
        CASE b[i + 2] OF
          98X: rep := "\(oq"
        | 99X: rep := "\(cq"
        | 9CX: rep := "\(lq"
        | 9DX: rep := "\(rq"
        | 94X: rep := "\(em"
        | 93X: rep := "\(en"
        | 0A6X: rep := "\&..."
        ELSE
        END;
        IF rep[0] # 0X THEN k := 3 END
      END
    ELSE
    END;
    IF rep[0] # 0X THEN
      IF i > start THEN out := Cat(out, Ropes.Substring(r, start, i - start)) END;
      out := CatS(out, rep); INC(i, k); start := i
    ELSE INC(i)
    END
  END;
  IF start = 0 THEN RETURN r END; (* nothing escaped *)
  IF n > start THEN out := Cat(out, Ropes.Substring(r, start, n - start)) END;
  RETURN out
END EscapeStr;

(* toSmallCaps: each run of lower case letters in upper case and
   smaller, \s-2 ... \s0; everything else escaped *)
PROCEDURE ToSmallCaps*(r: Rope): Rope;
  VAR b: Buf; n, i, q: LONGINT; out, run: Rope; ru: Utf8.Rune; lower: BOOLEAN;
BEGIN
  n := Len(r); b := ToBuf(r);
  out := NIL; run := NIL; lower := FALSE; i := 0;
  WHILE i < n DO
    q := i;
    IF ~Utf8.Decode(b^, q, ru) OR (q <= i) THEN ru := -1; q := i + 1 END;
    IF (ru >= 0) & (Unicode.Category(ru) = Unicode.Ll) THEN
      run := Cat(run, RuneRope(Unicode.ToUpper(ru))); lower := TRUE
    ELSE
      IF lower THEN
        out := CatS(Cat(CatS(out, "\s-2"), EscapeStr(run)), "\s0"); run := NIL; lower := FALSE
      END;
      out := Cat(out, EscapeStr(Ropes.Substring(r, i, q - i)))
    END;
    i := q
  END;
  IF lower THEN out := CatS(Cat(CatS(out, "\s-2"), EscapeStr(run)), "\s0") END;
  RETURN out
END ToSmallCaps;

(* toAscii: an identifier for a PDF anchor *)
PROCEDURE ToAscii*(r: Rope): Rope;
  VAR b, o: Buf; n, i, q, k, j: LONGINT; ru: Utf8.Rune; ch: CHAR;
    d: ARRAY 12 OF CHAR;
BEGIN
  n := Len(r); b := ToBuf(r);
  NEW(o, 10 * n + 1); k := 0; i := 0; (* a byte gives at most _u1114111_ *)
  WHILE i < n DO
    q := i;
    IF ~Utf8.Decode(b^, q, ru) OR (q <= i) THEN ru := ORD(b[i]); q := i + 1 END;
    IF PdAscii.ToAscii(ru, ch) & (ch # "/") THEN o[k] := ch; INC(k)
    ELSE
      o[k] := "_"; o[k + 1] := "u"; INC(k, 2);
      j := 0;
      REPEAT d[j] := CHR(ORD("0") + ru MOD 10); ru := ru DIV 10; INC(j) UNTIL ru = 0;
      WHILE j > 0 DO DEC(j); o[k] := d[j]; INC(k) END;
      o[k] := "_"; INC(k)
    END;
    i := q
  END;
  IF k = 0 THEN RETURN NIL END;
  RETURN Ropes.FromSubchars(o^, 0, k)
END ToAscii;

(* Puts v, a byte, at o[k] as \ooo *)
PROCEDURE Octal(VAR o: ARRAY OF CHAR; VAR k: LONGINT; v: LONGINT);
BEGIN
  o[k] := "\"; o[k + 1] := CHR(ORD("0") + v DIV 64);
  o[k + 2] := CHR(ORD("0") + v DIV 8 MOD 8); o[k + 3] := CHR(ORD("0") + v MOD 8);
  INC(k, 4)
END Octal;

(* escapePDFString: as it is, if it is ASCII without ( ) \ and ";
   otherwise UTF-16BE, each byte in octal, after a byte order mark.
   Built in one buffer: a byte gives at most 8 bytes (( ) \ and a byte
   not UTF-8 give 8 each) *)
PROCEDURE EscapePDFString*(r: Rope): Rope;
  VAR b, o: Buf; n, i, q, k: LONGINT; ru, lo, hi: LONGINT; x: Utf8.Rune;
    plain: BOOLEAN; ch: CHAR;
BEGIN
  n := Len(r); b := ToBuf(r);
  plain := TRUE; i := 0;
  WHILE plain & (i < n) DO
    ch := b[i];
    IF (ORD(ch) >= 80H) OR (ch = "(") OR (ch = ")") OR (ch = "\") OR (ch = 22X) THEN plain := FALSE END;
    INC(i)
  END;
  IF plain THEN RETURN r END;
  NEW(o, 8 * n + 8); k := 0;
  Octal(o^, k, 0FEH); Octal(o^, k, 0FFH); i := 0;
  WHILE i < n DO
    ch := b[i];
    IF (ORD(ch) < 80H) & (ch # "\") & (ch # "(") & (ch # ")") THEN
      Octal(o^, k, 0); o[k] := ch; INC(k); INC(i)
    ELSE
      q := i;
      IF ~Utf8.Decode(b^, q, x) OR (q <= i) THEN x := 0FFFDH; q := i + 1 END;
      ru := x;
      IF ru >= 10000H THEN
        DEC(ru, 10000H); hi := 0D800H + ru DIV 400H; lo := 0DC00H + ru MOD 400H;
        Octal(o^, k, hi DIV 256); Octal(o^, k, hi MOD 256);
        Octal(o^, k, lo DIV 256); Octal(o^, k, lo MOD 256)
      ELSE
        Octal(o^, k, ru DIV 256); Octal(o^, k, ru MOD 256)
      END;
      i := q
    END
  END;
  RETURN Ropes.FromSubchars(o^, 0, k)
END EscapePDFString;

(* Whether ch may stand in a URI as it is (isAllowedInURI), @ apart *)
PROCEDURE UriChar(ch: CHAR): BOOLEAN;
BEGIN
  CASE ch OF
    "0" .. "9", "A" .. "Z", "a" .. "z",
    "-", "_", ".", "~", ":", "/", "?", "#", "[", "]", "!", "$", "&", "'",
    "(", ")", "*", "+", ",", ";", "=", "%": RETURN TRUE
  ELSE RETURN FALSE
  END
END UriChar;

(* escapeUri: what is not allowed in a URI, and @, %-encoded byte by
   byte *)
PROCEDURE EscapeUri*(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; out: Rope; ch: CHAR; s: ARRAY 4 OF CHAR; hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789ABCDEF";
  n := Len(r); b := ToBuf(r); out := NIL;
  FOR i := 0 TO n - 1 DO
    ch := b[i];
    IF UriChar(ch) THEN out := CatC(out, ch)
    ELSE
      s[0] := "%"; s[1] := hex[ORD(ch) DIV 16]; s[2] := hex[ORD(ch) MOD 16]; s[3] := 0X;
      out := CatS(out, s)
    END
  END;
  RETURN out
END EscapeUri;

(* Paths and sizes *)

(* The extension of the path s, as takeExtension finds it, with its
   period; NIL if it has none *)
PROCEDURE Extension*(s: Rope): Rope;
  VAR n, i: LONGINT; ch: CHAR;
BEGIN
  n := Len(s); i := n;
  WHILE i > 0 DO
    DEC(i); ch := Ropes.Fetch(s, i);
    IF ch = "/" THEN RETURN NIL
    ELSIF ch = "." THEN RETURN Ropes.Substring(s, i, n - i)
    END
  END;
  RETURN NIL
END Extension;

(* The dimension key of attr in points (inPoints), FALSE if it has
   none; a percentage is 0 *)
PROCEDURE Points*(attr: A.Attr; key: ARRAY OF CHAR; VAR p: LONGREAL): BOOLEAN;
  VAR v, int, frac, unit, num: Rope; found: BOOLEAN; s: ARRAY 64 OF CHAR; x: LONGREAL;
BEGIN
  IF attr = NIL THEN RETURN FALSE END;
  v := A.GetKeyVal(attr, key, found);
  IF ~found OR ~Sh.NumUnit(v, int, frac, unit) THEN RETURN FALSE END;
  num := int;
  IF frac # NIL THEN num := Cat(CatS(num, "."), frac) END;
  IF Len(num) >= LEN(s) THEN RETURN FALSE END;
  Ropes.ToString(num, s);
  Strings.StrToLongReal(s, x);
  IF Eq(unit, "px") OR (unit = NIL) OR Eq(unit, "") THEN x := ENTIER(x) / 96.0D0
  ELSIF Eq(unit, "cm") THEN x := x * 0.3937007874D0
  ELSIF Eq(unit, "mm") THEN x := x * 0.03937007874D0
  ELSIF Eq(unit, "in") OR Eq(unit, "inch") THEN
  ELSIF Eq(unit, "%") THEN x := 0
  ELSIF Eq(unit, "pt") THEN x := x / 72.0D0
  ELSIF Eq(unit, "pc") THEN x := x / 6.0D0
  ELSIF Eq(unit, "em") THEN x := x * (11.0D0 / 64.0D0)
  ELSE RETURN FALSE
  END;
  p := x * 72.0D0;
  RETURN TRUE
END Points;

(* toRomanNumeral: n in upper case Roman numerals, "?" if out of range *)
PROCEDURE Roman*(n: LONGINT): Rope;
  VAR r: Rope;
BEGIN
  IF (n >= 4000) OR (n < 0) THEN RETURN R("?") END;
  r := NIL;
  WHILE n >= 1000 DO r := CatC(r, "M"); DEC(n, 1000) END;
  IF n >= 900 THEN r := CatS(r, "CM"); DEC(n, 900) END;
  IF n >= 500 THEN r := CatC(r, "D"); DEC(n, 500) END;
  IF n >= 400 THEN r := CatS(r, "CD"); DEC(n, 400) END;
  WHILE n >= 100 DO r := CatC(r, "C"); DEC(n, 100) END;
  IF n >= 90 THEN r := CatS(r, "XC"); DEC(n, 90) END;
  IF n >= 50 THEN r := CatC(r, "L"); DEC(n, 50) END;
  IF n >= 40 THEN r := CatS(r, "XL"); DEC(n, 40) END;
  WHILE n >= 10 DO r := CatC(r, "X"); DEC(n, 10) END;
  IF n = 9 THEN r := CatS(r, "IX"); n := 0 END;
  IF n >= 5 THEN r := CatC(r, "V"); DEC(n, 5) END;
  IF n = 4 THEN r := CatS(r, "IV"); n := 0 END;
  WHILE n >= 1 DO r := CatC(r, "I"); DEC(n) END;
  RETURN r
END Roman;

(* Fonts *)

(* Turns the feature c (I, B, C or V) of f on or off *)
PROCEDURE Toggle*(VAR f: Fonts; c: CHAR);
BEGIN
  CASE c OF
    "I": f.i := ~f.i
  | "B": f.b := ~f.b
  | "C": f.c := ~f.c
  | "V": f.v := ~f.v
  END
END Toggle;

(* Turns every feature of f off *)
PROCEDURE ResetFonts*(VAR f: Fonts);
BEGIN
  f.i := FALSE; f.b := FALSE; f.c := FALSE; f.v := FALSE
END ResetFonts;

(* s := fontChange's escape: \f[...] for the features of f on, bold
   also if bold *)
PROCEDURE FontString*(VAR f: Fonts; bold: BOOLEAN; VAR s: ARRAY OF CHAR);
  VAR k: INTEGER;
BEGIN
  COPY("\f[", s); k := 3;
  IF f.c THEN s[k] := "C"; INC(k) END;
  IF f.v THEN s[k] := "V"; INC(k) END;
  IF bold OR f.b THEN s[k] := "B"; INC(k) END;
  IF f.i THEN s[k] := "I"; INC(k) END;
  IF k = 3 THEN COPY("\f[R]", s)
  ELSIF (k = 4) & f.c THEN COPY("\f[CR]", s)
  ELSE s[k] := "]"; s[k + 1] := 0X
  END
END FontString;

(* fontChange: \f[...] for the features of f on, bold also if bold *)
PROCEDURE FontChange*(VAR f: Fonts; bold: BOOLEAN): L.Doc;
  VAR s: ARRAY 10 OF CHAR;
BEGIN
  FontString(f, bold, s);
  RETURN L.Text(s)
END FontChange;

(* Highlighted code (Phase 24) *)

(* The code text escaped as EscapeStr escapes it, with its reserved
   words between bold and back and its comments between italic and
   back, as lang's scanner finds them; all plain if lang is NIL. In a
   block, a line that starts with "." is preceded by "\&", the first
   one too. *)
PROCEDURE Highlight*(text: Rope; lang: PdCode.Language; block: BOOLEAN; bold, italic, back: ARRAY OF CHAR): Rope;
  VAR sp: PdCode.Span; out, piece: Rope;
BEGIN
  IF lang = NIL THEN sp := NIL ELSE sp := PdCode.Scan(lang, text) END;
  IF sp = NIL THEN
    out := EscapeStr(text);
    IF block & (Len(text) > 0) & (Ropes.Fetch(text, 0) = ".") THEN out := Cat(Ropes.FromString("\&"), out) END;
    RETURN out
  END;
  out := NIL;
  WHILE sp # NIL DO
    piece := Ropes.Substring(text, sp.start, sp.len);
    IF block & (Ropes.Fetch(piece, 0) = ".")
       & ((sp.start = 0) OR (Ropes.Fetch(text, sp.start - 1) = 0AX)) THEN
      out := Cat(out, Ropes.FromString("\&"))
    END;
    piece := EscapeStr(piece);
    CASE sp.kind OF
      PdCode.Reserved: out := Cat(Cat(Cat(out, Ropes.FromString(bold)), piece), Ropes.FromString(back))
    | PdCode.Comment: out := Cat(Cat(Cat(out, Ropes.FromString(italic)), piece), Ropes.FromString(back))
    ELSE out := Cat(out, piece)
    END;
    sp := sp.next
  END;
  RETURN out
END Highlight;

(* Aligned code (Phase 24.4; decisions 32 and 33): columns are written
   as numbers times the register PdCodeCol, gaps as PdCodeGap, which
   the template may set from code-column and code-gap; the block sets
   them to 0.5 and 1 em if they are not. *)

(* out with the pieces of the segment s, escaped, reserved words between
   bold and back, comments between italic and back *)
PROCEDURE SegText(out: Rope; s: PdCodeAlign.Segment; bold, italic, back: ARRAY OF CHAR): Rope;
  VAR p: PdCodeAlign.Piece;
BEGIN
  p := s.pieces;
  WHILE p # NIL DO
    CASE p.kind OF
      PdCode.Reserved: out := CatS(Cat(CatS(out, bold), EscapeStr(p.text)), back)
    | PdCode.Comment: out := CatS(Cat(CatS(out, italic), EscapeStr(p.text)), back)
    ELSE out := Cat(out, EscapeStr(p.text))
    END;
    p := p.next
  END;
  RETURN out
END SegText;

(* The line l's segments before upto (all if upto is NIL), each moved to
   its place: the first to its column, a later one in the fixed form
   to its column but at least a gap past the text before it, or in the
   elastic and hybrid forms to its group's register *)
PROCEDURE AlignedLine(l: PdCodeAlign.Line; upto: PdCodeAlign.Segment; align: INTEGER;
  bold, italic, back: ARRAY OF CHAR): Rope;
  VAR s: PdCodeAlign.Segment; out, col: Rope;
BEGIN
  out := NIL; s := l.segs;
  WHILE (s # NIL) & (s # upto) DO
    col := Sh.IntRope(s.col);
    IF s = l.segs THEN
      IF s.col > 0 THEN out := CatS(Cat(CatS(out, "\h'|"), col), "u*\n[PdCodeCol]u'")
      ELSIF Ropes.Fetch(s.pieces.text, 0) = "." THEN out := CatS(out, "\&")
      END
    ELSIF align = PdCodeAlign.Fixed THEN
      out := CatS(Cat(CatS(out, "\h'("), col), "u*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'")
    ELSE out := CatS(Cat(CatS(out, "\h'|\n[PdG"), Sh.IntRope(s.group.id)), "]u'")
    END;
    out := SegText(out, s, bold, italic, back);
    s := s.next
  END;
  RETURN out
END AlignedLine;

(* The code text, in the lines of a no-fill block, aligned as align
   (PdCodeAlign's Fixed, Elastic or Hybrid) says: reserved words
   between bold and back, comments between italic and back, as lang's
   scanner finds them (none if lang is NIL); before the lines, the
   requests that set the registers it needs: PdCodeCol and PdCodeGap
   if they are not set, and for the elastic and hybrid forms one
   register per group, PdG1, PdG2 ..., measured from its lines' text
   before it *)
PROCEDURE AlignedCode*(text: Rope; lang: PdCode.Language; align: INTEGER;
  bold, italic, back: ARRAY OF CHAR): Rope;
  VAR b: PdCodeAlign.Block; sp: PdCode.Span; out, reg: Rope; l: PdCodeAlign.Line;
    g: PdCodeAlign.Group; m: PdCodeAlign.Member;
BEGIN
  IF lang = NIL THEN sp := NIL ELSE sp := PdCode.Scan(lang, text) END;
  b := PdCodeAlign.Layout(text, sp);
  out := CatC(CatS(CatC(R(".if !r PdCodeCol .nr PdCodeCol 0.5m"), 0AX), ".if !r PdCodeGap .nr PdCodeGap 1m"), 0AX);
  IF align # PdCodeAlign.Fixed THEN
    g := b.groups;
    WHILE g # NIL DO
      reg := CatS(Sh.IntRope(g.id), " ");
      out := Cat(CatS(out, ".nr PdG"), reg);
      IF align = PdCodeAlign.Hybrid THEN out := CatS(Cat(out, Sh.IntRope(g.col)), "*\n[PdCodeCol]")
      ELSE out := CatS(out, "0")
      END;
      out := CatC(out, 0AX);
      m := g.members;
      WHILE m # NIL DO
        out := CatS(Cat(CatS(Cat(CatS(out, ".nr PdG"), reg), "\n[PdG"), Sh.IntRope(g.id)), "]>?(\w'\&");
        out := CatS(Cat(out, AlignedLine(m.line, m.seg, align, bold, italic, back)), "'u+\n[PdCodeGap]u)");
        out := CatC(out, 0AX);
        m := m.next
      END;
      g := g.next
    END
  END;
  l := b.lines;
  WHILE l # NIL DO
    out := Cat(out, AlignedLine(l, NIL, align, bold, italic, back));
    IF l.next # NIL THEN out := CatC(out, 0AX) END;
    l := l.next
  END;
  RETURN out
END AlignedCode;

(* Inline code, text with the attributes attr, in the fonts f (and
   bold if bold) with the code font added; with a language class and
   a code style other than none, its reserved words in bold and its
   comments in italic, in the code font (decision 38) *)
PROCEDURE InlineCode*(VAR f: Fonts; bold: BOOLEAN; attr: A.Attr; text: Rope): L.Doc;
  VAR begin, b, it: ARRAY 10 OF CHAR; lang: PdCode.Language; r: Rope; c, i: BOOLEAN;
BEGIN
  c := f.c; f.c := TRUE; FontString(f, bold, begin);
  IF Sh.CodeStyle(attr, lang) = Sh.CodeNone THEN lang := NIL END;
  IF lang # NIL THEN
    FontString(f, TRUE, b);
    i := f.i; f.i := TRUE; FontString(f, bold, it); f.i := i;
    r := Highlight(text, lang, FALSE, b, it, begin)
  ELSE r := EscapeStr(text)
  END;
  f.c := c;
  RETURN L.Cat3(L.Text(begin), L.Literal(r), FontChange(f, bold))
END InlineCode;

(* The plain text of inlines, for PDF bookmarks: an approximation of
   pandoc's plain writer *)

(* Appends the inlines i to r as Unicode superscripts (sup) or
   subscripts; FALSE if they have characters that have none *)
PROCEDURE Scripts(VAR r: Rope; i: A.Inline; sup: BOOLEAN): BOOLEAN;
  VAR b: Buf; n, k, q: LONGINT; ru, x: Utf8.Rune; out: Rope;
BEGIN
  out := NIL;
  WHILE i # NIL DO
    CASE i.kind OF
      A.Space, A.SoftBreak: out := CatS(out, " ")
    | A.LineBreak: out := CatC(out, 0AX)
    | A.Span: IF ~Scripts(out, i(A.ContInl).content, sup) THEN RETURN FALSE END
    | A.Str:
      b := ToBuf(i(A.StrInl).text); n := Len(i(A.StrInl).text); k := 0;
      WHILE k < n DO
        q := k;
        IF ~Utf8.Decode(b^, q, ru) OR (q <= k) THEN RETURN FALSE END;
        x := -1;
        IF (ru >= ORD("0")) & (ru <= ORD("9")) THEN
          IF ~sup THEN x := 2080H + ru - ORD("0")
          ELSIF ru = ORD("1") THEN x := 0B9H
          ELSIF ru = ORD("2") THEN x := 0B2H
          ELSIF ru = ORD("3") THEN x := 0B3H
          ELSE x := 2070H + ru - ORD("0")
          END
        ELSIF ru = ORD("+") THEN x := 207AH
        ELSIF (ru = ORD("-")) OR (ru = 2212H) THEN x := 207BH
        ELSIF ru = ORD("=") THEN x := 207CH
        ELSIF ru = ORD("(") THEN x := 207DH
        ELSIF ru = ORD(")") THEN x := 207EH
        ELSIF Unicode.IsSpace(ru) THEN x := ru
        END;
        IF x < 0 THEN RETURN FALSE END;
        IF ~sup & (x >= 207AH) & (x <= 207EH) THEN INC(x, 10H) END;
        out := Cat(out, RuneRope(x));
        k := q
      END
    ELSE RETURN FALSE
    END;
    i := i.next
  END;
  r := Cat(r, out);
  RETURN TRUE
END Scripts;

PROCEDURE PlainTo(VAR r, nt: Rope; VAR nn: LONGINT; i: A.Inline);
  VAR c: Rope; t: A.RawInl;
BEGIN
  WHILE i # NIL DO
    CASE i.kind OF
      A.Str: r := Cat(r, i(A.StrInl).text)
    | A.Space, A.SoftBreak: r := CatS(r, " ")
    | A.LineBreak: r := CatC(r, 0AX)
    | A.Code: r := Cat(r, i(A.CodeInl).text)
    | A.Math: r := Cat(r, i(A.MathInl).text)
    | A.RawInline:
      t := i(A.RawInl);
      IF Eq(t.format, "plain") THEN r := Cat(r, t.text) END
    | A.Quoted:
      IF i(A.QuotedInl).quote = A.DoubleQuote THEN
        r := CatS(r, "“"); PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, "”")
      ELSE
        r := CatS(r, "‘"); PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, "’")
      END
    | A.Image:
      r := CatS(r, "["); PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, "]")
    | A.SmallCaps:
      c := NIL; PlainTo(c, nt, nn, i(A.ContInl).content); r := Cat(r, MapCase(c, TRUE))
    | A.Superscript, A.Subscript:
      IF ~Scripts(r, i(A.ContInl).content, i.kind = A.Superscript) THEN
        IF i.kind = A.Superscript THEN r := CatS(r, "^(") ELSE r := CatS(r, "_(") END;
        PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, ")")
      END
    | A.Note:
      INC(nn);
      r := CatS(Cat(CatS(r, "["), Sh.IntRope(nn)), "]");
      nt := CatS(Cat(CatS(CatC(CatC(nt, 0AX), 0AX), "["), Sh.IntRope(nn)), "] ");
      nt := Cat(nt, Sh.StringifyBlocks(i(A.NoteInl).blocks))
    ELSE
      IF i IS A.ContInl THEN PlainTo(r, nt, nn, i(A.ContInl).content) END
    END;
    i := i.next
  END
END PlainTo;

(* Whether ch is a space, a tab, a line feed or a carriage return *)
PROCEDURE IsBlank*(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 9X) OR (ch = 0AX) OR (ch = 0DX)
END IsBlank;

(* inlinesToPlain: the plain text of i, stripped *)
PROCEDURE PlainText*(i: A.Inline): Rope;
  VAR r, nt: Rope; nn, s, e: LONGINT;
BEGIN
  r := NIL; nt := NIL; nn := 0;
  PlainTo(r, nt, nn, i);
  r := Cat(r, nt);
  s := 0; e := Len(r);
  WHILE (s < e) & IsBlank(Ropes.Fetch(r, s)) DO INC(s) END;
  WHILE (e > s) & IsBlank(Ropes.Fetch(r, e - 1)) DO DEC(e) END;
  IF e = s THEN RETURN NIL END;
  RETURN Ropes.Substring(r, s, e - s)
END PlainText;

(* height: the number of lines of d as rendered *)
PROCEDURE Height*(d: L.Doc): LONGINT;
  VAR r: Rope; n, i, len: LONGINT;
BEGIN
  r := L.Render(d, 0); len := Len(r);
  IF len = 0 THEN RETURN 0 END;
  n := 1;
  FOR i := 0 TO len - 2 DO
    IF Ropes.Fetch(r, i) = 0AX THEN INC(n) END
  END;
  RETURN n
END Height;

(* Tables *)

PROCEDURE AddDoc(VAR first, last: Docs; d: L.Doc);
  VAR n: Docs;
BEGIN
  NEW(n); n.d := d; n.next := NIL;
  IF first = NIL THEN first := n ELSE last.next := n END;
  last := n
END AddDoc;

(* makeRow: the cells T{ ... T}, a tab between each two *)
PROCEDURE MakeRow(cols: Docs): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  WHILE cols # NIL DO
    d := L.Above(d, cols.d);
    IF cols.next # NIL THEN d := L.Above(d, L.Text("T}	T{")) END;
    cols := cols.next
  END;
  RETURN L.Above(L.Above(L.Text("T{"), d), L.Text("T}"))
END MakeRow;

(* The parts of the table t for tbl, as pandoc's ms writer makes them
   from toLegacyTable (PdShared.LegacyRows): desc, the columns' format
   line; colheadings, the first row of the head and a rule, or NIL; and
   body, the other rows, their spans cut into empty pieces. The cells
   are written with blocks, the head's first, then the body's, row by
   row. When the columns have relative widths, each body cell starts
   with ".nr LL" for its width, and the result is FALSE (pandoc's
   "simple" table is TRUE). *)
PROCEDURE TableParts*(t: A.TableBlk; blocks: BlocksProc;
  VAR desc, colheadings, body: L.Doc): BOOLEAN;
  VAR simple, allNull: BOOLEAN; d: L.Doc; cs: A.ColSpec; ncols, k: LONGINT; s: Rope;
    cols, lastCol: Docs; widths: POINTER TO ARRAY OF LONGREAL; head, rows: Sh.LegacyRow;
BEGIN
  ncols := 0; cs := t.colSpecs;
  WHILE cs # NIL DO INC(ncols); cs := cs.next END;
  NEW(widths, ncols + 1);
  simple := TRUE; s := NIL; k := 0; cs := t.colSpecs;
  WHILE cs # NIL DO
    widths[k] := 0;
    IF cs.hasWidth & (cs.width > 0) THEN widths[k] := cs.width; simple := FALSE END;
    IF k > 0 THEN s := CatC(s, " ") END;
    CASE cs.align OF
      A.AlignRight: s := CatC(s, "r")
    | A.AlignCenter: s := CatC(s, "c")
    ELSE s := CatC(s, "l")
    END;
    IF widths[k] # 0 THEN s := CatS(Cat(CatS(s, "w("), Sh.Fixed(70 * widths[k], 1)), "n)") END;
    INC(k); cs := cs.next
  END;
  desc := L.Literal(CatC(s, "."));
  Sh.LegacyRows(t, head, rows);
  (* the header *)
  colheadings := NIL;
  IF head # NIL THEN
    cols := NIL; lastCol := NIL; allNull := TRUE;
    FOR k := 0 TO head.n - 1 DO
      IF head.cells[k] # NIL THEN allNull := FALSE END;
      AddDoc(cols, lastCol, blocks(head.cells[k]))
    END;
    IF ~allNull THEN colheadings := L.Above(MakeRow(cols), L.Char("_")) END
  END;
  (* the rows, each zipped with the widths *)
  body := NIL;
  WHILE rows # NIL DO
    cols := NIL; lastCol := NIL; k := 0;
    WHILE (k < rows.n) & (k < ncols) DO
      d := blocks(rows.cells[k]);
      IF ~simple THEN
        d := L.Above(L.Literal(CatS(Cat(R(".nr LL "), Sh.Fixed(widths[k] * 70, 1)), "n")), d)
      END;
      AddDoc(cols, lastCol, d); INC(k)
    END;
    body := L.Above(body, MakeRow(cols));
    rows := rows.next
  END;
  RETURN simple
END TableParts;

END PdRoff.
