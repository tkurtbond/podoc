MODULE PdMdWriter;
(* PdMdWriter: the markdown writer, as pandoc 3.10's markdown writer
   (Text.Pandoc.Writers.Markdown) writes pandoc's markdown with its
   default extensions and --wrap=none: notes at the end of the
   document, inline links, ATX headings, fenced code for code with
   attributes, simple and multiline tables. Tables that pandoc writes
   as grid or pipe tables are written as HTML.

   The output is built as a PdLayout Doc, as pandoc builds it. The
   writer's state (the notes, the identifiers used) changes as pandoc's
   does, in the same order: the metadata first, then the table of
   contents, the body and the notes. *)

IMPORT Ropes, Utf8, Unicode, A := PdAst, L := PdLayout, T := PdTemplate,
  C := PdContext, Sh := PdShared, I := PdMdInline, B := PdMdBase, PdWords,
  PdHtml, PdIO;

TYPE
  Rope = Ropes.Rope;
  Buf = PdIO.Text;

  NoteList = POINTER TO NoteDesc;
  NoteDesc = RECORD
    blocks: A.Block;
    next: NoteList
  END;

  (* a block and the block after it, saved *)
  LinkList = POINTER TO LinkDesc;
  LinkDesc = RECORD
    b, next: A.Block;
    rest: LinkList
  END;

  IdList = POINTER TO IdDesc;
  IdDesc = RECORD
    s: Rope;
    next: IdList
  END;

  Lines = POINTER TO ARRAY OF Rope;
  CellText = POINTER TO CellTextDesc;
  CellTextDesc = RECORD
    lines: Lines;
    n: LONGINT (* how many lines *)
  END;
  RowCells = POINTER TO ARRAY OF CellText;
  RowArr = POINTER TO ARRAY OF RowCells;
  IntArr = POINTER TO ARRAY OF LONGINT;
  RealArr = POINTER TO ARRAY OF LONGREAL;

