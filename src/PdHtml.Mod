MODULE PdHtml;
(* PdHtml: the HTML writer, as pandoc 3.10's html5 writer
   (Text.Pandoc.Writers.HTML) writes HTML without syntax highlighting,
   with --wrap=none and math written as its TeX.

   Everything is built as Ropes. Each block is written as pandoc's
   blaze-html renders it; a list of blocks is the blocks joined by new
   lines, those that write nothing left out. The document is divided
   into sections (PdShared.MakeSections) before it is written, and the
   notes are gathered and written at its end. *)

IMPORT Ropes, A := PdAst, L := PdLayout, T := PdTemplate, C := PdContext,
  Sh := PdShared, PdMime, PdIO, PdCode, PdCodeAlign;

TYPE
  Rope = Ropes.Rope;
  Buf = POINTER TO ARRAY OF CHAR;
  Hang = POINTER TO ARRAY OF LONGINT;
  Aligns = POINTER TO ARRAY OF INTEGER;

  (* A cell of a table as pandoc's Text.Pandoc.Writers.AnnotatedTable
     sees it: its first column and its spans fitted to the table *)
  NCell = POINTER TO NCellDesc;
  NCellDesc = RECORD
    cell: A.Cell; (* NIL: an empty cell *)
    col, colSpan, rowSpan: LONGINT;
    next: NCell
  END;
  NCells = RECORD first, last: NCell END;

