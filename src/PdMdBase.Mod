MODULE PdMdBase;
(* PdMdBase: the markdown reader's input and the tests its block and
   inline parsers share (Text.Pandoc.Readers.Markdown, Parsing).

   The reader works on a flat array of bytes, t[0 .. len-1], with 0X at
   t[len]; pos is where it is. pandoc parses some text twice: a block
   quote's or a list item's text is taken out, its markers removed, and
   parsed again as blocks (parseFromString). Enter and Leave do the
   same here: they switch to another text and back.

   The tests take a position and return the position after what they
   recognise, or -1 if it is not there; they change nothing. Their
   names are pandoc's parsers'. Columns are counted in bytes; a tab
   (kept only with --preserve-tabs) counts as tabStop spaces. *)

IMPORT Ropes, PdAst, PdIO, PdEntities;

CONST
  MaxName* = 64;

  (* HTML tag kinds *)
  TagOpen* = 1; TagClose* = 2; TagComment* = 3;

  (* the parser's context, pandoc's ParserContext *)
  NullState* = 0; ListItemState* = 1;

TYPE
  Text* = PdIO.Text;

  (* A text being built: t[0 .. len-1] *)
  Buf* = RECORD
    t*: Text;
    len*: LONGINT
  END;

  (* Where the parser was before Enter *)
  Frame* = RECORD
    t: Text;
    len, pos, id: LONGINT
  END;

  Name* = ARRAY MaxName OF CHAR;

  (* An HTML tag, as ScanTag finds it: t[start .. end-1] *)
  Tag* = RECORD
    kind*: INTEGER;
    name*: Name; (* in lower case; "" for a comment *)
    selfClosing*: BOOLEAN;
    start*, end*: LONGINT;
    attrStart*: LONGINT (* where the attributes start *)
  END;

  (* An HTML attribute, found by NextHtmlAttr *)
  HtmlAttr* = RECORD
    nameStart*, nameLen*: LONGINT;
    valStart*, valLen*: LONGINT; (* valStart = -1: no value *)
    end*: LONGINT
  END;

  (* What an opening code fence says, found by FenceStart *)
  Fence* = RECORD
    indent*: INTEGER; (* spaces before the fence *)
    ch*: CHAR; (* ` or ~ *)
    size*: LONGINT; (* how many *)
    raw*: BOOLEAN; (* {=format}: a raw block *)
    format*: PdAst.Rope;
    attr*: PdAst.Attr;
    body*: LONGINT (* the first line of the contents *)
  END;

VAR
  t*: Text;
  len*, pos*: LONGINT;
  tabStop*: INTEGER;
  context*: INTEGER;
  divLevel*: INTEGER; (* stateFencedDivLevel *)
  htmlBlock*: Name; (* stateInHtmlBlock; "" for Nothing *)
  allowLineBreaks*: BOOLEAN;
  nextExample*: LONGINT; (* stateNextExample *)
  lastStrPos*: LONGINT; (* stateLastStrPos: where the last str ended, in
    the text lastStrText; -1 for Nothing *)
  lastStrText*: LONGINT;
  textId*: LONGINT; (* the current text's id; each Enter makes a new one *)
  texts: LONGINT; (* the ids given out *)
  examples: PdAst.KeyVal; (* example labels and their numbers *)

(* Texts *)

(* A text of n bytes, with room for the 0X after them. *)
PROCEDURE NewText*(n: LONGINT): Text;
  VAR r: Text;
BEGIN
  NEW(r, n + 1); r[n] := 0X;
  RETURN r
END NewText;

(* Starts b empty. *)
PROCEDURE InitBuf*(VAR b: Buf);
BEGIN
  b.t := NewText(255); b.len := 0
END InitBuf;

PROCEDURE Room(VAR b: Buf; n: LONGINT);
  VAR nt: Text; i, size: LONGINT;
BEGIN
  IF b.len + n >= LEN(b.t^) THEN
    size := LEN(b.t^) * 2;
    WHILE b.len + n >= size DO size := size * 2 END;
    NEW(nt, size);
    FOR i := 0 TO b.len - 1 DO nt[i] := b.t[i] END;
    b.t := nt
  END
END Room;

(* Appends ch to b. *)
PROCEDURE PutChar*(VAR b: Buf; ch: CHAR);
BEGIN
  Room(b, 1); b.t[b.len] := ch; INC(b.len); b.t[b.len] := 0X
END PutChar;

(* Appends the string s to b. *)
PROCEDURE PutString*(VAR b: Buf; s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO PutChar(b, s[i]); INC(i) END
END PutString;

(* Appends t[from .. to-1] of the current text to b. *)
PROCEDURE Put*(VAR b: Buf; from, to: LONGINT);
  VAR i: LONGINT;
BEGIN
  IF to > from THEN
    Room(b, to - from);
    FOR i := from TO to - 1 DO b.t[b.len] := t[i]; INC(b.len) END;
    b.t[b.len] := 0X
  END
END Put;

(* Appends the code point c to b in UTF-8. *)
PROCEDURE PutUtf8*(VAR b: Buf; c: LONGINT);
BEGIN
  IF c < 80H THEN PutChar(b, CHR(c))
  ELSIF c < 800H THEN
    PutChar(b, CHR(0C0H + c DIV 40H));
    PutChar(b, CHR(80H + c MOD 40H))
  ELSIF c < 10000H THEN
    PutChar(b, CHR(0E0H + c DIV 1000H));
    PutChar(b, CHR(80H + c DIV 40H MOD 40H));
    PutChar(b, CHR(80H + c MOD 40H))
  ELSE
    PutChar(b, CHR(0F0H + c DIV 40000H));
    PutChar(b, CHR(80H + c DIV 1000H MOD 40H));
    PutChar(b, CHR(80H + c DIV 40H MOD 40H));
    PutChar(b, CHR(80H + c MOD 40H))
  END
END PutUtf8;

(* The rope of b's text. *)
PROCEDURE BufRope*(VAR b: Buf): PdAst.Rope;
BEGIN
  IF b.len = 0 THEN RETURN NIL END;
  RETURN Ropes.FromSubchars(b.t^, 0, b.len)
END BufRope;

(* The rope of t[from .. to-1]. *)
PROCEDURE Rope*(from, to: LONGINT): PdAst.Rope;
BEGIN
  IF to <= from THEN RETURN NIL END;
  RETURN Ropes.FromSubchars(t^, from, to - from)
END Rope;

(* Makes text, of n bytes with 0X after them, the current text, at its
   start; the old one is kept in f. *)
PROCEDURE Enter*(VAR f: Frame; text: Text; n: LONGINT);
BEGIN
  f.t := t; f.len := len; f.pos := pos; f.id := textId;
  t := text; len := n; pos := 0; INC(texts); textId := texts
END Enter;

(* Goes back to the text Enter left. *)
PROCEDURE Leave*(VAR f: Frame);
BEGIN
  t := f.t; len := f.len; pos := f.pos; textId := f.id
END Leave;

(* Sets the reader up for a new document, the text t[0 .. n-1]. *)
PROCEDURE Start*(text: Text; n: LONGINT; tabs: INTEGER);
  VAR i: LONGINT;
BEGIN
  t := NewText(n);
  FOR i := 0 TO n - 1 DO t[i] := text[i] END;
  len := n; pos := 0;
  IF tabs <= 0 THEN tabStop := 4 ELSE tabStop := tabs END;
  context := NullState; divLevel := 0; htmlBlock := "";
  allowLineBreaks := TRUE; nextExample := 1; examples := NIL;
  lastStrPos := -1; lastStrText := -1; textId := 0; texts := 0
END Start;

(* Characters *)

(* The byte at p, or 0X past the end. *)
PROCEDURE C*(p: LONGINT): CHAR;
BEGIN
  IF (p >= 0) & (p < len) THEN RETURN t[p] END;
  RETURN 0X
END C;

PROCEDURE IsSpace*(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X)
END IsSpace;

(* Parsec's space: any white space, the new line too *)
PROCEDURE IsWhite*(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
    OR (ch = 0BX) OR (ch = 0CX)
END IsWhite;

PROCEDURE IsDigit*(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "0") & (ch <= "9")
END IsDigit;

(* A letter. Bytes of UTF-8 sequences count as letters, as most of the
   characters they make are. *)
PROCEDURE IsLetter*(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z")
    OR (ORD(ch) >= 80H)
END IsLetter;

PROCEDURE IsAlnum*(ch: CHAR): BOOLEAN;
BEGIN
  RETURN IsLetter(ch) OR IsDigit(ch)
END IsAlnum;

PROCEDURE Lower*(ch: CHAR): CHAR;
BEGIN
  IF (ch >= "A") & (ch <= "Z") THEN RETURN CHR(ORD(ch) + 32) END;
  RETURN ch
END Lower;

(* Whether t[p ..] starts with s. *)
PROCEDURE Looking*(p: LONGINT; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF C(p + i) # s[i] THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END Looking;

(* Lines and spaces *)

(* skipSpaces *)
PROCEDURE SkipSpaces*(p: LONGINT): LONGINT;
BEGIN
  WHILE IsSpace(C(p)) DO INC(p) END;
  RETURN p
END SkipSpaces;

(* blankline: spaces and a new line *)
PROCEDURE BlankLine*(p: LONGINT): LONGINT;
BEGIN
  p := SkipSpaces(p);
  IF C(p) = 0AX THEN RETURN p + 1 END;
  RETURN -1
END BlankLine;

(* blanklines: one or more blank lines *)
PROCEDURE BlankLines*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := BlankLine(p);
  IF q < 0 THEN RETURN -1 END;
  REPEAT p := q; q := BlankLine(p) UNTIL q < 0;
  RETURN p
END BlankLines;

(* Skips any blank lines. *)
PROCEDURE SkipBlankLines*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := BlankLines(p);
  IF q >= 0 THEN RETURN q END;
  RETURN p
END SkipBlankLines;

(* Where the line at p ends: its new line, or len. *)
PROCEDURE LineEnd*(p: LONGINT): LONGINT;
BEGIN
  WHILE (p < len) & (t[p] # 0AX) DO INC(p) END;
  RETURN p
END LineEnd;

(* anyLine: the rest of a line and its new line, which must be there *)
PROCEDURE AnyLine*(p: LONGINT): LONGINT;
BEGIN
  IF p >= len THEN RETURN -1 END;
  p := LineEnd(p);
  IF p >= len THEN RETURN -1 END;
  RETURN p + 1
END AnyLine;

(* gobbleSpaces n: exactly n columns of spaces *)
PROCEDURE GobbleSpaces*(p: LONGINT; n: LONGINT): LONGINT;
BEGIN
  WHILE n > 0 DO
    IF C(p) = " " THEN DEC(n)
    ELSIF C(p) = 09X THEN DEC(n, tabStop); IF n < 0 THEN n := 0 END
    ELSE RETURN -1
    END;
    INC(p)
  END;
  RETURN p
END GobbleSpaces;

(* gobbleAtMostSpaces n: up to n columns of spaces; count is how many *)
PROCEDURE GobbleAtMost*(p: LONGINT; n: LONGINT; VAR count: LONGINT): LONGINT;
BEGIN
  count := 0;
  WHILE (count < n) & IsSpace(C(p)) DO
    IF C(p) = " " THEN INC(count) ELSE INC(count, tabStop) END;
    INC(p)
  END;
  IF count > n THEN count := n END;
  RETURN p
END GobbleAtMost;

(* skipNonindentSpaces: fewer spaces than a tab stop, and then no
   space; count is how many *)
PROCEDURE NonindentSpaces*(p: LONGINT; VAR count: LONGINT): LONGINT;
BEGIN
  p := GobbleAtMost(p, tabStop - 1, count);
  IF IsSpace(C(p)) THEN RETURN -1 END;
  RETURN p
END NonindentSpaces;

(* indentSpaces: a tab stop of spaces, or a tab *)
PROCEDURE IndentSpaces*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF C(p) = 09X THEN RETURN p + 1 END;
  q := p;
  WHILE (q - p < tabStop) & (C(q) = " ") DO INC(q) END;
  IF q - p = tabStop THEN RETURN q END;
  RETURN -1
END IndentSpaces;

(* Character references *)

PROCEDURE HexValue(ch: CHAR): INTEGER;
BEGIN
  IF IsDigit(ch) THEN RETURN ORD(ch) - ORD("0")
  ELSIF (ch >= "a") & (ch <= "f") THEN RETURN ORD(ch) - ORD("a") + 10
  ELSIF (ch >= "A") & (ch <= "F") THEN RETURN ORD(ch) - ORD("A") + 10
  END;
  RETURN -1
END HexValue;

(* characterReference: &name; or &#n; or &#xh; at p, appended to b as
   UTF-8. Phase 3 knows the numeric references and the five XML names;
   the full table of HTML names comes with the inlines. *)
PROCEDURE CharRef*(p: LONGINT; VAR b: Buf): LONGINT;
  VAR q, v, v2: LONGINT; name: ARRAY 40 OF CHAR; i: INTEGER;
BEGIN
  IF C(p) # "&" THEN RETURN -1 END;
  q := p + 1;
  IF C(q) = "#" THEN
    INC(q); v := 0;
    IF (C(q) = "x") OR (C(q) = "X") THEN
      INC(q);
      IF HexValue(C(q)) < 0 THEN RETURN -1 END;
      WHILE (HexValue(C(q)) >= 0) & (v < 110000H) DO
        v := v * 16 + HexValue(C(q)); INC(q)
      END
    ELSE
      IF ~IsDigit(C(q)) THEN RETURN -1 END;
      WHILE IsDigit(C(q)) & (v < 110000H) DO
        v := v * 10 + ORD(C(q)) - ORD("0"); INC(q)
      END
    END;
    IF C(q) # ";" THEN RETURN -1 END;
    IF (v = 0) OR (v >= 110000H) OR (v >= 0D800H) & (v < 0E000H) THEN
      v := 0FFFDH
    END;
    PutUtf8(b, v);
    RETURN q + 1
  END;
  i := 0;
  WHILE (q < len) & (C(q) # ";") & ~IsWhite(C(q)) & (i < LEN(name) - 1) DO
    name[i] := C(q); INC(i); INC(q)
  END;
  name[i] := 0X;
  IF (i = 0) OR (C(q) # ";") OR ~PdEntities.Lookup(name, v, v2) THEN RETURN -1 END;
  PutUtf8(b, v);
  IF v2 # 0 THEN PutUtf8(b, v2) END;
  RETURN q + 1
END CharRef;

(* escapedChar': a backslash and an ASCII punctuation character, with
   all_symbols_escapable: any character but a letter, a digit or a new
   line *)
PROCEDURE EscapedChar*(p: LONGINT): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  ch := C(p + 1);
  RETURN (C(p) = "\") & (p + 1 < len) & (ch # 0AX) & (ch # 0DX)
    & ~IsAlnum(ch)
END EscapedChar;

(* litChar at p, appended to b *)
PROCEDURE LitChar*(p: LONGINT; VAR b: Buf): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF EscapedChar(p) THEN PutChar(b, C(p + 1)); RETURN p + 2 END;
  q := CharRef(p, b);
  IF q >= 0 THEN RETURN q END;
  IF (C(p) # 0AX) & (p < len) THEN PutChar(b, C(p)); RETURN p + 1 END;
  IF (C(p) = 0AX) & (BlankLine(p + 1) < 0) THEN PutChar(b, " "); RETURN p + 1 END;
  RETURN -1
END LitChar;

(* Attributes *)

(* spnl: spaces, at most one new line, spaces, and no new line after *)
PROCEDURE Spnl*(p: LONGINT): LONGINT;
BEGIN
  p := SkipSpaces(p);
  IF C(p) = 0AX THEN p := SkipSpaces(p + 1) END;
  IF C(p) = 0AX THEN RETURN -1 END;
  RETURN p
END Spnl;

(* identifier: a letter, then letters, digits and - _ : . *)
PROCEDURE Identifier(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  IF ~IsLetter(C(p)) THEN RETURN -1 END;
  INC(p); ch := C(p);
  WHILE IsAlnum(ch) OR (ch = "-") OR (ch = "_") OR (ch = ":") OR (ch = ".") DO
    INC(p); ch := C(p)
  END;
  RETURN p
END Identifier;

(* Adds the words of value, split at white space, to a's classes. *)
PROCEDURE AddWords(a: PdAst.Attr; VAR b: Buf);
  VAR i, j: LONGINT;
BEGIN
  i := 0;
  WHILE i < b.len DO
    WHILE (i < b.len) & IsWhite(b.t[i]) DO INC(i) END;
    j := i;
    WHILE (j < b.len) & ~IsWhite(b.t[j]) DO INC(j) END;
    IF j > i THEN PdAst.AddClass(a, Ropes.FromSubchars(b.t^, i, j - i)) END;
    i := j
  END
END AddWords;

(* attribute: #id, .class, key=value or -, applied to a *)
PROCEDURE Attribute(p: LONGINT; a: PdAst.Attr): LONGINT;
  VAR q, k: LONGINT; b: Buf; key: PdAst.Rope; quote: CHAR;
BEGIN
  IF C(p) = "#" THEN
    q := p + 1;
    WHILE IsAlnum(C(q)) OR (C(q) = "-") OR (C(q) = "_") OR (C(q) = ":")
        OR (C(q) = ".") DO
      INC(q)
    END;
    IF q = p + 1 THEN RETURN -1 END;
    a.id := Rope(p + 1, q);
    RETURN q
  ELSIF C(p) = "." THEN
    q := Identifier(p + 1);
    IF q < 0 THEN RETURN -1 END;
    PdAst.AddClass(a, Rope(p + 1, q));
    RETURN q
  ELSIF C(p) = "-" THEN
    PdAst.AddClass(a, PdAst.S("unnumbered"));
    RETURN p + 1
  END;
  k := Identifier(p);
  IF (k < 0) OR (C(k) # "=") THEN RETURN -1 END;
  key := Rope(p, k);
  q := k + 1; InitBuf(b);
  IF ((C(q) = 22X) OR (C(q) = "'")) & ~IsWhite(C(q + 1))
      & (C(q + 1) # C(q)) THEN
    (* enclosed: the quote, no space, one or more litChars, the quote *)
    quote := C(q); INC(q);
    WHILE (q >= 0) & (C(q) # quote) DO q := LitChar(q, b) END;
    IF q < 0 THEN RETURN -1 END;
    INC(q)
  ELSIF ((C(q) = 22X) OR (C(q) = "'")) & (C(q + 1) = C(q)) THEN
    INC(q, 2)
  ELSIF ((C(q) = 22X) OR (C(q) = "'")) THEN
    RETURN -1
  ELSE
    WHILE (q < len) & ~IsWhite(C(q)) & (C(q) # "}") OR EscapedChar(q) DO
      IF EscapedChar(q) THEN PutChar(b, C(q + 1)); INC(q, 2)
      ELSE PutChar(b, C(q)); INC(q)
      END
    END
  END;
  IF Ropes.EqualString(key, "id") THEN a.id := BufRope(b)
  ELSIF Ropes.EqualString(key, "class") THEN AddWords(a, b)
  ELSE PdAst.AddKeyVal(a, key, BufRope(b))
  END;
  RETURN q
END Attribute;

(* attributes: {#id .class key=value ...}; a is new *)
PROCEDURE Attributes*(p: LONGINT; VAR a: PdAst.Attr): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF C(p) # "{" THEN RETURN -1 END;
  a := PdAst.NewAttr(NIL);
  p := Spnl(p + 1);
  IF p < 0 THEN RETURN -1 END;
  LOOP
    q := Attribute(p, a);
    IF q < 0 THEN EXIT END;
    p := Spnl(q);
    IF p < 0 THEN RETURN -1 END
  END;
  IF C(p) # "}" THEN RETURN -1 END;
  RETURN p + 1
END Attributes;

(* rawAttribute: {=format} *)
PROCEDURE RawAttribute*(p: LONGINT; VAR format: PdAst.Rope): LONGINT;
  VAR s: LONGINT; ch: CHAR;
BEGIN
  IF C(p) # "{" THEN RETURN -1 END;
  p := SkipSpaces(p + 1);
  IF C(p) # "=" THEN RETURN -1 END;
  INC(p); s := p; ch := C(p);
  WHILE IsAlnum(ch) OR (ch = "-") OR (ch = "_") DO INC(p); ch := C(p) END;
  IF p = s THEN RETURN -1 END;
  format := Rope(s, p);
  p := SkipSpaces(p);
  IF C(p) # "}" THEN RETURN -1 END;
  RETURN p + 1
END RawAttribute;

(* HTML tags *)

PROCEDURE IsNameChar(ch: CHAR): BOOLEAN;
BEGIN
  RETURN IsAlnum(ch) OR (ch = ":") OR (ch = "-") OR (ch = "_")
END IsNameChar;

(* Whether t[s .. e-1] is a name: a letter, then letters, digits and
   : - _ (pandoc's isName). *)
PROCEDURE IsName(s, e: LONGINT): BOOLEAN;
BEGIN
  IF (e <= s) OR ~IsLetter(C(s)) THEN RETURN FALSE END;
  INC(s);
  WHILE s < e DO
    IF ~IsNameChar(C(s)) THEN RETURN FALSE END;
    INC(s)
  END;
  RETURN TRUE
END IsName;

(* The end of a tag name or attribute name at p, as tagsoup finds it *)
PROCEDURE NameEnd(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  ch := C(p);
  WHILE (p < len) & ~IsWhite(ch) & (ch # "/") & (ch # ">") & (ch # "=")
      & (ch # "<") DO
    INC(p); ch := C(p)
  END;
  RETURN p
END NameEnd;

(* The next attribute of an opening tag, from p; FALSE at the tag's
   end. *)
PROCEDURE NextHtmlAttr*(p: LONGINT; VAR a: HtmlAttr): BOOLEAN;
  VAR q: LONGINT; quote: CHAR;
BEGIN
  WHILE IsWhite(C(p)) OR (C(p) = "/") & (C(p + 1) # ">") DO INC(p) END;
  IF (p >= len) OR (C(p) = ">") OR (C(p) = "/") OR (C(p) = "<") THEN
    RETURN FALSE
  END;
  q := NameEnd(p);
  IF q = p THEN q := p + 1 END; (* a stray = *)
  a.nameStart := p; a.nameLen := q - p; a.valStart := -1; a.valLen := 0;
  p := q;
  WHILE IsWhite(C(p)) DO INC(p) END;
  IF C(p) = "=" THEN
    INC(p);
    WHILE IsWhite(C(p)) DO INC(p) END;
    IF (C(p) = 22X) OR (C(p) = "'") THEN
      quote := C(p); INC(p); a.valStart := p;
      WHILE (p < len) & (C(p) # quote) DO INC(p) END;
      a.valLen := p - a.valStart;
      IF p < len THEN INC(p) END
    ELSE
      a.valStart := p;
      WHILE (p < len) & ~IsWhite(C(p)) & (C(p) # ">") DO INC(p) END;
      a.valLen := p - a.valStart
    END
  ELSE
    q := p (* no value: the white space is not the attribute's *)
  END;
  a.end := p;
  RETURN TRUE
END NextHtmlAttr;

(* An HTML tag at p: an opening or closing tag, or a comment, checked
   as pandoc's htmlTag checks it. *)
PROCEDURE ScanTag*(p: LONGINT; VAR tag: Tag): BOOLEAN;
  VAR q, s, e: LONGINT; i: INTEGER; a: HtmlAttr;
BEGIN
  IF C(p) # "<" THEN RETURN FALSE END;
  tag.start := p; tag.selfClosing := FALSE; tag.name := "";
  IF Looking(p, "<!--") THEN
    q := p + 4;
    WHILE (q < len) & ~Looking(q, "-->") DO INC(q) END;
    IF q >= len THEN RETURN FALSE END;
    tag.kind := TagComment; tag.end := q + 3; tag.attrStart := q;
    RETURN TRUE
  END;
  q := p + 1;
  IF C(q) = "/" THEN tag.kind := TagClose; INC(q) ELSE tag.kind := TagOpen END;
  s := q;
  IF C(q) = "?" THEN
    (* a processing instruction: <? ... > *)
    IF tag.kind = TagClose THEN RETURN FALSE END;
    e := q + 1;
    WHILE IsNameChar(C(e)) DO INC(e) END;
    WHILE (q < len) & (C(q) # ">") DO INC(q) END;
    IF q >= len THEN RETURN FALSE END
  ELSE
    e := NameEnd(q);
    IF ~IsName(s, e) OR (C(e - 1) = ":") THEN RETURN FALSE END;
    q := e;
    IF tag.kind = TagOpen THEN
      WHILE NextHtmlAttr(q, a) DO
        IF ~IsName(a.nameStart, a.nameStart + a.nameLen) THEN RETURN FALSE END;
        q := a.end
      END;
      WHILE IsWhite(C(q)) DO INC(q) END;
      IF Looking(q, "/>") THEN tag.selfClosing := TRUE; INC(q) END;
      IF C(q) # ">" THEN RETURN FALSE END
    ELSE
      WHILE (q < len) & (C(q) # ">") & (C(q) # "<") DO INC(q) END;
      IF C(q) # ">" THEN RETURN FALSE END
    END
  END;
  IF e - s >= MaxName THEN RETURN FALSE END;
  i := 0;
  WHILE s < e DO tag.name[i] := Lower(C(s)); INC(i); INC(s) END;
  tag.name[i] := 0X;
  tag.attrStart := e;
  tag.end := q + 1;
  RETURN TRUE
END ScanTag;

(* Whether name is in pandoc's blockTags (HTML, DocBook and EPUB block
   tags). *)
PROCEDURE InBlockTags(VAR name: Name): BOOLEAN;
BEGIN
  CASE name[0] OF
  | "a": RETURN (name = "address") OR (name = "article") OR (name = "aside")
  | "b": RETURN (name = "blockquote") OR (name = "body") OR (name = "bibliolist")
  | "c": RETURN (name = "canvas") OR (name = "caption") OR (name = "center")
      OR (name = "col") OR (name = "colgroup") OR (name = "calloutlist")
      OR (name = "caution") OR (name = "classsynopsis") OR (name = "cmdsynopsis")
      OR (name = "case")
  | "d": RETURN (name = "dd") OR (name = "details") OR (name = "dir")
      OR (name = "div") OR (name = "dl") OR (name = "dt") OR (name = "default")
  | "e": RETURN (name = "example") OR (name = "equation") OR (name = "epigraph")
  | "f": RETURN (name = "fieldset") OR (name = "figcaption") OR (name = "figure")
      OR (name = "footer") OR (name = "form") OR (name = "frameset")
      OR (name = "formalpara") OR (name = "funcsynopsis")
  | "g": RETURN name = "glosslist"
  | "h": RETURN (name = "h1") OR (name = "h2") OR (name = "h3") OR (name = "h4")
      OR (name = "h5") OR (name = "h6") OR (name = "head") OR (name = "header")
      OR (name = "hgroup") OR (name = "hr") OR (name = "html")
  | "i": RETURN (name = "isindex") OR (name = "itemizedlist") OR (name = "important")
      OR (name = "informalexample") OR (name = "informalfigure")
      OR (name = "informaltable") OR (name = "informalequation")
  | "l": RETURN (name = "li") OR (name = "literallayout")
  | "m": RETURN (name = "main") OR (name = "menu") OR (name = "meta")
      OR (name = "mediaobject") OR (name = "msgset")
  | "n": RETURN (name = "noframes") OR (name = "nav") OR (name = "note")
  | "o": RETURN (name = "ol") OR (name = "output") OR (name = "orderedlist")
  | "p": RETURN (name = "p") OR (name = "pre") OR (name = "programlisting")
      OR (name = "programlistingco") OR (name = "para") OR (name = "procedure")
  | "q": RETURN name = "qandaset"
  | "s": RETURN (name = "section") OR (name = "summary") OR (name = "script")
      OR (name = "style") OR (name = "segmentedlist") OR (name = "simplelist")
      OR (name = "screen") OR (name = "screenco") OR (name = "screenshot")
      OR (name = "synopsis") OR (name = "simpara") OR (name = "sidebar")
      OR (name = "switch")
  | "t": RETURN (name = "table") OR (name = "tbody") OR (name = "textarea")
      OR (name = "thead") OR (name = "tfoot") OR (name = "td") OR (name = "th")
      OR (name = "tr") OR (name = "tip") OR (name = "task") OR (name = "title")
  | "u": RETURN name = "ul"
  | "v": RETURN name = "variablelist"
  | "w": RETURN name = "warning"
  ELSE RETURN FALSE
  END
END InBlockTags;

(* pandoc's eitherBlockOrInline *)
PROCEDURE EitherBlockOrInline(VAR name: Name): BOOLEAN;
BEGIN
  RETURN (name = "audio") OR (name = "applet") OR (name = "button")
    OR (name = "iframe") OR (name = "embed") OR (name = "del")
    OR (name = "ins") OR (name = "progress") OR (name = "map")
    OR (name = "area") OR (name = "noscript") OR (name = "script")
    OR (name = "object") OR (name = "svg") OR (name = "video")
    OR (name = "source") OR (name = "track")
END EitherBlockOrInline;

(* isBlockTag *)
PROCEDURE IsBlockTag*(VAR tag: Tag): BOOLEAN;
BEGIN
  RETURN (tag.kind = TagComment) OR (tag.name[0] = "?")
    OR InBlockTags(tag.name) OR EitherBlockOrInline(tag.name)
END IsBlockTag;

(* The value of the HTML attribute name of the opening tag tag, in b;
   FALSE if it has none. *)
PROCEDURE TagAttr*(VAR tag: Tag; name: ARRAY OF CHAR; VAR b: Buf): BOOLEAN;
  VAR a: HtmlAttr; p, i: LONGINT; same: BOOLEAN;
BEGIN
  p := tag.attrStart;
  WHILE (p < tag.end) & NextHtmlAttr(p, a) DO
    same := TRUE; i := 0;
    WHILE same & (i < a.nameLen) DO
      IF (i >= LEN(name)) OR (Lower(C(a.nameStart + i)) # name[i]) THEN
        same := FALSE
      END;
      INC(i)
    END;
    IF same & ((i >= LEN(name)) OR (name[i] = 0X)) THEN
      InitBuf(b);
      IF a.valStart >= 0 THEN Put(b, a.valStart, a.valStart + a.valLen) END;
      RETURN TRUE
    END;
    p := a.end
  END;
  RETURN FALSE
END TagAttr;

(* isInlineTag *)
PROCEDURE IsInlineTag*(VAR tag: Tag): BOOLEAN;
  VAR b: Buf;
BEGIN
  IF tag.kind = TagComment THEN RETURN TRUE END;
  IF tag.name = "script" THEN
    RETURN (tag.kind = TagClose)
      OR TagAttr(tag, "type", b) & (b.len >= 8) & (b.t[0] = "m")
         & (b.t[1] = "a") & (b.t[2] = "t") & (b.t[3] = "h") & (b.t[4] = "/")
         & (b.t[5] = "t") & (b.t[6] = "e") & (b.t[7] = "x")
  END;
  IF tag.name = "style" THEN RETURN TRUE END;
  RETURN ~InBlockTags(tag.name) OR (tag.name[0] = "?")
END IsInlineTag;

(* htmlInBalanced: an opening tag at p and everything to its matching
   closing tag; the position after it. *)
PROCEDURE HtmlInBalanced*(p: LONGINT; VAR open: Tag): LONGINT;
  VAR tag: Tag; depth: LONGINT; q: LONGINT;
BEGIN
  depth := 1;
  IF open.selfClosing THEN RETURN -1 END;
  q := open.end;
  WHILE q < len DO
    IF (C(q) = "<") & ScanTag(q, tag) THEN
      IF tag.name = open.name THEN
        IF tag.kind = TagOpen THEN
          IF ~tag.selfClosing THEN INC(depth) END
        ELSIF tag.kind = TagClose THEN
          DEC(depth);
          IF depth = 0 THEN RETURN tag.end END
        END
      END;
      q := tag.end
    ELSE
      INC(q)
    END
  END;
  RETURN -1
END HtmlInBalanced;

(* The attributes of an HTML tag as a div's: id, class split into
   words, and the others *)
PROCEDURE HtmlTagAttr*(VAR tag: Tag): PdAst.Attr;
  VAR a: PdAst.Attr; h: HtmlAttr; p, i, j: LONGINT; key, value: PdAst.Rope;
    b: Buf;
BEGIN
  a := PdAst.NewAttr(NIL);
  p := tag.attrStart;
  WHILE (p < tag.end) & NextHtmlAttr(p, h) DO
    key := NIL;
    FOR i := h.nameStart TO h.nameStart + h.nameLen - 1 DO
      key := Ropes.AppendChar(key, Lower(t[i]))
    END;
    IF h.valStart >= 0 THEN value := Rope(h.valStart, h.valStart + h.valLen)
    ELSE value := NIL
    END;
    IF Ropes.EqualString(key, "id") THEN
      a.id := value
    ELSIF Ropes.EqualString(key, "class") THEN
      InitBuf(b);
      IF h.valStart >= 0 THEN Put(b, h.valStart, h.valStart + h.valLen) END;
      i := 0;
      WHILE i < b.len DO
        WHILE (i < b.len) & IsWhite(b.t[i]) DO INC(i) END;
        j := i;
        WHILE (j < b.len) & ~IsWhite(b.t[j]) DO INC(j) END;
        IF j > i THEN PdAst.AddClass(a, Ropes.FromSubchars(b.t^, i, j - i)) END;
        i := j
      END
    ELSE
      PdAst.AddKeyVal(a, key, value)
    END;
    p := h.end
  END;
  RETURN a
END HtmlTagAttr;

(* notFollowedByHtmlCloser fails at p: inside an HTML block, its
   closing tag is there. *)
PROCEDURE HtmlCloser*(p: LONGINT): BOOLEAN;
  VAR tag: Tag;
BEGIN
  RETURN (htmlBlock # "") & ScanTag(p, tag) & (tag.kind = TagClose)
    & (tag.name = htmlBlock)
END HtmlCloser;

(* divFenceEnd: ::: and blank lines *)
PROCEDURE DivFenceEnd*(p: LONGINT): LONGINT;
BEGIN
  IF ~Looking(p, ":::") THEN RETURN -1 END;
  INC(p, 3);
  WHILE C(p) = ":" DO INC(p) END;
  RETURN BlankLines(p)
END DivFenceEnd;

(* notFollowedByDivCloser fails at p *)
PROCEDURE DivCloser*(p: LONGINT): BOOLEAN;
BEGIN
  RETURN (divLevel > 0) & (DivFenceEnd(p) >= 0)
END DivCloser;

(* Block starts *)

(* hrule *)
PROCEDURE Hrule*(p: LONGINT): LONGINT;
  VAR ch: CHAR; n: INTEGER;
BEGIN
  p := SkipSpaces(p);
  ch := C(p);
  IF (ch # "*") & (ch # "-") & (ch # "_") THEN RETURN -1 END;
  INC(p);
  FOR n := 1 TO 2 DO
    p := SkipSpaces(p);
    IF C(p) # ch THEN RETURN -1 END;
    INC(p)
  END;
  WHILE IsSpace(C(p)) OR (C(p) = ch) DO INC(p) END;
  IF C(p) # 0AX THEN RETURN -1 END;
  RETURN SkipBlankLines(p + 1)
END Hrule;

(* The marker's spaces, as the list starts take them: one space or a
   new line ahead, then up to three more if no space follows them *)
PROCEDURE MarkerSpaces(p: LONGINT): LONGINT;
  VAR q, n: LONGINT;
BEGIN
  q := GobbleSpaces(p, 1);
  IF q < 0 THEN
    IF C(p) # 0AX THEN RETURN -1 END;
    q := p
  END;
  p := GobbleAtMost(q, 3, n);
  IF IsSpace(C(p)) THEN RETURN q END;
  RETURN p
END MarkerSpaces;

(* bulletListStart *)
PROCEDURE BulletListStart*(p: LONGINT): LONGINT;
  VAR n: LONGINT; ch: CHAR;
BEGIN
  IF C(p) = 0AX THEN INC(p) END;
  p := NonindentSpaces(p, n);
  IF (p < 0) OR (Hrule(p) >= 0) THEN RETURN -1 END;
  ch := C(p);
  IF (ch # "*") & (ch # "+") & (ch # "-") THEN RETURN -1 END;
  RETURN MarkerSpaces(p + 1)
END BulletListStart;

(* romanNumeral: its value, 0 if there is none *)
PROCEDURE Roman(VAR p: LONGINT; upper: BOOLEAN): LONGINT;
  VAR total, q: LONGINT;

  PROCEDURE Is(ch: CHAR; at: LONGINT): BOOLEAN;
  BEGIN
    IF ~upper THEN ch := Lower(ch) END;
    RETURN C(at) = ch
  END Is;

  PROCEDURE Many(ch: CHAR; value: LONGINT);
  BEGIN
    WHILE Is(ch, q) DO INC(total, value); INC(q) END
  END Many;

  PROCEDURE Opt(ch: CHAR; value: LONGINT);
  BEGIN
    IF Is(ch, q) THEN INC(total, value); INC(q) END
  END Opt;

  PROCEDURE Pair(a, b: CHAR; value: LONGINT);
  BEGIN
    IF Is(a, q) & Is(b, q + 1) THEN INC(total, value); INC(q, 2) END
  END Pair;

BEGIN
  q := p; total := 0;
  IF ~(Is("I", q) OR Is("V", q) OR Is("X", q) OR Is("L", q) OR Is("C", q)
      OR Is("D", q) OR Is("M", q)) THEN
    RETURN 0
  END;
  Many("M", 1000); Pair("C", "M", 900); Opt("D", 500); Pair("C", "D", 400);
  Many("C", 100); Pair("X", "C", 90); Opt("L", 50); Pair("X", "L", 40);
  Many("X", 10); Pair("I", "X", 9); Opt("V", 5); Pair("I", "V", 4);
  Many("I", 1);
  IF total > 0 THEN p := q END;
  RETURN total
END Roman;

(* exampleNum: @ and an optional label; its number *)
PROCEDURE ExampleNum(VAR p: LONGINT; VAR num: LONGINT): BOOLEAN;
  VAR q, s: LONGINT; kv: PdAst.KeyVal; label: PdAst.Rope; b: Buf;
BEGIN
  IF C(p) # "@" THEN RETURN FALSE END;
  q := p + 1; s := q;
  LOOP
    IF IsAlnum(C(q)) THEN
      WHILE IsAlnum(C(q)) DO INC(q) END
    ELSIF ((C(q) = "_") OR (C(q) = "-")) & IsAlnum(C(q + 1)) THEN
      INC(q)
    ELSE EXIT
    END
  END;
  p := q;
  IF q = s THEN num := nextExample; INC(nextExample); RETURN TRUE END;
  label := Rope(s, q);
  kv := examples;
  WHILE (kv # NIL) & ~Ropes.Equal(kv.key, label) DO kv := kv.next END;
  IF kv # NIL THEN
    num := 0; q := 0;
    WHILE q < Ropes.Length(kv.value) DO
      num := num * 10 + ORD(Ropes.Fetch(kv.value, q)) - ORD("0"); INC(q)
    END
  ELSE
    num := nextExample; INC(nextExample);
    InitBuf(b); q := num;
    REPEAT PutChar(b, CHR(ORD("0") + q MOD 10)); q := q DIV 10 UNTIL q = 0;
    NEW(kv); kv.key := label; kv.next := examples; examples := kv;
    kv.value := NIL;
    FOR q := b.len - 1 TO 0 BY -1 DO
      kv.value := Ropes.AppendChar(kv.value, b.t[q])
    END
  END;
  RETURN TRUE
END ExampleNum;

(* One number parser of anyOrderedListMarker, by style: a number and
   its style. DefaultStyle here is pandoc's defaultNum, #. *)
PROCEDURE ListNum(VAR p: LONGINT; style: INTEGER; VAR num: LONGINT;
                  VAR st: INTEGER): BOOLEAN;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  q := p; ch := C(q);
  CASE style OF
  | PdAst.Decimal:
      IF ~IsDigit(ch) THEN RETURN FALSE END;
      num := 0;
      WHILE IsDigit(C(q)) DO
        IF num < 100000000 THEN num := num * 10 + ORD(C(q)) - ORD("0") END;
        INC(q)
      END
  | PdAst.Example:
      IF ~ExampleNum(q, num) THEN RETURN FALSE END
  | PdAst.DefaultStyle:
      IF ch # "#" THEN RETURN FALSE END;
      num := 1; INC(q)
  | PdAst.LowerAlpha:
      IF (ch < "a") OR (ch > "z") THEN RETURN FALSE END;
      num := ORD(ch) - ORD("a") + 1; INC(q)
  | PdAst.UpperAlpha:
      IF (ch < "A") OR (ch > "Z") THEN RETURN FALSE END;
      num := ORD(ch) - ORD("A") + 1; INC(q)
  | PdAst.LowerRoman:
      num := Roman(q, FALSE);
      IF num = 0 THEN RETURN FALSE END
  | PdAst.UpperRoman:
      num := Roman(q, TRUE);
      IF num = 0 THEN RETURN FALSE END
  END;
  st := style; p := q;
  RETURN TRUE
END ListNum;

(* The delimiter delim (Period, OneParen, TwoParens) around a number of
   style style (romanOne is LowerRoman or UpperRoman with one I) *)
PROCEDURE Delimited(p: LONGINT; delim, style: INTEGER; one: BOOLEAN;
                    VAR num: LONGINT; VAR st: INTEGER): LONGINT;
  VAR save: LONGINT;
BEGIN
  IF delim = PdAst.TwoParens THEN
    IF C(p) # "(" THEN RETURN -1 END;
    INC(p)
  END;
  save := nextExample;
  IF one THEN
    IF (style = PdAst.LowerRoman) & (C(p) = "i") OR (style = PdAst.UpperRoman) & (C(p) = "I") THEN
      num := 1; st := style; INC(p)
    ELSE RETURN -1
    END
  ELSIF ~ListNum(p, style, num, st) THEN RETURN -1
  END;
  IF (delim = PdAst.Period) & (C(p) = ".") OR (delim # PdAst.Period) & (C(p) = ")") THEN
    RETURN p + 1
  END;
  nextExample := save;
  RETURN -1
END Delimited;

(* orderedListMarker or anyOrderedListMarker at p: with anyStyle, any
   marker, its style and delimiter set; otherwise one of style and
   delim (or #). *)
PROCEDURE ListMarker(p: LONGINT; anyStyle: BOOLEAN; VAR num: LONGINT;
                     VAR style, delim: INTEGER): LONGINT;
  VAR q: LONGINT; d, s, st: INTEGER;
BEGIN
  IF anyStyle THEN
    FOR d := PdAst.Period TO PdAst.TwoParens DO
      q := Delimited(p, d, PdAst.Decimal, FALSE, num, st);
      IF q < 0 THEN q := Delimited(p, d, PdAst.Example, FALSE, num, st) END;
      IF q < 0 THEN q := Delimited(p, d, PdAst.DefaultStyle, FALSE, num, st) END;
      IF q < 0 THEN q := Delimited(p, d, PdAst.LowerRoman, TRUE, num, st) END;
      IF q < 0 THEN q := Delimited(p, d, PdAst.UpperRoman, TRUE, num, st) END;
      IF q < 0 THEN q := Delimited(p, d, PdAst.LowerAlpha, FALSE, num, st) END;
      IF q < 0 THEN q := Delimited(p, d, PdAst.LowerRoman, FALSE, num, st) END;
      IF q < 0 THEN q := Delimited(p, d, PdAst.UpperAlpha, FALSE, num, st) END;
      IF q < 0 THEN q := Delimited(p, d, PdAst.UpperRoman, FALSE, num, st) END;
      IF q >= 0 THEN
        style := st;
        IF (d = PdAst.Period) & (st = PdAst.DefaultStyle) THEN
          delim := PdAst.DefaultDelim
        ELSE delim := d
        END;
        RETURN q
      END
    END;
    RETURN -1
  END;
  IF delim = PdAst.DefaultDelim THEN d := PdAst.Period ELSE d := delim END;
  q := Delimited(p, d, PdAst.DefaultStyle, FALSE, num, st);
  IF q < 0 THEN
    s := style;
    IF s = PdAst.DefaultStyle THEN s := PdAst.Decimal END;
    q := Delimited(p, d, s, FALSE, num, st)
  END;
  RETURN q
END ListMarker;

(* orderedListStart: with anyStyle, any marker, whose number, style and
   delimiter are set; otherwise a marker of style and delim, whose
   number is set. *)
PROCEDURE OrderedListStart*(p: LONGINT; anyStyle: BOOLEAN; VAR num: LONGINT;
                            VAR style, delim: INTEGER): LONGINT;
  VAR n, save: LONGINT; q: LONGINT;
BEGIN
  save := nextExample;
  IF C(p) = 0AX THEN INC(p) END;
  p := NonindentSpaces(p, n);
  IF p < 0 THEN RETURN -1 END;
  IF Looking(p, "p.") & IsSpace(C(p + 2)) & IsDigit(C(p + 3)) THEN RETURN -1 END;
  q := ListMarker(p, anyStyle, num, style, delim);
  IF q < 0 THEN RETURN -1 END;
  p := q;
  q := GobbleSpaces(p, 1);
  IF q < 0 THEN
    IF C(p) # 0AX THEN nextExample := save; RETURN -1 END;
    q := p
  END;
  IF (delim = PdAst.Period) & ((style = PdAst.UpperAlpha)
      OR (style = PdAst.UpperRoman) & ((num = 1) OR (num = 5) OR (num = 10)
        OR (num = 50) OR (num = 100) OR (num = 500) OR (num = 1000))) THEN
    IF (C(q) # 0AX) & ~IsSpace(C(q)) THEN nextExample := save; RETURN -1 END
  END;
  p := GobbleAtMost(q, 3, n);
  IF IsSpace(C(p)) THEN RETURN q END;
  RETURN p
END OrderedListStart;

(* defListStart *)
PROCEDURE DefListStart*(p: LONGINT): LONGINT;
  VAR n: LONGINT;
BEGIN
  p := NonindentSpaces(p, n);
  IF (p < 0) OR (C(p) # ":") & (C(p) # "~") THEN RETURN -1 END;
  RETURN MarkerSpaces(p + 1)
END DefListStart;

(* listStart *)
PROCEDURE ListStart*(p: LONGINT): BOOLEAN;
  VAR num, save: LONGINT; style, delim: INTEGER; r: BOOLEAN;
BEGIN
  save := nextExample;
  r := (BulletListStart(p) >= 0)
    OR (OrderedListStart(p, TRUE, num, style, delim) >= 0)
    OR (DefListStart(p) >= 0);
  nextExample := save;
  RETURN r
END ListStart;

(* Code fences *)

(* blockDelimiter: nonindent spaces and at least three of ch (size 0)
   or at least size of them; how many *)
PROCEDURE BlockDelimiter(p: LONGINT; ch: CHAR; size: LONGINT;
                         VAR count: LONGINT): LONGINT;
  VAR n, s: LONGINT;
BEGIN
  p := NonindentSpaces(p, n);
  IF (p < 0) OR (C(p) # ch) THEN RETURN -1 END;
  s := p;
  WHILE C(p) = ch DO INC(p) END;
  count := p - s;
  IF size = 0 THEN size := 3 END;
  IF count < size THEN RETURN -1 END;
  RETURN p
END BlockDelimiter;

PROCEDURE LowerRope(r: PdAst.Rope): PdAst.Rope;
  VAR i, n: LONGINT; res: PdAst.Rope;
BEGIN
  res := NIL; n := Ropes.Length(r);
  FOR i := 0 TO n - 1 DO res := Ropes.AppendChar(res, Lower(Ropes.Fetch(r, i))) END;
  RETURN res
END LowerRope;

(* The opening line of a fenced code block at p, described in f *)
PROCEDURE FenceStart*(p: LONGINT; VAR f: Fence): LONGINT;
  VAR n, q, s: LONGINT; lang: PdAst.Rope; a: PdAst.Attr; ch: CHAR;
BEGIN
  p := NonindentSpaces(p, n);
  IF p < 0 THEN RETURN -1 END;
  f.indent := SHORT(n);
  f.ch := C(p);
  IF (f.ch # "`") & (f.ch # "~") THEN RETURN -1 END;
  p := BlockDelimiter(p, f.ch, 0, f.size);
  IF p < 0 THEN RETURN -1 END;
  p := SkipSpaces(p);
  f.raw := FALSE; f.attr := NIL; f.format := NIL;
  q := RawAttribute(p, f.format);
  IF q >= 0 THEN
    f.raw := TRUE; p := q
  ELSE
    s := p; ch := C(p);
    WHILE (p < len) & (ch # "`") & (ch # "{") & (ch # "}") & ~IsWhite(ch) DO
      INC(p); ch := C(p)
    END;
    lang := NIL;
    IF p > s THEN
      lang := LowerRope(Rope(s, p));
      IF Ropes.EqualString(lang, "c++") THEN lang := PdAst.S("cpp")
      ELSIF Ropes.EqualString(lang, "objective-c") THEN lang := PdAst.S("objectivec")
      END
    END;
    p := SkipSpaces(p);
    q := Attributes(p, a);
    IF q >= 0 THEN
      p := q;
      IF lang # NIL THEN
        f.attr := PdAst.NewAttr(a.id);
        PdAst.AddClass(f.attr, lang);
        f.attr.classes.next := a.classes;
        f.attr.attrs := a.attrs
      ELSE f.attr := a
      END
    ELSE
      f.attr := PdAst.NewAttr(NIL);
      IF lang # NIL THEN PdAst.AddClass(f.attr, lang) END
    END
  END;
  p := BlankLine(p);
  f.body := p;
  RETURN p
END FenceStart;

(* The closing fence of f at p: the position after it and the blank
   lines after it *)
PROCEDURE FenceEnd*(p: LONGINT; VAR f: Fence): LONGINT;
  VAR n: LONGINT;
BEGIN
  p := BlockDelimiter(p, f.ch, f.size, n);
  IF p < 0 THEN RETURN -1 END;
  WHILE C(p) = f.ch DO INC(p) END;
  RETURN BlankLines(p)
END FenceEnd;

(* codeBlockFenced at p: the position after it; f describes it, and
   close is where its closing fence starts *)
PROCEDURE FencedCode*(p: LONGINT; VAR f: Fence; VAR close: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  p := FenceStart(p, f);
  IF p < 0 THEN RETURN -1 END;
  LOOP
    q := FenceEnd(p, f);
    IF q >= 0 THEN close := p; RETURN q END;
    p := AnyLine(p);
    IF p < 0 THEN RETURN -1 END
  END
END FencedCode;

(* Whether a fenced code block starts at p *)
PROCEDURE IsFencedCode*(p: LONGINT): BOOLEAN;
  VAR f: Fence; close: LONGINT;
BEGIN
  RETURN FencedCode(p, f, close) >= 0
END IsFencedCode;

(* emailBlockQuoteStart: nonindent spaces, >, and an optional space *)
PROCEDURE QuoteStart*(p: LONGINT): LONGINT;
  VAR n: LONGINT;
BEGIN
  p := NonindentSpaces(p, n);
  IF (p < 0) OR (C(p) # ">") THEN RETURN -1 END;
  INC(p);
  IF C(p) = " " THEN INC(p) END;
  RETURN p
END QuoteStart;

BEGIN
  t := NewText(0); len := 0; pos := 0; tabStop := 4;
  context := NullState; divLevel := 0; htmlBlock := "";
  allowLineBreaks := TRUE; nextExample := 1; examples := NIL
END PdMdBase.
