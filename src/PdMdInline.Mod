MODULE PdMdInline;
(* PdMdInline: the markdown reader's inlines (Text.Pandoc.Readers.Markdown,
   inline and the parsers it chooses among).

   Inline parses one inline at PdMdBase.pos and adds it to a list, as
   pandoc's Builder joins inlines: adjacent Strs become one, spaces and
   breaks merge, and so do adjacent emphases of one kind (PdAst.Append).
   A parser adds to the list only when it has succeeded; when it fails,
   Inline puts the position and the state back as Parsec's try does.

   Reference links and note references cannot be resolved until the
   whole document has been read: they are left in the tree as RefInl
   and NoteRefInl, which PdMarkdown replaces.

   Raw TeX is read in its general form only (RawTeX). Not read yet:
   citations, example references, wikilinks, base64 data URIs. *)

IMPORT Ropes, Utf8, Unicode, A := PdAst, B := PdMdBase, W := PdWords,
  CW := PdWidth, PdEntities, PdAscii;

CONST
  (* the quote context *)
  NoQuote = 0; InSingle = 1; InDouble = 2;

  (* the kinds of the unresolved inlines *)
  RefKind* = 100; NoteRefKind* = 101;

TYPE
  (* Whether the inlines stop at p, before the inline there *)
  Stop* = PROCEDURE (p: LONGINT): BOOLEAN;

  (* A reference link or image, [text][key] or [text]: content is its
     text; key its key; attr the attributes after it; fallback what
     takes its place if the key is not defined. *)
  RefInl* = POINTER TO RefInlDesc;
  RefInlDesc* = RECORD (A.ContInlDesc)
    image*: BOOLEAN;
    key*: A.Rope;
    attr*: A.Attr;
    fallback*: A.Inline
  END;

  (* A note reference, [^ref] *)
  NoteRefInl* = POINTER TO NoteRefInlDesc;
  NoteRefInlDesc* = RECORD (A.InlineDesc)
    ref*: A.Rope
  END;

  (* The parser's state, saved to go back to *)
  Mark = RECORD
    pos, lastStrPos, lastStrText: LONGINT;
    quote: INTEGER;
    allowLinks: BOOLEAN
  END;

VAR
  quote: INTEGER; (* stateQuoteContext *)
  allowLinks: BOOLEAN; (* stateAllowLinks *)
  nbsp: ARRAY 3 OF CHAR; (* U+00A0 in UTF-8 *)

PROCEDURE^ Inline*(VAR l: A.Inlines): BOOLEAN;

(* Readies the inline parser for a new document. *)
PROCEDURE Reset*;
BEGIN
  quote := NoQuote; allowLinks := TRUE
END Reset;

(* State *)

PROCEDURE Save(VAR m: Mark);
BEGIN
  m.pos := B.pos; m.lastStrPos := B.lastStrPos;
  m.lastStrText := B.lastStrText; m.quote := quote;
  m.allowLinks := allowLinks
END Save;

PROCEDURE Restore(VAR m: Mark);
BEGIN
  B.pos := m.pos; B.lastStrPos := m.lastStrPos;
  B.lastStrText := m.lastStrText; quote := m.quote;
  allowLinks := m.allowLinks
END Restore;

(* Restores m; TRUE, to try another parser after a failed one *)
PROCEDURE Again(VAR m: Mark): BOOLEAN;
BEGIN
  Restore(m);
  RETURN TRUE
END Again;

(* notAfterString *)
PROCEDURE NotAfterString*(): BOOLEAN;
BEGIN
  RETURN ~((B.lastStrText = B.textId) & (B.lastStrPos = B.pos))
END NotAfterString;

(* updateLastStrPos *)
PROCEDURE UpdateLastStrPos;
BEGIN
  B.lastStrPos := B.pos; B.lastStrText := B.textId
END UpdateLastStrPos;

(* Characters *)

(* The character at s[p], of the n bytes of s, in r; returns where the
   next starts. A byte that does not start a UTF-8 sequence is
   U+FFFD. *)
PROCEDURE RuneOf*(VAR s: ARRAY OF CHAR; p, n: LONGINT; VAR r: Utf8.Rune): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF p >= n THEN r := 0; RETURN p END;
  IF ORD(s[p]) < 80H THEN r := ORD(s[p]); RETURN p + 1 END;
  q := p;
  IF ~Utf8.Decode(s, q, r) OR (q <= p) OR (q > n) THEN
    r := 0FFFDH; q := p + 1
  END;
  RETURN q
END RuneOf;

(* The character at p of the current text in r; returns where the next
   starts *)
PROCEDURE RuneAt*(p: LONGINT; VAR r: Utf8.Rune): LONGINT;
BEGIN
  RETURN RuneOf(B.t^, p, B.len, r)
END RuneAt;

(* Where the character after the one at p starts *)
PROCEDURE RuneEnd*(p: LONGINT): LONGINT;
  VAR r: Utf8.Rune;
BEGIN
  RETURN RuneAt(p, r)
END RuneEnd;

(* doclayout's charWidth (PdWidth) for the character at p, whose end
   is put in q: 2 for wide characters, 0 for control and combining
   ones, else 1 *)
PROCEDURE CharWidth*(p: LONGINT; VAR q: LONGINT): INTEGER;
  VAR r: Utf8.Rune;
BEGIN
  q := RuneAt(p, r);
  IF q <= p THEN q := p + 1 END;
  RETURN CW.Width(r)
END CharWidth;

(* doclayout's realLength: the width of t[from .. to-1], emoji
   sequences joined (PdWidth.State) *)
PROCEDURE RealLength*(from, to: LONGINT): LONGINT;
  VAR r: Utf8.Rune; st: CW.State;
BEGIN
  CW.Start(st);
  WHILE from < to DO from := RuneAt(from, r); CW.Add(st, r) END;
  RETURN CW.Total(st)
END RealLength;

(* isAlphaNum: whether the character at p is a letter or a number *)
PROCEDURE AlnumAt*(p: LONGINT): BOOLEAN;
  VAR r: Utf8.Rune; q: LONGINT;
BEGIN
  IF p >= B.len THEN RETURN FALSE END;
  q := RuneAt(p, r);
  IF r < 80H THEN RETURN B.IsAlnum(B.t[p]) END;
  RETURN Unicode.IsLetter(r) OR Unicode.IsNumber(r)
END AlnumAt;

(* Unicode's isSpace for the character at p *)
PROCEDURE SpaceAt*(p: LONGINT): BOOLEAN;
  VAR r: Utf8.Rune; q: LONGINT;
BEGIN
  IF p >= B.len THEN RETURN FALSE END;
  q := RuneAt(p, r);
  RETURN Unicode.IsSpace(r)
END SpaceAt;

(* Unicode's isPunctuation for the character at p *)
PROCEDURE PunctAt*(p: LONGINT): BOOLEAN;
  VAR r: Utf8.Rune; q: LONGINT;
BEGIN
  IF p >= B.len THEN RETURN FALSE END;
  q := RuneAt(p, r);
  RETURN Unicode.IsPunct(r)
END PunctAt;

(* isSpaceChar: space, tab, new line, carriage return *)
PROCEDURE IsSpaceChar(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
END IsSpaceChar;

PROCEDURE IsHex*(ch: CHAR): BOOLEAN;
BEGIN
  RETURN B.IsDigit(ch) OR (ch >= "a") & (ch <= "f") OR (ch >= "A") & (ch <= "F")
END IsHex;

(* Buffers *)

PROCEDURE PutBuf*(VAR b: B.Buf; VAR c: B.Buf);
  VAR i: LONGINT;
BEGIN
  FOR i := 0 TO c.len - 1 DO B.PutChar(b, c.t[i]) END
END PutBuf;

PROCEDURE PutRope*(VAR b: B.Buf; r: A.Rope);
  VAR i, n: LONGINT;
BEGIN
  n := Ropes.Length(r);
  FOR i := 0 TO n - 1 DO B.PutChar(b, Ropes.Fetch(r, i)) END
END PutRope;

(* T.unwords . T.words: the words of s[0 .. n-1], split at white space,
   joined by single spaces, appended to out *)
PROCEDURE Words*(VAR s: ARRAY OF CHAR; n: LONGINT; VAR out: B.Buf);
  VAR i, j, k: LONGINT; r: Utf8.Rune; first: BOOLEAN;
BEGIN
  i := 0; first := TRUE;
  LOOP
    LOOP
      IF i >= n THEN EXIT END;
      j := RuneOf(s, i, n, r);
      IF ~Unicode.IsSpace(r) THEN EXIT END;
      i := j
    END;
    IF i >= n THEN EXIT END;
    IF ~first THEN B.PutChar(out, " ") END;
    first := FALSE;
    LOOP
      IF i >= n THEN EXIT END;
      j := RuneOf(s, i, n, r);
      IF Unicode.IsSpace(r) THEN EXIT END;
      FOR k := i TO j - 1 DO B.PutChar(out, s[k]) END;
      i := j
    END
  END
END Words;

(* escapeURI: s[0 .. n-1] with white space and <>|"{}[]^` percent
   encoded, appended to out *)
PROCEDURE EscapeURI*(VAR s: ARRAY OF CHAR; n: LONGINT; VAR out: B.Buf);
  VAR i, j, k: LONGINT; r: Utf8.Rune; ch: CHAR; hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789ABCDEF";
  i := 0;
  WHILE i < n DO
    j := RuneOf(s, i, n, r); ch := s[i];
    IF Unicode.IsSpace(r) OR (ch = "<") OR (ch = ">") OR (ch = "|")
        OR (ch = 22X) OR (ch = "{") OR (ch = "}") OR (ch = "[")
        OR (ch = "]") OR (ch = "^") OR (ch = "`") THEN
      FOR k := i TO j - 1 DO
        B.PutChar(out, "%");
        B.PutChar(out, hex[ORD(s[k]) DIV 16]);
        B.PutChar(out, hex[ORD(s[k]) MOD 16])
      END
    ELSE
      FOR k := i TO j - 1 DO B.PutChar(out, s[k]) END
    END;
    i := j
  END
END EscapeURI;

(* lookupEntity of s[from .. to-1], a name without & and ; *)
PROCEDURE LookupEntity(VAR s: ARRAY OF CHAR; from, to: LONGINT; VAR c1, c2: LONGINT): BOOLEAN;
  VAR name: ARRAY 40 OF CHAR; i: LONGINT; v, d: LONGINT;
BEGIN
  c2 := 0;
  IF (to <= from) OR (to - from >= LEN(name)) THEN RETURN FALSE END;
  IF s[from] = "#" THEN
    i := from + 1; v := 0;
    IF (i < to) & ((s[i] = "x") OR (s[i] = "X")) THEN
      INC(i);
      IF i >= to THEN RETURN FALSE END;
      WHILE i < to DO
        IF ~IsHex(s[i]) THEN RETURN FALSE END;
        IF B.IsDigit(s[i]) THEN d := ORD(s[i]) - ORD("0")
        ELSE d := ORD(B.Lower(s[i])) - ORD("a") + 10
        END;
        IF v < 110000H THEN v := v * 16 + d END;
        INC(i)
      END
    ELSE
      IF i >= to THEN RETURN FALSE END;
      WHILE i < to DO
        IF ~B.IsDigit(s[i]) THEN RETURN FALSE END;
        IF v < 110000H THEN v := v * 10 + ORD(s[i]) - ORD("0") END;
        INC(i)
      END
    END;
    IF (v = 0) OR (v >= 110000H) OR (v >= 0D800H) & (v < 0E000H) THEN
      v := 0FFFDH
    END;
    c1 := v;
    RETURN TRUE
  END;
  FOR i := from TO to - 1 DO name[i - from] := s[i] END;
  name[to - from] := 0X;
  RETURN PdEntities.Lookup(name, c1, c2)
END LookupEntity;

(* fromEntities: s[from .. to-1] with its character references
   replaced, appended to b *)
PROCEDURE FromEntities*(VAR s: ARRAY OF CHAR; from, to: LONGINT; VAR b: B.Buf);
  VAR i, j, k, c1, c2: LONGINT;
BEGIN
  i := from;
  WHILE i < to DO
    IF s[i] # "&" THEN
      B.PutChar(b, s[i]); INC(i)
    ELSE
      j := i + 1;
      WHILE (j < to) & (s[j] # ";") & ~B.IsWhite(s[j]) DO INC(j) END;
      IF LookupEntity(s, i + 1, j, c1, c2) THEN
        B.PutUtf8(b, c1);
        IF c2 # 0 THEN B.PutUtf8(b, c2) END;
        i := j;
        IF (i < to) & (s[i] = ";") THEN INC(i) END
      ELSE
        FOR k := i TO j - 1 DO B.PutChar(b, s[k]) END;
        i := j
      END
    END
  END
END FromEntities;

(* Building *)

(* Adds a Str of t[from .. to-1] to l. *)
PROCEDURE AddText*(VAR l: A.Inlines; from, to: LONGINT);
BEGIN
  A.Append(l, A.NewStr(B.Rope(from, to)))
END AddText;

(* Adds a Str of the string s to l. *)
PROCEDURE AddString*(VAR l: A.Inlines; s: ARRAY OF CHAR);
BEGIN
  A.Append(l, A.NewStr(A.S(s)))
END AddString;

(* Adds a Str of the character c to l. *)
PROCEDURE AddChar*(VAR l: A.Inlines; c: LONGINT);
  VAR b: B.Buf;
BEGIN
  B.InitBuf(b); B.PutUtf8(b, c);
  A.Append(l, A.NewStr(B.BufRope(b)))
END AddChar;

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

(* Parsing a piece of text on its own *)

(* parseFromString inlines: the inlines of s[from .. from+n-1], added
   to out. If fresh (parseFromString'), the last Str's position is
   forgotten while it is parsed. *)
PROCEDURE ParseChars(VAR s: ARRAY OF CHAR; from, n: LONGINT; fresh: BOOLEAN;
    VAR out: A.Inlines);
  VAR f: B.Frame; text: B.Text; i, sp, st: LONGINT;
BEGIN
  IF n < 0 THEN n := 0 END;
  text := B.NewText(n);
  FOR i := 0 TO n - 1 DO text[i] := s[from + i] END;
  sp := B.lastStrPos; st := B.lastStrText;
  IF fresh THEN B.lastStrPos := -1 END;
  B.Enter(f, text, n);
  WHILE Inline(out) DO END;
  B.Leave(f);
  IF fresh THEN B.lastStrPos := sp; B.lastStrText := st END
END ParseChars;

PROCEDURE ParseBuf(VAR b: B.Buf; fresh: BOOLEAN; VAR out: A.Inlines);
BEGIN
  ParseChars(b.t^, 0, b.len, fresh, out)
END ParseBuf;

PROCEDURE ParseRange(from, to: LONGINT; fresh: BOOLEAN; VAR out: A.Inlines);
BEGIN
  ParseChars(B.t^, from, to - from, fresh, out)
END ParseRange;

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
   found to l, moves B.pos past it and returns TRUE. If it fails, the
   caller restores the position and the state. *)

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
      A.Append(l, A.NewSimple(A.LineBreak)); B.pos := p;
      RETURN TRUE
    END
  END;
  A.Append(l, A.NewSimple(A.Space)); B.pos := q;
  RETURN TRUE
END Whitespace;

(* endline *)
PROCEDURE EndlineInline(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; soft: BOOLEAN;
BEGIN
  p := Endline(B.pos, soft);
  IF p < 0 THEN RETURN FALSE END;
  IF soft THEN A.Append(l, A.NewSimple(A.SoftBreak)) END;
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
    A.Append(l, A.NewRawInline(fmt, text)); B.pos := q
  ELSE
    q := B.Attributes(p, attr);
    IF q >= 0 THEN p := q ELSE attr := A.NewAttr(NIL) END;
    A.Append(l, A.NewCode(attr, text)); B.pos := p
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
    A.Append(l, A.NewSimple(A.LineBreak)); B.pos := p + 1;
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

(* Whether the character at p is a letter, as TeX's tokenizer reads
   one: an ASCII or a Unicode letter *)
PROCEDURE TeXLetterAt(p: LONGINT): BOOLEAN;
  VAR r: Utf8.Rune; q: LONGINT;
BEGIN
  IF p >= B.len THEN RETURN FALSE END;
  q := RuneAt(p, r);
  IF r < 80H THEN
    RETURN (CAP(B.t[p]) >= "A") & (CAP(B.t[p]) <= "Z")
  END;
  RETURN Unicode.IsLetter(r)
END TeXLetterAt;

(* The position after the spaces and tabs at p *)
PROCEDURE TeXSpaces(p: LONGINT): LONGINT;
BEGIN
  WHILE (B.C(p) = " ") OR (B.C(p) = 09X) DO INC(p) END;
  RETURN p
END TeXSpaces;

(* sp: the position after the spaces and tabs at p, a new line that
   does not end the paragraph and the spaces and tabs after it *)
PROCEDURE TeXSp(p: LONGINT): LONGINT;
BEGIN
  p := TeXSpaces(p);
  IF (B.C(p) = 0AX) & (p + 1 < B.len) & (B.BlankLine(p + 1) < 0) THEN
    p := TeXSpaces(p + 1)
  END;
  RETURN p
END TeXSp;

(* The position after the group at p, opened by op and closed by cl,
   with braces inside it balanced; -1 if it is not closed *)
PROCEDURE TeXGroup(p: LONGINT; op, cl: CHAR): LONGINT;
  VAR depth: INTEGER; ch: CHAR;
BEGIN
  IF B.C(p) # op THEN RETURN -1 END;
  INC(p); depth := 0;
  LOOP
    IF p >= B.len THEN RETURN -1 END;
    ch := B.C(p);
    IF ch = "\" THEN INC(p)
    ELSIF (ch = cl) & (depth = 0) THEN RETURN p + 1
    ELSIF ch = "{" THEN INC(depth)
    ELSIF (ch = "}") & (depth > 0) THEN DEC(depth)
    ELSIF ch = "}" THEN RETURN -1
    END;
    INC(p)
  END
END TeXGroup;

(* The end of the Word token (a run of letters and numbers) at p; p if
   there is none *)
PROCEDURE TeXWord(p: LONGINT): LONGINT;
BEGIN
  WHILE AlnumAt(p) DO p := RuneEnd(p) END;
  RETURN p
END TeXWord;

(* dimenarg at p: =, -, a Word token starting with a digit, then "."
   and a Word token, each optional; together a number of digits and
   dots and a unit or nothing: the position after it; -1 if there is
   none *)
PROCEDURE TeXDimen(p: LONGINT): LONGINT;
  VAR q, u, e: LONGINT; units: ARRAY 40 OF CHAR; i: INTEGER;
BEGIN
  p := TeXSp(p);
  IF B.C(p) = "=" THEN INC(p) END;
  IF B.C(p) = "-" THEN INC(p) END;
  e := p;
  IF (B.C(e) >= "0") & (B.C(e) <= "9") THEN e := TeXWord(e) END; (* s1 *)
  IF (B.C(e) = ".") & (TeXWord(e + 1) > e + 1) THEN (* s2 *)
    e := TeXWord(e + 1)
  END;
  q := p;
  WHILE (q < e) & (((B.C(q) >= "0") & (B.C(q) <= "9")) OR (B.C(q) = ".")) DO
    INC(q)
  END;
  IF q = p THEN RETURN -1 END;
  u := e;
  IF u = q THEN RETURN q END;
  IF u - q # 2 THEN RETURN -1 END;
  units := "ptpcinbpcmmmddccspexemmupx";
  i := 0;
  WHILE (i < 26) & ((units[i] # B.C(q)) OR (units[i + 1] # B.C(q + 1))) DO
    INC(i, 2)
  END;
  IF i < 26 THEN RETURN u END;
  RETURN -1
END TeXDimen;

(* rawLaTeXInline': a TeX command at p, \name, with the spaces after
   it, a star, its options [...], a dimension and its arguments {...}:
   the position after it, or -1. Only the general form of pandoc's
   LaTeX reader: commands it reads specially, macros and environments
   are not recognised. *)
PROCEDURE RawTeXEnd*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF (B.C(p) # "\") OR ~TeXLetterAt(p + 1) THEN RETURN -1 END;
  INC(p);
  WHILE TeXLetterAt(p) DO p := RuneEnd(p) END;
  p := TeXSpaces(p);
  IF B.C(p) = "*" THEN p := TeXSp(p + 1) END;
  LOOP (* rawopt *)
    q := TeXGroup(TeXSp(p), "[", "]");
    IF q < 0 THEN EXIT END;
    p := TeXSp(q)
  END;
  q := TeXDimen(p);
  IF q >= 0 THEN p := q END;
  WHILE B.C(p) = "{" DO
    p := TeXGroup(p, "{", "}");
    IF p < 0 THEN RETURN -1 END
  END;
  RETURN p
END RawTeXEnd;

(* The command RawTeXEnd finds, as a raw inline, without a final new
   line *)
PROCEDURE RawTeX(VAR l: A.Inlines): BOOLEAN;
  VAR p, e: LONGINT;
BEGIN
  p := RawTeXEnd(B.pos);
  IF p < 0 THEN RETURN FALSE END;
  e := p;
  IF B.C(e - 1) = 0AX THEN DEC(e) END;
  A.Append(l, A.NewRawInline(A.S("tex"), B.Rope(B.pos, e)));
  B.pos := p;
  RETURN TRUE
END RawTeX;

(* charRef *)
PROCEDURE Entity(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; b: B.Buf;
BEGIN
  B.InitBuf(b);
  p := B.CharRef(B.pos, b);
  IF p < 0 THEN RETURN FALSE END;
  A.Append(l, A.NewStr(B.BufRope(b))); B.pos := p;
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

(* Notes *)

(* noteMarker: [^ref] at p; the position after it, or -1 *)
PROCEDURE NoteMarker*(p: LONGINT): LONGINT;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  IF ~B.Looking(p, "[^") THEN RETURN -1 END;
  q := p + 2;
  LOOP
    IF q >= B.len THEN RETURN -1 END;
    ch := B.C(q);
    IF (ch = 0DX) OR (ch = 0AX) OR (ch = 09X) OR (ch = " ") OR (ch = "^")
        OR (ch = "[") OR (ch = "]") THEN
      EXIT
    END;
    INC(q)
  END;
  IF (q = p + 2) OR (B.C(q) # "]") THEN RETURN -1 END;
  RETURN q + 1
END NoteMarker;

(* note: a reference to a note, [^ref] *)
PROCEDURE NoteRef(VAR l: A.Inlines): BOOLEAN;
  VAR q: LONGINT; n: NoteRefInl;
BEGIN
  q := NoteMarker(B.pos);
  IF q < 0 THEN RETURN FALSE END;
  NEW(n); n.kind := NoteRefKind; n.next := NIL;
  n.ref := B.Rope(B.pos + 2, q - 1);
  A.Append(l, n); B.pos := q;
  RETURN TRUE
END NoteRef;

(* Text *)

(* str: letters, numbers and single dots; after an abbreviation, a
   space becomes a non-breaking one *)
PROCEDURE Str(VAR l: A.Inlines): BOOLEAN;
  VAR s, p: LONGINT; m: Mark; ws: A.Inlines; text: A.Rope;
BEGIN
  s := B.pos; p := s;
  LOOP
    IF AlnumAt(p) THEN p := RuneEnd(p)
    ELSIF (B.C(p) = ".") & (B.C(p + 1) # ".") THEN INC(p)
    ELSE EXIT
    END
  END;
  IF p = s THEN RETURN FALSE END;
  B.pos := p; UpdateLastStrPos;
  text := B.Rope(s, p);
  IF W.IsAbbreviation(B.t, s, p) THEN
    Save(m); A.InitInlines(ws);
    IF Whitespace(ws) & (NoteMarker(B.pos) < 0) THEN
      IF ws.first.kind = A.Space THEN
        A.Append(l, A.NewStr(Ropes.Cat(text, A.S(nbsp))))
      ELSE
        A.Append(l, A.NewStr(text)); A.Append(l, ws.first)
      END;
      RETURN TRUE
    END;
    Restore(m)
  END;
  A.Append(l, A.NewStr(text));
  RETURN TRUE
END Str;

(* symbol: any other character *)
PROCEDURE Symbol(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; ch: CHAR;
BEGIN
  p := B.pos; ch := B.C(p);
  IF (p >= B.len) OR (ch = "<") OR (ch = 0AX) OR (ch = 09X) OR (ch = " ") THEN
    RETURN FALSE
  END;
  p := RuneEnd(p);
  AddText(l, B.pos, p); B.pos := p;
  RETURN TRUE
END Symbol;

(* Emphasis *)

(* ender: n c's at p, not followed by a letter or a number if c is _;
   the position after them, or -1 *)
PROCEDURE EnderAt(p: LONGINT; c: CHAR; n: INTEGER): LONGINT;
  VAR i: INTEGER;
BEGIN
  FOR i := 1 TO n DO
    IF B.C(p) # c THEN RETURN -1 END;
    INC(p)
  END;
  IF (c = "_") & AlnumAt(p) THEN RETURN -1 END;
  RETURN p
END EnderAt;

PROCEDURE^ Two(c: CHAR; prefix: A.Inline; VAR l: A.Inlines);

(* one: emphasis, after the opening c *)
PROCEDURE One(c: CHAR; prefix: A.Inline; VAR l: A.Inlines);
  VAR cont: A.Inlines; e: LONGINT; s: ARRAY 2 OF CHAR;
BEGIN
  A.InitInlines(cont); A.Append(cont, prefix);
  LOOP
    IF (EnderAt(B.pos, c, 1) < 0) & Inline(cont) THEN
    ELSIF (B.C(B.pos) = c) & (B.C(B.pos + 1) = c)
        & (EnderAt(B.pos + 2, c, 1) < 0) THEN
      B.pos := B.pos + 2; Two(c, NIL, cont)
    ELSE
      EXIT
    END
  END;
  e := EnderAt(B.pos, c, 1);
  IF e >= 0 THEN
    B.pos := e; UpdateLastStrPos;
    A.Append(l, A.NewCont(A.Emph, cont.first))
  ELSE
    s[0] := c; s[1] := 0X;
    AddString(l, s); A.Append(l, cont.first)
  END
END One;

(* two: strong emphasis, after the opening cc *)
PROCEDURE Two(c: CHAR; prefix: A.Inline; VAR l: A.Inlines);
  VAR cont: A.Inlines; e: LONGINT; s: ARRAY 3 OF CHAR;
BEGIN
  A.InitInlines(cont); A.Append(cont, prefix);
  WHILE (EnderAt(B.pos, c, 2) < 0) & Inline(cont) DO END;
  e := EnderAt(B.pos, c, 2);
  IF e >= 0 THEN
    B.pos := e; UpdateLastStrPos;
    A.Append(l, A.NewCont(A.Strong, cont.first))
  ELSE
    s[0] := c; s[1] := c; s[2] := 0X;
    AddString(l, s); A.Append(l, cont.first)
  END
END Two;

(* three: after the opening ccc *)
PROCEDURE Three(c: CHAR; VAR l: A.Inlines);
  VAR cont: A.Inlines; e: LONGINT; s: ARRAY 4 OF CHAR;
BEGIN
  A.InitInlines(cont);
  WHILE (EnderAt(B.pos, c, 1) < 0) & Inline(cont) DO END;
  e := EnderAt(B.pos, c, 3);
  IF e >= 0 THEN
    B.pos := e; UpdateLastStrPos;
    A.Append(l, A.NewCont(A.Strong, A.NewCont(A.Emph, cont.first)));
    RETURN
  END;
  e := EnderAt(B.pos, c, 2);
  IF e >= 0 THEN
    B.pos := e; UpdateLastStrPos;
    One(c, A.NewCont(A.Strong, cont.first), l);
    RETURN
  END;
  e := EnderAt(B.pos, c, 1);
  IF e >= 0 THEN
    B.pos := e; UpdateLastStrPos;
    Two(c, A.NewCont(A.Emph, cont.first), l);
    RETURN
  END;
  s[0] := c; s[1] := c; s[2] := c; s[3] := 0X;
  AddString(l, s); A.Append(l, cont.first)
END Three;

(* strongOrEmph: enclosure c *)
PROCEDURE Enclosure(c: CHAR; VAR l: A.Inlines): BOOLEAN;
  VAR s, n: LONGINT; ws: A.Inlines;
BEGIN
  IF (c = "_") & ~NotAfterString() THEN RETURN FALSE END;
  s := B.pos;
  WHILE B.C(B.pos) = c DO INC(B.pos) END;
  n := B.pos - s;
  A.InitInlines(ws);
  IF Whitespace(ws) THEN
    AddText(l, s, s + n); A.Append(l, ws.first)
  ELSIF n = 3 THEN Three(c, l)
  ELSIF n = 2 THEN Two(c, NIL, l)
  ELSIF n = 1 THEN One(c, NIL, l)
  ELSE AddText(l, s, s + n)
  END;
  RETURN TRUE
END Enclosure;

(* strikeout: ~~text~~ *)
PROCEDURE Strikeout(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; ch: CHAR; cont: A.Inlines;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "~~") THEN RETURN FALSE END;
  ch := B.C(p + 2);
  IF (p + 2 >= B.len) OR IsSpaceChar(ch) OR (ch = "~") THEN RETURN FALSE END;
  B.pos := p + 2; A.InitInlines(cont);
  LOOP
    IF B.Looking(B.pos, "~~") THEN B.pos := B.pos + 2; EXIT END;
    IF B.IsSpace(B.C(B.pos)) THEN
      IF ~Whitespace(cont) OR B.Looking(B.pos, "~~") THEN RETURN FALSE END
    ELSIF ~Inline(cont) THEN
      RETURN FALSE
    END
  END;
  A.Append(l, A.NewCont(A.Strikeout, Trim(cont)));
  RETURN TRUE
END Strikeout;

(* litBetweenNoSpace op cl: the text between op and cl, with escapes
   and character references read, in b; the position after cl, or -1 *)
PROCEDURE LitBetweenNoSpace(op, cl: CHAR; VAR b: B.Buf): LONGINT;
  VAR p, q: LONGINT; ch: CHAR; attr: A.Attr;
BEGIN
  p := B.pos;
  IF B.C(p) # op THEN RETURN -1 END;
  INC(p);
  LOOP
    IF p >= B.len THEN RETURN -1 END;
    ch := B.C(p);
    IF ch = cl THEN RETURN p + 1 END;
    IF B.EscapedChar(p) THEN
      IF B.C(p + 1) = " " THEN B.PutString(b, nbsp)
      ELSE B.PutChar(b, B.C(p + 1))
      END;
      p := p + 2
    ELSE
      q := B.CharRef(p, b);
      IF q >= 0 THEN
        p := q
      ELSE
        q := B.Attributes(p, attr);
        IF q >= 0 THEN
          B.Put(b, p, q); p := q
        ELSIF (ch # 0AX) & (ch # " ") & (ch # 0DX) & (ch # 09X) THEN
          B.PutChar(b, ch); INC(p)
        ELSE
          RETURN -1
        END
      END
    END
  END
END LitBetweenNoSpace;

(* superscript and subscript: ^text^ and ~text~ *)
PROCEDURE Script(c: CHAR; kind: INTEGER; VAR l: A.Inlines): BOOLEAN;
  VAR b: B.Buf; e: LONGINT; cont: A.Inlines;
BEGIN
  B.InitBuf(b);
  e := LitBetweenNoSpace(c, c, b);
  IF e < 0 THEN RETURN FALSE END;
  B.pos := e;
  A.InitInlines(cont);
  ParseBuf(b, FALSE, cont);
  A.Append(l, A.NewCont(kind, cont.first));
  RETURN TRUE
END Script;

(* Math *)

PROCEDURE^ Math(VAR l: A.Inlines): BOOLEAN;
PROCEDURE^ RawHtmlInline(VAR l: A.Inlines): BOOLEAN;

(* Brackets *)

(* inBalancedBrackets inlines: the inlines between [ and the matching
   ], added to out *)
PROCEDURE InBalancedBrackets(VAR out: A.Inlines): BOOLEAN;
  VAR start, depth: LONGINT; ch: CHAR; m: Mark; ok: BOOLEAN; junk: A.Inlines;
BEGIN
  IF B.C(B.pos) # "[" THEN RETURN FALSE END;
  INC(B.pos); start := B.pos; depth := 1;
  LOOP
    IF B.pos >= B.len THEN RETURN FALSE END;
    ch := B.C(B.pos); Save(m); ok := FALSE; A.InitInlines(junk);
    CASE ch OF
    | "\": IF B.EscapedChar(B.pos) THEN B.pos := B.pos + 2; ok := TRUE END
    | "`": ok := CodeSpan(junk)
    | "$": ok := Math(junk)
    | 0AX: ok := EndlineInline(junk)
    | "<": ok := RawHtmlInline(junk)
    ELSE
    END;
    IF ~ok THEN
      Restore(m);
      IF ch = "]" THEN
        INC(B.pos); DEC(depth);
        IF depth = 0 THEN EXIT END
      ELSIF ch = "[" THEN
        INC(B.pos); INC(depth)
      ELSIF ch # 0AX THEN
        INC(B.pos)
      ELSE
        RETURN FALSE
      END
    END
  END;
  ParseRange(start, B.pos - 1, FALSE, out);
  RETURN TRUE
END InBalancedBrackets;

(* reference: a link's text in brackets, trimmed, in lab; rs and re
   are where its raw text, the brackets included, starts and ends *)
PROCEDURE Reference(VAR lab: A.Inline; VAR rs, re: LONGINT): BOOLEAN;
  VAR c: A.Inlines;
BEGIN
  IF NoteMarker(B.pos) >= 0 THEN RETURN FALSE END;
  rs := B.pos; A.InitInlines(c);
  IF ~InBalancedBrackets(c) THEN RETURN FALSE END;
  re := B.pos; lab := Trim(c);
  RETURN TRUE
END Reference;

(* toKey of s[from .. to-1]: without its brackets if unbracket and it
   has them, its words joined by single spaces, in lower case *)
PROCEDURE Key*(VAR s: ARRAY OF CHAR; from, to: LONGINT; unbracket: BOOLEAN): A.Rope;
  VAR w, k: B.Buf; i, j: LONGINT; r: Utf8.Rune;
BEGIN
  IF unbracket & (to - from >= 2) & (s[from] = "[") & (s[to - 1] = "]") THEN
    INC(from); DEC(to)
  END;
  B.InitBuf(w);
  IF to > from THEN
    B.InitBuf(k);
    FOR i := from TO to - 1 DO B.PutChar(k, s[i]) END;
    Words(k.t^, k.len, w)
  END;
  B.InitBuf(k); i := 0;
  WHILE i < w.len DO
    j := RuneOf(w.t^, i, w.len, r);
    IF r = 0FFFDH THEN
      WHILE i < j DO B.PutChar(k, w.t[i]); INC(i) END
    ELSE
      B.PutUtf8(k, Unicode.ToLower(r)); i := j
    END
  END;
  RETURN B.BufRope(k)
END Key;

(* Links *)

(* charsInBalanced '(' ')' litChar, after the (: the characters up to
   the matching ), appended to b; the position after the ), or -1 *)
PROCEDURE Balanced(p: LONGINT; VAR b: B.Buf): LONGINT;
  VAR ch: CHAR;
BEGIN
  LOOP
    ch := B.C(p);
    IF ch = ")" THEN RETURN p + 1
    ELSIF ch = "(" THEN
      B.PutChar(b, "(");
      p := Balanced(p + 1, b);
      IF p < 0 THEN RETURN -1 END;
      B.PutChar(b, ")")
    ELSE
      p := B.LitChar(p, b);
      IF p < 0 THEN RETURN -1 END
    END
  END
END Balanced;

(* quotedTitle c at p: the title, its words joined by single spaces,
   appended to b; the position after it, or -1 *)
PROCEDURE QuotedTitle(p: LONGINT; c: CHAR; VAR b: B.Buf): LONGINT;
  VAR raw, n: B.Buf; q: LONGINT; ch: CHAR;
BEGIN
  IF B.C(p) # c THEN RETURN -1 END;
  INC(p);
  IF B.IsWhite(B.C(p)) THEN RETURN -1 END;
  B.InitBuf(raw);
  LOOP
    ch := B.C(p);
    IF (ch = c) & ~AlnumAt(p + 1) THEN INC(p); EXIT END;
    IF ch = c THEN
      B.InitBuf(n);
      q := QuotedTitle(p, c, n);
      IF q >= 0 THEN
        B.PutChar(raw, c); PutBuf(raw, n); B.PutChar(raw, c); p := q
      ELSE
        B.PutChar(raw, c); INC(p)
      END
    ELSIF (p < B.len) & (ch # "\") & (ch # 0AX) & (ch # "&") THEN
      q := p;
      WHILE (q < B.len) & (B.C(q) # "\") & (B.C(q) # 0AX) & (B.C(q) # "&")
          & (B.C(q) # c) DO
        INC(q)
      END;
      B.Put(raw, p, q); p := q
    ELSE
      p := B.LitChar(p, raw);
      IF p < 0 THEN RETURN -1 END
    END
  END;
  Words(raw.t^, raw.len, b);
  RETURN p
END QuotedTitle;

(* linkTitle: a title in " or ' *)
PROCEDURE LinkTitle(p: LONGINT; VAR b: B.Buf): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := QuotedTitle(p, 22X, b);
  IF q < 0 THEN q := QuotedTitle(p, 27X, b) END;
  RETURN q
END LinkTitle;

(* linkTitle': spaces, at most one new line, and a title *)
PROCEDURE TitleAfter(p: LONGINT; VAR b: B.Buf): LONGINT;
BEGIN
  p := B.Spnl(p);
  IF p < 0 THEN RETURN -1 END;
  RETURN LinkTitle(p, b)
END TitleAfter;

(* source: (url "title"); the position after it, or -1 *)
PROCEDURE Source(VAR src, title: A.Rope): LONGINT;
  VAR p, q: LONGINT; ch: CHAR; b, u, t, n: B.Buf; done: BOOLEAN;
BEGIN
  p := B.pos;
  IF B.C(p) # "(" THEN RETURN -1 END;
  p := B.SkipSpaces(p + 1);
  B.InitBuf(u); done := FALSE;
  IF B.C(p) = "<" THEN
    q := p + 1;
    WHILE (q >= 0) & (B.C(q) # ">") DO q := B.LitChar(q, u) END;
    IF q >= 0 THEN
      p := q + 1; done := TRUE;
      WHILE (u.len > 0) & B.IsWhite(u.t[u.len - 1]) DO DEC(u.len) END
    ELSE
      B.InitBuf(u)
    END
  END;
  IF ~done THEN
    B.InitBuf(b);
    LOOP
      IF p >= B.len THEN EXIT END;
      ch := B.C(p); q := -1;
      IF ch = "(" THEN
        B.InitBuf(n);
        q := Balanced(p + 1, n);
        IF q >= 0 THEN B.PutChar(b, "("); PutBuf(b, n); B.PutChar(b, ")") END
      END;
      IF q >= 0 THEN
        p := q
      ELSIF (ch # 0AX) & (ch # 0DX) & (ch # " ") & (ch # ")") THEN
        p := B.LitChar(p, b);
        IF p < 0 THEN RETURN -1 END
      ELSIF (ch = 0AX) OR (ch = 0DX) THEN
        B.InitBuf(n);
        IF TitleAfter(p, n) >= 0 THEN EXIT END;
        q := B.LitChar(p, b);
        IF q < 0 THEN EXIT END;
        p := q
      ELSIF ch = " " THEN
        q := B.SkipSpaces(p);
        ch := B.C(q);
        IF (ch = 22X) OR (ch = 27X) OR (ch = ")") THEN EXIT END;
        B.Put(b, p, q); p := q
      ELSE
        EXIT
      END
    END;
    Words(b.t^, b.len, u)
  END;
  B.InitBuf(t);
  q := TitleAfter(p, t);
  IF q >= 0 THEN p := q ELSE B.InitBuf(t) END;
  p := B.SkipSpaces(p);
  IF B.C(p) # ")" THEN RETURN -1 END;
  B.InitBuf(b);
  EscapeURI(u.t^, u.len, b);
  src := B.BufRope(b); title := B.BufRope(t);
  RETURN p + 1
END Source;

(* regLink: the source and attributes of a link or image whose text
   is lab *)
PROCEDURE RegLink(kind: INTEGER; lab: A.Inline; VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT; src, title: A.Rope; attr: A.Attr;
BEGIN
  p := Source(src, title);
  IF p < 0 THEN RETURN FALSE END;
  q := B.Attributes(p, attr);
  IF q >= 0 THEN p := q ELSE attr := A.NewAttr(NIL) END;
  B.pos := p;
  A.Append(l, A.NewLink(kind, attr, lab, src, title));
  RETURN TRUE
END RegLink;

(* referenceLink: [text][key], [text][] or [text], with the text lab,
   whose raw text is t[rs .. re-1]; never fails *)
PROCEDURE ReferenceLink(lab: A.Inline; rs, re: LONGINT; image: BOOLEAN;
    VAR l: A.Inlines);
  VAR sp, labIsRef: BOOLEAN; m: Mark; lab2: A.Inline; rs2, re2, q: LONGINT;
    attr: A.Attr; pr, fb, f: A.Inlines; r: RefInl;
BEGIN
  sp := B.C(B.pos) = " ";
  Save(m);
  IF ~Reference(lab2, rs2, re2) THEN Restore(m); rs2 := -1; re2 := -1 END;
  q := B.Attributes(B.pos, attr);
  IF q >= 0 THEN B.pos := q ELSE attr := A.NewAttr(NIL) END;
  labIsRef := (rs2 < 0) OR (re2 - rs2 = 2);
  NEW(r); r.kind := RefKind; r.next := NIL;
  r.content := lab; r.image := image; r.attr := attr;
  IF labIsRef THEN r.key := Key(B.t^, rs, re, TRUE)
  ELSE r.key := Key(B.t^, rs2, re2, TRUE)
  END;
  A.InitInlines(pr);
  IF rs2 >= 0 THEN ParseRange(rs2, re2, TRUE, pr) END;
  A.InitInlines(fb);
  IF image THEN ParseRange(rs, re, TRUE, fb)
  ELSE ParseRange(rs + 1, re - 1, TRUE, fb)
  END;
  A.InitInlines(f);
  IF image THEN
    AddString(f, "!"); A.Append(f, fb.first)
  ELSE
    AddString(f, "["); A.Append(f, fb.first); AddString(f, "]")
  END;
  IF sp THEN A.Append(f, A.NewSimple(A.Space)) END;
  A.Append(f, pr.first);
  r.fallback := f.first;
  A.Append(l, r)
END ReferenceLink;

(* link *)
PROCEDURE Link(VAR l: A.Inlines): BOOLEAN;
  VAR m0, m1: Mark; lab: A.Inline; rs, re, p: LONGINT;
BEGIN
  IF ~allowLinks THEN RETURN FALSE END;
  Save(m0); allowLinks := FALSE;
  IF ~Reference(lab, rs, re) THEN RETURN FALSE END;
  p := B.pos; Restore(m0); B.pos := p; allowLinks := TRUE;
  Save(m1);
  IF RegLink(A.Link, lab, l) THEN RETURN TRUE END;
  Restore(m1);
  ReferenceLink(lab, rs, re, FALSE, l);
  RETURN TRUE
END Link;

(* image *)
PROCEDURE Image(VAR l: A.Inlines): BOOLEAN;
  VAR m: Mark; lab: A.Inline; rs, re: LONGINT;
BEGIN
  IF B.C(B.pos) # "!" THEN RETURN FALSE END;
  INC(B.pos);
  IF ~Reference(lab, rs, re) THEN RETURN FALSE END;
  Save(m);
  IF RegLink(A.Image, lab, l) THEN RETURN TRUE END;
  Restore(m);
  ReferenceLink(lab, rs, re, TRUE, l);
  RETURN TRUE
END Image;

(* referenceTitle at p: a title in quotes or parentheses, after spaces
   and at most one new line, in b; the position after it, or -1 *)
PROCEDURE ReferenceTitle(p: LONGINT; VAR b: B.Buf): LONGINT;
  VAR q: LONGINT;
BEGIN
  p := B.Spnl(p);
  IF p < 0 THEN RETURN -1 END;
  q := LinkTitle(p, b);
  IF (q < 0) & (B.C(p) = "(") THEN q := Balanced(p + 1, b) END;
  RETURN q
END ReferenceTitle;

(* Whether a reference, [text], is at p *)
PROCEDURE ReferenceAt(p: LONGINT): BOOLEAN;
  VAR m: Mark; lab: A.Inline; rs, re: LONGINT; ok: BOOLEAN;
BEGIN
  Save(m); B.pos := p;
  ok := Reference(lab, rs, re);
  Restore(m);
  RETURN ok
END ReferenceAt;

(* referenceKey: a link reference definition, [key]: url "title"
   {attributes}, at B.pos. If there is one, its key, target and
   attributes, and B.pos after it and the blank lines after it. *)
PROCEDURE ReferenceKey*(VAR key, url, title: A.Rope; VAR attr: A.Attr): BOOLEAN;
  VAR m: Mark; p, q, r, n: LONGINT; lab: A.Inline; rs, re: LONGINT;
    u, w, t, b: B.Buf; done: BOOLEAN; a: A.Attr;
BEGIN
  Save(m);
  p := B.NonindentSpaces(B.pos, n);
  IF p < 0 THEN RETURN FALSE END;
  B.pos := p;
  IF ~Reference(lab, rs, re) OR (B.C(B.pos) # ":") THEN
    Restore(m); RETURN FALSE
  END;
  p := B.SkipSpaces(B.pos + 1);
  IF B.C(p) = 0AX THEN p := B.SkipSpaces(p + 1) END;
  IF B.C(p) = "[" THEN Restore(m); RETURN FALSE END;
  B.InitBuf(u); done := FALSE;
  IF B.C(p) = "<" THEN
    q := p + 1;
    WHILE (q >= 0) & (B.C(q) # ">") DO q := B.LitChar(q, u) END;
    IF q >= 0 THEN p := q + 1; done := TRUE ELSE B.InitBuf(u) END
  END;
  IF ~done THEN
    LOOP
      q := p;
      WHILE B.IsSpace(B.C(q)) DO INC(q) END;
      B.InitBuf(t);
      IF (ReferenceTitle(q, t) >= 0) OR (B.Attributes(q, a) >= 0)
          OR ReferenceAt(q) THEN
        EXIT
      END;
      B.InitBuf(w); r := q;
      WHILE (r < B.len) & ~SpaceAt(r) & ~B.IsWhite(B.C(r)) & (r >= 0) DO
        r := B.LitChar(r, w)
      END;
      IF (r < 0) OR (w.len = 0) THEN EXIT END;
      IF u.len > 0 THEN B.PutChar(u, " ") END;
      PutBuf(u, w); p := r
    END
  END;
  WHILE (u.len > 0) & B.IsWhite(u.t[u.len - 1]) DO DEC(u.len) END;
  B.InitBuf(t);
  q := ReferenceTitle(p, t);
  IF q >= 0 THEN p := q ELSE B.InitBuf(t) END;
  q := B.Spnl(p);
  IF q >= 0 THEN q := B.Attributes(q, attr) END;
  IF q >= 0 THEN p := q ELSE attr := A.NewAttr(NIL) END;
  p := B.BlankLines(p);
  IF p < 0 THEN Restore(m); RETURN FALSE END;
  B.pos := p;
  key := Key(B.t^, rs, re, TRUE);
  B.InitBuf(b); EscapeURI(u.t^, u.len, b);
  url := B.BufRope(b); title := B.BufRope(t);
  RETURN TRUE
END ReferenceKey;

(* Spans *)

(* isSmallCapsFontVariant *)
PROCEDURE IsSmallCaps(r: A.Rope): BOOLEAN;
  VAR b: B.Buf; i, n: LONGINT; ch: CHAR; want: ARRAY 24 OF CHAR;
BEGIN
  want := "font-variant:small-caps";
  B.InitBuf(b); n := Ropes.Length(r);
  FOR i := 0 TO n - 1 DO
    ch := Ropes.Fetch(r, i);
    IF (ch # " ") & (ch # 09X) & (ch # ";") THEN B.PutChar(b, B.Lower(ch)) END
  END;
  IF b.len # 23 THEN RETURN FALSE END;
  FOR i := 0 TO 22 DO
    IF b.t[i] # want[i] THEN RETURN FALSE END
  END;
  RETURN TRUE
END IsSmallCaps;

(* wrapSpan attr content: smallcaps, ul and underline as constructors;
   a Span if anything else is left *)
PROCEDURE WrapSpan(attr: A.Attr; content: A.Inline): A.Inline;
  CONST Max = 32;
  VAR kinds: ARRAY Max OF INTEGER; n, i: INTEGER; styleSC, found: BOOLEAN;
    style: A.Rope; na: A.Attr; c: A.StrList; kv: A.KeyVal; x: A.Inline;
BEGIN
  style := A.GetKeyVal(attr, "style", found);
  styleSC := found & IsSmallCaps(style);
  na := A.NewAttr(attr.id); n := 0;
  c := attr.classes;
  WHILE c # NIL DO
    IF Ropes.EqualString(c.s, "smallcaps") & (n < Max) THEN
      kinds[n] := A.SmallCaps; INC(n)
    ELSIF (Ropes.EqualString(c.s, "ul") OR Ropes.EqualString(c.s, "underline"))
        & (n < Max) THEN
      kinds[n] := A.Underline; INC(n)
    ELSE
      A.AddClass(na, c.s)
    END;
    c := c.next
  END;
  IF styleSC & (n < Max) THEN kinds[n] := A.SmallCaps; INC(n) END;
  kv := attr.attrs;
  WHILE kv # NIL DO
    IF ~styleSC OR ~Ropes.EqualString(kv.key, "style") THEN
      A.AddKeyVal(na, kv.key, kv.value)
    END;
    kv := kv.next
  END;
  x := content;
  FOR i := n - 1 TO 0 BY -1 DO x := A.NewCont(kinds[i], x) END;
  IF ~A.IsEmptyAttr(na) THEN
    x := A.NewSpan(na, x)
  ELSIF n = 0 THEN
    x := A.NewSpan(A.NewAttr(NIL), x)
  END;
  RETURN x
END WrapSpan;

(* bracketedSpan: [text]{attributes} *)
PROCEDURE BracketedSpan(VAR l: A.Inlines): BOOLEAN;
  VAR lab: A.Inline; rs, re, q: LONGINT; attr: A.Attr;
BEGIN
  IF ~Reference(lab, rs, re) THEN RETURN FALSE END;
  q := B.Attributes(B.pos, attr);
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  A.Append(l, WrapSpan(attr, lab));
  RETURN TRUE
END BracketedSpan;

(* spanHtml: <span ...>text</span> *)
PROCEDURE SpanHtml(VAR l: A.Inlines): BOOLEAN;
  VAR tag, close: B.Tag; c: A.Inlines; attr: A.Attr;
BEGIN
  IF ~B.ScanTag(B.pos, tag) OR (tag.kind # B.TagOpen) OR (tag.name # "span") THEN
    RETURN FALSE
  END;
  attr := B.HtmlTagAttr(tag);
  B.pos := tag.end; A.InitInlines(c);
  LOOP
    IF B.ScanTag(B.pos, close) & (close.kind = B.TagClose)
        & (close.name = "span") THEN
      B.pos := close.end; EXIT
    END;
    IF ~Inline(c) THEN RETURN FALSE END
  END;
  A.Append(l, WrapSpan(attr, c.first));
  RETURN TRUE
END SpanHtml;

(* rawHtmlInline *)
PROCEDURE RawHtmlInline(VAR l: A.Inlines): BOOLEAN;
  VAR tag: B.Tag;
BEGIN
  IF ~B.ScanTag(B.pos, tag) OR ~B.IsInlineTag(tag) THEN RETURN FALSE END;
  IF (B.htmlBlock # "") & (tag.kind = B.TagClose) & (tag.name = B.htmlBlock) THEN
    RETURN FALSE
  END;
  A.Append(l, A.NewRawInline(A.S("html"), B.Rope(tag.start, tag.end)));
  B.pos := tag.end;
  RETURN TRUE
END RawHtmlInline;

(* Autolinks *)

PROCEDURE IsWordChar(p: LONGINT): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  IF p >= B.len THEN RETURN FALSE END;
  ch := B.C(p);
  RETURN (ch = "#") OR (ch = "$") OR (ch = "%") OR (ch = "+") OR (ch = "/")
    OR (ch = "@") OR (ch = "\") OR (ch = "_") OR (ch = "-") OR (ch = "&")
    OR (ch = "=") OR AlnumAt(p)
END IsWordChar;

(* percentEscaped *)
PROCEDURE PercentEnd(p: LONGINT): LONGINT;
BEGIN
  IF (B.C(p) # "%") OR ~IsHex(B.C(p + 1)) THEN RETURN -1 END;
  INC(p);
  WHILE IsHex(B.C(p)) DO INC(p) END;
  RETURN p
END PercentEnd;

(* uriChunk at p; the position after it, or -1 *)
PROCEDURE UriChunk(p: LONGINT): LONGINT;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  IF IsWordChar(p) THEN
    WHILE IsWordChar(p) DO p := RuneEnd(p) END;
    RETURN p
  END;
  ch := B.C(p);
  IF ch = "," THEN
    q := p;
    WHILE B.C(q) = "," DO INC(q) END
  ELSIF (p < B.len) & ~SpaceAt(p) & (ch # "<") & (ch # ">") THEN
    q := RuneEnd(p)
  ELSE
    RETURN -1
  END;
  IF IsWordChar(q) OR (PercentEnd(q) >= 0) THEN RETURN q END;
  RETURN -1
END UriChunk;

(* uri at p: the URI as written in orig, escaped in src; the position
   after it, or -1 *)
PROCEDURE Uri*(p: LONGINT; VAR orig, src: B.Buf): LONGINT;
  VAR n, s, q, r: LONGINT; ch, close: CHAR;
BEGIN
  n := W.Scheme(B.t, p);
  IF (n = 0) OR (B.C(p + n) # ":") THEN RETURN -1 END;
  s := p + n + 1; ch := B.C(s);
  IF (ch = "*") OR (ch = "_") OR (ch = "]") THEN RETURN -1 END;
  q := s;
  LOOP
    ch := B.C(q); r := -1;
    IF (ch = "(") OR (ch = "{") OR (ch = "[") THEN
      IF ch = "(" THEN close := ")"
      ELSIF ch = "{" THEN close := "}"
      ELSE close := "]"
      END;
      r := UriChunk(q + 1);
      IF (r >= 0) & (B.C(r) = close) THEN INC(r) ELSE r := -1 END
    END;
    IF r < 0 THEN r := UriChunk(q) END;
    IF r < 0 THEN EXIT END;
    q := r
  END;
  IF q = s THEN RETURN -1 END;
  IF B.C(q) = "/" THEN INC(q) END;
  B.Put(orig, p, s);
  FromEntities(B.t^, s, q, orig);
  EscapeURI(orig.t^, orig.len, src);
  RETURN q
END Uri;

(* emailWord *)
PROCEDURE EmailWord(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  IF ~AlnumAt(p) THEN RETURN -1 END;
  p := RuneEnd(p);
  LOOP
    ch := B.C(p);
    IF AlnumAt(p) THEN p := RuneEnd(p)
    ELSIF (p < B.len) & ((ch = "!") OR (ch = 22X) OR (ch = "#") OR (ch = "$")
        OR (ch = "%") OR (ch = "&") OR (ch = 27X) OR (ch = "*") OR (ch = "+")
        OR (ch = "-") OR (ch = "/") OR (ch = "=") OR (ch = "?") OR (ch = "^")
        OR (ch = "_") OR (ch = "{") OR (ch = "|") OR (ch = "}") OR (ch = "~")
        OR (ch = ";")) THEN
      INC(p)
    ELSE
      EXIT
    END
  END;
  RETURN p
END EmailWord;

(* subdomain *)
PROCEDURE Subdomain(p: LONGINT): LONGINT;
  VAR s: LONGINT;
BEGIN
  s := p;
  LOOP
    IF AlnumAt(p) THEN p := RuneEnd(p)
    ELSIF (B.C(p) = "-") & ((p + 1 >= B.len) OR AlnumAt(p + 1)) THEN INC(p)
    ELSE EXIT
    END
  END;
  IF p = s THEN RETURN -1 END;
  RETURN p
END Subdomain;

(* emailAddress at p: the address in orig, the mailto: URI in src; the
   position after it, or -1 *)
PROCEDURE Email*(p: LONGINT; VAR orig, src: B.Buf): LONGINT;
  VAR q, r: LONGINT; b: B.Buf;
BEGIN
  q := EmailWord(p);
  IF q < 0 THEN RETURN -1 END;
  LOOP
    IF B.C(q) # "." THEN EXIT END;
    r := EmailWord(q + 1);
    IF r < 0 THEN EXIT END;
    q := r
  END;
  IF B.C(q) # "@" THEN RETURN -1 END;
  q := Subdomain(q + 1);
  IF q < 0 THEN RETURN -1 END;
  LOOP
    IF B.C(q) # "." THEN EXIT END;
    r := Subdomain(q + 1);
    IF r < 0 THEN EXIT END;
    q := r
  END;
  FromEntities(B.t^, p, q, orig);
  B.InitBuf(b); B.PutString(b, "mailto:"); PutBuf(b, orig);
  EscapeURI(b.t^, b.len, src);
  RETURN q
END Email;

(* autoLink: <uri> or <address> *)
PROCEDURE AutoLink(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, e: LONGINT; orig, src, extra: B.Buf; cls: ARRAY 6 OF CHAR;
    attr: A.Attr;
BEGIN
  IF ~allowLinks OR (B.C(B.pos) # "<") THEN RETURN FALSE END;
  p := B.pos + 1;
  B.InitBuf(orig); B.InitBuf(src);
  q := Uri(p, orig, src); cls := "uri";
  IF q < 0 THEN
    B.InitBuf(orig); B.InitBuf(src);
    q := Email(p, orig, src); cls := "email"
  END;
  IF q < 0 THEN RETURN FALSE END;
  e := q;
  WHILE (e < B.len) & (B.C(e) # ">") & ~IsSpaceChar(B.C(e)) DO INC(e) END;
  IF B.C(e) # ">" THEN RETURN FALSE END;
  B.InitBuf(extra);
  FromEntities(B.t^, q, e, extra);
  p := e + 1;
  q := B.Attributes(p, attr);
  IF q >= 0 THEN p := q
  ELSE attr := A.NewAttr(NIL); A.AddClass(attr, A.S(cls))
  END;
  EscapeURI(extra.t^, extra.len, src);
  PutBuf(orig, extra);
  A.Append(l, A.NewLink(A.Link, attr, A.NewStr(B.BufRope(orig)),
    B.BufRope(src), NIL));
  B.pos := p;
  RETURN TRUE
END AutoLink;

(* Smart punctuation *)

(* singleQuoted and doubleQuoted, at c; FALSE if no quotation starts
   here *)
PROCEDURE QuotedText(c: CHAR; VAR l: A.Inlines): BOOLEAN;
  VAR ctx, old: INTEGER; m: Mark; cont: A.Inlines; ok: BOOLEAN;
BEGIN
  IF c = 22X THEN ctx := InDouble ELSE ctx := InSingle END;
  IF (quote = ctx) OR ~NotAfterString() OR (B.pos + 1 >= B.len)
      OR IsSpaceChar(B.C(B.pos + 1)) THEN
    RETURN FALSE
  END;
  INC(B.pos);
  Save(m); old := quote; quote := ctx;
  A.InitInlines(cont);
  (* many1Till: the closing quote may not come first *)
  IF (B.C(B.pos) = c) & ((c = 22X) OR ~AlnumAt(B.pos + 1)) THEN ok := FALSE
  ELSE ok := Inline(cont)
  END;
  LOOP
    IF ~ok THEN EXIT END;
    IF (B.C(B.pos) = c) & ((c = 22X) OR ~AlnumAt(B.pos + 1)) THEN EXIT END;
    ok := Inline(cont)
  END;
  IF ok THEN
    INC(B.pos); quote := old;
    IF c = 22X THEN A.Append(l, A.NewQuoted(A.DoubleQuote, Trim(cont)))
    ELSE A.Append(l, A.NewQuoted(A.SingleQuote, Trim(cont)))
    END
  ELSE
    Restore(m);
    IF c = 22X THEN AddChar(l, 201CH) ELSE AddChar(l, 2019H) END
  END;
  RETURN TRUE
END QuotedText;

(* smart: quotes, dashes and ellipses *)
PROCEDURE Smart(VAR l: A.Inlines): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  ch := B.C(B.pos);
  IF (ch = 22X) OR (ch = 27X) THEN
    IF ~QuotedText(ch, l) THEN
      IF ch = 22X THEN AddChar(l, 201DH) ELSE AddChar(l, 2019H) END;
      INC(B.pos)
    END
  ELSIF B.Looking(B.pos, "---") THEN
    AddChar(l, 2014H); B.pos := B.pos + 3
  ELSIF B.Looking(B.pos, "--") THEN
    AddChar(l, 2013H); B.pos := B.pos + 2
  ELSIF B.Looking(B.pos, "...") THEN
    AddChar(l, 2026H); B.pos := B.pos + 3
  ELSE
    RETURN FALSE
  END;
  RETURN TRUE
END Smart;

(* Math *)

(* inBalancedBraces after \text at p: the position after the braces,
   or -1 *)
PROCEDURE BalancedBraces(p: LONGINT): LONGINT;
  VAR depth: LONGINT; ch: CHAR;
BEGIN
  IF B.C(p) # "{" THEN RETURN -1 END;
  INC(p); depth := 1;
  WHILE depth > 0 DO
    IF p >= B.len THEN RETURN -1 END;
    ch := B.C(p); INC(p);
    IF ch = "\" THEN
      IF p >= B.len THEN RETURN -1 END;
      INC(p)
    ELSIF ch = "}" THEN DEC(depth)
    ELSIF ch = "{" THEN INC(depth)
    END
  END;
  RETURN p
END BalancedBraces;

(* An item of display math at p, appended to b; the position after
   it, or -1 *)
PROCEDURE DisplayItem(p: LONGINT; VAR b: B.Buf): LONGINT;
BEGIN
  IF p >= B.len THEN RETURN -1 END;
  IF B.C(p) # 0AX THEN B.PutChar(b, B.C(p)); RETURN p + 1 END;
  IF B.BlankLine(p + 1) >= 0 THEN RETURN -1 END;
  B.PutChar(b, 0AX);
  RETURN p + 1
END DisplayItem;

(* An item of inline math at p, appended to b; the position after it,
   or -1 *)
PROCEDURE InlineItem(p: LONGINT; VAR b: B.Buf): LONGINT;
  VAR q, r: LONGINT; ch: CHAR;
BEGIN
  IF p >= B.len THEN RETURN -1 END;
  ch := B.C(p);
  IF ~IsSpaceChar(ch) & (ch # "\") THEN
    B.PutChar(b, ch); RETURN p + 1
  END;
  IF ch = "\" THEN
    IF B.Looking(p + 1, "text") THEN
      q := BalancedBraces(p + 5);
      IF q >= 0 THEN B.Put(b, p, q); RETURN q END
    END;
    IF p + 1 >= B.len THEN RETURN -1 END;
    q := RuneEnd(p + 1);
    B.Put(b, p, q);
    RETURN q
  END;
  (* blankline: spaces and a new line *)
  q := B.SkipSpaces(p);
  IF B.C(q) = 0AX THEN
    r := q + 1;
    IF (B.BlankLine(r) < 0) & (B.C(r) # "$") THEN
      B.PutChar(b, 0AX); RETURN r
    END
  END;
  IF B.IsSpace(ch) THEN
    q := B.SkipSpaces(p);
    IF B.C(q) = "$" THEN RETURN -1 END;
    B.Put(b, p, q);
    RETURN q
  END;
  RETURN -1
END InlineItem;

(* isWS *)
PROCEDURE IsWS(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 0DX) OR (ch = 0AX) OR (ch = 09X)
END IsWS;

(* trimMath: b without white space at its start, and at its end unless
   after a backslash, where one is kept *)
PROCEDURE TrimMath(VAR b: B.Buf): A.Rope;
  VAR s, e, k: LONGINT;
BEGIN
  e := b.len;
  WHILE (e > 0) & IsWS(b.t[e - 1]) DO DEC(e) END;
  IF (e < b.len) & (e > 0) & (b.t[e - 1] = "\") THEN INC(e) END;
  s := 0;
  WHILE (s < e) & IsWS(b.t[s]) DO INC(s) END;
  k := e - s;
  IF k <= 0 THEN RETURN NIL END;
  RETURN Ropes.FromSubchars(b.t^, s, k)
END TrimMath;

(* math: $$display$$ or $inline$, with an apostrophe after inline
   math *)
PROCEDURE Math(VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT; b: B.Buf; text: A.Rope;
BEGIN
  p := B.pos;
  IF B.C(p) # "$" THEN RETURN FALSE END;
  B.InitBuf(b);
  (* many1Till: the closing delimiter may not come first *)
  IF (B.C(p + 1) = "$") & ~B.Looking(p + 2, "$$") THEN
    q := DisplayItem(p + 2, b);
    WHILE (q >= 0) & ~B.Looking(q, "$$") DO q := DisplayItem(q, b) END;
    IF q >= 0 THEN
      A.Append(l, A.NewMath(A.DisplayMath, B.BufRope(b)));
      B.pos := q + 2;
      RETURN TRUE
    END;
    B.InitBuf(b)
  END;
  IF (p + 1 >= B.len) OR SpaceAt(p + 1) OR B.IsWhite(B.C(p + 1))
     OR (B.C(p + 1) = "$") THEN
    RETURN FALSE
  END;
  q := InlineItem(p + 1, b);
  WHILE (q >= 0) & (B.C(q) # "$") DO q := InlineItem(q, b) END;
  IF (q < 0) OR B.IsDigit(B.C(q + 1)) THEN RETURN FALSE END;
  text := TrimMath(b);
  A.Append(l, A.NewMath(A.InlineMath, text));
  B.pos := q + 1;
  (* an apostrophe after it *)
  p := B.pos;
  IF B.C(p) = 27X THEN q := p + 1
  ELSIF (B.C(p) = 0E2X) & (B.C(p + 1) = 80X) & (B.C(p + 2) = 99X) THEN q := p + 3
  ELSE q := -1
  END;
  IF (q >= 0) & ~SpaceAt(q) & ~B.IsWhite(B.C(q)) & ~PunctAt(q) THEN
    AddChar(l, 2019H); B.pos := q
  END;
  RETURN TRUE
END Math;

(* inlineNote: ^[text] *)
PROCEDURE InlineNote(VAR l: A.Inlines): BOOLEAN;
  VAR old: INTEGER; c: A.Inlines; ok: BOOLEAN; ch: CHAR; attr: A.Attr;
BEGIN
  IF B.C(B.pos) # "^" THEN RETURN FALSE END;
  INC(B.pos);
  old := quote; quote := NoQuote;
  A.InitInlines(c);
  ok := InBalancedBrackets(c);
  quote := old;
  IF ~ok THEN RETURN FALSE END;
  ch := B.C(B.pos);
  IF (ch = "(") OR (ch = "[") OR (B.Attributes(B.pos, attr) >= 0) THEN
    RETURN FALSE
  END;
  A.Append(l, A.NewNote(A.NewInlinesBlock(A.Para, c.first)));
  RETURN TRUE
END InlineNote;

(* inline: one inline at B.pos, added to l; FALSE if there is none *)
PROCEDURE Inline*(VAR l: A.Inlines): BOOLEAN;
  VAR ch: CHAR; m: Mark; ok: BOOLEAN;
BEGIN
  IF B.pos >= B.len THEN RETURN FALSE END;
  ch := B.C(B.pos); Save(m); ok := FALSE;
  CASE ch OF
  | " ", 09X: ok := Whitespace(l)
  | 0AX: ok := EndlineInline(l)
  | "`": ok := CodeSpan(l)
  | "_", "*": ok := Enclosure(ch, l)
  | "^": ok := InlineNote(l) OR Again(m) & Script("^", A.Superscript, l)
  | "[": ok := NoteRef(l) OR Again(m) & BracketedSpan(l) OR Again(m) & Link(l)
  | "!": ok := Image(l)
  | "$": ok := Math(l)
  | "~": ok := Strikeout(l) OR Again(m) & Script("~", A.Subscript, l)
  | "<": ok := AutoLink(l) OR Again(m) & SpanHtml(l)
      OR Again(m) & RawHtmlInline(l) OR Again(m) & LtSign(l)
  | "\": ok := Escape(l) OR Again(m) & RawTeX(l)
  | 22X, 27X, "-", ".": ok := Smart(l)
  | "&": ok := Entity(l)
  ELSE
  END;
  IF ~ok THEN
    Restore(m);
    ok := Str(l) OR Again(m) & Symbol(l);
    IF ~ok THEN Restore(m) END
  END;
  RETURN ok
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

(* pipeTableRow's chunk: the end of the code span, math, raw HTML,
   escaped character or raw TeX at p, which a pipe table row's cells
   are not split in; -1 if there is none. Nothing changes. *)
PROCEDURE Chunk*(p: LONGINT): LONGINT;
  VAR l: A.Inlines; m, m0: Mark; q: LONGINT; ch: CHAR;
BEGIN
  Save(m0); B.pos := p; Save(m); A.InitInlines(l);
  ch := B.C(p);
  IF (ch = "`") & CodeSpan(l) OR (ch = "$") & Math(l)
      OR (ch = "<") & RawHtmlInline(l)
      OR (ch = "\") & (Escape(l) OR Again(m) & RawTeX(l)) THEN
    q := B.pos
  ELSE
    q := -1
  END;
  Restore(m0);
  RETURN q
END Chunk;

(* Inlines of the text t[from .. to-1], parsed on their own, trimmed *)
PROCEDURE ParseText*(from, to: LONGINT): A.Inline;
  VAR l: A.Inlines;
BEGIN
  A.InitInlines(l);
  ParseRange(from, to, FALSE, l);
  RETURN Trim(l)
END ParseText;

(* Identifiers *)

PROCEDURE^ StringifyTo(i: A.Inline; VAR b: B.Buf);

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
  | NoteRefKind:
      (* unresolved, as pandoc reads a header's identifier *)
      B.PutString(b, "[^"); PutRope(b, i(NoteRefInl).ref); B.PutChar(b, "]")
  | RefKind: StringifyTo(i(RefInl).fallback, b)
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

(* inlineListToIdentifier, with the extensions gfm_auto_identifiers
   (gfm) and ascii_identifiers (ascii), as textToIdentifier makes it:
   the text in lower case; kept only letters, numbers, white space and
   _ - . (gfm: _ -, marks and connector punctuation); its words joined
   by - (gfm: each white space a -); with ascii, each character turned
   into ASCII, as toAsciiText does, or dropped; without gfm, anything
   before its first letter dropped. pandoc turns emoji into their
   names first, with gfm or ascii; podoc does not. *)
PROCEDURE IdentifierExt*(i: A.Inline; gfm, ascii: BOOLEAN): A.Rope;
  VAR s, r, a: B.Buf; p, q: LONGINT; c: Utf8.Rune; cat: INTEGER;
    space, keep: BOOLEAN; ch: CHAR;
BEGIN
  Stringify(i, s);
  B.InitBuf(r); p := 0; space := FALSE;
  WHILE p < s.len DO
    q := p;
    IF ~Utf8.Decode(s.t^, q, c) OR (q <= p) THEN c := 0FFFDH; q := p + 1 END;
    p := q;
    c := Unicode.ToLower(c);
    IF Unicode.IsSpace(c) THEN
      IF gfm THEN B.PutChar(r, "-") ELSE space := TRUE END
    ELSE
      keep := Unicode.IsLetter(c) OR Unicode.IsNumber(c)
        OR (c = ORD("_")) OR (c = ORD("-"));
      IF ~keep THEN
        IF gfm THEN
          cat := Unicode.Category(c);
          keep := (cat = Unicode.Mn) OR (cat = Unicode.Mc)
            OR (cat = Unicode.Me) OR (cat = Unicode.Pc)
        ELSE keep := c = ORD(".")
        END
      END;
      IF keep THEN
        IF space & (r.len > 0) THEN B.PutChar(r, "-") END;
        space := FALSE;
        B.PutUtf8(r, c)
      END
    END
  END;
  IF ascii THEN
    B.InitBuf(a); p := 0;
    WHILE p < r.len DO
      q := p;
      IF ~Utf8.Decode(r.t^, q, c) OR (q <= p) THEN c := 0FFFDH; q := p + 1 END;
      p := q;
      IF PdAscii.ToAscii(c, ch) THEN B.PutChar(a, ch) END
    END;
    r := a
  END;
  IF ~gfm THEN
    B.InitBuf(a); p := 0; keep := FALSE;
    WHILE (p < r.len) & ~keep DO
      q := p;
      IF ~Utf8.Decode(r.t^, q, c) OR (q <= p) THEN c := 0FFFDH; q := p + 1 END;
      keep := Unicode.IsLetter(c);
      IF ~keep THEN p := q END
    END;
    WHILE p < r.len DO B.PutChar(a, r.t[p]); INC(p) END;
    r := a
  END;
  RETURN B.BufRope(r)
END IdentifierExt;

BEGIN
  nbsp[0] := 0C2X; nbsp[1] := 0A0X; nbsp[2] := 0X;
  Reset
END PdMdInline.