VAR
  (* options *)
  preserve, wantToc, numberSections: BOOLEAN;
  tocDepth: INTEGER;
  idPrefix: Rope;

  (* the writer's state *)
  notes, lastNote: NoteList; (* stNotes, in order *)
  noteCount: LONGINT; (* how many notes are in notes *)
  noteNum: LONGINT; (* stNoteNum: the number of the first of them *)
  ids: IdList; (* stIds *)
  inList, escapeSpaces, noBreaks: BOOLEAN; (* the environment *)

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

(* n spaces *)
PROCEDURE Spaces(n: LONGINT): Rope;
BEGIN
  IF n <= 0 THEN RETURN NIL END;
  RETURN Ropes.Make(n, " ")
END Spaces;

(* The longest run of ch in r *)
PROCEDURE LongestRun(r: Rope; ch: CHAR): LONGINT;
  VAR b: Buf; n, i, run, max: LONGINT;
BEGIN
  n := Len(r); b := ToBuf(r); run := 0; max := 0;
  FOR i := 0 TO n - 1 DO
    IF b[i] = ch THEN INC(run); IF run > max THEN max := run END
    ELSE run := 0
    END
  END;
  RETURN max
END LongestRun;

PROCEDURE StartsWith(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN Sh.StartsWith(r, s)
END StartsWith;

(* r without whitespace at either end (T.strip) *)
PROCEDURE Strip(r: Rope): Rope;
  VAR b: Buf; n, i, j: LONGINT;
BEGIN
  n := Len(r); b := ToBuf(r); i := 0; j := n;
  WHILE (i < j) & (b[i] <= " ") DO INC(i) END;
  WHILE (j > i) & (b[j - 1] <= " ") DO DEC(j) END;
  IF i >= j THEN RETURN NIL END;
  RETURN Ropes.FromSubchars(b^, i, j - i)
END Strip;

(* Docs *)

PROCEDURE Lit(s: ARRAY OF CHAR): L.Doc;
BEGIN
  RETURN L.Text(s)
END Lit;

PROCEDURE Lr(r: Rope): L.Doc;
BEGIN
  RETURN L.Literal(r)
END Lr;

(* Escapes *)

(* Whether b[i] starts a letter or number (Haskell's isAlphaNum); next
   is where the character after it starts *)
PROCEDURE AlnumAt(b: Buf; i: LONGINT; VAR next: LONGINT): BOOLEAN;
  VAR r: Utf8.Rune; j: LONGINT; ch: CHAR;
BEGIN
  ch := b[i]; next := i + 1;
  IF ch < 80X THEN
    RETURN (ch >= "0") & (ch <= "9") OR (ch >= "A") & (ch <= "Z") OR (ch >= "a") & (ch <= "z")
  END;
  j := i;
  IF Utf8.Decode(b^, j, r) THEN
    next := j;
    RETURN Unicode.IsLetter(r) OR Unicode.IsNumber(r)
  END;
  RETURN FALSE
END AlnumAt;

(* Whether b[i ..] starts with a character reference *)
PROCEDURE IsCharRef(b: Buf; i, n: LONGINT): BOOLEAN;
  VAR m, k: LONGINT; t: PdIO.Text; f: B.Frame; o: B.Buf; ok: BOOLEAN;
BEGIN
  m := n - i; IF m > 40 THEN m := 40 END;
  t := B.NewText(m);
  FOR k := 0 TO m - 1 DO t[k] := b[i + k] END;
  B.Enter(f, t, m); B.InitBuf(o);
  ok := B.CharRef(0, o) >= 0;
  B.Leave(f);
  RETURN ok
END IsCharRef;

(* escapeText, then unsmartify: the text of a Str as markdown *)
PROCEDURE Escape(r: Rope): Rope;
  VAR b: Buf; n, i, j, k: LONGINT; o: B.Buf; ch: CHAR;
BEGIN
  n := Len(r);
  IF n = 0 THEN RETURN NIL END;
  b := ToBuf(r); B.InitBuf(o); i := 0;
  IF b[0] = "#" THEN
    j := 1; WHILE b[j] = "#" DO INC(j) END;
    IF (j = n) OR (b[j] = " ") OR (b[j] = 9X) THEN B.PutChar(o, "\") END;
    B.PutChar(o, "#"); i := 1
  ELSIF b[0] = "@" THEN
    IF (n > 1) & ((b[1] = "_") OR (b[1] = "{") OR AlnumAt(b, 1, k)) THEN B.PutChar(o, "\") END;
    B.PutChar(o, "@"); i := 1
  END;
  WHILE i < n DO
    ch := b[i];
    IF (ch = "\") & (i = n - 1) THEN B.PutString(o, "\\"); INC(i)
    ELSIF (ch = "-") & (b[i + 1] = "-") THEN B.PutString(o, "\-"); INC(i)
    ELSIF (ch = ".") & (b[i + 1] = ".") & (b[i + 2] = ".") THEN B.PutString(o, "\..."); INC(i, 3)
    ELSIF (ch = ":") & (b[i + 1] = ":") & (b[i + 2] = ":") THEN B.PutString(o, "\:::"); INC(i, 3)
    ELSIF AlnumAt(b, i, j) & (b[j] = "_") & AlnumAt(b, j + 1, k) THEN
      WHILE i < j DO B.PutChar(o, b[i]); INC(i) END;
      B.PutChar(o, "_"); i := j + 1
    ELSIF ch = "\" THEN B.PutString(o, "\\"); INC(i)
    ELSIF (ch = "!") & (b[i + 1] = "[") THEN B.PutString(o, "\!["); INC(i, 2)
    ELSIF (ch = "~") & (b[i + 1] = "~") THEN B.PutString(o, "\~"); INC(i)
    ELSIF (ch = "&") & IsCharRef(b, i, n) THEN B.PutString(o, "\&"); INC(i)
    ELSIF (ch = "[") OR (ch = "]") OR (ch = "`") OR (ch = "*") OR (ch = "_")
       OR (ch = ">") OR (ch = "<") OR (ch = "|") OR (ch = "^") OR (ch = "~")
       OR (ch = "$") OR (ch = "'") OR (ch = '"') THEN
      B.PutChar(o, "\"); B.PutChar(o, ch); INC(i)
    ELSIF (ch = 0E2X) & (b[i + 1] = 80X) THEN
      CASE b[i + 2] OF
        98X, 99X: B.PutChar(o, "'"); INC(i, 3)
      | 0A6X: B.PutString(o, "..."); INC(i, 3)
      | 93X: B.PutString(o, "--"); INC(i, 3)
      | 94X: B.PutString(o, "---"); INC(i, 3)
      | 9CX, 9DX: B.PutChar(o, '"'); INC(i, 3)
      ELSE B.PutChar(o, ch); INC(i)
      END
    ELSE B.PutChar(o, ch); INC(i)
    END
  END;
  RETURN B.BufRope(o)
END Escape;

(* r with a backslash before each " and \ (escAttr) *)
PROCEDURE EscAttr(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; o: B.Buf;
BEGIN
  n := Len(r); b := ToBuf(r); B.InitBuf(o);
  FOR i := 0 TO n - 1 DO
    IF (b[i] = '"') OR (b[i] = "\") THEN B.PutChar(o, "\") END;
    B.PutChar(o, b[i])
  END;
  RETURN B.BufRope(o)
END EscAttr;

(* For the YAML block: \ as \\, then " as \" *)
PROCEDURE EscYaml(r: Rope): Rope;
BEGIN
  RETURN EscAttr(r)
END EscYaml;

(* escapeURI: the bytes of whitespace and of <>|"{}[]^` percent-encoded *)
PROCEDURE EscapeURI(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; o: B.Buf; ch: CHAR;
    hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789ABCDEF";
  n := Len(r); b := ToBuf(r); B.InitBuf(o);
  FOR i := 0 TO n - 1 DO
    ch := b[i];
    IF (ch = " ") OR (ch >= 9X) & (ch <= 0DX) OR (ch = "<") OR (ch = ">") OR (ch = "|")
       OR (ch = '"') OR (ch = "{") OR (ch = "}") OR (ch = "[") OR (ch = "]")
       OR (ch = "^") OR (ch = "`") THEN
      B.PutChar(o, "%"); B.PutChar(o, hex[ORD(ch) DIV 16]); B.PutChar(o, hex[ORD(ch) MOD 16])
    ELSE B.PutChar(o, ch)
    END
  END;
  RETURN B.BufRope(o)
END EscapeURI;

(* isURI: a known scheme, a colon and something after it *)
PROCEDURE IsUri(r: Rope): BOOLEAN;
  VAR b: Buf; n, k: LONGINT;
BEGIN
  n := Len(r); b := ToBuf(r); k := 0;
  WHILE (k < n) & (b[k] # ":") DO INC(k) END;
  RETURN (k > 0) & (k < n - 1) & (PdWords.Scheme(b, 0) = k)
END IsUri;

(* Attributes *)

PROCEDURE IsNullAttr(a: A.Attr): BOOLEAN;
BEGIN
  RETURN (a = NIL) OR A.IsEmptyAttr(a)
END IsNullAttr;

(* attrsToMarkdown *)
PROCEDURE Attrs(a: A.Attr): L.Doc;
  VAR r: Rope; c: A.StrList; kv: A.KeyVal;

  PROCEDURE Add(p: Rope);
  BEGIN
    IF Len(r) > 1 THEN r := CatC(r, " ") END;
    r := Cat(r, p)
  END Add;

BEGIN
  r := R("{");
  IF a # NIL THEN
    IF Len(a.id) > 0 THEN Add(Cat(R("#"), EscAttr(Cat(idPrefix, a.id)))) END;
    c := a.classes;
    WHILE c # NIL DO
      IF Len(c.s) > 0 THEN Add(EscAttr(Cat(R("."), c.s))) END;
      c := c.next
    END;
    kv := a.attrs;
    WHILE kv # NIL DO
      Add(CatC(Cat(CatS(EscAttr(kv.key), '="'), EscAttr(kv.value)), '"'));
      kv := kv.next
    END
  END;
  RETURN Lr(CatC(r, "}"))
END Attrs;

(* classOrAttrsToMarkdown *)
PROCEDURE ClassOrAttrs(a: A.Attr): L.Doc;
BEGIN
  IF (a # NIL) & (Len(a.id) = 0) & (a.classes # NIL) & (a.classes.next = NIL)
     & (a.attrs = NIL) THEN
    RETURN Lr(a.classes.s)
  END;
  RETURN Attrs(a)
END ClassOrAttrs;

(* Identifiers *)

PROCEDURE Used(id: Rope): BOOLEAN;
  VAR s: IdList;
BEGIN
  s := ids;
  WHILE (s # NIL) & ~Ropes.Equal(s.s, id) DO s := s.next END;
  RETURN s # NIL
END Used;

PROCEDURE Use(id: Rope);
  VAR s: IdList;
BEGIN
  NEW(s); s.s := id; s.next := ids; ids := s
END Use;

(* Inlines *)

PROCEDURE^ Inlines(i: A.Inline): L.Doc;
PROCEDURE^ BlockList(b: A.Block): L.Doc;

(* The only inline of the list i, if it is a Str; NIL otherwise *)
PROCEDURE SingleStr(i: A.Inline): A.StrInl;
BEGIN
  IF (i # NIL) & (i.next = NIL) & (i.kind = A.Str) THEN RETURN i(A.StrInl) END;
  RETURN NIL
END SingleStr;

PROCEDURE StrDoc(s: Rope): L.Doc;
BEGIN
  RETURN Lr(Escape(s))
END StrDoc;

PROCEDURE SpaceDoc(): L.Doc;
BEGIN
  IF escapeSpaces THEN RETURN Lit("\ ") END;
  RETURN L.Space()
END SpaceDoc;

(* Content between open and close, or nothing if there is none *)
PROCEDURE Delim(i: A.Inline; open, close: ARRAY OF CHAR): L.Doc;
BEGIN
  IF i = NIL THEN RETURN NIL END;
  RETURN L.Delimited(Lit(open), Lit(close), Inlines(i))
END Delim;

(* Superscript and subscript: their content with spaces escaped *)
PROCEDURE DelimEsc(i: A.Inline; open, close: ARRAY OF CHAR): L.Doc;
  VAR save: BOOLEAN; d: L.Doc;
BEGIN
  IF i = NIL THEN RETURN NIL END;
  save := escapeSpaces; escapeSpaces := TRUE;
  d := L.Delimited(Lit(open), Lit(close), Inlines(i));
  escapeSpaces := save;
  RETURN d
END DelimEsc;

PROCEDURE IsMarkdownFormat(f: Rope): BOOLEAN;
BEGIN
  RETURN Eq(f, "markdown") OR Eq(f, "markdown_github") OR Eq(f, "markdown_phpextra")
    OR Eq(f, "markdown_mmd") OR Eq(f, "markdown_strict")
END IsMarkdownFormat;

(* A link (or, after "!", an image): its text, then its target *)
PROCEDURE LinkForm(attr: A.Attr; content: A.Inline; src, title: Rope): L.Doc;
  VAR txt, d: L.Doc; suffix, linktitle: Rope; s: A.StrInl; useAuto: BOOLEAN; c: A.StrList;
BEGIN
  txt := Inlines(content);
  linktitle := NIL;
  IF Len(title) > 0 THEN linktitle := CatC(Cat(R(' "'), title), '"') END;
  suffix := src;
  IF StartsWith(src, "mailto:") THEN suffix := Ropes.Substring(src, 7, Len(src) - 7) END;
  useAuto := FALSE;
  IF IsUri(src) & ((attr = NIL) OR (Len(attr.id) = 0) & (attr.attrs = NIL)) THEN
    IF attr = NIL THEN c := NIL ELSE c := attr.classes END;
    IF (c = NIL) OR (c.next = NIL) & (Eq(c.s, "uri") OR Eq(c.s, "email")) THEN
      s := SingleStr(content);
      useAuto := (s # NIL) & Ropes.Equal(EscapeURI(s.text), suffix)
    END
  END;
  IF useAuto THEN RETURN Lr(CatC(Cat(R("<"), suffix), ">")) END;
  d := L.Cat3(Lit("["), txt, Lr(CatC(Cat(Cat(R("]("), src), linktitle), ")")));
  IF ~IsNullAttr(attr) THEN d := L.Cat(d, Attrs(attr)) END;
  RETURN d
END LinkForm;

PROCEDURE Image(i: A.LinkInl): L.Doc;
  VAR txt: A.Inline; s: A.StrInl; d, dummy: L.Doc;
BEGIN
  txt := i.content; s := SingleStr(txt);
  IF (txt = NIL) OR (s # NIL) & Ropes.Equal(s.text, i.url) THEN txt := A.NewStr(NIL) END;
  d := L.Cat(Lit("!"), LinkForm(i.attr, txt, i.url, i.title));
  dummy := Inlines(i.content);
  RETURN d
END Image;

PROCEDURE NoteRef(blocks: A.Block): L.Doc;
  VAR n: NoteList;
BEGIN
  NEW(n); n.blocks := blocks; n.next := NIL;
  IF notes = NIL THEN notes := n ELSE lastNote.next := n END;
  lastNote := n; INC(noteCount);
  RETURN Lr(CatC(Cat(R("[^"), Cat(idPrefix, Sh.IntRope(noteNum + noteCount - 1))), "]"))
END NoteRef;

PROCEDURE Span(i: A.SpanInl): L.Doc;
  VAR contents, d: L.Doc; s: A.StrInl; a: A.Attr; c: A.StrList;
BEGIN
  a := i.attr;
  IF (a # NIL) & (Len(a.id) = 0) & (a.classes # NIL) & (a.classes.next = NIL)
     & Eq(a.classes.s, "emoji") THEN
    s := SingleStr(i.content);
    IF s # NIL THEN RETURN StrDoc(s.text) END
  END;
  contents := Inlines(i.content);
  IF IsNullAttr(a) THEN d := contents
  ELSE d := L.Cat3(Lit("["), contents, L.Cat(Lit("]"), Attrs(a)))
  END;
  IF a # NIL THEN
    c := a.classes;
    IF (c # NIL) & (c.next = NIL) & (Eq(c.s, "csl-block") OR Eq(c.s, "csl-left-margin")
       OR Eq(c.s, "csl-indent")) THEN
      d := L.Cat(L.Cr(), d)
    END
  END;
  RETURN d
END Span;

PROCEDURE Code(i: A.CodeInl): L.Doc;
  VAR n: LONGINT; marker, spacer: Rope; d: L.Doc;
BEGIN
  n := LongestRun(i.text, "`");
  marker := Ropes.Make(n + 1, "`");
  spacer := NIL; IF n > 0 THEN spacer := R(" ") END;
  d := Lr(Cat(Cat(Cat(Cat(marker, spacer), i.text), spacer), marker));
  IF ~IsNullAttr(i.attr) THEN d := L.Cat(d, Attrs(i.attr)) END;
  RETURN d
END Code;

PROCEDURE Raw(i: A.RawInl): L.Doc;
  VAR ticks: Rope;
BEGIN
  IF IsMarkdownFormat(i.format) THEN RETURN Lr(i.text) END;
  ticks := Ropes.Make(LongestRun(i.text, "`") + 1, "`");
  RETURN Lr(CatC(Cat(CatS(Cat(Cat(ticks, i.text), ticks), "{="), i.format), "}"))
END Raw;

PROCEDURE Inline(i: A.Inline): L.Doc;
  VAR d: L.Doc; c: A.Inline; q: Rope;
BEGIN
  d := NIL;
  CASE i.kind OF
    A.Str: d := StrDoc(i(A.StrInl).text)
  | A.Space: d := SpaceDoc()
  | A.SoftBreak:
    IF ~noBreaks & preserve THEN d := L.Cr() ELSE d := SpaceDoc() END
  | A.LineBreak:
    IF noBreaks THEN d := SpaceDoc() ELSE d := L.Cat(Lit("\"), L.Cr()) END
  | A.Emph:
    c := i(A.ContInl).content;
    IF (c # NIL) & (c.next = NIL) & (c.kind = A.Emph) THEN d := Inlines(c(A.ContInl).content)
    ELSE d := Delim(c, "*", "*")
    END
  | A.Underline:
    c := i(A.ContInl).content;
    IF c # NIL THEN d := L.Cat3(Lit("["), Inlines(c), Lit("]{.underline}")) END
  | A.Strong: d := Delim(i(A.ContInl).content, "**", "**")
  | A.Strikeout: d := Delim(i(A.ContInl).content, "~~", "~~")
  | A.Superscript: d := DelimEsc(i(A.ContInl).content, "^", "^")
  | A.Subscript: d := DelimEsc(i(A.ContInl).content, "~", "~")
  | A.SmallCaps:
    d := L.Cat3(Lit("["), Inlines(i(A.ContInl).content), Lit("]{.smallcaps}"))
  | A.Quoted:
    IF i(A.QuotedInl).quote = A.SingleQuote THEN q := R("'") ELSE q := R('"') END;
    d := L.Cat3(Lr(q), Inlines(i(A.ContInl).content), Lr(q))
  | A.Cite: d := Inlines(i(A.ContInl).content)
  | A.Code: d := Code(i(A.CodeInl))
  | A.Math:
    IF i(A.MathInl).math = A.InlineMath THEN
      d := Lr(CatC(Cat(R("$"), Strip(i(A.MathInl).text)), "$"))
    ELSE d := Lr(CatS(Cat(R("$$"), i(A.MathInl).text), "$$"))
    END
  | A.RawInline: d := Raw(i(A.RawInl))
  | A.Link: d := LinkForm(i(A.LinkInl).attr, i(A.LinkInl).content, i(A.LinkInl).url, i(A.LinkInl).title)
  | A.Image: d := Image(i(A.LinkInl))
  | A.Note: d := NoteRef(i(A.NoteInl).blocks)
  | A.Span: d := Span(i(A.SpanInl))
  END;
  RETURN d
END Inline;

(* inlineListToMarkdown *)
PROCEDURE Inlines(i: A.Inline): L.Doc;
  VAR d: L.Doc; s: Rope; n: LONGINT; nx: A.Inline;
BEGIN
  d := NIL;
  WHILE i # NIL DO
    nx := i.next;
    IF (i.kind = A.Math) & (nx # NIL) & (nx.kind = A.Str)
       & ((Len(nx(A.StrInl).text) = 0)
          OR (Ropes.Fetch(nx(A.StrInl).text, 0) >= "0") & (Ropes.Fetch(nx(A.StrInl).text, 0) <= "9")) THEN
      d := L.Cat(d, Inline(i));
      d := L.Cat(d, Lit("`<!-- -->`{=html}"))
    ELSIF (i.kind = A.Str) & (nx # NIL) & ((nx.kind = A.Link) OR (nx.kind = A.Span)) THEN
      s := i(A.StrInl).text; n := Len(s);
      IF (n > 0) & (Ropes.Fetch(s, n - 1) = "!") THEN
        d := L.Cat(d, StrDoc(Ropes.Substring(s, 0, n - 1)));
        d := L.Cat(d, Lit("\!"))
      ELSE d := L.Cat(d, Inline(i))
      END
    ELSE d := L.Cat(d, Inline(i))
    END;
    i := nx
  END;
  RETURN d
END Inlines;

(* Blocks *)

PROCEDURE^ Block(b: A.Block): L.Doc;

(* r with a backslash before each . ( and ) *)
PROCEDURE EscapeMarker(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; o: B.Buf;
BEGIN
  n := Len(r); b := ToBuf(r); B.InitBuf(o);
  FOR i := 0 TO n - 1 DO
    IF (b[i] = ".") OR (b[i] = "(") OR (b[i] = ")") THEN B.PutChar(o, "\") END;
    B.PutChar(o, b[i])
  END;
  RETURN B.BufRope(o)
END EscapeMarker;

(* Plain: the inlines, a list marker at their start escaped *)
PROCEDURE PlainDoc(il: A.Inline): L.Doc;
  VAR nx, r: A.Inline; t: Rope;
BEGIN
  IF (il # NIL) & (il.kind = A.Str) THEN
    t := il(A.StrInl).text; nx := il.next;
    IF ((nx = NIL) OR (nx.kind = A.Space) OR (nx.kind = A.SoftBreak))
       & B.IsOrderedListMarker(t) THEN
      r := A.NewRawInline(R("markdown"), EscapeMarker(t)); r.next := nx; il := r
    ELSIF Eq(t, "+") OR Eq(t, "-") OR Eq(t, "%") THEN
      r := A.NewRawInline(R("markdown"), R("\")); r.next := il; il := r
    END
  END;
  RETURN L.Cat(Inlines(il), L.Cr())
END PlainDoc;

PROCEDURE RawDoc(format, text: Rope): L.Doc;
BEGIN
  IF IsMarkdownFormat(format) THEN RETURN L.Cat(L.Nest(0, Lr(text)), Lr(R(0AX)))
  ELSIF Eq(format, "html") OR Eq(format, "html5") OR Eq(format, "html4")
     OR Eq(format, "latex") OR Eq(format, "tex") THEN
    RETURN L.Cat(Lr(text), Lr(R(0AX)))
  END;
  RETURN L.Above(L.Above(Lr(CatC(Cat(R("```{="), format), "}")), Lr(text)),
    L.Cat(Lit("```"), Lr(R(0AX))))
END RawDoc;

PROCEDURE LineBlock(l: A.InlineList): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  WHILE l # NIL DO
    d := L.Above(d, L.Hang(2, Lit("| "), Inlines(l.inlines)));
    l := l.next
  END;
  RETURN L.Cat(d, L.BlankLine())
END LineBlock;

PROCEDURE Header(h: A.HeaderBlk): L.Doc;
  VAR autoId, base, id: Rope; k: LONGINT; attr, contents: L.Doc; save: BOOLEAN;
    a: A.Attr;
BEGIN
  base := I.Identifier(h.inlines);
  IF Len(base) = 0 THEN base := R("section") END;
  autoId := base;
  IF Used(autoId) THEN
    k := 1;
    REPEAT autoId := Cat(CatC(base, "-"), Sh.IntRope(k)); INC(k)
    UNTIL ~Used(autoId) OR (k > 60000)
  END;
  Use(autoId);
  a := h.attr; attr := NIL;
  IF ~IsNullAttr(a) THEN
    IF a.id = NIL THEN id := NIL ELSE id := a.id END;
    IF ~((a.classes = NIL) & (a.attrs = NIL) & Ropes.Equal(id, autoId)) THEN
      attr := L.Cat(L.Space(), Attrs(a))
    END
  END;
  save := noBreaks; noBreaks := TRUE;
  contents := Inlines(h.inlines);
  noBreaks := save;
  RETURN L.NoWrap(L.Cat(L.Cat3(Lr(Ropes.Make(h.level, "#")), Lit(" "), contents),
    L.Cat(attr, L.BlankLine())))
END Header;

(* The lines of r (T.lines): split on new lines, a final empty line
   dropped *)
PROCEDURE SplitLines(r: Rope; VAR n: LONGINT): Lines;
  VAR ls: Lines; len, i, j, k: LONGINT;
BEGIN
  len := Len(r); n := 0;
  i := 0;
  WHILE i < len DO
    j := Ropes.IndexChar(r, 0AX, i);
    IF j < 0 THEN j := len END;
    INC(n); i := j + 1
  END;
  NEW(ls, n + 1);
  i := 0; k := 0;
  WHILE i < len DO
    j := Ropes.IndexChar(r, 0AX, i);
    IF j < 0 THEN j := len END;
    ls[k] := Ropes.Substring(r, i, j - i); INC(k); i := j + 1
  END;
  RETURN ls
END SplitLines;

PROCEDURE CodeBlock(c: A.CodeBlk): L.Doc;
  VAR ls: Lines; n, k, max, w: LONGINT; s, out: Rope; ticks: L.Doc; b: Buf; all: BOOLEAN;
BEGIN
  ls := SplitLines(c.text, n);
  IF ~IsNullAttr(c.attr) THEN
    max := 2;
    FOR k := 0 TO n - 1 DO
      s := Strip(ls[k]); w := Len(s);
      IF (w >= 3) & StartsWith(s, "```") THEN
        b := ToBuf(s); all := TRUE;
        WHILE w > 0 DO DEC(w); IF b[w] # "`" THEN all := FALSE END END;
        IF all & (Len(s) > max) THEN max := Len(s) END
      END
    END;
    ticks := Lr(Ropes.Make(max + 1, "`"));
    RETURN L.Cat(L.Cat3(ticks, L.NoWrap(L.Cat(Lit(" "), ClassOrAttrs(c.attr))), L.Cr()),
      L.Cat(L.Cat3(Lr(c.text), L.Cr(), ticks), L.BlankLine()))
  END;
  out := NIL;
  FOR k := 0 TO n - 1 DO
    IF Len(ls[k]) = 0 THEN out := CatC(out, 0AX)
    ELSE out := CatC(Cat(Cat(out, R("    ")), ls[k]), 0AX)
    END
  END;
  RETURN L.Above(Lr(out), L.BlankLine())
END CodeBlock;

(* computeDivNestingLevel: foldr go 0 bs *)
PROCEDURE Nesting(b: A.Block; n: LONGINT): LONGINT;
  VAR m, r: LONGINT;
BEGIN
  IF b = NIL THEN RETURN n END;
  r := Nesting(b.next, n);
  IF b.kind = A.Div THEN
    m := Nesting(b(A.DivBlk).blocks, r + 1);
    IF r + 1 > m THEN m := r + 1 END;
    RETURN m
  END;
  RETURN r
END Nesting;

PROCEDURE Div(d: A.DivBlk): L.Doc;
  VAR b: A.Block; colons: L.Doc; contents: L.Doc;
BEGIN
  b := d.blocks;
  IF (d.attr # NIL) & (d.attr.classes # NIL) & Eq(d.attr.classes.s, "sourceCode")
     & (b # NIL) & (b.next = NIL) & (b.kind = A.CodeBlock)
     & (b(A.CodeBlk).attr # NIL) & (b(A.CodeBlk).attr.classes # NIL)
     & Eq(b(A.CodeBlk).attr.classes.s, "sourceCode") THEN
    RETURN BlockList(b)
  END;
  contents := BlockList(b);
  colons := Lr(Ropes.Make(3 + Nesting(b, 0), ":"));
  RETURN L.Above(L.Above(L.NoWrap(L.Hsep(colons, ClassOrAttrs(d.attr))), L.Chomp(contents)),
    L.Cat(colons, L.BlankLine()))
END Div;

(* taskListItemToAscii: the item's blocks, a task box at the start of
   its first Plain or Para written as markdown *)
PROCEDURE TaskListToAscii(b: A.Block): A.Block;
  VAR il, r: A.Inline; t: Rope; box: Rope; nb: A.Block;
BEGIN
  IF (b # NIL) & ((b.kind = A.Plain) OR (b.kind = A.Para)) THEN
    il := b(A.InlinesBlk).inlines;
    IF (il # NIL) & (il.kind = A.Str) & (il.next # NIL) & (il.next.kind = A.Space) THEN
      t := il(A.StrInl).text; box := NIL;
      IF Eq(t, "☐") OR Eq(t, "❏") THEN box := R("[ ]")
      ELSIF Eq(t, "☒") OR Eq(t, "✓") THEN box := R("[x]")
      END;
      IF box # NIL THEN
        r := A.NewRawInline(R("markdown"), box); r.next := il.next;
        nb := A.NewInlinesBlock(b.kind, r); nb.next := b.next;
        RETURN nb
      END
    END
  END;
  RETURN b
END TaskListToAscii;

(* itemEndsWithTightList *)
PROCEDURE EndsWithTightList(b: A.Block): BOOLEAN;
BEGIN
  RETURN (b # NIL) & (b.kind = A.Plain) & (b.next # NIL) & (b.next.next = NIL)
    & ((b.next.kind = A.BulletList) OR (b.next.kind = A.OrderedList))
    & Sh.IsTightList(b.next(A.ListBlk).items)
END EndsWithTightList;

PROCEDURE ItemContents(bs: A.Block): L.Doc;
  VAR contents: L.Doc;
BEGIN
  contents := BlockList(TaskListToAscii(bs));
  IF EndsWithTightList(bs) THEN contents := L.Cat(L.Chomp(contents), L.Cr()) END;
  RETURN contents
END ItemContents;

(* vcat or vsep *)
PROCEDURE Join(a, b: L.Doc; tight: BOOLEAN): L.Doc;
BEGIN
  IF tight THEN RETURN L.Above(a, b) END;
  RETURN L.AboveBlank(a, b)
END Join;

PROCEDURE BulletList(l: A.ListBlk): L.Doc;
  VAR it: A.BlockList; d: L.Doc; save, tight: BOOLEAN;
BEGIN
  save := inList; inList := TRUE;
  tight := Sh.IsTightList(l.items);
  d := NIL; it := l.items;
  WHILE it # NIL DO
    d := Join(d, L.Hang(2, Lit("- "), ItemContents(it.blocks)), tight);
    it := it.next
  END;
  inList := save;
  RETURN L.Cat(d, L.BlankLine())
END BulletList;

PROCEDURE Roman(n: LONGINT): Rope;
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

(* The k-th (from 0) marker of the ordered list l (orderedListMarkers) *)
PROCEDURE Marker(l: A.OrderedBlk; k: LONGINT): Rope;
  VAR m: Rope; s: LONGINT;
BEGIN
  CASE l.style OF
    A.LowerAlpha, A.UpperAlpha:
    s := l.start - 1; IF s < 0 THEN s := 0 END;
    s := (s + k) MOD 26;
    IF l.style = A.LowerAlpha THEN m := Ropes.FromChar(CHR(ORD("a") + s))
    ELSE m := Ropes.FromChar(CHR(ORD("A") + s))
    END
  | A.UpperRoman: m := Roman(l.start + k)
  | A.LowerRoman: m := Ropes.LowercaseAscii(Roman(l.start + k))
  ELSE m := Sh.IntRope(l.start + k)
  END;
  CASE l.delim OF
    A.OneParen: m := CatC(m, ")")
  | A.TwoParens: m := CatC(Cat(R("("), m), ")")
  ELSE m := CatC(m, ".")
  END;
  RETURN m
END Marker;

PROCEDURE OrderedList(l: A.OrderedBlk): L.Doc;
  VAR it: A.BlockList; d: L.Doc; save, tight: BOOLEAN; k, len, ind: LONGINT; m, sps: Rope;
BEGIN
  save := inList; inList := TRUE;
  tight := Sh.IsTightList(l.items);
  d := NIL; it := l.items; k := 0;
  WHILE it # NIL DO
    m := Marker(l, k); len := Len(m);
    IF len < 3 THEN m := Cat(m, Spaces(3 - len)); len := 3 END;
    IF 4 - len > 0 THEN sps := Spaces(4 - len) ELSE sps := R(" ") END;
    ind := len + 1; IF ind < 4 THEN ind := 4 END;
    d := Join(d, L.Hang(ind, Lr(Cat(m, sps)), ItemContents(it.blocks)), tight);
    INC(k); it := it.next
  END;
  inList := save;
  RETURN L.Cat(d, L.BlankLine())
END OrderedList;

PROCEDURE DefItem(di: A.DefItem): L.Doc;
  VAR label, contents, def: L.Doc; it: A.BlockList; b: A.Block; tight: BOOLEAN;
    nb: A.Block;
BEGIN
  nb := A.NewInlinesBlock(A.Plain, di.term);
  label := Block(nb);
  tight := (di.defs # NIL) & (di.defs.blocks # NIL) & (di.defs.blocks.kind = A.Plain);
  contents := NIL; it := di.defs;
  WHILE it # NIL DO
    def := NIL; b := it.blocks;
    WHILE b # NIL DO def := L.Above(def, Block(b)); b := b.next END;
    contents := Join(contents, L.Hang(2, Lit(": "), def), tight);
    it := it.next
  END;
  IF ~tight THEN contents := L.Cat(L.BlankLine(), contents) END;
  RETURN L.Above(L.Cat(L.BlankLine(), L.NoWrap(label)), L.Cat(contents, L.BlankLine()))
END DefItem;

PROCEDURE DefList(l: A.DefListBlk): L.Doc;
  VAR di: A.DefItem; d: L.Doc; save: BOOLEAN;
BEGIN
  save := inList; inList := TRUE;
  d := NIL; di := l.items;
  WHILE di # NIL DO d := L.Cat(d, DefItem(di)); di := di.next END;
  inList := save;
  RETURN L.Cat(d, L.BlankLine())
END DefList;

(* The inlines of the blocks b (blocksToInlines), a new list *)
PROCEDURE ToInlines(b: A.Block): A.Inline;
  VAR l: A.Inlines;
BEGIN
  A.InitInlines(l); Sh.BlocksToInlines(l, b);
  RETURN l.first
END ToInlines;

PROCEDURE Figure(f: A.FigureBlk): L.Doc;
  VAR b: A.Block; img: A.LinkInl; ia, na: A.Attr; kv: A.KeyVal; capt, title, alt: Rope;
    descr, ni: A.Inline; found: BOOLEAN; c: A.StrList;
BEGIN
  b := f.blocks;
  IF (b # NIL) & (b.next = NIL) & (b.kind = A.Plain) & (b(A.InlinesBlk).inlines # NIL)
     & (b(A.InlinesBlk).inlines.next = NIL) & (b(A.InlinesBlk).inlines.kind = A.Image)
     & ((f.attr = NIL) OR (f.attr.classes = NIL) & (f.attr.attrs = NIL)) THEN
    img := b(A.InlinesBlk).inlines(A.LinkInl); ia := img.attr;
    IF (ia = NIL) OR (Len(ia.id) = 0) THEN
      IF f.attr = NIL THEN na := A.NewAttr(NIL) ELSE na := A.NewAttr(f.attr.id) END;
      capt := Ropes.Trim(Sh.StringifyBlocks(f.caption.blocks));
      IF ia # NIL THEN
        c := ia.classes;
        WHILE c # NIL DO A.AddClass(na, c.s); c := c.next END;
        kv := ia.attrs;
        WHILE kv # NIL DO
          IF ~Eq(kv.key, "alt") OR (Len(kv.value) > 0) & ~Ropes.Equal(kv.value, capt) THEN
            A.AddKeyVal(na, kv.key, kv.value)
          END;
          kv := kv.next
        END
      END;
      title := img.title;
      IF StartsWith(title, "fig:") THEN title := Ropes.Substring(title, 4, Len(title) - 4) END;
      descr := ToInlines(f.caption.blocks);
      alt := Sh.Stringify(img.content);
      IF (img.content # NIL) & ~Ropes.Equal(Sh.Stringify(descr), alt) THEN
        found := FALSE; kv := na.attrs;
        WHILE kv # NIL DO IF Eq(kv.key, "alt") THEN found := TRUE END; kv := kv.next END;
        IF ~found THEN
          NEW(kv); kv.key := R("alt"); kv.value := alt; kv.next := na.attrs; na.attrs := kv
        END
      END;
      ni := A.NewLink(A.Image, na, descr, img.url, title);
      RETURN L.Cat(Inline(ni), L.BlankLine())
    END
  END;
  RETURN L.Cat(Lr(Strip(PdHtml.Fragment(f))), L.BlankLine())
END Figure;

(* removeBlankLinesInHTML *)
PROCEDURE RemoveBlankLines(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; o: B.Buf; afterNl: BOOLEAN; ch: CHAR;
BEGIN
  n := Len(r); b := ToBuf(r); B.InitBuf(o); afterNl := FALSE;
  FOR i := 0 TO n - 1 DO
    ch := b[i];
    IF ch = 0AX THEN
      IF afterNl THEN B.PutString(o, "&#10;"); afterNl := FALSE
      ELSE B.PutChar(o, ch); afterNl := TRUE
      END
    ELSE
      B.PutChar(o, ch);
      IF (ch # " ") & (ch # 9X) & (ch # 0DX) THEN afterNl := FALSE END
    END
  END;
  RETURN B.BufRope(o)
END RemoveBlankLines;

(* Tables *)

PROCEDURE CellCount(c: A.Cell): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0; WHILE c # NIL DO INC(n); c := c.next END;
  RETURN n
END CellCount;

(* Whether every cell of the row is [], [Plain] or [Para] without a
   LineBreak (simple), all Plain (plain), and has no spans *)
PROCEDURE CheckRow(row: A.Row; VAR simple, plain, spans: BOOLEAN);
  VAR c: A.Cell; b: A.Block; i: A.Inline;
BEGIN
  WHILE row # NIL DO
    c := row.cells;
    WHILE c # NIL DO
      IF (c.rowSpan > 1) OR (c.colSpan > 1) THEN spans := TRUE END;
      b := c.blocks;
      IF b # NIL THEN
        IF (b.next # NIL) OR (b.kind # A.Plain) & (b.kind # A.Para) THEN simple := FALSE
        ELSE
          i := b(A.InlinesBlk).inlines;
          WHILE i # NIL DO IF i.kind = A.LineBreak THEN simple := FALSE END; i := i.next END
        END
      END;
      WHILE b # NIL DO IF b.kind # A.Plain THEN plain := FALSE END; b := b.next END;
      c := c.next
    END;
    row := row.next
  END
END CheckRow;

(* The cell's blocks, rendered, as lines *)
PROCEDURE RenderCell(c: A.Cell): CellText;
  VAR ct: CellText; r: Rope;
BEGIN
  NEW(ct);
  IF c = NIL THEN ct.lines := NIL; ct.n := 0; RETURN ct END;
  r := L.Render(BlockList(c.blocks), 0);
  ct.lines := SplitLines(r, ct.n);
  WHILE (ct.n > 0) & (Len(ct.lines[ct.n - 1]) = 0) DO DEC(ct.n) END;
  RETURN ct
END RenderCell;

PROCEDURE RenderRow(row: A.Row; nc: LONGINT): RowCells;
  VAR rc: RowCells; c: A.Cell; k: LONGINT;
BEGIN
  NEW(rc, nc + 1); c := row.cells;
  FOR k := 0 TO nc - 1 DO
    rc[k] := RenderCell(c);
    IF c # NIL THEN c := c.next END
  END;
  RETURN rc
END RenderRow;

(* The row laid out in columns of the widths, aligned, as pandoc's
   hcat of blocks lays it out: every column but the last padded to its
   width, nothing trimmed *)
PROCEDURE RowDoc(rc: RowCells; widths, aligns: IntArr; nc: LONGINT): L.Doc;
  VAR h, k, li, w, len, pad: LONGINT; line, s, out: Rope;
BEGIN
  h := 0;
  FOR k := 0 TO nc - 1 DO IF rc[k].n > h THEN h := rc[k].n END END;
  IF h = 0 THEN RETURN NIL END;
  out := NIL;
  FOR li := 0 TO h - 1 DO
    line := NIL;
    FOR k := 0 TO nc - 1 DO
      IF k > 0 THEN line := CatC(line, " ") END;
      IF li < rc[k].n THEN s := rc[k].lines[li] ELSE s := NIL END;
      w := widths[k]; len := L.Width(s);
      IF aligns[k] = A.AlignCenter THEN pad := (w - len) DIV 2
      ELSIF aligns[k] = A.AlignRight THEN pad := w - len
      ELSE pad := 0
      END;
      IF pad < 0 THEN pad := 0 END;
      line := Cat(Cat(line, Spaces(pad)), s);
      (* the last column is not padded on the right *)
      IF k < nc - 1 THEN line := Cat(line, Spaces(w - pad - len)) END
    END;
    IF li > 0 THEN out := CatC(out, 0AX) END;
    out := Cat(out, line)
  END;
  RETURN Lr(out)
END RowDoc;

(* pandocTable *)
PROCEDURE PandocTable(multiline, headless: BOOLEAN; head: RowCells; rows: RowArr; nr: LONGINT;
                      aligns: IntArr; widths: RealArr; nc: LONGINT): L.Doc;
  VAR wc: IntArr; k, j, li, m, sum: LONGINT; allZero: BOOLEAN; underline, border, headD, body, d: L.Doc;

  PROCEDURE Widen(rc: RowCells);
    VAR k, li, w: LONGINT;
  BEGIN
    FOR k := 0 TO nc - 1 DO
      FOR li := 0 TO rc[k].n - 1 DO
        w := L.Width(rc[k].lines[li]) + 2;
        IF w > wc[k] THEN wc[k] := w END
      END
    END
  END Widen;

BEGIN
  NEW(wc, nc + 1);
  FOR k := 0 TO nc - 1 DO wc[k] := 2 END;
  Widen(head);
  FOR j := 0 TO nr - 1 DO Widen(rows[j]) END;
  allZero := TRUE;
  FOR k := 0 TO nc - 1 DO IF widths[k] # 0 THEN allZero := FALSE END END;
  IF ~allZero THEN
    FOR k := 0 TO nc - 1 DO
      m := ENTIER(71 * widths[k]);
      IF m > wc[k] THEN wc[k] := m END
    END
  END;
  underline := NIL; sum := 0;
  FOR k := 0 TO nc - 1 DO
    IF k > 0 THEN underline := L.Cat(underline, Lit(" ")) END;
    underline := L.Cat(underline, Lr(Ropes.Make(wc[k], "-")));
    INC(sum, wc[k])
  END;
  IF multiline THEN border := Lr(Ropes.Make(sum + nc - 1, "-"))
  ELSIF headless THEN border := underline
  ELSE border := NIL
  END;
  IF headless THEN headD := NIL
  ELSE headD := L.Cat3(border, L.Cr(), RowDoc(head, wc, aligns, nc))
  END;
  body := NIL;
  FOR j := 0 TO nr - 1 DO body := Join(body, RowDoc(rows[j], wc, aligns, nc), ~multiline) END;
  IF multiline & (nr < 2) THEN body := L.Above(body, L.BlankLine()) END;
  d := L.Above(L.Above(headD, underline), body);
  IF headless THEN d := L.Above(d, underline) ELSE d := L.Above(d, border) END;
  li := 0;
  RETURN d
END PandocTable;

PROCEDURE Table(t: A.TableBlk): L.Doc;
  VAR caption: A.Inline; capD, capt: L.Doc; cs: A.ColSpec; tb: A.TableBody;
    nc, ncs, nr, k, n: LONGINT; aligns: IntArr; widths: RealArr;
    headRow, row: A.Row; simple, plain, spans, hasFooter, allZero, headless, multiline: BOOLEAN;
    head: RowCells; rows: RowArr; c: A.Cell; pass: INTEGER;
BEGIN
  caption := ToInlines(t.caption.blocks);
  (* the rows: the first head row is the header, the rest are rows *)
  headRow := t.head.rows;
  nc := 0; ncs := 0; cs := t.colSpecs;
  WHILE cs # NIL DO INC(ncs); cs := cs.next END;
  nc := ncs;
  IF headRow # NIL THEN n := CellCount(headRow.cells); IF n > nc THEN nc := n END END;
  nr := 0; simple := TRUE; plain := TRUE; spans := FALSE;
  CheckRow(t.head.rows, simple, plain, spans);
  CheckRow(t.foot.rows, simple, plain, spans);
  (* count the rows and widen nc: pass 0 head rows after the first,
     then each body's head and body rows, then the foot rows *)
  IF headRow # NIL THEN row := headRow.next ELSE row := NIL END;
  tb := t.bodies; pass := 0;
  LOOP
    WHILE row # NIL DO
      INC(nr); n := CellCount(row.cells); IF n > nc THEN nc := n END;
      row := row.next
    END;
    IF pass = 1 THEN row := tb.body; pass := 2; tb := tb.next
    ELSIF tb # NIL THEN
      CheckRow(tb.head, simple, plain, spans); CheckRow(tb.body, simple, plain, spans);
      row := tb.head; pass := 1
    ELSIF pass # 3 THEN row := t.foot.rows; pass := 3
    ELSE EXIT
    END
  END;
  hasFooter := t.foot.rows # NIL;
  NEW(aligns, nc + 1); NEW(widths, nc + 1);
  cs := t.colSpecs; allZero := TRUE;
  FOR k := 0 TO nc - 1 DO
    aligns[k] := A.AlignDefault; widths[k] := 0;
    IF cs # NIL THEN
      aligns[k] := cs.align;
      IF cs.hasWidth & (cs.width > 0) THEN widths[k] := cs.width; allZero := FALSE END;
      cs := cs.next
    END
  END;
  IF (simple & ~hasFooter & allZero & ~spans) OR (plain & ~spans & ~hasFooter) THEN
    multiline := ~(simple & ~hasFooter & allZero & ~spans);
    capt := Inlines(caption);
    IF ~IsNullAttr(t.attr) THEN capt := L.Hsep(capt, Attrs(t.attr)) END;
    IF caption = NIL THEN capD := L.BlankLine()
    ELSE capD := L.Above(L.Above(L.BlankLine(), L.Cat(Lit(": "), capt)), L.BlankLine())
    END;
    headless := TRUE;
    IF headRow # NIL THEN
      c := headRow.cells;
      WHILE c # NIL DO IF c.blocks # NIL THEN headless := FALSE END; c := c.next END
    END;
    IF headRow # NIL THEN head := RenderRow(headRow, nc)
    ELSE NEW(head, nc + 1); FOR k := 0 TO nc - 1 DO head[k] := RenderCell(NIL) END
    END;
    NEW(rows, nr + 1); k := 0;
    IF headRow # NIL THEN row := headRow.next ELSE row := NIL END;
    tb := t.bodies; pass := 0;
    LOOP
      WHILE row # NIL DO rows[k] := RenderRow(row, nc); INC(k); row := row.next END;
      IF pass = 1 THEN row := tb.body; pass := 2; tb := tb.next
      ELSIF tb # NIL THEN row := tb.head; pass := 1
      ELSIF pass # 3 THEN row := t.foot.rows; pass := 3
      ELSE EXIT
      END
    END;
    RETURN L.Above(L.Nest(2, L.Above(PandocTable(multiline, headless, head, rows, nr, aligns,
      widths, nc), capD)), L.BlankLine())
  END;
  RETURN L.Above(Lr(RemoveBlankLines(PdHtml.Fragment(t))), L.BlankLine())
END Table;

(* Notes *)

PROCEDURE NoteDoc(blocks: A.Block; num: LONGINT): L.Doc;
  VAR contents, spacer: L.Doc; n: Rope; size: LONGINT;
BEGIN
  contents := BlockList(blocks);
  n := Cat(idPrefix, Sh.IntRope(num));
  size := 4 + L.Width(n);
  IF (blocks # NIL) & ((blocks.kind = A.Para) OR (blocks.kind = A.Plain)) THEN
    IF 4 - size > 0 THEN spacer := Lr(Spaces(4 - size)) ELSE spacer := Lit(" ") END
  ELSE spacer := L.Cr()
  END;
  RETURN L.Hang(4, L.Cat(Lr(CatS(Cat(R("[^"), n), "]:")), spacer), contents)
END NoteDoc;

(* notesAndRefs: the notes so far, written, then forgotten *)
PROCEDURE NotesAndRefs(): L.Doc;
  VAR l: NoteList; d: L.Doc; num: LONGINT;
BEGIN
  l := notes; num := noteNum;
  notes := NIL; lastNote := NIL;
  noteNum := noteNum + noteCount; noteCount := 0;
  d := NIL;
  WHILE l # NIL DO
    d := L.AboveBlank(d, NoteDoc(l.blocks, num));
    INC(num); l := l.next
  END;
  IF d = NIL THEN RETURN NIL END;
  RETURN L.Cat(L.BlankLine(), d)
END NotesAndRefs;

PROCEDURE Block(b: A.Block): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  CASE b.kind OF
    A.Plain: d := PlainDoc(b(A.InlinesBlk).inlines)
  | A.Para: d := L.Cat(PlainDoc(b(A.InlinesBlk).inlines), L.BlankLine())
  | A.LineBlock: d := LineBlock(b(A.LineBlk).lines)
  | A.CodeBlock: d := CodeBlock(b(A.CodeBlk))
  | A.RawBlock: d := RawDoc(b(A.RawBlk).format, b(A.RawBlk).text)
  | A.BlockQuote:
    d := L.Cat3(Lit("> "), L.Prefixed("> ", BlockList(b(A.BlocksBlk).blocks)), L.BlankLine())
  | A.OrderedList: d := OrderedList(b(A.OrderedBlk))
  | A.BulletList: d := BulletList(b(A.ListBlk))
  | A.DefinitionList: d := DefList(b(A.DefListBlk))
  | A.Header: d := Header(b(A.HeaderBlk))
  | A.HorizontalRule:
    d := L.Cat3(L.BlankLine(), Lr(Ropes.Make(72, "-")), L.BlankLine())
  | A.Table: d := Table(b(A.TableBlk))
  | A.Figure: d := Figure(b(A.FigureBlk))
  | A.Div: d := Div(b(A.DivBlk))
  END;
  RETURN d
END Block;

PROCEDURE IsList(b: A.Block): BOOLEAN;
BEGIN
  RETURN (b.kind = A.BulletList) OR (b.kind = A.OrderedList) OR (b.kind = A.DefinitionList)
END IsList;

PROCEDURE CommentSep(): L.Doc;
BEGIN
  RETURN RawDoc(R("html"), CatC(R("<!-- -->"), 0AX))
END CommentSep;

(* blockListToMarkdown: the blocks, fixed as fixBlocks fixes them *)
PROCEDURE BlockList(b: A.Block): L.Doc;
  VAR d: L.Doc; nx: A.Block; raw: Rope; n: LONGINT;
BEGIN
  d := NIL;
  WHILE b # NIL DO
    nx := b.next;
    IF IsList(b) & (nx # NIL) & (nx.kind = A.CodeBlock) & IsNullAttr(nx(A.CodeBlk).attr) THEN
      d := L.Cat(L.Cat3(d, Block(b), CommentSep()), Block(nx));
      nx := nx.next
    ELSIF IsList(b) & (nx # NIL) & (nx.kind = b.kind) THEN
      d := L.Cat3(d, Block(b), CommentSep())
    ELSIF b.kind = A.Plain THEN
      IF (nx # NIL) & (nx.kind = A.RawBlock) OR inList & ~((nx # NIL) & (nx.kind = A.Div)) THEN
        d := L.Cat(d, PlainDoc(b(A.InlinesBlk).inlines))
      ELSE d := L.Cat3(d, PlainDoc(b(A.InlinesBlk).inlines), L.BlankLine())
      END
    ELSIF (b.kind = A.RawBlock) & (nx # NIL) & (nx.kind # A.Plain) & (nx.kind # A.RawBlock) THEN
      raw := b(A.RawBlk).text; n := Len(raw);
      IF (n > 0) & (Ropes.Fetch(raw, n - 1) # 0AX) THEN raw := CatC(raw, 0AX) END;
      d := L.Cat(d, RawDoc(b(A.RawBlk).format, raw))
    ELSE d := L.Cat(d, Block(b))
    END;
    b := nx
  END;
  RETURN d
END BlockList;

(* The YAML metadata block *)

PROCEDURE^ ContextToYaml(ctx: T.Value): L.Doc;

PROCEDURE IsSpecial(s: Rope): BOOLEAN;
BEGIN
  RETURN Eq(s, "y") OR Eq(s, "Y") OR Eq(s, "yes") OR Eq(s, "Yes") OR Eq(s, "YES")
    OR Eq(s, "n") OR Eq(s, "N") OR Eq(s, "no") OR Eq(s, "No") OR Eq(s, "NO")
    OR Eq(s, "true") OR Eq(s, "True") OR Eq(s, "TRUE")
    OR Eq(s, "false") OR Eq(s, "False") OR Eq(s, "FALSE")
    OR Eq(s, "on") OR Eq(s, "On") OR Eq(s, "ON")
    OR Eq(s, "off") OR Eq(s, "Off") OR Eq(s, "OFF")
    OR Eq(s, "null") OR Eq(s, "Null") OR Eq(s, "NULL") OR Eq(s, "~") OR Eq(s, "*")
END IsSpecial;

PROCEDURE NeedsQuotes(x: L.Doc): BOOLEAN;
  VAR s, all: Rope; ch: CHAR;
BEGIN
  IF L.SingleText(x, s) & IsSpecial(s) THEN RETURN TRUE END;
  all := L.AllText(x);
  IF (Ropes.IndexChar(all, "#", 0) >= 0) OR (Ropes.IndexChar(all, ":", 0) >= 0) THEN RETURN TRUE END;
  IF Len(all) > 0 THEN
    ch := Ropes.Fetch(all, 0);
    CASE ch OF
      "-", "?", ":", ",", "[", "]", "{", "}", "#", "&", "*", "!", "|", ">", "'", '"', "%", "@", "`":
      RETURN TRUE
    ELSE
    END
  END;
  RETURN FALSE
END NeedsQuotes;

PROCEDURE ValToYaml(v: T.Value): L.Doc;
  VAR d: L.Doc; e: T.Entry;
BEGIN
  d := NIL;
  CASE v.kind OF
    T.ListV:
    e := v.items;
    WHILE e # NIL DO d := L.Above(d, L.Hang(2, Lit("- "), ValToYaml(e.value))); e := e.next END
  | T.MapV: d := ContextToYaml(v)
  | T.BoolV: IF v.b THEN d := Lit("true") ELSE d := Lit("false") END
  | T.SimpleV:
    IF L.IsEmpty(v.doc) THEN d := NIL
    ELSIF L.HasNewlines(v.doc) THEN d := L.Hang(0, L.Cat(Lit("|"), L.Cr()), v.doc)
    ELSIF NeedsQuotes(v.doc) THEN d := L.Cat3(Lit('"'), L.MapText(v.doc, EscYaml), Lit('"'))
    ELSE d := v.doc
    END
  END;
  RETURN d
END ValToYaml;

PROCEDURE ContextToYaml(ctx: T.Value): L.Doc;
  VAR e: T.Entry; es: POINTER TO ARRAY OF T.Entry; n, i, j: LONGINT; x: T.Entry;
    d, key: L.Doc; v: T.Value;
BEGIN
  n := 0; e := ctx.items;
  WHILE e # NIL DO INC(n); e := e.next END;
  IF n = 0 THEN RETURN NIL END;
  NEW(es, n); e := ctx.items; i := 0;
  WHILE e # NIL DO es[i] := e; INC(i); e := e.next END;
  (* a stable sort by the case-folded keys *)
  FOR i := 1 TO n - 1 DO
    x := es[i]; j := i;
    WHILE (j > 0) & (Ropes.CompareNoCase(es[j - 1].key, x.key) > 0) DO es[j] := es[j - 1]; DEC(j) END;
    es[j] := x
  END;
  d := NIL;
  FOR i := 0 TO n - 1 DO
    v := es[i].value; key := Lr(CatC(es[i].key, ":"));
    IF v.kind = T.ListV THEN
      IF v.items # NIL THEN d := L.Above(d, L.Above(key, ValToYaml(v))) END
    ELSIF v.kind = T.MapV THEN
      IF v.items = NIL THEN d := L.Above(d, Lr(CatS(es[i].key, ": {}")))
      ELSE d := L.Above(d, L.Above(key, L.Nest(2, ValToYaml(v))))
      END
    ELSIF (v.kind = T.SimpleV) & L.IsEmpty(v.doc) THEN
    ELSE d := L.Above(d, L.Hsep(key, L.Nest(2, ValToYaml(v))))
    END
  END;
  RETURN d
END ContextToYaml;

(* The links between the blocks of b, and of the Divs among them, which
   MakeSections cuts, saved onto l *)
PROCEDURE SaveLinks(b: A.Block; VAR l: LinkList);
  VAR k: LinkList;
BEGIN
  WHILE b # NIL DO
    NEW(k); k.b := b; k.next := b.next; k.rest := l; l := k;
    IF b.kind = A.Div THEN SaveLinks(b(A.DivBlk).blocks, l) END;
    b := b.next
  END
END SaveLinks;

PROCEDURE RestoreLinks(l: LinkList);
BEGIN
  WHILE l # NIL DO l.b.next := l.next; l := l.rest END
END RestoreLinks;

(* The table of contents of the blocks b, which are left as they were *)
PROCEDURE Contents(b: A.Block): A.Block;
  VAR l: LinkList; t: A.Block;
BEGIN
  l := NIL; SaveLinks(b, l);
  t := PdHtml.TableOfContents(b, numberSections, tocDepth);
  RestoreLinks(l);
  RETURN t
END Contents;

(* The writer's interface *)

(* The blocks b as markdown, for the template's metadata *)
PROCEDURE BlockDoc*(b: A.Block): L.Doc;
BEGIN
  RETURN BlockList(b)
END BlockDoc;

(* The inlines i as markdown, for the template's metadata *)
PROCEDURE InlineDoc*(i: A.Inline): L.Doc;
BEGIN
  RETURN L.Chomp(Inlines(i))
END InlineDoc;

(* Sets the writer's options: whether soft breaks are kept as new lines
   (--wrap=preserve), whether there is a table of contents (--toc) and
   its depth, whether sections are numbered (-N), and the identifier
   prefix (--id-prefix) *)
PROCEDURE SetOptions*(preserveBreaks, toc: BOOLEAN; depth: INTEGER; number: BOOLEAN;
                      prefix: ARRAY OF CHAR);
BEGIN
  preserve := preserveBreaks; wantToc := toc; tocDepth := depth; numberSections := number;
  idPrefix := R(prefix); IF Len(idPrefix) = 0 THEN idPrefix := NIL END
END SetOptions;

(* Writes the document doc as markdown: its body, or, if tmpl is not
   NIL, the template filled in *)
PROCEDURE WriteDoc*(doc: A.Doc; tmpl: T.Template);
  VAR metadata, ctx: T.Value; titleblock, toc, main: L.Doc; e: T.Entry; blocks, b, last: A.Block;
    tb: A.Block;
BEGIN
  notes := NIL; lastNote := NIL; noteCount := 0; noteNum := 1; ids := NIL;
  inList := FALSE; escapeSpaces := FALSE; noBreaks := FALSE;
  metadata := C.FromMeta(doc.meta, BlockDoc, InlineDoc);
  titleblock := L.Above(L.Above(Lit("---"), ContextToYaml(metadata)), Lit("---"));
  toc := NIL;
  IF wantToc THEN
    tb := Contents(doc.blocks);
    IF tb = NIL THEN toc := L.BlankLine() ELSE toc := Block(tb) END
  END;
  (* a final Div with the id "refs" is dropped *)
  blocks := doc.blocks; last := NIL; b := blocks;
  WHILE (b # NIL) & (b.next # NIL) DO last := b; b := b.next END;
  IF (b # NIL) & (b.kind = A.Div) & (b(A.DivBlk).attr # NIL) & Eq(b(A.DivBlk).attr.id, "refs") THEN
    IF last = NIL THEN blocks := NIL ELSE last.next := NIL END
  END;
  main := L.Cat(BlockList(blocks), NotesAndRefs());
  IF last # NIL THEN last.next := b END;
  IF tmpl = NIL THEN
    L.Write(L.Chomp(main), 0); PdIO.WriteLn;
    RETURN
  END;
  ctx := metadata;
  e := C.variables.items;
  WHILE e # NIL DO T.PutRope(ctx, e.key, e.value); e := e.next END;
  C.DefField(ctx, "toc", T.NewSimple(toc));
  C.DefField(ctx, "table-of-contents", T.NewSimple(toc));
  C.DefField(ctx, "body", T.NewSimple(main));
  IF (doc.meta # NIL) & (doc.meta.entries # NIL) THEN
    C.DefField(ctx, "titleblock", T.NewSimple(titleblock))
  END;
  L.Write(T.Render(tmpl, ctx), 0)
END WriteDoc;

BEGIN
  preserve := FALSE; wantToc := FALSE; numberSections := FALSE; tocDepth := 3; idPrefix := NIL;
  notes := NIL; lastNote := NIL; noteCount := 0; noteNum := 1; ids := NIL;
  inList := FALSE; escapeSpaces := FALSE; noBreaks := FALSE
END PdMdWriter.
