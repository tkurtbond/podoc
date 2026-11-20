MODULE PdMdInline;
(* PdMdInline: the markdown reader's inlines (Text.Pandoc.Readers.Markdown,
   inline and the parsers it chooses among).

   Inline parses one inline at PdMdBase.pos and adds it to a list, as
   pandoc's Builder joins inlines: adjacent Strs become one, spaces and
   breaks merge, and so do adjacent emphases of one kind.

   So far: text, spaces, soft and hard line breaks, code spans (with
   attributes, or raw), backslash escapes and character references. The
   other inline syntax (emphasis, links, notes, citations, smart
   punctuation, raw HTML and TeX, math) is read as plain text for now. *)

IMPORT Ropes, Utf8, Unicode, A := PdAst, B := PdMdBase;

TYPE
  (* Whether the inlines stop at p, before the inline there *)
  Stop* = PROCEDURE (p: LONGINT): BOOLEAN;

VAR
  nbsp: ARRAY 3 OF CHAR;  (* U+00A0 in UTF-8 *)

(* Building *)

PROCEDURE IsBreak(k: INTEGER): BOOLEAN;
BEGIN
  RETURN (k = A.Space) OR (k = A.SoftBreak) OR (k = A.LineBreak)
END IsBreak;

PROCEDURE Mergeable(k: INTEGER): BOOLEAN;
BEGIN
  RETURN (k = A.Emph) OR (k = A.Underline) OR (k = A.Strong)
    OR (k = A.Subscript) OR (k = A.Superscript) OR (k = A.Strikeout)
END Mergeable;