VAR
  idPrefix, sourceFile: Rope;
  numberSections, preserve, wantToc: BOOLEAN;
  tocDepth: INTEGER;
  notes: Rope; (* the notes' list items *)
  noteCount: LONGINT;
  mathSeen, cslSeen, cslHasSpacing: BOOLEAN;
  proportionalSeen: BOOLEAN; (* a code block in the proportional style *)
  cslSpacing: Rope;
  inLink, inCite, inCslEntry: INTEGER;
  known: Rope; (* " name name ... ": HTML5 and RDFa attribute names *)
  nl: Rope;

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

(* a, s and a new line *)
PROCEDURE CatL(a: Rope; s: ARRAY OF CHAR): Rope;
BEGIN
  RETURN Ropes.Cat(Ropes.Cat(a, Ropes.FromString(s)), nl)
END CatL;

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

(* r with & < > written as entities; with quotes, " and ' too (as an
   attribute's value); with fe, U+FE0E (text presentation) after the
   arrows U+21A9 and U+2194 that lack it, as pandoc's strToHtml *)
PROCEDURE Escape(r: Rope; quotes, fe: BOOLEAN): Rope;
  VAR b: Buf; n, i, start: LONGINT; out: Rope; ch: CHAR; ent: ARRAY 8 OF CHAR;
BEGIN
  n := Len(r);
  IF n = 0 THEN RETURN NIL END;
  b := ToBuf(r);
  out := NIL; start := 0; i := 0;
  WHILE i < n DO
    ch := b[i]; ent[0] := 0X;
    IF ch = "&" THEN ent := "&amp;"
    ELSIF ch = "<" THEN ent := "&lt;"
    ELSIF ch = ">" THEN ent := "&gt;"
    ELSIF quotes & (ch = 22X) THEN ent := "&quot;"
    ELSIF quotes & (ch = 27X) THEN ent := "&#39;"
    END;
    IF ent[0] # 0X THEN
      IF i > start THEN out := Cat(out, Ropes.FromSubchars(b^, start, i - start)) END;
      out := CatS(out, ent); INC(i); start := i
    ELSIF fe & (ch = 0E2X) & (i + 2 < n) & (b[i + 1] = 86X)
       & ((b[i + 2] = 0A9X) OR (b[i + 2] = 94X))
       & ~((i + 5 < n) & (b[i + 3] = 0EFX) & (b[i + 4] = 0B8X) & (b[i + 5] = 8EX)) THEN
      out := Cat(out, Ropes.FromSubchars(b^, start, i + 3 - start));
      ent[0] := 0EFX; ent[1] := 0B8X; ent[2] := 8EX; ent[3] := 0X;
      out := CatS(out, ent); INC(i, 3); start := i
    ELSE INC(i)
    END
  END;
  IF n > start THEN out := Cat(out, Ropes.FromSubchars(b^, start, n - start)) END;
  RETURN out
END Escape;

PROCEDURE Text(r: Rope): Rope;
BEGIN
  RETURN Escape(r, FALSE, TRUE)
END Text;

(* Attributes *)

(* Whether key is an HTML5 or RDFa attribute *)
PROCEDURE IsKnown(key: Rope): BOOLEAN;
  VAR b: Buf; n: LONGINT;
BEGIN
  n := Len(key);
  IF (n = 0) OR (Ropes.IndexChar(key, " ", 0) >= 0) THEN RETURN FALSE END;
  NEW(b, n + 3); b[0] := " "; Ropes.Blit(key, 0, b^, 1, n);
  b[n + 1] := " "; b[n + 2] := 0X;
  RETURN Ropes.Find(known, b^, 0) >= 0
END IsKnown;

(* The name an attribute key is written with: data- before it unless
   it is HTML's, has a namespace, or starts with data- or aria- *)
PROCEDURE KeyName(key: Rope): Rope;
BEGIN
  IF (IsKnown(key) & ~Eq(key, "label")) OR (Ropes.IndexChar(key, ":", 0) >= 0)
     OR Sh.StartsWith(key, "data-") OR Sh.StartsWith(key, "aria-") THEN
    RETURN key
  END;
  RETURN Cat(R("data-"), key)
END KeyName;

(* r, then ' name="value"', value escaped *)
PROCEDURE Pair(r, name, value: Rope): Rope;
BEGIN
  RETURN CatS(Cat(CatS(Cat(CatS(r, " "), name), '="'), Escape(value, TRUE, FALSE)), '"')
END Pair;

PROCEDURE PairS(r: Rope; name: ARRAY OF CHAR; value: Rope): Rope;
BEGIN
  RETURN Pair(r, R(name), value)
END PairS;

(* The attributes id, classes and kvs written as pandoc's attrsToHtml
   writes them, each after a space: the id with the prefix, the
   classes once each, the pairs whose keys are not empty, each key
   once *)
PROCEDURE AttrStr(id: Rope; classes: A.StrList; kvs: A.KeyVal): Rope;
  VAR r, cls: Rope; l, m: A.StrList; kv, p: A.KeyVal; dup: BOOLEAN;
BEGIN
  r := NIL;
  IF Len(id) > 0 THEN r := PairS(r, "id", Cat(idPrefix, id)) END;
  cls := NIL; l := classes;
  WHILE l # NIL DO
    IF Len(l.s) > 0 THEN
      dup := FALSE; m := classes;
      WHILE (m # l) & ~dup DO dup := Ropes.Equal(m.s, l.s); m := m.next END;
      IF ~dup THEN
        IF cls # NIL THEN cls := CatS(cls, " ") END;
        cls := Cat(cls, l.s)
      END
    END;
    l := l.next
  END;
  IF cls # NIL THEN r := PairS(r, "class", cls) END;
  kv := kvs;
  WHILE kv # NIL DO
    IF Len(kv.key) > 0 THEN
      dup := FALSE; p := kvs;
      WHILE (p # kv) & ~dup DO dup := Ropes.Equal(p.key, kv.key); p := p.next END;
      IF ~dup THEN r := Pair(r, KeyName(kv.key), kv.value) END
    END;
    kv := kv.next
  END;
  RETURN r
END AttrStr;

PROCEDURE AttrOf(a: A.Attr): Rope;
BEGIN
  IF a = NIL THEN RETURN NIL END;
  RETURN AttrStr(a.id, a.classes, a.attrs)
END AttrOf;

PROCEDURE Id(a: A.Attr): Rope;
BEGIN
  IF a = NIL THEN RETURN NIL END;
  RETURN a.id
END Id;

PROCEDURE Classes(a: A.Attr): A.StrList;
BEGIN
  IF a = NIL THEN RETURN NIL END;
  RETURN a.classes
END Classes;

PROCEDURE KVs(a: A.Attr): A.KeyVal;
BEGIN
  IF a = NIL THEN RETURN NIL END;
  RETURN a.attrs
END KVs;

(* The HTML html with the attributes attrs added to its first element,
   after those it has *)
PROCEDURE AddAttrs(html, attrs: Rope): Rope;
  VAR p: LONGINT;
BEGIN
  IF (Len(attrs) = 0) OR (Len(html) = 0) OR (Ropes.Fetch(html, 0) # "<") THEN
    RETURN html
  END;
  p := Ropes.IndexChar(html, ">", 0);
  IF p < 0 THEN RETURN html END;
  IF (p >= 2) & (Ropes.Fetch(html, p - 1) = "/") & (Ropes.Fetch(html, p - 2) = " ") THEN
    DEC(p, 2)
  END;
  RETURN Ropes.Insert(html, p, attrs)
END AddAttrs;

PROCEDURE NewKV(key, value: Rope; next: A.KeyVal): A.KeyVal;
  VAR kv: A.KeyVal;
BEGIN
  NEW(kv); kv.key := key; kv.value := value; kv.next := next;
  RETURN kv
END NewKV;

PROCEDURE NewStrL(s: Rope; next: A.StrList): A.StrList;
  VAR l: A.StrList;
BEGIN
  NEW(l); l.s := s; l.next := next;
  RETURN l
END NewStrL;

(* A copy of kvs without the pairs whose key is key *)
PROCEDURE WithoutKey(kvs: A.KeyVal; key: ARRAY OF CHAR): A.KeyVal;
  VAR a: A.Attr;
BEGIN
  a := A.NewAttr(NIL);
  WHILE kvs # NIL DO
    IF ~Eq(kvs.key, key) THEN A.AddKeyVal(a, kvs.key, kvs.value) END;
    kvs := kvs.next
  END;
  RETURN a.attrs
END WithoutKey;

(* A copy of l without the classes equal to s *)
PROCEDURE WithoutClass(l: A.StrList; s: ARRAY OF CHAR): A.StrList;
  VAR a: A.Attr;
BEGIN
  a := A.NewAttr(NIL);
  WHILE l # NIL DO
    IF ~Eq(l.s, s) THEN A.AddClass(a, l.s) END;
    l := l.next
  END;
  RETURN a.classes
END WithoutClass;

(* A copy of l without the first class equal to s *)
PROCEDURE DeleteClass(l: A.StrList; s: ARRAY OF CHAR): A.StrList;
  VAR a: A.Attr; done: BOOLEAN;
BEGIN
  a := A.NewAttr(NIL); done := FALSE;
  WHILE l # NIL DO
    IF ~done & Eq(l.s, s) THEN done := TRUE ELSE A.AddClass(a, l.s) END;
    l := l.next
  END;
  RETURN a.classes
END DeleteClass;

PROCEDURE HasStr(l: A.StrList; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  WHILE (l # NIL) & ~Eq(l.s, s) DO l := l.next END;
  RETURN l # NIL
END HasStr;

(* a \\ b: a without the first occurrence of each class of b *)
PROCEDURE MinusClasses(a, b: A.StrList): A.StrList;
  VAR r: A.Attr; l: A.StrList; used: POINTER TO ARRAY OF BOOLEAN; n, i: LONGINT;
    found: BOOLEAN;
BEGIN
  n := 0; l := a; WHILE l # NIL DO INC(n); l := l.next END;
  NEW(used, n + 1);
  FOR i := 0 TO n DO used[i] := FALSE END;
  WHILE b # NIL DO
    l := a; i := 0; found := FALSE;
    WHILE (l # NIL) & ~found DO
      IF ~used[i] & Ropes.Equal(l.s, b.s) THEN used[i] := TRUE; found := TRUE END;
      l := l.next; INC(i)
    END;
    b := b.next
  END;
  r := A.NewAttr(NIL); l := a; i := 0;
  WHILE l # NIL DO
    IF ~used[i] THEN A.AddClass(r, l.s) END;
    l := l.next; INC(i)
  END;
  RETURN r.classes
END MinusClasses;

(* a \\ b for pairs *)
PROCEDURE MinusKVs(a, b: A.KeyVal): A.KeyVal;
  VAR r: A.Attr; l: A.KeyVal; used: POINTER TO ARRAY OF BOOLEAN; n, i: LONGINT;
    found: BOOLEAN;
BEGIN
  n := 0; l := a; WHILE l # NIL DO INC(n); l := l.next END;
  NEW(used, n + 1);
  FOR i := 0 TO n DO used[i] := FALSE END;
  WHILE b # NIL DO
    l := a; i := 0; found := FALSE;
    WHILE (l # NIL) & ~found DO
      IF ~used[i] & Ropes.Equal(l.key, b.key) & Ropes.Equal(l.value, b.value) THEN
        used[i] := TRUE; found := TRUE
      END;
      l := l.next; INC(i)
    END;
    b := b.next
  END;
  r := A.NewAttr(NIL); l := a; i := 0;
  WHILE l # NIL DO
    IF ~used[i] THEN A.AddKeyVal(r, l.key, l.value) END;
    l := l.next; INC(i)
  END;
  RETURN r.attrs
END MinusKVs;

PROCEDURE EqClasses(a, b: A.StrList): BOOLEAN;
BEGIN
  WHILE (a # NIL) & (b # NIL) & Ropes.Equal(a.s, b.s) DO a := a.next; b := b.next END;
  RETURN (a = NIL) & (b = NIL)
END EqClasses;

PROCEDURE EqKVs(a, b: A.KeyVal): BOOLEAN;
BEGIN
  WHILE (a # NIL) & (b # NIL) & Ropes.Equal(a.key, b.key) & Ropes.Equal(a.value, b.value) DO
    a := a.next; b := b.next
  END;
  RETURN (a = NIL) & (b = NIL)
END EqKVs;

PROCEDURE IsSpace(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch >= 9X) & (ch <= 0DX)
END IsSpace;

(* The CSS rules of a style attribute's value s, as pandoc's
   cssAttributes parses them: NIL if they do not parse *)
PROCEDURE CssRules(s: Rope): A.KeyVal;
  VAR b: Buf; n, i, ps, vs: LONGINT; a: A.Attr; p, v: Rope; first: BOOLEAN;
BEGIN
  b := ToBuf(s); n := Len(s); i := 0; a := A.NewAttr(NIL); first := TRUE;
  LOOP
    IF (i >= n) OR (b[i] = ":") THEN
      IF first THEN RETURN NIL END;
      EXIT
    END;
    ps := i;
    WHILE (i < n) & (b[i] # ":") DO INC(i) END;
    IF i >= n THEN RETURN NIL END;
    p := Ropes.Trim(Ropes.FromSubchars(b^, ps, i - ps));
    INC(i); vs := i;
    WHILE (i < n) & (b[i] # ":") & (b[i] # ";") DO INC(i) END;
    IF i = vs THEN RETURN NIL END;
    v := Ropes.Trim(Ropes.FromSubchars(b^, vs, i - vs));
    IF (i < n) & (b[i] = ";") THEN INC(i) END;
    WHILE (i < n) & IsSpace(b[i]) DO INC(i) END;
    A.AddKeyVal(a, p, v); first := FALSE
  END;
  RETURN a.attrs
END CssRules;

(* kvs with the CSS property key: value added to its style
   (htmlAddStyle) *)
PROCEDURE AddStyle(key, value: ARRAY OF CHAR; kvs: A.KeyVal): A.KeyVal;
  VAR p, rules, q: A.KeyVal; a: A.Attr; style: Rope; found: BOOLEAN;
BEGIN
  p := kvs;
  WHILE (p # NIL) & ~Eq(p.key, "style") DO p := p.next END;
  IF p = NIL THEN
    RETURN NewKV(R("style"), CatS(CatS(CatS(R(key), ": "), value), ";"), kvs)
  END;
  rules := CssRules(p.value); q := rules; found := FALSE;
  WHILE (q # NIL) & ~found DO
    IF Eq(q.key, key) THEN q.value := R(value); found := TRUE END;
    q := q.next
  END;
  IF ~found THEN rules := NewKV(R(key), R(value), rules) END;
  style := NIL; q := rules;
  WHILE q # NIL DO
    IF style # NIL THEN style := CatS(style, " ") END;
    style := CatS(Cat(CatS(Cat(style, q.key), ": "), q.value), ";");
    q := q.next
  END;
  a := A.NewAttr(NIL); q := kvs;
  WHILE q # NIL DO
    IF q = p THEN A.AddKeyVal(a, q.key, style) ELSE A.AddKeyVal(a, q.key, q.value) END;
    q := q.next
  END;
  RETURN a.attrs
END AddStyle;

(* Inlines *)

PROCEDURE^ Inlines(i: A.Inline): Rope;
PROCEDURE^ Blocks(b: A.Block): Rope;
PROCEDURE^ Block(b: A.Block; VAR empty: BOOLEAN): Rope;

PROCEDURE IsHtml(format: Rope): BOOLEAN;
BEGIN
  RETURN Eq(format, "html") OR Eq(format, "html5") OR Eq(format, "html4")
END IsHtml;

PROCEDURE CslDivClass(a: A.Attr): BOOLEAN;
  VAR c: A.StrList;
BEGIN
  IF (a = NIL) OR (Len(a.id) > 0) OR (a.attrs # NIL) OR (a.classes = NIL)
     OR (a.classes.next # NIL) THEN
    RETURN FALSE
  END;
  c := a.classes;
  RETURN Eq(c.s, "csl-block") OR Eq(c.s, "csl-left-margin")
    OR Eq(c.s, "csl-right-inline") OR Eq(c.s, "csl-indent")
END CslDivClass;

(* The tag a span's class c stands for, or "" *)
PROCEDURE SpanTag(c: Rope; VAR open, close: ARRAY OF CHAR);
BEGIN
  IF Eq(c, "kbd") OR Eq(c, "mark") OR Eq(c, "dfn") OR Eq(c, "abbr") THEN
    Ropes.ToString(Cat(R("<"), c), open);
    Ropes.ToString(CatS(Cat(R("</"), c), ">"), close)
  ELSIF Eq(c, "smallcaps") THEN COPY('<span class="smallcaps"', open); COPY("</span>", close)
  ELSIF Eq(c, "underline") THEN COPY("<u", open); COPY("</u>", close)
  ELSE open[0] := 0X; close[0] := 0X
  END
END SpanTag;

PROCEDURE Span(a: A.Attr; content: A.Inline): Rope;
  VAR c, cs, classes: A.StrList; kvs: A.KeyVal; styles, outerOpen, outerClose,
    innerOpen, innerClose, h: Rope; open, close: ARRAY 32 OF CHAR;
    found: BOOLEAN;
BEGIN
  IF CslDivClass(a) THEN
    RETURN CatS(Cat(CatS(Cat(R('<div class="'), a.classes.s), '">'), Inlines(content)), "</div>")
  END;
  classes := Classes(a); kvs := KVs(a);
  styles := NIL;
  IF HasStr(classes, "csl-no-emph") THEN styles := CatS(styles, "font-style:normal;") END;
  IF HasStr(classes, "csl-no-strong") THEN styles := CatS(styles, "font-weight:normal;") END;
  IF HasStr(classes, "csl-no-smallcaps") THEN styles := CatS(styles, "font-variant:normal;") END;
  IF styles # NIL THEN kvs := NewKV(R("style"), styles, kvs) END;
  found := FALSE; cs := NIL; innerOpen := NIL; innerClose := NIL;
  outerOpen := NIL; outerClose := NIL;
  c := classes;
  WHILE c # NIL DO
    SpanTag(c.s, open, close);
    IF open[0] # 0X THEN
      IF ~found THEN outerOpen := R(open); outerClose := R(close); found := TRUE
      ELSE innerOpen := CatS(CatS(innerOpen, open), ">"); innerClose := Cat(R(close), innerClose)
      END
    ELSIF found THEN cs := NewStrL(c.s, cs)
    END;
    c := c.next
  END;
  h := Inlines(content);
  IF found THEN
    RETURN Cat(Cat(Cat(CatS(Cat(outerOpen, AttrStr(Id(a), cs, kvs)), ">"), innerOpen),
      Cat(h, innerClose)), outerClose)
  END;
  classes := WithoutClass(WithoutClass(WithoutClass(classes, "csl-no-emph"),
    "csl-no-strong"), "csl-no-smallcaps");
  RETURN CatS(Cat(CatS(Cat(R("<span"), AttrStr(Id(a), classes, kvs)), ">"), h), "</span>")
END Span;

(* Element: <tag>content</tag> *)
PROCEDURE Wrap(tag: ARRAY OF CHAR; content: Rope): Rope;
BEGIN
  RETURN CatS(CatS(CatS(Cat(CatS(CatS(R("<"), tag), ">"), content), "</"), tag), ">")
END Wrap;

(* Highlighted code (Phase 24.5; decision 46) *)

(* out with the code text r escaped (as a block's text, else as Text
   does), between <b> and </b> if kind is
   PdCode.Reserved, <i> and </i> if it is PdCode.Comment *)
PROCEDURE CodePiece(out, r: Rope; kind: INTEGER; block: BOOLEAN): Rope;
BEGIN
  IF block THEN r := Escape(r, TRUE, FALSE) ELSE r := Text(r) END;
  IF kind = PdCode.Reserved THEN RETURN CatS(Cat(CatS(out, "<b>"), r), "</b>")
  ELSIF kind = PdCode.Comment THEN RETURN CatS(Cat(CatS(out, "<i>"), r), "</i>")
  END;
  RETURN Cat(out, r)
END CodePiece;

(* The code text escaped, its reserved words in <b> and its comments in
   <i>, as lang's scanner finds them; all plain if lang is NIL *)
PROCEDURE Highlight(text: Rope; lang: PdCode.Language; block: BOOLEAN): Rope;
  VAR sp: PdCode.Span; out: Rope;
BEGIN
  IF lang = NIL THEN sp := NIL ELSE sp := PdCode.Scan(lang, text) END;
  IF sp = NIL THEN RETURN CodePiece(NIL, text, PdCode.Plain, block) END;
  out := NIL;
  WHILE sp # NIL DO
    out := CodePiece(out, Ropes.Substring(text, sp.start, sp.len), sp.kind, block);
    sp := sp.next
  END;
  RETURN out
END Highlight;

(* out with n spaces, in a <span class="pd-gap"> if n > 0 *)
PROCEDURE Gap(out: Rope; n: LONGINT): Rope;
BEGIN
  IF n > 0 THEN
    out := CatS(out, '<span class="pd-gap">');
    WHILE n > 0 DO out := CatS(out, " "); DEC(n) END;
    out := CatS(out, "</span>")
  END;
  RETURN out
END Gap;

(* The code text laid out in the fixed alignment (decisions 32, 33 and
   46): a line's indentation, and each segment before another, in an
   inline block that the template's CSS makes at least --pd-w columns
   wide (the distance to the next segment's column) and the text and
   the least gap wide, so that each segment starts at its column if the
   text before it leaves room. The spaces before a segment, in the text
   as they were, are in a <span class="pd-gap"> that the CSS gives no
   width, so that the text copied from a browser is the code's. *)
PROCEDURE AlignedCode(text: Rope; lang: PdCode.Language): Rope;
  VAR b: PdCodeAlign.Block; l: PdCodeAlign.Line; s: PdCodeAlign.Segment;
    p: PdCodeAlign.Piece; out: Rope; sp: PdCode.Span;
BEGIN
  IF lang = NIL THEN sp := NIL ELSE sp := PdCode.Scan(lang, text) END;
  b := PdCodeAlign.Layout(text, sp);
  out := NIL; l := b.lines;
  WHILE l # NIL DO
    s := l.segs;
    IF (s # NIL) & (s.col > 0) THEN
      out := CatS(Cat(CatS(out, '<span class="pd-ind" style="--pd-w:'), Sh.IntRope(s.col)), '">');
      out := CatS(Gap(out, s.gap), "</span>")
    END;
    WHILE s # NIL DO
      IF s.next # NIL THEN
        out := CatS(Cat(CatS(out, '<span class="pd-seg" style="--pd-w:'), Sh.IntRope(s.next.col - s.col)), '">')
      END;
      IF s # l.segs THEN out := Gap(out, s.gap) END;
      p := s.pieces;
      WHILE p # NIL DO out := CodePiece(out, p.text, p.kind, TRUE); p := p.next END;
      IF s.next # NIL THEN out := CatS(out, "</span>") END;
      s := s.next
    END;
    out := Gap(out, l.trail);
    l := l.next;
    IF l # NIL THEN out := Cat(out, nl) END
  END;
  RETURN out
END AlignedCode;

(* A code block: in the mono style, highlighted in its <code>; in the
   proportional style, in a <pre> with the class pd-proportional, that
   the template's CSS sets in the body font, aligned (its <code> with
   the class pd-aligned) unless --code-align is none, with elastic and
   hybrid as fixed (decision 46) *)
PROCEDURE CodeBlock(c: A.CodeBlk): Rope;
  VAR lang: PdCode.Language; style: INTEGER; attr, code, body: Rope; cls: A.Attr;
    l: A.StrList;
BEGIN
  style := Sh.CodeStyle(c.attr, lang);
  IF style = Sh.CodeProportional THEN
    proportionalSeen := TRUE;
    cls := A.NewAttr(NIL);
    IF c.attr # NIL THEN
      l := c.attr.classes;
      WHILE l # NIL DO A.AddClass(cls, l.s); l := l.next END
    END;
    A.AddClass(cls, R("pd-proportional"));
    attr := AttrStr(Id(c.attr), cls.classes, KVs(c.attr));
    IF Sh.codeAlign = PdCodeAlign.None THEN
      code := R("<code>"); body := Highlight(c.text, lang, TRUE)
    ELSE
      code := R('<code class="pd-aligned">'); body := AlignedCode(c.text, lang)
    END
  ELSE
    IF style = Sh.CodeNone THEN lang := NIL END;
    attr := AttrOf(c.attr); code := R("<code>"); body := Highlight(c.text, lang, TRUE)
  END;
  RETURN CatS(Cat(Cat(CatS(Cat(R("<pre"), attr), ">"), code), body), "</code></pre>")
END CodeBlock;

(* Inline code: highlighted, in either style, if it has a language
   (decision 38) *)
PROCEDURE Code(i: A.CodeInl): Rope;
  VAR classes: A.StrList; tag: ARRAY 8 OF CHAR; lang: PdCode.Language; text: Rope;
BEGIN
  IF Sh.CodeStyle(i.attr, lang) = Sh.CodeNone THEN lang := NIL END;
  IF lang = NIL THEN text := Text(i.text) ELSE text := Highlight(i.text, lang, FALSE) END;
  classes := Classes(i.attr);
  IF HasStr(classes, "sample") THEN tag := "samp"; classes := DeleteClass(classes, "sample")
  ELSIF HasStr(classes, "variable") THEN tag := "var"; classes := DeleteClass(classes, "variable")
  ELSE tag := "code"
  END;
  RETURN CatS(CatS(CatS(Cat(CatS(Cat(CatS(R("<"), tag), AttrStr(Id(i.attr), classes, KVs(i.attr))), ">"),
    text), "</"), tag), ">")
END Code;

(* The url of a link to #x with the identifier prefix *)
PROCEDURE Href(url: Rope): Rope;
BEGIN
  IF (Len(url) > 0) & (Ropes.Fetch(url, 0) = "#") THEN
    RETURN Cat(Cat(R("#"), idPrefix), Ropes.Substring(url, 1, Len(url) - 1))
  END;
  RETURN url
END Href;

PROCEDURE Link(i: A.LinkInl): Rope;
  VAR text, r: Rope; kvs: A.KeyVal;
BEGIN
  IF inLink > 0 THEN RETURN Span(i.attr, i.content) END;
  INC(inLink); text := Inlines(i.content); DEC(inLink);
  kvs := KVs(i.attr);
  IF (inCite > 0) & Sh.StartsWith(i.url, "#ref-") THEN
    kvs := NewKV(R("role"), R("doc-biblioref"), kvs)
  END;
  IF Sh.StartsWith(i.url, "mailto:") THEN
    r := PairS(R("<a"), "href", i.url)
  ELSE
    r := PairS(R("<a"), "href", Href(i.url))
  END;
  r := Cat(r, AttrStr(Id(i.attr), Classes(i.attr), kvs));
  IF ~Sh.StartsWith(i.url, "mailto:") & (Len(i.title) > 0) THEN
    r := PairS(r, "title", i.title)
  END;
  RETURN CatS(Cat(CatS(r, ">"), text), "</a>")
END Link;

(* Dimensions of images *)

PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "0") & (ch <= "9")
END IsDigit;


(* int.frac as Haskell's show writes a Double *)
PROCEDURE ShowDouble(int, frac: Rope): Rope;
  VAR digits: Rope; b: Buf; n, i, j, first, last, exp: LONGINT; r: Rope;
BEGIN
  digits := Cat(int, frac); b := ToBuf(digits); n := Len(digits);
  first := 0; WHILE (first < n) & (b[first] = "0") DO INC(first) END;
  IF first = n THEN RETURN R("0.0") END;
  last := n - 1; WHILE b[last] = "0" DO DEC(last) END;
  exp := Len(int) - first; (* the value is 0.d1d2... * 10^exp *)
  IF (exp >= 0) & (exp <= 7) THEN
    IF exp = 0 THEN r := R("0.")
    ELSE
      r := NIL;
      FOR i := first TO first + exp - 1 DO
        IF i <= last THEN r := Ropes.AppendChar(r, b[i]) ELSE r := Ropes.AppendChar(r, "0") END
      END;
      r := CatS(r, ".")
    END;
    j := first + exp;
    IF j > last THEN r := CatS(r, "0")
    ELSE FOR i := j TO last DO r := Ropes.AppendChar(r, b[i]) END
    END;
    IF exp < 7 THEN RETURN r END
  END;
  IF (exp = 0) THEN RETURN r END;
  r := Ropes.FromChar(b[first]); r := CatS(r, ".");
  IF first = last THEN r := CatS(r, "0")
  ELSE FOR i := first + 1 TO last DO r := Ropes.AppendChar(r, b[i]) END
  END;
  RETURN Cat(CatS(r, "e"), Sh.IntRope(exp - 1))
END ShowDouble;

(* Adds to a the attribute for the dimension name (width or height)
   in kvs, as pandoc's dimensionsToAttrList *)
PROCEDURE AddDimension(a: A.Attr; kvs: A.KeyVal; name: ARRAY OF CHAR);
  VAR found: BOOLEAN; v, int, frac, unit: Rope; at: A.Attr;
BEGIN
  at := A.NewAttr(NIL); at.attrs := kvs;
  v := A.GetKeyVal(at, name, found);
  IF ~found OR ~Sh.NumUnit(v, int, frac, unit) THEN RETURN END;
  IF (Len(unit) = 0) OR Eq(unit, "px") THEN
    A.AddKeyVal(a, R(name), Sh.StripZeros(int))
  ELSIF Eq(unit, "%") THEN
    A.AddKeyVal(a, R("style"), CatS(Cat(CatS(R(name), ":"), ShowDouble(int, frac)), "%"))
  ELSIF Eq(unit, "cm") OR Eq(unit, "mm") OR Eq(unit, "in") OR Eq(unit, "inch")
     OR Eq(unit, "pt") OR Eq(unit, "pc") OR Eq(unit, "em") THEN
    IF Eq(unit, "inch") THEN unit := R("in") END;
    A.AddKeyVal(a, R("style"), Cat(Cat(CatS(R(name), ":"), Sh.ShowFl(int, frac)), unit))
  END
END AddDimension;

(* The attributes of an image: its own without width and height, the
   dimensions, its styles joined into one, first *)
PROCEDURE ImgAttrs(attr: A.Attr): Rope;
  VAR a, b: A.Attr; kv: A.KeyVal; style: Rope; hasStyle: BOOLEAN;
BEGIN
  a := A.NewAttr(NIL); kv := KVs(attr);
  WHILE kv # NIL DO
    IF ~Eq(kv.key, "width") & ~Eq(kv.key, "height") THEN A.AddKeyVal(a, kv.key, kv.value) END;
    kv := kv.next
  END;
  AddDimension(a, KVs(attr), "width"); AddDimension(a, KVs(attr), "height");
  style := NIL; hasStyle := FALSE; b := A.NewAttr(NIL); kv := a.attrs;
  WHILE kv # NIL DO
    IF Eq(kv.key, "style") THEN
      IF hasStyle THEN style := CatS(style, ";") END;
      style := Cat(style, kv.value); hasStyle := TRUE
    ELSE A.AddKeyVal(b, kv.key, kv.value)
    END;
    kv := kv.next
  END;
  IF hasStyle THEN b.attrs := NewKV(R("style"), style, b.attrs) END;
  RETURN AttrStr(Id(attr), Classes(attr), b.attrs)
END ImgAttrs;

(* The category of the medium at url: PdMime's, or Image for a data:
   URI of an image and Other for one of another type *)
PROCEDURE MediaCategory(url: Rope): INTEGER;
  VAR b: Buf; n, i, slash, dot: LONGINT; ext: ARRAY 32 OF CHAR; t: Rope;
BEGIN
  IF Sh.StartsWith(url, "data:") THEN
    i := Ropes.IndexChar(url, "/", 5);
    IF i < 0 THEN i := Len(url) END;
    t := Ropes.Substring(url, 5, i - 5);
    IF Eq(t, "image") THEN RETURN PdMime.Image
    ELSIF Eq(t, "video") THEN RETURN PdMime.Video
    ELSIF Eq(t, "audio") THEN RETURN PdMime.Audio
    END;
    RETURN PdMime.Other
  END;
  b := ToBuf(url); n := Len(url);
  IF (n >= 3) & (b[n - 3] = ".") & (b[n - 2] = "g") & (b[n - 1] = "z") THEN DEC(n, 3) END;
  i := 0; WHILE (i < n) & (b[i] # "?") & (b[i] # "#") DO INC(i) END;
  n := i;
  slash := -1; dot := -1;
  FOR i := 0 TO n - 1 DO
    IF b[i] = "/" THEN slash := i; dot := -1 ELSIF b[i] = "." THEN dot := i END
  END;
  IF (dot < 0) OR (dot = slash + 1) & FALSE OR (n - dot - 1 >= LEN(ext)) THEN
    RETURN PdMime.Unknown
  END;
  FOR i := dot + 1 TO n - 1 DO ext[i - dot - 1] := b[i] END;
  ext[n - dot - 1] := 0X;
  RETURN PdMime.Category(ext)
END MediaCategory;

PROCEDURE Image(i: A.LinkInl): Rope;
  VAR r, alt: Rope; cat: INTEGER; found: BOOLEAN; tag: ARRAY 8 OF CHAR;
BEGIN
  alt := Sh.Stringify(i.content);
  r := PairS(NIL, "src", i.url);
  IF Len(i.title) > 0 THEN r := PairS(r, "title", i.title) END;
  r := Cat(r, ImgAttrs(i.attr));
  cat := MediaCategory(i.url);
  IF (cat = PdMime.Video) OR (cat = PdMime.Audio) THEN
    IF cat = PdMime.Video THEN tag := "video" ELSE tag := "audio" END;
    IF i.content = NIL THEN
      IF cat = PdMime.Video THEN alt := R("Video") ELSE alt := R("Audio") END
    END;
    RETURN CatS(CatS(CatS(Cat(CatS(PairS(CatS(Cat(CatS(R("<"), tag), r), ' controls=""><a'),
      "href", i.url), ">"), Text(alt)), "</a></"), tag), ">")
  ELSIF cat = PdMime.Other THEN
    RETURN CatS(Cat(R("<embed"), r), " />")
  END;
  IF i.content # NIL THEN
    alt := A.GetKeyVal(i.attr, "alt", found);
    IF ~found THEN r := PairS(r, "alt", Sh.Stringify(i.content)) END
  END;
  RETURN CatS(Cat(R("<img"), r), " />")
END Image;

PROCEDURE Note(i: A.NoteInl): Rope;
  VAR n, contents: Rope; last, b, nb: A.Block; link: A.Inline; la: A.Attr;
    ib: A.InlinesBlk; l: A.Inlines; empty: BOOLEAN;
BEGIN
  n := Sh.IntRope(noteCount + 1);
  contents := NIL;
  IF i.blocks # NIL THEN
    la := A.NewAttr(NIL); A.AddClass(la, R("footnote-back"));
    A.AddKeyVal(la, R("role"), R("doc-backlink"));
    link := A.NewLink(A.Link, la, A.NewStr(R("↩")), Cat(R("#fnref"), n), NIL);
    last := A.LastBlock(i.blocks);
    NEW(ib); ib.next := NIL;
    IF (last.kind = A.Para) OR (last.kind = A.Plain) THEN
      ib.kind := last.kind;
      A.InitInlines(l); A.AddInline(l, A.CopyInlines(last(A.InlinesBlk).inlines));
      A.AddInline(l, link); ib.inlines := l.first
    ELSE
      ib.kind := A.Plain; ib.inlines := link; last := NIL
    END;
    b := i.blocks;
    WHILE b # last DO
      nb := b.next; b.next := NIL;
      contents := Cat(contents, Block(b, empty));
      b.next := nb;
      IF ~empty THEN contents := Cat(contents, nl) END;
      b := nb
    END;
    contents := Cat(contents, Block(ib, empty))
  END;
  INC(noteCount);
  notes := Cat(notes, CatL(Cat(CatS(PairS(R("<li"), "id", Cat(idPrefix, Cat(R("fn"), n))), ">"), contents), "</li>"));
  RETURN CatS(Cat(CatS(PairS(PairS(CatS(PairS(R("<a"), "href", Cat(Cat(R("#"), idPrefix), Cat(R("fn"), n))),
    ' class="footnote-ref"'), "id", Cat(idPrefix, Cat(R("fnref"), n))), "role", R("doc-noteref")),
    "><sup>"), n), "</sup></a>")
END Note;

PROCEDURE Inline(i: A.Inline): Rope;
  VAR r: Rope; c: A.Citation; f: A.RawInl;
BEGIN
  r := NIL;
  CASE i.kind OF
    A.Str: r := Text(i(A.StrInl).text)
  | A.Space: r := R(" ")
  | A.SoftBreak: IF preserve THEN r := nl ELSE r := R(" ") END
  | A.LineBreak: r := CatL(NIL, "<br />")
  | A.Emph: r := Wrap("em", Inlines(i(A.ContInl).content))
  | A.Underline: r := Wrap("u", Inlines(i(A.ContInl).content))
  | A.Strong: r := Wrap("strong", Inlines(i(A.ContInl).content))
  | A.Strikeout: r := Wrap("del", Inlines(i(A.ContInl).content))
  | A.Superscript: r := Wrap("sup", Inlines(i(A.ContInl).content))
  | A.Subscript: r := Wrap("sub", Inlines(i(A.ContInl).content))
  | A.SmallCaps:
    r := CatS(Cat(R('<span class="smallcaps">'), Inlines(i(A.ContInl).content)), "</span>")
  | A.Quoted:
    IF i(A.QuotedInl).quote = A.DoubleQuote THEN
      r := CatS(Cat(R("“"), Inlines(i(A.ContInl).content)), "”")
    ELSE
      r := CatS(Cat(R("‘"), Inlines(i(A.ContInl).content)), "’")
    END
  | A.Cite:
    c := i(A.CiteInl).citations;
    WHILE c # NIL DO
      r := Cat(r, c.id); IF c.next # NIL THEN r := CatS(r, " ") END;
      c := c.next
    END;
    INC(inCite);
    r := CatS(Cat(CatS(PairS(R('<span class="citation"'), "data-cites", r), ">"),
      Inlines(i(A.ContInl).content)), "</span>");
    DEC(inCite)
  | A.Code: r := Code(i(A.CodeInl))
  | A.Math:
    mathSeen := TRUE;
    IF i(A.MathInl).math = A.InlineMath THEN r := R('<span class="math inline">')
    ELSE r := R('<span class="math display">')
    END;
    r := CatS(Cat(r, Escape(i(A.MathInl).text, FALSE, FALSE)), "</span>")
  | A.RawInline:
    f := i(A.RawInl);
    IF IsHtml(f.format) THEN r := f.text END
  | A.Link: r := Link(i(A.LinkInl))
  | A.Image: r := Image(i(A.LinkInl))
  | A.Note: r := Note(i(A.NoteInl))
  | A.Span: r := Span(i(A.SpanInl).attr, i(A.SpanInl).content)
  END;
  RETURN r
END Inline;

PROCEDURE Inlines(i: A.Inline): Rope;
  VAR r: Rope;
BEGIN
  r := NIL;
  WHILE i # NIL DO r := Cat(r, Inline(i)); i := i.next END;
  RETURN r
END Inlines;

(* Blocks *)

PROCEDURE Header(h: A.HeaderBlk): Rope;
  VAR contents, num: Rope; found: BOOLEAN; classes: A.StrList; tag: ARRAY 4 OF CHAR;
BEGIN
  contents := Inlines(h.inlines);
  num := A.GetKeyVal(h.attr, "number", found);
  IF numberSections & found & (Len(num) > 0) & ~A.HasClass(h.attr, "unnumbered") THEN
    contents := Cat(CatS(Cat(R('<span class="header-section-number">'), num), "</span> "), contents)
  END;
  classes := Classes(h.attr);
  IF h.level > 6 THEN classes := NewStrL(R("heading"), classes); tag := "p"
  ELSIF h.level < 1 THEN tag := "p" (* from incrementSection *)
  ELSE tag := "h0"; tag[1] := CHR(ORD("0") + h.level)
  END;
  RETURN CatS(CatS(CatS(Cat(CatS(Cat(CatS(R("<"), tag), AttrStr(Id(h.attr), classes, KVs(h.attr))), ">"),
    contents), "</"), tag), ">")
END Header;

(* A Div with the class section, first, and a header first *)
PROCEDURE SectionDiv(d: A.DivBlk): Rope;
  VAR h: A.HeaderBlk; header, inner, r: Rope; dclasses, hclasses: A.StrList;
    dkvs, hkvs: A.KeyVal; ident, hident: Rope; empty: BOOLEAN;
BEGIN
  h := d.blocks(A.HeaderBlk);
  IF (h.inlines # NIL) & (h.inlines.next = NIL) & (h.inlines.kind = A.Str)
     & Eq(h.inlines(A.StrInl).text, 0X) THEN
    header := NIL
  ELSE header := Block(h, empty)
  END;
  ident := d.attr.id; dclasses := d.attr.classes.next; dkvs := d.attr.attrs;
  hident := Id(h.attr); hclasses := Classes(h.attr); hkvs := KVs(h.attr);
  inner := NIL;
  IF h.next # NIL THEN inner := Blocks(h.next) END;
  IF (Len(hident) > 0) & (Len(ident) > 0) & ~Ropes.Equal(hident, ident)
     OR ~EqClasses(hclasses, dclasses) OR ~EqKVs(hkvs, dkvs) THEN
    r := CatL(Cat(R("<section"), AttrStr(ident, dclasses, dkvs)), ">");
    r := Cat(Cat(r, header), nl);
    IF h.next # NIL THEN r := Cat(Cat(r, inner), nl) END;
    RETURN CatS(r, "</section>")
  END;
  r := AddAttrs(header, AttrStr(ident, MinusClasses(dclasses, hclasses), MinusKVs(dkvs, hkvs)));
  IF h.next # NIL THEN r := Cat(Cat(r, nl), inner) END;
  RETURN r
END SectionDiv;

(* Whether s is an integer, as Haskell's read reads an Int *)
PROCEDURE IsInt(s: Rope): BOOLEAN;
  VAR i, n: LONGINT;
BEGIN
  n := Len(s); i := 0;
  IF (n > 0) & (Ropes.Fetch(s, 0) = "-") THEN i := 1 END;
  IF i >= n THEN RETURN FALSE END;
  WHILE (i < n) & IsDigit(Ropes.Fetch(s, i)) DO INC(i) END;
  RETURN i = n
END IsInt;

PROCEDURE Div(d: A.DivBlk): Rope;
  VAR found, csl, entry, column, empty: BOOLEAN; v, contents: Rope; kv: A.KeyVal;
    a: A.Attr; b: A.Block; classes: A.StrList; tag: ARRAY 8 OF CHAR;
BEGIN
  IF (d.attr # NIL) & (d.attr.classes # NIL) & Eq(d.attr.classes.s, "section")
     & (d.blocks # NIL) & (d.blocks IS A.HeaderBlk) THEN
    RETURN SectionDiv(d)
  END;
  v := A.GetKeyVal(d.attr, "wrapper", found);
  IF found & Eq(v, "1") & (d.blocks # NIL) & (d.blocks.next = NIL) THEN
    RETURN AddAttrs(Block(d.blocks, empty),
      AttrStr(Id(d.attr), Classes(d.attr), WithoutKey(KVs(d.attr), "wrapper")))
  END;
  csl := Eq(Id(d.attr), "refs") OR A.HasClass(d.attr, "csl-bib-body");
  IF csl THEN
    cslSeen := TRUE;
    v := A.GetKeyVal(d.attr, "entry-spacing", found);
    cslHasSpacing := found & IsInt(v);
    IF cslHasSpacing THEN cslSpacing := Ropes.Trim(v) END
  END;
  entry := A.HasClass(d.attr, "csl-entry");
  column := A.HasClass(d.attr, "column");
  a := A.NewAttr(NIL); kv := KVs(d.attr);
  WHILE kv # NIL DO
    IF ~Eq(kv.key, "width") OR ~column THEN A.AddKeyVal(a, kv.key, kv.value) END;
    kv := kv.next
  END;
  IF column THEN
    kv := KVs(d.attr);
    WHILE kv # NIL DO
      IF Eq(kv.key, "width") THEN
        A.AddKeyVal(a, R("style"), CatS(Cat(R("width:"), kv.value), ";"))
      END;
      kv := kv.next
    END
  END;
  IF csl THEN A.AddKeyVal(a, R("role"), R("list")) END;
  IF entry THEN A.AddKeyVal(a, R("role"), R("listitem")) END;
  IF entry THEN INC(inCslEntry) END;
  IF A.HasClass(d.attr, "columns") THEN
    contents := NIL; b := d.blocks;
    WHILE b # NIL DO contents := Cat(contents, Block(b, empty)); b := b.next END
  ELSE contents := Blocks(d.blocks)
  END;
  IF entry THEN DEC(inCslEntry) END;
  contents := Cat(Cat(nl, contents), nl);
  IF A.HasClass(d.attr, "notes") THEN
    RETURN CatS(Cat(CatS(Cat(R("<div"), AttrOf(d.attr)), ">"), contents), "</div>")
  END;
  classes := Classes(d.attr);
  IF HasStr(classes, "section") THEN tag := "section"; classes := WithoutClass(classes, "section")
  ELSE tag := "div"
  END;
  RETURN CatS(CatS(CatS(Cat(CatS(Cat(CatS(R("<"), tag), AttrStr(Id(d.attr), classes, a.attrs)), ">"),
    contents), "</"), tag), ">")
END Div;

(* A task list item's first block: a Plain or Para starting with a
   ballot box and a space *)
PROCEDURE TaskItem(b: A.Block; VAR checked: BOOLEAN): BOOLEAN;
  VAR i: A.Inline;
BEGIN
  IF (b = NIL) OR ((b.kind # A.Plain) & (b.kind # A.Para)) THEN RETURN FALSE END;
  i := b(A.InlinesBlk).inlines;
  IF (i = NIL) OR (i.kind # A.Str) OR (i.next = NIL) OR (i.next.kind # A.Space) THEN
    RETURN FALSE
  END;
  checked := Eq(i(A.StrInl).text, "☒");
  RETURN checked OR Eq(i(A.StrInl).text, "☐")
END TaskItem;

PROCEDURE ListItem(b: A.Block): Rope;
  VAR checked: BOOLEAN; r: Rope;
BEGIN
  IF ~TaskItem(b, checked) THEN RETURN Blocks(b) END;
  r := R('<label><input type="checkbox"');
  IF checked THEN r := CatS(r, ' checked=""') END;
  r := CatS(Cat(CatS(r, " />"), Inlines(b(A.InlinesBlk).inlines.next.next)), "</label>");
  IF b.kind = A.Para THEN r := Wrap("p", r) END;
  IF b.next # NIL THEN r := Cat(Cat(r, nl), Blocks(b.next)) END;
  RETURN r
END ListItem;

PROCEDURE List(open, close: Rope; items: A.BlockList): Rope;
  VAR r: Rope;
BEGIN
  r := open;
  WHILE items # NIL DO
    r := CatS(Cat(CatS(Cat(r, nl), "<li>"), ListItem(items.blocks)), "</li>");
    items := items.next
  END;
  RETURN Cat(Cat(r, nl), close)
END List;

PROCEDURE BulletList(l: A.ListBlk): Rope;
  VAR it: A.BlockList; all, checked: BOOLEAN;
BEGIN
  all := TRUE; it := l.items;
  WHILE (it # NIL) & all DO all := TaskItem(it.blocks, checked); it := it.next END;
  IF all THEN RETURN List(R('<ul class="task-list">'), R("</ul>"), l.items) END;
  RETURN List(R("<ul>"), R("</ul>"), l.items)
END BulletList;

PROCEDURE OrderedList(l: A.OrderedBlk): Rope;
  VAR open: Rope;
BEGIN
  open := R("<ol");
  IF l.start # 1 THEN open := PairS(open, "start", Sh.IntRope(l.start)) END;
  IF l.style = A.Example THEN open := CatS(open, ' class="example"') END;
  CASE l.style OF
    A.DefaultStyle:
  | A.Example, A.Decimal: open := CatS(open, ' type="1"')
  | A.LowerAlpha: open := CatS(open, ' type="a"')
  | A.UpperAlpha: open := CatS(open, ' type="A"')
  | A.LowerRoman: open := CatS(open, ' type="i"')
  | A.UpperRoman: open := CatS(open, ' type="I"')
  END;
  RETURN List(CatS(open, ">"), R("</ol>"), l.items)
END OrderedList;

PROCEDURE DefinitionList(l: A.DefListBlk): Rope;
  VAR r: Rope; it: A.DefItem; d: A.BlockList;
BEGIN
  r := R("<dl>"); it := l.items;
  WHILE it # NIL DO
    r := Cat(Cat(Cat(r, nl), Wrap("dt", Inlines(it.term))), nl);
    d := it.defs;
    WHILE d # NIL DO
      r := Cat(r, Wrap("dd", Cat(Cat(nl, Blocks(d.blocks)), nl)));
      IF d.next # NIL THEN r := Cat(r, nl) END;
      d := d.next
    END;
    it := it.next
  END;
  RETURN CatS(Cat(r, nl), "</dl>")
END DefinitionList;

PROCEDURE Figure(f: A.FigureBlk): Rope;
  VAR r, capt, alt: Rope; i: A.Inline; found, hidden: BOOLEAN;
BEGIN
  r := Cat(Cat(CatS(Cat(R("<figure"), AttrOf(f.attr)), ">"), nl), Blocks(f.blocks));
  r := Cat(r, nl);
  IF f.caption.blocks # NIL THEN
    hidden := FALSE;
    IF (f.blocks # NIL) & (f.blocks.next = NIL) & (f.blocks.kind = A.Plain) THEN
      i := f.blocks(A.InlinesBlk).inlines;
      IF (i # NIL) & (i.next = NIL) & (i.kind = A.Image) THEN
        alt := A.GetKeyVal(i(A.LinkInl).attr, "alt", found);
        IF ~found THEN alt := Sh.Stringify(i(A.LinkInl).content) END;
        hidden := Ropes.Equal(Sh.StringifyBlocks(f.caption.blocks), alt)
      END
    END;
    capt := Blocks(f.caption.blocks);
    IF hidden THEN r := CatS(r, '<figcaption aria-hidden="true">')
    ELSE r := CatS(r, "<figcaption>")
    END;
    r := Cat(CatS(Cat(r, capt), "</figcaption>"), nl)
  END;
  RETURN CatS(r, "</figure>")
END Figure;

(* Tables *)

PROCEDURE AddNCell(VAR l: NCells; c: NCell);
BEGIN
  IF l.first = NIL THEN l.first := c ELSE l.last.next := c END;
  l.last := c
END AddNCell;

(* Fits the cells of a row, from cells on, to the columns lo..hi-1
   whose hang is 1 (that no cell above spans), as AnnotatedTable does;
   maxSpan is the most rows a cell may span *)
PROCEDURE Annotate(VAR cells: A.Cell; hang: Hang; lo, hi, maxSpan: LONGINT; VAR out: NCells);
  VAR col, w, rs, acc: LONGINT; c: A.Cell; nc: NCell;
BEGIN
  col := lo;
  WHILE col < hi DO
    IF hang[col] > 1 THEN DEC(hang[col]); INC(col)
    ELSE
      c := cells; IF c # NIL THEN cells := c.next END;
      w := 1; rs := 1;
      IF c # NIL THEN
        IF c.colSpan > 1 THEN w := c.colSpan END;
        IF c.rowSpan > 1 THEN rs := c.rowSpan END;
        IF rs > maxSpan THEN rs := maxSpan END
      END;
      acc := 0;
      WHILE (acc < w) & (col + acc < hi) & (hang[col + acc] <= 1) DO
        hang[col + acc] := rs; INC(acc)
      END;
      NEW(nc); nc.cell := c; nc.col := col; nc.colSpan := acc; nc.rowSpan := rs; nc.next := NIL;
      AddNCell(out, nc);
      col := col + acc
    END
  END
END Annotate;

PROCEDURE NewHang(n: LONGINT): Hang;
  VAR h: Hang; i: LONGINT;
BEGIN
  NEW(h, n + 1);
  FOR i := 0 TO n DO h[i] := 1 END;
  RETURN h
END NewHang;

PROCEDURE CountRows(r: A.Row): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0; WHILE r # NIL DO INC(n); r := r.next END;
  RETURN n
END CountRows;

PROCEDURE CellHtml(nc: NCell; th: BOOLEAN; aligns: Aligns): Rope;
  VAR attr: A.Attr; align: INTEGER; blocks: A.Block; kvs: A.KeyVal; r: Rope;
    tag: ARRAY 4 OF CHAR;
BEGIN
  attr := NIL; align := A.AlignDefault; blocks := NIL;
  IF nc.cell # NIL THEN attr := nc.cell.attr; align := nc.cell.align; blocks := nc.cell.blocks END;
  IF (align = A.AlignDefault) & (nc.col < LEN(aligns^)) THEN align := aligns[nc.col] END;
  kvs := KVs(attr);
  CASE align OF
    A.AlignLeft: kvs := AddStyle("text-align", "left", kvs)
  | A.AlignRight: kvs := AddStyle("text-align", "right", kvs)
  | A.AlignCenter: kvs := AddStyle("text-align", "center", kvs)
  | A.AlignDefault:
  END;
  IF th THEN tag := "th" ELSE tag := "td" END;
  r := CatS(R("<"), tag);
  IF nc.colSpan # 1 THEN r := PairS(r, "colspan", Sh.IntRope(nc.colSpan)) END;
  IF nc.rowSpan # 1 THEN r := PairS(r, "rowspan", Sh.IntRope(nc.rowSpan)) END;
  r := CatS(Cat(r, AttrStr(Id(attr), Classes(attr), kvs)), ">");
  RETURN CatL(CatS(CatS(Cat(r, Blocks(blocks)), "</"), tag), ">")
END CellHtml;

PROCEDURE RowHtml(attr: A.Attr; stub, body: NCell; th: BOOLEAN; aligns: Aligns): Rope;
  VAR r: Rope;
BEGIN
  r := CatL(Cat(R("<tr"), AttrOf(attr)), ">");
  WHILE stub # NIL DO r := Cat(r, CellHtml(stub, TRUE, aligns)); stub := stub.next END;
  WHILE body # NIL DO r := Cat(r, CellHtml(body, th, aligns)); body := body.next END;
  RETURN CatL(r, "</tr>")
END RowHtml;

(* The rows rows, all of whose cells are of one kind (th or not), over
   ncols columns: "\n" and each row *)
PROCEDURE HeadRows(rows: A.Row; ncols: LONGINT; th: BOOLEAN; aligns: Aligns): Rope;
  VAR hang: Hang; n, i: LONGINT; cells: A.Cell; out: NCells; r: Rope;
BEGIN
  hang := NewHang(ncols); n := CountRows(rows); i := 0; r := nl;
  WHILE rows # NIL DO
    cells := rows.cells; out.first := NIL; out.last := NIL;
    Annotate(cells, hang, 0, ncols, n - i, out);
    r := Cat(r, RowHtml(rows.attr, NIL, out.first, th, aligns));
    rows := rows.next; INC(i)
  END;
  RETURN r
END HeadRows;

PROCEDURE IsEmptyCell(c: A.Cell): BOOLEAN;
BEGIN
  RETURN (c.attr = NIL) & (c.align = A.AlignDefault) & (c.rowSpan = 1) & (c.colSpan = 1)
    & (c.blocks = NIL)
END IsEmptyCell;

(* thead or tfoot *)
PROCEDURE TablePart(VAR p: A.TablePart; tag: ARRAY OF CHAR; th: BOOLEAN; ncols: LONGINT;
  aligns: Aligns): Rope;
  VAR row: A.Row; c: A.Cell; empty: BOOLEAN;
BEGIN
  empty := TRUE; row := p.rows;
  WHILE (row # NIL) & empty DO
    c := row.cells;
    WHILE (c # NIL) & empty DO empty := IsEmptyCell(c); c := c.next END;
    row := row.next
  END;
  IF empty THEN RETURN NIL END;
  RETURN Cat(CatS(CatS(CatS(Cat(CatS(Cat(CatS(R("<"), tag), AttrOf(p.attr)), ">"),
    HeadRows(p.rows, ncols, th, aligns)), "</"), tag), ">"), nl)
END TablePart;

PROCEDURE TableBody(tb: A.TableBody; ncols: LONGINT; aligns: Aligns): Rope;
  VAR r: Rope; rhc, n, i: LONGINT; stubHang, bodyHang: Hang; rows: A.Row;
    cells: A.Cell; stub, body: NCells;
BEGIN
  r := CatS(Cat(R("<tbody"), AttrOf(tb.attr)), ">");
  IF tb.head # NIL THEN r := Cat(r, HeadRows(tb.head, ncols, TRUE, aligns)) END;
  rhc := tb.rowHeadColumns;
  IF rhc > ncols THEN rhc := ncols END;
  IF rhc < 0 THEN rhc := 0 END;
  stubHang := NewHang(ncols); bodyHang := NewHang(ncols);
  rows := tb.body; n := CountRows(rows); i := 0; r := Cat(r, nl);
  WHILE rows # NIL DO
    cells := rows.cells;
    stub.first := NIL; stub.last := NIL; body.first := NIL; body.last := NIL;
    Annotate(cells, stubHang, 0, rhc, n - i, stub);
    Annotate(cells, bodyHang, rhc, ncols, n - i, body);
    r := Cat(r, RowHtml(rows.attr, stub.first, body.first, FALSE, aligns));
    rows := rows.next; INC(i)
  END;
  RETURN CatS(r, "</tbody>")
END TableBody;

PROCEDURE Table(t: A.TableBlk): Rope;
  VAR ncols, i: LONGINT; cs: A.ColSpec; aligns: Aligns; total: LONGREAL;
    allDefault, found: BOOLEAN; r, cols: Rope; kvs: A.KeyVal; tb: A.TableBody;
BEGIN
  ncols := 0; cs := t.colSpecs; total := 0; allDefault := TRUE;
  WHILE cs # NIL DO
    INC(ncols);
    IF cs.hasWidth THEN total := total + cs.width; allDefault := FALSE END;
    cs := cs.next
  END;
  NEW(aligns, ncols + 1); cs := t.colSpecs; i := 0;
  WHILE cs # NIL DO aligns[i] := cs.align; INC(i); cs := cs.next END;
  aligns[ncols] := A.AlignDefault;
  kvs := KVs(t.attr);
  r := A.GetKeyVal(t.attr, "style", found);
  IF ~found & (total > 0) & (total < 1) THEN
    (* truncated, as pandoc 3.14 does (3.10 rounded) *)
    kvs := NewKV(R("style"), CatS(Cat(R("width:"), Sh.IntRope(ENTIER(total * 100))), "%;"), kvs)
  END;
  r := Cat(CatS(Cat(R("<table"), AttrStr(Id(t.attr), Classes(t.attr), kvs)), ">"), nl);
  IF t.caption.blocks # NIL THEN
    r := Cat(Cat(r, Wrap("caption", Blocks(t.caption.blocks))), nl)
  END;
  IF ~allDefault THEN
    cols := CatL(NIL, "<colgroup>"); cs := t.colSpecs;
    WHILE cs # NIL DO
      IF cs.hasWidth THEN
        cols := CatS(cols, '<col style="width: ');
        cols := CatL(Cat(cols, Sh.IntRope(ENTIER(100 * cs.width))), '%" />')
      ELSE cols := CatL(cols, "<col />")
      END;
      cs := cs.next
    END;
    r := Cat(r, CatL(cols, "</colgroup>"))
  END;
  r := Cat(r, TablePart(t.head, "thead", TRUE, ncols, aligns));
  tb := t.bodies;
  WHILE tb # NIL DO
    r := Cat(r, TableBody(tb, ncols, aligns));
    IF tb.next # NIL THEN r := Cat(r, nl) END;
    tb := tb.next
  END;
  r := Cat(r, TablePart(t.foot, "tfoot", FALSE, ncols, aligns));
  RETURN CatS(Cat(r, nl), "</table>")
END Table;

PROCEDURE Block(b: A.Block; VAR empty: BOOLEAN): Rope;
  VAR r: Rope; l: A.InlineList; k: INTEGER;
BEGIN
  empty := FALSE; r := NIL;
  k := b.kind;
  IF (k = A.Para) & (inCslEntry > 0) THEN k := A.Plain END;
  CASE k OF
    A.Plain:
    r := Inlines(b(A.InlinesBlk).inlines); empty := b(A.InlinesBlk).inlines = NIL
  | A.Para:
    IF b(A.InlinesBlk).inlines = NIL THEN empty := TRUE
    ELSE r := Wrap("p", Inlines(b(A.InlinesBlk).inlines))
    END
  | A.LineBlock:
    l := b(A.LineBlk).lines; r := NIL;
    WHILE l # NIL DO
      r := Cat(r, Inlines(l.inlines));
      IF l.next # NIL THEN r := CatL(r, "<br />") END;
      l := l.next
    END;
    r := CatS(Cat(R('<div class="line-block">'), r), "</div>")
  | A.CodeBlock:
    r := CodeBlock(b(A.CodeBlk))
  | A.RawBlock:
    IF IsHtml(b(A.RawBlk).format) THEN r := b(A.RawBlk).text ELSE empty := TRUE END
  | A.BlockQuote:
    r := Cat(Cat(CatL(NIL, "<blockquote>"), Blocks(b(A.BlocksBlk).blocks)),
      CatS(nl, "</blockquote>"))
  | A.OrderedList: r := OrderedList(b(A.OrderedBlk))
  | A.BulletList: r := BulletList(b(A.ListBlk))
  | A.DefinitionList: r := DefinitionList(b(A.DefListBlk))
  | A.Header: r := Header(b(A.HeaderBlk))
  | A.HorizontalRule: r := R("<hr />")
  | A.Table: r := Table(b(A.TableBlk))
  | A.Figure: r := Figure(b(A.FigureBlk))
  | A.Div: r := Div(b(A.DivBlk))
  END;
  RETURN r
END Block;

PROCEDURE Blocks(b: A.Block): Rope;
  VAR r, x: Rope; any, empty: BOOLEAN;
BEGIN
  r := NIL; any := FALSE;
  WHILE b # NIL DO
    x := Block(b, empty);
    IF ~empty THEN
      IF any THEN r := Cat(r, nl) END;
      r := Cat(r, x); any := TRUE
    END;
    b := b.next
  END;
  RETURN r
END Blocks;

(* The writers PdContext takes, for metadata *)

PROCEDURE BlockDoc*(b: A.Block): L.Doc;
BEGIN
  RETURN L.Literal(Blocks(b))
END BlockDoc;

PROCEDURE InlineDoc*(i: A.Inline): L.Doc;
BEGIN
  RETURN L.Literal(Inlines(i))
END InlineDoc;

(* The table of contents *)

(* i without links (their contents in their place) and notes, copied *)
PROCEDURE DeLink(i: A.Inline): A.Inline;
  VAR l: A.Inlines; n: A.Inline;
BEGIN
  A.InitInlines(l);
  WHILE i # NIL DO
    IF i.kind = A.Link THEN A.AddInline(l, DeLink(i(A.ContInl).content))
    ELSIF i.kind = A.Note THEN
    ELSE
      n := A.CopyInlines(i); n.next := NIL; (* CopyInlines copies the rest too *)
      IF n IS A.ContInl THEN n(A.ContInl).content := DeLink(i(A.ContInl).content) END;
      A.AddInline(l, n)
    END;
    i := i.next
  END;
  RETURN l.first
END DeLink;

PROCEDURE^ TocItems(b: A.Block; VAR items: A.BlockList);

PROCEDURE TocItem(d: A.DivBlk; h: A.HeaderBlk; VAR items: A.BlockList);
  VAR num, id: Rope; found: BOOLEAN; l: A.Inlines; sa, la: A.Attr; text: A.Inline;
    item, last: A.BlockList; sub: A.BlockList; plain: A.Block;
BEGIN
  num := A.GetKeyVal(h.attr, "number", found);
  A.InitInlines(l);
  IF numberSections & found THEN
    sa := A.NewAttr(NIL); A.AddClass(sa, R("toc-section-number"));
    A.AddInline(l, A.NewSpan(sa, A.NewStr(num))); A.AddInline(l, A.NewSimple(A.Space))
  END;
  A.AddInline(l, DeLink(h.inlines));
  text := l.first; id := Id(d.attr);
  IF Len(id) > 0 THEN
    la := A.NewAttr(Cat(R("toc-"), id));
    text := A.NewLink(A.Link, la, text, Cat(R("#"), id), NIL)
  END;
  plain := A.NewInlinesBlock(A.Plain, text);
  sub := NIL; TocItems(h.next, sub);
  IF sub # NIL THEN plain.next := A.NewBulletList(sub) END;
  NEW(item); item.blocks := plain; item.next := NIL;
  IF items = NIL THEN items := item
  ELSE last := items; WHILE last.next # NIL DO last := last.next END; last.next := item
  END
END TocItem;

PROCEDURE TocItems(b: A.Block; VAR items: A.BlockList);
  VAR d: A.DivBlk; h: A.HeaderBlk; found: BOOLEAN; num: Rope;
BEGIN
  WHILE b # NIL DO
    IF b IS A.DivBlk THEN
      d := b(A.DivBlk);
      IF (d.blocks # NIL) & (d.blocks IS A.HeaderBlk) THEN
        h := d.blocks(A.HeaderBlk);
        num := A.GetKeyVal(h.attr, "number", found);
        IF (found OR ~A.HasClass(h.attr, "unlisted")) & (h.level <= tocDepth) THEN
          TocItem(d, h, items)
        END
      ELSIF (d.blocks # NIL) & (d.blocks.next = NIL) & (d.blocks IS A.DivBlk) THEN
        TocItems(d.blocks, items)
      END
    END;
    b := b.next
  END
END TocItems;

(* The table of contents of blocks, as pandoc's toTableOfContents
   makes it: a bullet list, NIL if there are no headings. number and
   depth are -N and --toc-depth *)
PROCEDURE TableOfContents*(blocks: A.Block; number: BOOLEAN; depth: INTEGER): A.Block;
  VAR items: A.BlockList; saveNumber: BOOLEAN; saveDepth: INTEGER;
BEGIN
  saveNumber := numberSections; saveDepth := tocDepth;
  numberSections := number; tocDepth := depth;
  items := NIL; TocItems(Sh.MakeSections(number, -1, blocks), items);
  numberSections := saveNumber; tocDepth := saveDepth;
  IF items = NIL THEN RETURN NIL END;
  RETURN A.NewBulletList(items)
END TableOfContents;

(* Metadata for the template *)


(* s escaped as pandoc's escapeStringForXML *)
PROCEDURE EscapeXml(s: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; r: Rope; ch: CHAR;
BEGIN
  r := Escape(s, FALSE, FALSE); n := Len(r); b := ToBuf(r); r := NIL;
  FOR i := 0 TO n - 1 DO
    ch := b[i];
    IF ch = 22X THEN r := CatS(r, "&quot;")
    ELSIF (ch >= " ") OR (ch = 9X) OR (ch = 0AX) OR (ch = 0DX) THEN r := Ropes.AppendChar(r, ch)
    END
  END;
  RETURN r
END EscapeXml;

PROCEDURE AddAuthor(l: T.Value; i: A.Inline);
BEGIN
  T.Add(l, T.NewSimple(L.Literal(EscapeXml(Sh.Stringify(i)))))
END AddAuthor;

(* author-meta: the authors, as pandoc's docAuthors orders them *)
PROCEDURE Authors(meta: A.MetaMapV): T.Value;
  VAR l: T.Value; a: A.InlineList;
BEGIN
  l := T.NewList(); a := Sh.DocAuthors(meta);
  WHILE a # NIL DO AddAuthor(l, a.inlines); a := a.next END;
  RETURN l
END Authors;

(* The metadata value of key as text, as pandoc's lookupMetaString *)
PROCEDURE MetaString(meta: A.MetaMapV; key: ARRAY OF CHAR): Rope;
  VAR v: A.MetaValue;
BEGIN
  v := A.GetMeta(meta, key);
  IF v = NIL THEN RETURN NIL END;
  WITH
    v: A.MetaStringV DO RETURN v.s
  | v: A.MetaInlinesV DO RETURN Sh.Stringify(v.inlines)
  | v: A.MetaBlocksV DO RETURN Sh.StringifyBlocks(v.blocks)
  | v: A.MetaBoolV DO IF v.b THEN RETURN R("True") ELSE RETURN R("False") END
  ELSE
  END;
  RETURN NIL
END MetaString;

(* Dates *)

PROCEDURE MonthName(VAR s: ARRAY OF CHAR; VAR i: LONGINT; n: LONGINT; full: BOOLEAN;
  VAR m: LONGINT): BOOLEAN;
  CONST names = "january   february  march     april     may       june      july      august    september october   november  december  ";
  VAR k, j, len: LONGINT; ok: BOOLEAN; name: ARRAY 124 OF CHAR;
BEGIN
  name := names;
  FOR k := 0 TO 11 DO
    len := 0; WHILE name[k * 10 + len] # " " DO INC(len) END;
    IF ~full THEN len := 3 END;
    ok := i + len <= n; j := 0;
    WHILE ok & (j < len) DO
      ok := Ropes.LowerChar(s[i + j]) = name[k * 10 + j]; INC(j)
    END;
    IF ok THEN m := k + 1; INC(i, len); RETURN TRUE END
  END;
  RETURN FALSE
END MonthName;

(* Reads up to max digits (at least min) of s at i *)
PROCEDURE Digits(VAR s: ARRAY OF CHAR; VAR i: LONGINT; n, min, max: LONGINT; VAR v: LONGINT): BOOLEAN;
  VAR k: LONGINT;
BEGIN
  v := 0; k := 0;
  WHILE (k < max) & (i < n) & IsDigit(s[i]) DO v := v * 10 + ORD(s[i]) - ORD("0"); INC(i); INC(k) END;
  RETURN k >= min
END Digits;

(* Whether s (n characters) is a date in the format fmt (strftime's
   %Y %y %m %d %e %b %B and literal characters) *)
PROCEDURE MatchDate(VAR s: ARRAY OF CHAR; n: LONGINT; fmt: ARRAY OF CHAR; VAR y, m, d: LONGINT): BOOLEAN;
  VAR i, j, max: LONGINT; ok: BOOLEAN; c: CHAR;
BEGIN
  y := 1970; m := 1; d := 1; i := 0; j := 0; ok := TRUE;
  WHILE ok & (fmt[j] # 0X) DO
    IF fmt[j] = "%" THEN
      c := fmt[j + 1]; INC(j, 2);
      IF fmt[j] = "%" THEN max := 2 ELSE max := 2 END;
      CASE c OF
        "Y": ok := Digits(s, i, n, 4, 4, y)
      | "y":
        ok := Digits(s, i, n, 2, 2, y);
        IF y < 69 THEN INC(y, 2000) ELSE INC(y, 1900) END
      | "m":
        IF fmt[j] = "%" THEN ok := Digits(s, i, n, 2, 2, m) ELSE ok := Digits(s, i, n, 1, max, m) END
      | "d":
        IF fmt[j] = "%" THEN ok := Digits(s, i, n, 2, 2, d) ELSE ok := Digits(s, i, n, 1, max, d) END
      | "e":
        IF (i < n) & (s[i] = " ") THEN INC(i) END;
        ok := Digits(s, i, n, 1, 2, d)
      | "b": ok := MonthName(s, i, n, FALSE, m)
      | "B": ok := MonthName(s, i, n, TRUE, m)
      END
    ELSIF fmt[j] = " " THEN
      (* white space, with U+00A0, which smart typing puts after "Dec." *)
      LOOP
        IF (i < n) & IsSpace(s[i]) THEN INC(i)
        ELSIF (i + 1 < n) & (s[i] = 0C2X) & (s[i + 1] = 0A0X) THEN INC(i, 2)
        ELSE EXIT
        END
      END;
      INC(j)
    ELSE
      ok := (i < n) & (s[i] = fmt[j]); INC(i); INC(j)
    END
  END;
  RETURN ok & (i = n)
END MatchDate;

PROCEDURE DaysIn(m, y: LONGINT): LONGINT;
BEGIN
  CASE m OF
    2: IF (y MOD 4 = 0) & ((y MOD 100 # 0) OR (y MOD 400 = 0)) THEN RETURN 29 ELSE RETURN 28 END
  | 4, 6, 9, 11: RETURN 30
  ELSE RETURN 31
  END
END DaysIn;

PROCEDURE Pad(VAR r: Rope; v, width: LONGINT);
  VAR s: Rope;
BEGIN
  s := Sh.IntRope(v);
  WHILE Len(s) < width DO s := Cat(R("0"), s) END;
  r := Cat(r, s)
END Pad;

(* The date s as YYYY-MM-DD, as pandoc's normalizeDate, or NIL *)
PROCEDURE NormalizeDate(s: Rope): Rope;
  VAR b: Buf; n, y, m, d, k: LONGINT; ok: BOOLEAN; r: Rope;
BEGIN
  s := Ropes.Trim(s); b := ToBuf(s); n := Len(s); ok := FALSE; k := 0;
  WHILE ~ok & (k < 10) DO
    CASE k OF
      0: ok := MatchDate(b^, n, "%m/%d/%y", y, m, d)
    | 1: ok := MatchDate(b^, n, "%m/%d/%Y", y, m, d)
    | 2: ok := MatchDate(b^, n, "%Y-%m-%d", y, m, d)
    | 3: ok := MatchDate(b^, n, "%d %b %Y", y, m, d)
    | 4: ok := MatchDate(b^, n, "%e %B %Y", y, m, d)
    | 5: ok := MatchDate(b^, n, "%b. %e, %Y", y, m, d)
    | 6: ok := MatchDate(b^, n, "%B %e, %Y", y, m, d)
    | 7: ok := MatchDate(b^, n, "%Y%m%d", y, m, d)
    | 8: ok := MatchDate(b^, n, "%Y%m", y, m, d)
    | 9: ok := MatchDate(b^, n, "%Y", y, m, d)
    END;
    ok := ok & (m >= 1) & (m <= 12) & (d >= 1) & (d <= DaysIn(m, y));
    INC(k)
  END;
  IF ~ok OR (y < 1601) OR (y > 9999) THEN RETURN NIL END;
  r := NIL; Pad(r, y, 4); r := CatS(r, "-"); Pad(r, m, 2); r := CatS(r, "-"); Pad(r, d, 2);
  RETURN r
END NormalizeDate;

(* The base name of the file name s: without its directory and its
   last extension *)
PROCEDURE BaseName(s: Rope): Rope;
  VAR i, dot: LONGINT;
BEGIN
  i := Ropes.RIndexChar(s, "/", Len(s));
  IF i >= 0 THEN s := Ropes.Substring(s, i + 1, Len(s) - i - 1) END;
  dot := Ropes.RIndexChar(s, ".", Len(s));
  IF dot > 0 THEN s := Ropes.Substring(s, 0, dot) END;
  RETURN s
END BaseName;

(* The writer *)

(* Sets the writer's options: the prefix of identifiers, whether
   sections are numbered, whether soft breaks are kept as new lines
   (--wrap=preserve), whether there is a table of contents and its
   depth, and the first input file's name ("-" for standard input),
   which titles a page that has no title *)
PROCEDURE SetOptions*(prefix: ARRAY OF CHAR; number, preserveBreaks, toc: BOOLEAN;
  depth: INTEGER; source: ARRAY OF CHAR);
BEGIN
  idPrefix := R(prefix); numberSections := number; preserve := preserveBreaks;
  wantToc := toc; tocDepth := depth; sourceFile := R(source)
END SetOptions;

PROCEDURE Lit(r: Rope): T.Value;
BEGIN
  RETURN T.NewSimple(L.Literal(r))
END Lit;

(* Writes the document doc as HTML: its body, or, if tmpl is not NIL,
   the template filled in *)
PROCEDURE ResetState;
BEGIN
  notes := NIL; noteCount := 0; mathSeen := FALSE; cslSeen := FALSE; cslHasSpacing := FALSE;
  proportionalSeen := FALSE;
  inLink := 0; inCite := 0; inCslEntry := 0
END ResetState;

(* body, with the notes' section after it if there are notes *)
PROCEDURE AddNotes(body: Rope): Rope;
BEGIN
  IF notes # NIL THEN
    body := Cat(Cat(body, nl), PairS(R("<section"), "id", Cat(idPrefix, R("footnotes"))));
    body := CatL(body, ' class="footnotes footnotes-end-of-document" role="doc-endnotes">');
    body := CatS(CatL(Cat(CatL(CatL(body, "<hr />"), "<ol>"), notes), "</ol>"), "</section>")
  END;
  RETURN body
END AddNotes;

(* The block b alone (not those after it) as HTML, as pandoc writes a
   document holding only b, without a template *)
PROCEDURE Fragment*(b: A.Block): Rope;
  VAR next: A.Block; r: Rope; empty: BOOLEAN;
BEGIN
  ResetState;
  next := b.next; b.next := NIL;
  r := Block(b, empty);
  b.next := next;
  IF empty THEN r := NIL END;
  r := AddNotes(r);
  ResetState;
  RETURN r
END Fragment;

PROCEDURE WriteDoc*(doc: A.Doc; tmpl: T.Template);
  VAR sections: A.Block; ctx: T.Value; body, toc, s, date: Rope; items: A.BlockList;
    empty: BOOLEAN; meta: A.MetaMapV; v: T.Value;
BEGIN
  ResetState;
  meta := doc.meta; Sh.SetCodeStyle(meta);
  sections := Sh.MakeSections(numberSections, -1, doc.blocks);
  IF tmpl # NIL THEN ctx := C.Build(meta, BlockDoc, InlineDoc) END;
  toc := NIL;
  IF wantToc THEN
    items := NIL; TocItems(sections, items);
    IF items # NIL THEN toc := Block(A.NewBulletList(items), empty) END
  END;
  body := AddNotes(Blocks(sections));
  IF tmpl = NIL THEN
    PdIO.WriteRope(body); PdIO.WriteLn;
    RETURN
  END;
  IF cslSeen THEN
    C.DefField(ctx, "csl-css", T.NewBool(TRUE));
    IF cslHasSpacing THEN C.DefField(ctx, "csl-entry-spacing", Lit(CatS(cslSpacing, "em"))) END
  END;
  IF mathSeen THEN C.DefField(ctx, "math", T.NewString("")) END;
  IF proportionalSeen THEN C.DefField(ctx, "code-proportional", T.NewBool(TRUE)) END;
  C.DefField(ctx, "abstract-title", T.NewString("Abstract"));
  C.DefField(ctx, "mathjax", T.NewBool(FALSE));
  C.DefField(ctx, "displaymath-css", T.NewBool(TRUE));
  C.DefField(ctx, "document-css", T.NewBool(~T.Has(ctx, "css")));
  C.DefField(ctx, "quotes", T.NewBool(FALSE));
  IF toc # NIL THEN
    C.DefField(ctx, "toc", Lit(toc)); C.DefField(ctx, "table-of-contents", Lit(toc))
  END;
  C.DefField(ctx, "author-meta", Authors(meta));
  date := NormalizeDate(EscapeXml(Sh.Stringify(Sh.DocMeta(meta, "date"))));
  IF date # NIL THEN C.DefField(ctx, "date-meta", Lit(date)) END;
  C.DefField(ctx, "description-meta", Lit(EscapeXml(MetaString(meta, "description"))));
  s := EscapeXml(Sh.Stringify(Sh.DocMeta(meta, "title")));
  C.DefField(ctx, "pagetitle", Lit(s));
  C.DefField(ctx, "idprefix", Lit(idPrefix));
  C.DefField(ctx, "table-caption-below", T.NewBool(FALSE));
  C.DefField(ctx, "html5", T.NewBool(TRUE));
  v := T.Get(ctx, "pagetitle");
  IF ((v = NIL) OR (v.kind # T.SimpleV) OR (Len(L.Render(v.doc, 0)) = 0))
     & T.HasVariable(tmpl, "pagetitle") THEN
    C.ResetField(ctx, "pagetitle", Lit(BaseName(sourceFile)))
  END;
  C.DefField(ctx, "body", Lit(body));
  L.Write(T.Render(tmpl, ctx), 0)
END WriteDoc;

PROCEDURE Known(s: ARRAY OF CHAR);
BEGIN
  known := CatS(known, s)
END Known;

BEGIN
  nl := Ropes.FromChar(0AX);
  idPrefix := NIL; sourceFile := R("-"); numberSections := FALSE; preserve := FALSE;
  wantToc := FALSE; tocDepth := 3;
  known := R(" ");
  Known("abbr accept accept-charset accesskey action allow allowfullscreen ");
  Known("allowpaymentrequest allowusermedia alt as async autocapitalize ");
  Known("autocomplete autofocus autoplay charset checked cite class color cols ");
  Known("colspan content contenteditable controls coords crossorigin data ");
  Known("datetime decoding default defer dir dirname disabled download draggable ");
  Known("enctype enterkeyhint fetchpriority for form formaction formenctype ");
  Known("formmethod formnovalidate formtarget headers height hidden high href ");
  Known("hreflang http-equiv id imagesizes imagesrcset inputmode integrity is ");
  Known("ismap itemid itemprop itemref itemscope itemtype kind label lang list ");
  Known("loading loop low manifest max maxlength media method min minlength ");
  Known("multiple muted name nomodule nonce novalidate onabort onafterprint ");
  Known("onauxclick onbeforeprint onbeforeunload onblur oncancel oncanplay ");
  Known("oncanplaythrough onchange onclick onclose oncontextmenu oncopy ");
  Known("oncuechange oncut ondblclick ondrag ondragend ondragenter ondragexit ");
  Known("ondragleave ondragover ondragstart ondrop ondurationchange onemptied ");
  Known("onended onerror onfocus onhashchange oninput oninvalid onkeydown ");
  Known("onkeypress onkeyup onlanguagechange onload onloadeddata ");
  Known("onloadedmetadata onloadend onloadstart onmessage onmessageerror ");
  Known("onmousedown onmouseenter onmouseleave onmousemove onmouseout ");
  Known("onmouseover onmouseup onoffline ononline onpagehide onpageshow onpaste ");
  Known("onpause onplay onplaying onpopstate onprogress onratechange ");
  Known("onrejectionhandled onreset onresize onscroll onsecuritypolicyviolation ");
  Known("onseeked onseeking onselect onstalled onstorage onsubmit onsuspend ");
  Known("ontimeupdate ontoggle onunhandledrejection onunload onvolumechange ");
  Known("onwaiting onwheel open optimum pattern ping placeholder playsinline ");
  Known("poster preload readonly referrerpolicy rel required reversed role rows ");
  Known("rowspan sandbox scope selected shape size sizes slot span spellcheck ");
  Known("src srcdoc srclang srcset start step style tabindex target title ");
  Known("translate type typemustmatch updateviacache usemap value width ");
  Known("workertype wrap about rev resource property datatype typeof vocab prefix ")
END PdHtml.