(* Appends the list i to l, the last of l and the first of i merged as
   pandoc-types' Inlines monoid merges them. *)
PROCEDURE Add*(VAR l: A.Inlines; i: A.Inline);
  VAR x, rest: A.Inline; c: A.Inlines;
BEGIN
  IF i = NIL THEN RETURN END;
  IF l.last = NIL THEN A.AddInline(l, i); RETURN END;
  x := l.last; rest := i.next;
  IF IsBreak(x.kind) & IsBreak(i.kind) THEN
    IF (x.kind = A.LineBreak) & (i.kind = A.LineBreak) THEN
      A.AddInline(l, i); RETURN
    ELSIF (x.kind = A.LineBreak) OR (i.kind = A.LineBreak) THEN
      x.kind := A.LineBreak
    ELSIF (x.kind = A.SoftBreak) OR (i.kind = A.SoftBreak) THEN
      x.kind := A.SoftBreak
    END
  ELSIF (x.kind = A.Str) & (i.kind = A.Str) THEN
    x(A.StrInl).text := Ropes.Cat(x(A.StrInl).text, i(A.StrInl).text)
  ELSIF (x.kind = i.kind) & Mergeable(x.kind) THEN
    c.first := x(A.ContInl).content; c.last := NIL;
    IF c.first # NIL THEN c.last := A.LastInline(c.first) END;
    Add(c, i(A.ContInl).content);
    x(A.ContInl).content := c.first
  ELSE
    A.AddInline(l, i); RETURN
  END;
  IF rest # NIL THEN A.AddInline(l, rest) END
END Add;

(* trimInlines: l without Space and SoftBreak at its ends *)
PROCEDURE Trim*(VAR l: A.Inlines): A.Inline;
  VAR i, last, end: A.Inline;
BEGIN
  i := l.first;
  WHILE (i # NIL) & ((i.kind = A.Space) OR (i.kind = A.SoftBreak)) DO
    i := i.next
  END;
  IF i = NIL THEN RETURN NIL END;
  last := i; end := i;
  WHILE end # NIL DO
    IF (end.kind # A.Space) & (end.kind # A.SoftBreak) THEN last := end END;
    end := end.next
  END;
  last.next := NIL;
  RETURN i
END Trim;

(* Adds a Str of t[from .. to-1] to l. *)
PROCEDURE AddText(VAR l: A.Inlines; from, to: LONGINT);
BEGIN
  Add(l, A.NewStr(B.Rope(from, to)))
END AddText;

(* Adds a Str of the string s to l. *)
PROCEDURE AddString(VAR l: A.Inlines; s: ARRAY OF CHAR);
BEGIN
  Add(l, A.NewStr(A.S(s)))
END AddString;

(* Line ends *)

(* endline at p, a new line: where the next line's text starts, or -1
   if the new line ends the inlines here; soft is whether it is a
   SoftBreak (FALSE at the end of the text). *)
PROCEDURE Endline*(p: LONGINT; VAR soft: BOOLEAN): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF B.C(p) # 0AX THEN RETURN -1 END;
  q := p + 1;
  IF (B.BlankLine(q) >= 0) OR ~B.allowLineBreaks
      OR (B.context = B.ListItemState) & B.ListStart(q)
      OR (B.C(q) = "`") & B.IsFencedCode(q)
      OR B.HtmlCloser(q) OR B.DivCloser(q) THEN
    RETURN -1
  END;
  IF q >= B.len THEN soft := FALSE; RETURN q END;
  soft := TRUE;
  RETURN B.SkipSpaces(q)
END Endline;

(* The parsers. Each parses at B.pos; if it succeeds it adds what it
   found to l, moves B.pos past it and returns TRUE. *)

(* whitespace *)
PROCEDURE Whitespace(VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT; soft: BOOLEAN;
BEGIN
  p := B.pos;
  IF ~B.IsSpace(B.C(p)) THEN RETURN FALSE END;
  q := B.SkipSpaces(p + 1);
  IF q > p + 1 THEN
    p := Endline(q, soft);
    IF p >= 0 THEN
      Add(l, A.NewSimple(A.LineBreak)); B.pos := p;
      RETURN TRUE
    END
  END;
  Add(l, A.NewSimple(A.Space)); B.pos := q;
  RETURN TRUE
END Whitespace;

(* endline *)
PROCEDURE EndlineInline(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; soft: BOOLEAN;
BEGIN
  p := Endline(B.pos, soft);
  IF p < 0 THEN RETURN FALSE END;
  IF soft THEN Add(l, A.NewSimple(A.SoftBreak)) END;
  B.pos := p;
  RETURN TRUE
END EndlineInline;

(* code: n backticks, the code, n backticks, and attributes *)
PROCEDURE CodeSpan(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, n, k, s, e: LONGINT; b: B.Buf; attr: A.Attr; fmt, text: A.Rope;
BEGIN
  p := B.pos; n := 0;
  WHILE B.C(p) = "`" DO INC(p); INC(n) END;
  p := B.SkipSpaces(p);
  B.InitBuf(b);
  LOOP
    q := B.SkipSpaces(p); k := 0;
    WHILE B.C(q + k) = "`" DO INC(k) END;
    IF k = n THEN p := q + k; EXIT END;
    IF p >= B.len THEN RETURN FALSE END;
    IF B.C(p) = "`" THEN
      WHILE B.C(p) = "`" DO B.PutChar(b, "`"); INC(p) END
    ELSIF B.C(p) = 0AX THEN
      IF (B.context = B.ListItemState) & B.ListStart(p + 1)
          OR (B.BlankLine(p + 1) >= 0) THEN
        RETURN FALSE
      END;
      B.PutChar(b, " "); INC(p)
    ELSE
      q := p;
      WHILE (q < B.len) & (B.C(q) # "`") & (B.C(q) # 0AX) DO INC(q) END;
      B.Put(b, p, q); p := q
    END
  END;
  s := 0; e := b.len;
  WHILE (s < e) & B.IsWhite(b.t[s]) DO INC(s) END;
  WHILE (e > s) & B.IsWhite(b.t[e - 1]) DO DEC(e) END;
  IF e > s THEN text := Ropes.FromSubchars(b.t^, s, e - s) ELSE text := NIL END;
  q := B.RawAttribute(p, fmt);
  IF q >= 0 THEN
    Add(l, A.NewRawInline(fmt, text)); B.pos := q
  ELSE
    q := B.Attributes(p, attr);
    IF q >= 0 THEN p := q ELSE attr := A.NewAttr(NIL) END;
    Add(l, A.NewCode(attr, text)); B.pos := p
  END;
  RETURN TRUE
END CodeSpan;

(* escapedNewline and escapedChar *)
PROCEDURE Escape(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT;
BEGIN
  p := B.pos;
  IF B.C(p) # "\" THEN RETURN FALSE END;
  IF B.C(p + 1) = 0AX THEN
    Add(l, A.NewSimple(A.LineBreak)); B.pos := p + 1;
    RETURN TRUE
  ELSIF B.EscapedChar(p) THEN
    IF B.C(p + 1) = " " THEN AddString(l, nbsp)
    ELSE AddText(l, p + 1, p + 2)
    END;
    B.pos := p + 2;
    RETURN TRUE
  END;
  RETURN FALSE
END Escape;

(* charRef *)
PROCEDURE Entity(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; b: B.Buf;
BEGIN
  B.InitBuf(b);
  p := B.CharRef(B.pos, b);
  IF p < 0 THEN RETURN FALSE END;
  Add(l, A.NewStr(B.BufRope(b))); B.pos := p;
  RETURN TRUE
END Entity;

(* ltSign: a < that does not start a block tag *)
PROCEDURE LtSign(VAR l: A.Inlines): BOOLEAN;
  VAR tag: B.Tag;
BEGIN
  IF B.HtmlCloser(B.pos) OR B.ScanTag(B.pos, tag) & B.IsBlockTag(tag) THEN
    RETURN FALSE
  END;
  AddString(l, "<"); INC(B.pos);
  RETURN TRUE
END LtSign;

(* str and symbol: a run of letters and digits, or one other
   character. Taken in these pieces, a stop test (an ATX heading's
   closing #) falls where pandoc's falls; the Strs are joined. *)
PROCEDURE Text(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; ch: CHAR;
BEGIN
  p := B.pos; ch := B.C(p);
  IF (p >= B.len) OR (ch = "<") OR (ch = 0AX) OR B.IsSpace(ch) THEN
    RETURN FALSE
  END;
  INC(p);
  IF B.IsAlnum(ch) THEN
    WHILE (p < B.len) & B.IsAlnum(B.C(p)) DO INC(p) END
  END;
  AddText(l, B.pos, p); B.pos := p;
  RETURN TRUE
END Text;

(* inline: one inline at B.pos, added to l; FALSE if there is none *)
PROCEDURE Inline*(VAR l: A.Inlines): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  IF B.pos >= B.len THEN RETURN FALSE END;
  ch := B.C(B.pos);
  CASE ch OF
  | " ", 09X: RETURN Whitespace(l)
  | 0AX: RETURN EndlineInline(l)
  | "`": IF CodeSpan(l) THEN RETURN TRUE END
  | "<": RETURN LtSign(l)
  | "\": IF Escape(l) THEN RETURN TRUE END
  | "&": IF Entity(l) THEN RETURN TRUE END
  ELSE
  END;
  RETURN Text(l)
END Inline;

(* inlines: as many inlines as there are at B.pos, up to where stop
   (if it is not NIL) says they stop; added to l. Whether there was
   one. *)
PROCEDURE Inlines*(VAR l: A.Inlines; stop: Stop): BOOLEAN;
  VAR any: BOOLEAN;
BEGIN
  any := FALSE;
  WHILE ((stop = NIL) OR ~stop(B.pos)) & Inline(l) DO any := TRUE END;
  RETURN any
END Inlines;

(* Inlines of the text t[from .. to-1], parsed on their own, trimmed *)
PROCEDURE ParseText*(from, to: LONGINT): A.Inline;
  VAR f: B.Frame; text: B.Text; i: LONGINT; l: A.Inlines;
BEGIN
  text := B.NewText(to - from);
  FOR i := from TO to - 1 DO text[i - from] := B.t[i] END;
  B.Enter(f, text, to - from);
  A.InitInlines(l);
  WHILE Inline(l) DO END;
  B.Leave(f);
  RETURN Trim(l)
END ParseText;

(* Identifiers *)

PROCEDURE^ StringifyTo(i: A.Inline; VAR b: B.Buf);

PROCEDURE PutRope(VAR b: B.Buf; r: A.Rope);
  VAR i, n: LONGINT;
BEGIN
  n := Ropes.Length(r);
  FOR i := 0 TO n - 1 DO B.PutChar(b, Ropes.Fetch(r, i)) END
END PutRope;

PROCEDURE StringifyOne(i: A.Inline; VAR b: B.Buf);
BEGIN
  CASE i.kind OF
  | A.Str: PutRope(b, i(A.StrInl).text)
  | A.Space, A.SoftBreak, A.LineBreak: B.PutChar(b, " ")
  | A.Code: PutRope(b, i(A.CodeInl).text)
  | A.Math: PutRope(b, i(A.MathInl).text)
  | A.RawInline:
      IF Ropes.EqualString(i(A.RawInl).format, "html")
          & (Ropes.Length(i(A.RawInl).text) >= 3)
          & (Ropes.Fetch(i(A.RawInl).text, 0) = "<")
          & (Ropes.Fetch(i(A.RawInl).text, 1) = "b")
          & (Ropes.Fetch(i(A.RawInl).text, 2) = "r") THEN
        B.PutChar(b, " ")
      END
  | A.Note:
  | A.Quoted:
      IF i(A.QuotedInl).quote = A.SingleQuote THEN B.PutUtf8(b, 2018H)
      ELSE B.PutUtf8(b, 201CH)
      END;
      StringifyTo(i(A.ContInl).content, b);
      IF i(A.QuotedInl).quote = A.SingleQuote THEN B.PutUtf8(b, 2019H)
      ELSE B.PutUtf8(b, 201DH)
      END
  ELSE
    IF i IS A.ContInl THEN StringifyTo(i(A.ContInl).content, b) END
  END
END StringifyOne;

PROCEDURE StringifyTo(i: A.Inline; VAR b: B.Buf);
BEGIN
  WHILE i # NIL DO StringifyOne(i, b); i := i.next END
END StringifyTo;

(* stringify: the text of the inlines i, without their formatting *)
PROCEDURE Stringify*(i: A.Inline; VAR b: B.Buf);
BEGIN
  B.InitBuf(b);
  StringifyTo(i, b)
END Stringify;

(* inlineListToIdentifier, with pandoc markdown's extensions: the text
   in lower case, kept only letters, numbers, white space and _ - .;
   its words joined by -; anything before its first letter dropped. *)
PROCEDURE Identifier*(i: A.Inline): A.Rope;
  VAR s, r: B.Buf; p, q: LONGINT; c: Utf8.Rune; space, started: BOOLEAN;
BEGIN
  Stringify(i, s);
  B.InitBuf(r); p := 0; space := FALSE; started := FALSE;
  WHILE p < s.len DO
    q := p;
    IF ~Utf8.Decode(s.t^, q, c) OR (q <= p) THEN c := 0FFFDH; q := p + 1 END;
    p := q;
    c := Unicode.ToLower(c);
    IF Unicode.IsSpace(c) THEN
      space := TRUE
    ELSIF Unicode.IsLetter(c) OR started & (Unicode.IsNumber(c)
        OR (c = ORD("_")) OR (c = ORD("-")) OR (c = ORD("."))) THEN
      IF space & started THEN B.PutChar(r, "-") END;
      space := FALSE; started := TRUE;
      B.PutUtf8(r, c)
    END
  END;
  RETURN B.BufRope(r)
END Identifier;

BEGIN
  nbsp[0] := 0C2X; nbsp[1] := 0A0X; nbsp[2] := 0X
END PdMdInline.
