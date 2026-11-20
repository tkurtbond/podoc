MODULE PdMarkdown;
(* PdMarkdown: the markdown reader's blocks (Text.Pandoc.Readers.Markdown,
   parseBlocks and block), and Read, which reads a document.

   The blocks are tried in pandoc's order. So far: blank lines, fenced
   code, bullet, ordered and definition lists, HTML and fenced divs,
   setext and ATX headings (with attributes and identifiers), raw HTML
   blocks, indented code, line blocks, block quotes, horizontal rules,
   paragraphs and plain text. Metadata blocks, the title block, tables,
   raw TeX, notes, reference keys and implicit figures come in later
   phases. *)

IMPORT Ropes, PdIO, A := PdAst, B := PdMdBase, I := PdMdInline;

CONST
  (* what starts a list item *)
  BulletItem = 1; OrderedItem = 2; DefItem = 3;

VAR
  ids: A.StrList; (* the header identifiers used so far *)

PROCEDURE^ Block(VAR l: A.Blocks): BOOLEAN;

(* Sub-texts *)

(* parseBlocks: blocks to the end of the current text *)
PROCEDURE ParseBlocks(): A.Block;
  VAR l: A.Blocks; e: LONGINT;
BEGIN
  A.InitBlocks(l);
  WHILE B.pos < B.len DO
    IF ~Block(l) THEN
      (* pandoc would stop with a parse error; a line as plain text *)
      e := B.LineEnd(B.pos);
      A.AddBlock(l, A.NewInlinesBlock(A.Plain, I.ParseText(B.pos, e)));
      B.pos := e;
      IF B.pos < B.len THEN INC(B.pos) END
    END
  END;
  RETURN l.first
END ParseBlocks;

(* parseFromString parseBlocks: the blocks of the text in b *)
PROCEDURE BlocksOf(VAR b: B.Buf): A.Block;
  VAR f: B.Frame; r: A.Block;
BEGIN
  B.Enter(f, b.t, b.len);
  r := ParseBlocks();
  B.Leave(f);
  RETURN r
END BlocksOf;

(* parseFromString (trimInlines <$> inlines): the inlines of the text
   in b *)
PROCEDURE InlinesOf(VAR b: B.Buf): A.Inline;
  VAR f: B.Frame; l: A.Inlines;
BEGIN
  B.Enter(f, b.t, b.len);
  A.InitInlines(l);
  WHILE I.Inline(l) DO END;
  B.Leave(f);
  RETURN I.Trim(l)
END InlinesOf;

(* Identifiers *)

PROCEDURE Used(id: A.Rope): BOOLEAN;
  VAR s: A.StrList;
BEGIN
  s := ids;
  WHILE (s # NIL) & ~Ropes.Equal(s.s, id) DO s := s.next END;
  RETURN s # NIL
END Used;

PROCEDURE Use(id: A.Rope);
  VAR s: A.StrList;
BEGIN
  NEW(s); s.s := id; s.next := ids; ids := s
END Use;

(* The decimal digits of n *)
PROCEDURE Number(n: LONGINT): A.Rope;
  VAR d: ARRAY 24 OF CHAR; i: INTEGER; r: A.Rope;
BEGIN
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  r := NIL;
  WHILE i > 0 DO DEC(i); r := Ropes.AppendChar(r, d[i]) END;
  RETURN r
END Number;

(* registerHeader: an identifier for a header without one, made unique
   as uniqueIdent makes it; either is recorded as used *)
PROCEDURE RegisterHeader(attr: A.Attr; inl: A.Inline);
  VAR base, id: A.Rope; n: LONGINT;
BEGIN
  IF attr.id = NIL THEN
    base := I.Identifier(inl);
    IF base = NIL THEN base := A.S("section") END;
    id := base;
    IF Used(id) THEN
      n := 1;
      REPEAT
        id := Ropes.Cat(Ropes.AppendChar(base, "-"), Number(n)); INC(n)
      UNTIL ~Used(id) OR (n > 60000);
      IF Used(id) THEN id := base END
    END;
    attr.id := id
  END;
  Use(attr.id)
END RegisterHeader;

(* Code *)

(* codeBlockFenced *)
PROCEDURE FencedCode(VAR l: A.Blocks): BOOLEAN;
  VAR f: B.Fence; p, q, e, close, n: LONGINT; b: B.Buf; first: BOOLEAN;
BEGIN
  q := B.FencedCode(B.pos, f, close);
  IF q < 0 THEN RETURN FALSE END;
  B.InitBuf(b); p := f.body; first := TRUE;
  WHILE p < close DO
    p := B.GobbleAtMost(p, f.indent, n);
    e := B.LineEnd(p);
    IF ~first THEN B.PutChar(b, 0AX) END;
    B.Put(b, p, e); first := FALSE;
    p := e + 1
  END;
  IF f.raw THEN A.AddBlock(l, A.NewRawBlock(f.format, B.BufRope(b)))
  ELSE A.AddBlock(l, A.NewCodeBlock(f.attr, B.BufRope(b)))
  END;
  B.pos := q;
  RETURN TRUE
END FencedCode;

(* codeBlockIndented *)
PROCEDURE IndentedCode(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, r, e: LONGINT; b: B.Buf; any: BOOLEAN;
BEGIN
  p := B.pos; any := FALSE; B.InitBuf(b);
  LOOP
    q := B.IndentSpaces(p);
    IF q >= 0 THEN e := B.AnyLine(q) ELSE e := -1 END;
    IF e >= 0 THEN
      B.Put(b, q, e); p := e; any := TRUE
    ELSIF any THEN
      r := B.BlankLines(p);
      IF r < 0 THEN EXIT END;
      q := B.IndentSpaces(r);
      IF (q < 0) OR (B.AnyLine(q) < 0) THEN EXIT END;
      WHILE p < r DO p := B.BlankLine(p); B.PutChar(b, 0AX) END
    ELSE
      EXIT
    END
  END;
  IF ~any THEN RETURN FALSE END;
  B.pos := B.SkipBlankLines(p);
  WHILE (b.len > 0) & (b.t[b.len - 1] = 0AX) DO DEC(b.len) END;
  A.AddBlock(l, A.NewCodeBlock(A.NewAttr(NIL), B.BufRope(b)));
  RETURN TRUE
END IndentedCode;

(* Headers *)

(* atxClosing at p: the position after it, its attributes in a *)
PROCEDURE AtxClosing(p: LONGINT; VAR a: A.Attr): LONGINT;
  VAR q: LONGINT;
BEGIN
  WHILE B.C(p) = "#" DO INC(p) END;
  p := B.SkipSpaces(p);
  q := B.Attributes(p, a);
  IF q >= 0 THEN p := q ELSE a := A.NewAttr(NIL) END;
  RETURN B.BlankLines(p)
END AtxClosing;

PROCEDURE AtxStop(p: LONGINT): BOOLEAN;
  VAR a: A.Attr;
BEGIN
  RETURN AtxClosing(p, a) >= 0
END AtxStop;

(* setextHeaderEnd *)
PROCEDURE SetextEnd(p: LONGINT; VAR a: A.Attr): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := B.Attributes(p, a);
  IF q >= 0 THEN p := q ELSE a := A.NewAttr(NIL) END;
  RETURN B.BlankLines(p)
END SetextEnd;

PROCEDURE SetextStop(p: LONGINT): BOOLEAN;
  VAR a: A.Attr;
BEGIN
  RETURN SetextEnd(p, a) >= 0
END SetextStop;

(* Inlines up to where stop says, line breaks not allowed, trimmed *)
PROCEDURE HeaderInlines(stop: I.Stop): A.Inline;
  VAR l: A.Inlines; old, any: BOOLEAN;
BEGIN
  old := B.allowLineBreaks; B.allowLineBreaks := FALSE;
  A.InitInlines(l);
  any := I.Inlines(l, stop);
  B.allowLineBreaks := old;
  RETURN I.Trim(l)
END HeaderInlines;

(* atxHeader *)
PROCEDURE AtxHeader(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, start: LONGINT; level: INTEGER; inl: A.Inline; a: A.Attr;
    ch: CHAR;
BEGIN
  start := B.pos; p := start; level := 0;
  WHILE B.C(p) = "#" DO INC(p); INC(level) END;
  ch := B.C(p);
  IF (level = 0) OR (ch = ".") OR (ch = ")")
      OR (p < B.len) & ~B.IsWhite(ch) THEN
    RETURN FALSE
  END;
  B.pos := B.SkipSpaces(p);
  inl := HeaderInlines(AtxStop);
  q := AtxClosing(B.pos, a);
  IF q < 0 THEN B.pos := start; RETURN FALSE END;
  B.pos := q;
  RegisterHeader(a, inl);
  A.AddBlock(l, A.NewHeader(level, a, inl));
  RETURN TRUE
END AtxHeader;

(* setextHeader *)
PROCEDURE SetextHeader(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, start: LONGINT; level: INTEGER; inl: A.Inline; a: A.Attr;
    ch: CHAR;
BEGIN
  start := B.pos;
  p := B.AnyLine(start);
  IF p < 0 THEN RETURN FALSE END;
  q := p;
  WHILE (B.C(q) = "=") OR (B.C(q) = "-") DO INC(q) END;
  IF (q = p) OR (B.BlankLine(q) < 0) THEN RETURN FALSE END;
  B.pos := B.SkipSpaces(start);
  inl := HeaderInlines(SetextStop);
  q := SetextEnd(B.pos, a);
  IF q >= 0 THEN
    ch := B.C(q);
    IF (ch = "=") OR (ch = "-") THEN
      WHILE B.C(q) = ch DO INC(q) END;
      q := B.BlankLines(q);
      IF q >= 0 THEN
        IF ch = "=" THEN level := 1 ELSE level := 2 END;
        B.pos := q;
        RegisterHeader(a, inl);
        A.AddBlock(l, A.NewHeader(level, a, inl));
        RETURN TRUE
      END
    END
  END;
  B.pos := start;
  RETURN FALSE
END SetextHeader;

(* Lists *)

(* The column of p in its line; a tab goes to the next multiple of 8,
   as in Parsec's positions *)
PROCEDURE Column(p: LONGINT): LONGINT;
  VAR s, col: LONGINT;
BEGIN
  s := p;
  WHILE (s > 0) & (B.t[s - 1] # 0AX) DO DEC(s) END;
  col := 0;
  WHILE s < p DO
    IF B.t[s] = 09X THEN col := col + 8 - col MOD 8 ELSE INC(col) END;
    INC(s)
  END;
  RETURN col
END Column;

(* A list item's start of the kind kind at p: the position after it *)
PROCEDURE ItemStart(p: LONGINT; kind: INTEGER; style, delim: INTEGER): LONGINT;
  VAR num: LONGINT;
BEGIN
  CASE kind OF
  | BulletItem: RETURN B.BulletListStart(p)
  | OrderedItem: RETURN B.OrderedListStart(p, FALSE, num, style, delim)
  | DefItem: RETURN B.DefListStart(p)
  END
END ItemStart;

(* Appends the line at p and its new line to b; the position after it,
   or -1 if there is no new line *)
PROCEDURE PutLine(VAR b: B.Buf; p: LONGINT): LONGINT;
  VAR e: LONGINT;
BEGIN
  e := B.AnyLine(p);
  IF e < 0 THEN RETURN -1 END;
  B.Put(b, p, e - 1); B.PutChar(b, 0AX);
  RETURN e
END PutLine;

(* manyChar blankline: a new line in b for each blank line at p *)
PROCEDURE PutBlanks(VAR b: B.Buf; p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := B.BlankLine(p);
  WHILE q >= 0 DO B.PutChar(b, 0AX); p := q; q := B.BlankLine(p) END;
  RETURN p
END PutBlanks;

(* listLine ci at p: the line, in b *)
PROCEDURE ListLine(VAR b: B.Buf; p, ci: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := B.GobbleSpaces(p, ci);
  IF (q >= 0) & B.ListStart(B.SkipSpaces(q)) OR B.HtmlCloser(p)
      OR B.DivCloser(p) THEN
    RETURN -1
  END;
  IF q >= 0 THEN p := q END;
  RETURN PutLine(b, p)
END ListLine;

(* rawListItem at p: the item's first lines, in b; ci is the
   continuation indent *)
PROCEDURE RawListItem(VAR b: B.Buf; p: LONGINT; kind, style, delim: INTEGER;
                      VAR ci: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := ItemStart(p, kind, style, delim);
  IF q < 0 THEN RETURN -1 END;
  IF (kind = OrderedItem) & (style = A.Example) THEN ci := 4
  ELSE ci := Column(q) - Column(p)
  END;
  p := PutLine(b, q);
  IF p < 0 THEN RETURN -1 END;
  LOOP
    IF B.ListStart(p) OR B.IsFencedCode(p) OR (B.BlankLine(p) >= 0) THEN EXIT END;
    q := ListLine(b, p, ci);
    IF q < 0 THEN EXIT END;
    p := q
  END;
  RETURN PutBlanks(b, p)
END RawListItem;

(* listContinuation ci at p, appended to b *)
PROCEDURE ListContinuation(VAR b: B.Buf; p, ci: LONGINT): LONGINT;
  VAR q, save: LONGINT;
BEGIN
  save := b.len;
  IF (B.BlankLine(p) >= 0) OR B.HtmlCloser(p) OR B.DivCloser(p) THEN RETURN -1 END;
  q := B.GobbleSpaces(p, ci);
  IF q < 0 THEN RETURN -1 END;
  p := PutLine(b, q);
  IF p < 0 THEN b.len := save; RETURN -1 END;
  LOOP
    IF (B.BlankLine(p) >= 0) OR B.HtmlCloser(p) OR B.DivCloser(p) THEN EXIT END;
    q := B.GobbleSpaces(p, ci);
    IF q < 0 THEN
      IF B.ListStart(p) THEN EXIT END;
      q := p
    END;
    q := PutLine(b, q);
    IF q < 0 THEN EXIT END;
    p := q
  END;
  RETURN PutBlanks(b, p)
END ListContinuation;

(* taskListItemFromAscii *)
PROCEDURE TaskItem(blocks: A.Block);
  VAR i, n: A.Inline; check: A.Inline;
BEGIN
  IF (blocks = NIL) OR (blocks.kind # A.Plain) & (blocks.kind # A.Para) THEN
    RETURN
  END;
  i := blocks(A.InlinesBlk).inlines;
  IF (i = NIL) OR (i.kind # A.Str) THEN RETURN END;
  n := i.next;
  IF Ropes.EqualString(i(A.StrInl).text, "[") & (n # NIL) & (n.kind = A.Space)
      & (n.next # NIL) & (n.next.kind = A.Str)
      & Ropes.EqualString(n.next(A.StrInl).text, "]")
      & (n.next.next # NIL) & (n.next.next.kind = A.Space) THEN
    check := A.NewStr(Ropes.FromString("☐"));
    check.next := n.next.next
  ELSIF (Ropes.EqualString(i(A.StrInl).text, "[x]")
      OR Ropes.EqualString(i(A.StrInl).text, "[X]"))
      & (n # NIL) & (n.kind = A.Space) THEN
    check := A.NewStr(Ropes.FromString("☒"));
    check.next := n
  ELSE
    RETURN
  END;
  blocks(A.InlinesBlk).inlines := check
END TaskItem;

(* listItem at B.pos: its blocks in items *)
PROCEDURE ListItem(VAR items: A.BlockList; kind, style, delim: INTEGER): BOOLEAN;
  VAR b: B.Buf; p, q, ci: LONGINT; old: INTEGER; blocks: A.Block;
BEGIN
  old := B.context; B.context := B.ListItemState;
  B.InitBuf(b);
  p := RawListItem(b, B.pos, kind, style, delim, ci);
  IF p < 0 THEN B.context := old; RETURN FALSE END;
  q := ListContinuation(b, p, ci);
  WHILE q >= 0 DO p := q; q := ListContinuation(b, p, ci) END;
  B.pos := p;
  blocks := BlocksOf(b);
  B.context := old;
  TaskItem(blocks);
  NEW(items); items.blocks := blocks; items.next := NIL;
  RETURN TRUE
END ListItem;

(* many1 listItem: the items, NIL if there is none *)
PROCEDURE ListItems(kind, style, delim: INTEGER): A.BlockList;
  VAR first, last, item: A.BlockList;
BEGIN
  first := NIL; last := NIL;
  WHILE ListItem(item, kind, style, delim) DO
    IF first = NIL THEN first := item ELSE last.next := item END;
    last := item
  END;
  RETURN first
END ListItems;

PROCEDURE HasPara(b: A.Block): BOOLEAN;
BEGIN
  WHILE (b # NIL) & (b.kind # A.Para) DO b := b.next END;
  RETURN b # NIL
END HasPara;

(* compactify *)
PROCEDURE Compactify(items: A.BlockList);
  VAR it, last: A.BlockList; final, b: A.Block; others: BOOLEAN;
BEGIN
  IF items = NIL THEN RETURN END;
  last := items; others := FALSE;
  WHILE last.next # NIL DO
    others := others OR HasPara(last.blocks); last := last.next
  END;
  final := A.LastBlock(last.blocks);
  IF (final # NIL) & (final.kind = A.Para) & ~others THEN
    b := last.blocks;
    WHILE (b # final) & (b.kind # A.Para) DO b := b.next END;
    IF b = final THEN final.kind := A.Plain; RETURN END
  END;
  IF ~others & ~HasPara(last.blocks) THEN RETURN END;
  it := items;
  WHILE it # NIL DO
    b := it.blocks;
    WHILE b # NIL DO
      IF b.kind = A.Plain THEN b.kind := A.Para END;
      b := b.next
    END;
    it := it.next
  END
END Compactify;

(* bulletList *)
PROCEDURE BulletList(VAR l: A.Blocks): BOOLEAN;
  VAR items: A.BlockList;
BEGIN
  items := ListItems(BulletItem, 0, 0);
  IF items = NIL THEN RETURN FALSE END;
  Compactify(items);
  A.AddBlock(l, A.NewBulletList(items));
  RETURN TRUE
END BulletList;

(* orderedList *)
PROCEDURE OrderedList(VAR l: A.Blocks): BOOLEAN;
  VAR items: A.BlockList; start, save: LONGINT; style, delim: INTEGER;
BEGIN
  save := B.nextExample;
  IF B.OrderedListStart(B.pos, TRUE, start, style, delim) < 0 THEN
    B.nextExample := save; RETURN FALSE
  END;
  B.nextExample := save;
  items := ListItems(OrderedItem, style, delim);
  IF items = NIL THEN B.nextExample := save; RETURN FALSE END;
  Compactify(items);
  A.AddBlock(l, A.NewOrderedList(start, style, delim, items));
  RETURN TRUE
END OrderedList;

(* definitionListItem *)
PROCEDURE DefinitionItem(VAR item: A.DefItem): BOOLEAN;
  VAR start, e, q: LONGINT; term: A.Inline; tight: BOOLEAN;
    defs, d: A.BlockList; b: A.Block;
BEGIN
  start := B.pos;
  e := B.AnyLine(start);
  IF e < 0 THEN RETURN FALSE END;
  B.pos := e;
  q := B.BlankLines(B.pos);
  tight := q < 0;
  IF ~tight THEN B.pos := q END;
  defs := ListItems(DefItem, 0, 0);
  IF defs = NIL THEN B.pos := start; RETURN FALSE END;
  B.pos := B.SkipBlankLines(B.pos);
  term := I.ParseText(start, e - 1);
  IF tight THEN
    d := defs;
    WHILE d # NIL DO
      b := d.blocks;
      WHILE b # NIL DO
        IF b.kind = A.Para THEN b.kind := A.Plain END;
        b := b.next
      END;
      d := d.next
    END
  END;
  NEW(item); item.term := term; item.defs := defs; item.next := NIL;
  RETURN TRUE
END DefinitionItem;

(* definitionList *)
PROCEDURE DefinitionList(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; first, last, item: A.DefItem;
BEGIN
  p := B.AnyLine(B.pos);
  IF p < 0 THEN RETURN FALSE END;
  q := B.BlankLine(p);
  IF q >= 0 THEN p := q END;
  IF B.DefListStart(p) < 0 THEN RETURN FALSE END;
  first := NIL; last := NIL;
  WHILE DefinitionItem(item) DO
    IF first = NIL THEN first := item ELSE last.next := item END;
    last := item
  END;
  IF first = NIL THEN RETURN FALSE END;
  A.AddBlock(l, A.NewDefinitionList(first));
  RETURN TRUE
END DefinitionList;

(* Divs and HTML *)

(* The closing tag </name> at p: the position after it *)
PROCEDURE Closer(p: LONGINT; name: ARRAY OF CHAR): LONGINT;
  VAR tag: B.Tag;
BEGIN
  IF B.ScanTag(p, tag) & (tag.kind = B.TagClose) & (tag.name = name) THEN
    RETURN tag.end
  END;
  RETURN -1
END Closer;

(* The attributes of an HTML tag as a div's: id, class split into
   words, and the others *)
PROCEDURE DivAttr(VAR tag: B.Tag): A.Attr;
  VAR a: A.Attr; h: B.HtmlAttr; p, i, j: LONGINT; key, value: A.Rope;
    b: B.Buf;
BEGIN
  a := A.NewAttr(NIL);
  p := tag.attrStart;
  WHILE (p < tag.end) & B.NextHtmlAttr(p, h) DO
    key := NIL;
    FOR i := h.nameStart TO h.nameStart + h.nameLen - 1 DO
      key := Ropes.AppendChar(key, B.Lower(B.t[i]))
    END;
    IF h.valStart >= 0 THEN value := B.Rope(h.valStart, h.valStart + h.valLen)
    ELSE value := NIL
    END;
    IF Ropes.EqualString(key, "id") THEN
      a.id := value
    ELSIF Ropes.EqualString(key, "class") THEN
      B.InitBuf(b);
      IF h.valStart >= 0 THEN B.Put(b, h.valStart, h.valStart + h.valLen) END;
      i := 0;
      WHILE i < b.len DO
        WHILE (i < b.len) & B.IsWhite(b.t[i]) DO INC(i) END;
        j := i;
        WHILE (j < b.len) & ~B.IsWhite(b.t[j]) DO INC(j) END;
        IF j > i THEN A.AddClass(a, Ropes.FromSubchars(b.t^, i, j - i)) END;
        i := j
      END
    ELSE
      A.AddKeyVal(a, key, value)
    END;
    p := h.end
  END;
  RETURN a
END DivAttr;

(* Blocks up to the end of the text, or until stop holds at B.pos (or
   no block can be read) *)
PROCEDURE BlocksUntil(stop: I.Stop): A.Block;
  VAR l: A.Blocks;
BEGIN
  A.InitBlocks(l);
  WHILE (B.pos < B.len) & ~stop(B.pos) & Block(l) DO END;
  RETURN l.first
END BlocksUntil;

PROCEDURE DivCloseStop(p: LONGINT): BOOLEAN;
BEGIN
  RETURN Closer(p, "div") >= 0
END DivCloseStop;

(* divHtml *)
PROCEDURE DivHtml(VAR l: A.Blocks): BOOLEAN;
  VAR tag: B.Tag; old: B.Name; blocks: A.Block; q: LONGINT;
BEGIN
  IF ~B.ScanTag(B.pos, tag) OR (tag.kind # B.TagOpen) OR (tag.name # "div") THEN
    RETURN FALSE
  END;
  old := B.htmlBlock; B.htmlBlock := "div";
  B.pos := B.SkipBlankLines(tag.end);
  blocks := BlocksUntil(DivCloseStop);
  q := Closer(B.pos, "div");
  IF q >= 0 THEN B.pos := q END;
  B.htmlBlock := old;
  A.AddBlock(l, A.NewDiv(DivAttr(tag), blocks));
  RETURN TRUE
END DivHtml;

PROCEDURE DivFenceStop(p: LONGINT): BOOLEAN;
BEGIN
  RETURN B.DivFenceEnd(p) >= 0
END DivFenceStop;

(* divFenced *)
PROCEDURE DivFenced(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, s: LONGINT; a: A.Attr; blocks: A.Block;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, ":::") THEN RETURN FALSE END;
  INC(p, 3);
  WHILE B.C(p) = ":" DO INC(p) END;
  p := B.SkipSpaces(p);
  q := B.Attributes(p, a);
  IF q >= 0 THEN
    p := q
  ELSE
    s := p;
    WHILE (p < B.len) & ~B.IsWhite(B.C(p)) DO INC(p) END;
    IF p = s THEN RETURN FALSE END;
    a := A.NewAttr(NIL); A.AddClass(a, B.Rope(s, p))
  END;
  p := B.SkipSpaces(p);
  WHILE B.C(p) = ":" DO INC(p) END;
  p := B.BlankLine(p);
  IF p < 0 THEN RETURN FALSE END;
  B.pos := p;
  INC(B.divLevel);
  blocks := BlocksUntil(DivFenceStop);
  q := B.DivFenceEnd(B.pos);
  IF q >= 0 THEN B.pos := q END;
  DEC(B.divLevel);
  A.AddBlock(l, A.NewDiv(a, blocks));
  RETURN TRUE
END DivFenced;

PROCEDURE IsVerbatim(VAR tag: B.Tag): BOOLEAN;
BEGIN
  RETURN (tag.name = "pre") OR (tag.name = "style") OR (tag.name = "script")
    OR (tag.name = "textarea")
END IsVerbatim;

(* rawHtmlBlocks, the opening tag tag at B.pos *)
PROCEDURE RawHtmlBlocks(VAR l: A.Blocks; VAR tag: B.Tag);
  VAR p, q, indent, n: LONGINT; old: B.Name; contents: A.Blocks;
    close: B.Tag; done: BOOLEAN;
BEGIN
  p := B.SkipSpaces(tag.end);
  indent := 0;
  q := B.BlankLine(p);
  IF q >= 0 THEN
    p := q;
    WHILE B.IsSpace(B.C(p)) DO
      IF B.C(p) = " " THEN INC(indent) ELSE INC(indent, B.tabStop) END;
      INC(p)
    END
  END;
  old := B.htmlBlock; B.htmlBlock := tag.name;
  B.pos := p;
  A.InitBlocks(contents);
  IF ~tag.selfClosing THEN
    done := FALSE;
    WHILE ~done & (B.pos < B.len) DO
      p := B.pos;
      q := B.GobbleAtMost(p, indent, n);
      IF Closer(q, tag.name) >= 0 THEN done := TRUE
      ELSE
        B.pos := q;
        IF ~Block(contents) THEN B.pos := p; done := TRUE END
      END
    END
  END;
  A.AddBlock(l, A.NewRawBlock(A.S("html"), B.Rope(tag.start, tag.end)));
  IF contents.first # NIL THEN A.AddBlock(l, contents.first) END;
  q := B.GobbleAtMost(B.pos, indent, n);
  IF B.ScanTag(q, close) & (close.kind = B.TagClose) & (close.name = tag.name) THEN
    A.AddBlock(l, A.NewRawBlock(A.S("html"), B.Rope(close.start, close.end)));
    B.pos := close.end
  END;
  B.htmlBlock := old
END RawHtmlBlocks;

(* htmlBlock *)
PROCEDURE HtmlBlock(VAR l: A.Blocks): BOOLEAN;
  VAR tag: B.Tag; q: LONGINT;
BEGIN
  IF ~B.ScanTag(B.pos, tag) OR ~B.IsBlockTag(tag) THEN RETURN FALSE END;
  IF (tag.kind = B.TagOpen) & (tag.name[0] # "?") THEN
    IF IsVerbatim(tag) THEN
      q := B.HtmlInBalanced(B.pos, tag);
      IF q >= 0 THEN
        A.AddBlock(l, A.NewRawBlock(A.S("html"), B.Rope(B.pos, q)));
        B.pos := q;
        RETURN TRUE
      END
    END;
    RawHtmlBlocks(l, tag)
  ELSE
    (* htmlBlock': a closing tag, a comment or an instruction *)
    A.AddBlock(l, A.NewRawBlock(A.S("html"), B.Rope(tag.start, tag.end)));
    B.pos := B.SkipBlankLines(B.SkipSpaces(tag.end))
  END;
  RETURN TRUE
END HtmlBlock;

(* Quotes and line blocks *)

(* blockQuote *)
PROCEDURE BlockQuote(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; b: B.Buf; soft: BOOLEAN;
BEGIN
  p := B.QuoteStart(B.pos);
  IF p < 0 THEN RETURN FALSE END;
  B.InitBuf(b);
  LOOP
    (* emailLine *)
    LOOP
      q := p;
      WHILE (q < B.len) & (B.C(q) # 0AX) DO INC(q) END;
      B.Put(b, p, q); p := q;
      IF p >= B.len THEN EXIT END;
      q := I.Endline(p, soft);
      IF (q < 0) OR (B.QuoteStart(p + 1) >= 0) THEN EXIT END;
      B.PutChar(b, 0AX); p := q
    END;
    IF (B.C(p) = 0AX) & (B.QuoteStart(p + 1) >= 0) THEN
      B.PutChar(b, 0AX); p := B.QuoteStart(p + 1)
    ELSE
      EXIT
    END
  END;
  IF B.C(p) = 0AX THEN INC(p) END;
  B.pos := B.SkipBlankLines(p);
  B.PutChar(b, 0AX); B.PutChar(b, 0AX);
  A.AddBlock(l, A.NewBlockQuote(BlocksOf(b)));
  RETURN TRUE
END BlockQuote;

(* lineBlock *)
PROCEDURE LineBlock(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, e: LONGINT; b: B.Buf; first, last, line: A.InlineList;
BEGIN
  p := B.pos; first := NIL; last := NIL;
  LOOP
    IF B.C(p) # "|" THEN EXIT END;
    B.InitBuf(b);
    q := B.BlankLine(p + 1);
    IF (B.C(p + 1) = " ") & (B.C(B.SkipSpaces(p + 2)) # 0AX)
        & (B.AnyLine(p + 2) >= 0) THEN
      (* lineBlockLine *)
      q := p + 2;
      WHILE B.IsSpace(B.C(q)) DO B.PutChar(b, 0C2X); B.PutChar(b, 0A0X); INC(q) END;
      e := B.LineEnd(q);
      B.Put(b, q, e); p := e + 1;
      WHILE (B.C(p) = " ") & (B.AnyLine(p + 1) >= 0) DO
        e := B.LineEnd(p + 1);
        B.PutChar(b, " "); B.Put(b, p + 1, e); p := e + 1
      END
    ELSIF q >= 0 THEN
      (* blankLineBlockLine *)
      B.PutChar(b, 0AX); p := q
    ELSE
      EXIT
    END;
    NEW(line); line.inlines := InlinesOf(b); line.next := NIL;
    IF first = NIL THEN first := line ELSE last.next := line END;
    last := line
  END;
  IF first = NIL THEN RETURN FALSE END;
  B.pos := B.SkipBlankLines(p);
  A.AddBlock(l, A.NewLineBlock(first));
  RETURN TRUE
END LineBlock;

(* Paragraphs *)

(* para and plain *)
PROCEDURE Para(VAR l: A.Blocks): BOOLEAN;
  VAR il: A.Inlines; inl: A.Inline; p, q: LONGINT; kind: INTEGER;
BEGIN
  A.InitInlines(il);
  IF ~I.Inlines(il, NIL) THEN RETURN FALSE END;
  inl := I.Trim(il);
  kind := A.Plain;
  p := B.pos;
  IF B.C(p) = 0AX THEN
    q := B.BlankLines(p + 1);
    IF q >= 0 THEN kind := A.Para; B.pos := q
    ELSIF B.IsFencedCode(p + 1)
        OR (B.htmlBlock = "div") & (Closer(p + 1, "div") >= 0)
        OR (B.divLevel > 0) & (B.DivFenceEnd(p + 1) >= 0) THEN
      kind := A.Para; B.pos := p + 1
    END
  END;
  A.AddBlock(l, A.NewInlinesBlock(kind, inl));
  RETURN TRUE
END Para;

(* block: one block at B.pos, added to l (blank lines add nothing);
   FALSE if there is none *)
PROCEDURE Block(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  IF B.pos >= B.len THEN RETURN FALSE END;
  q := B.BlankLines(B.pos);
  IF q >= 0 THEN B.pos := q; RETURN TRUE END;
  IF FencedCode(l) OR BulletList(l) OR DivHtml(l) OR DivFenced(l)
      OR SetextHeader(l) OR AtxHeader(l) OR HtmlBlock(l)
      OR IndentedCode(l) OR LineBlock(l) OR BlockQuote(l) THEN
    RETURN TRUE
  END;
  q := B.Hrule(B.pos);
  IF q >= 0 THEN
    A.AddBlock(l, A.NewHorizontalRule()); B.pos := q;
    RETURN TRUE
  END;
  RETURN OrderedList(l) OR DefinitionList(l) OR Para(l)
END Block;

(* Reading *)

(* The document in text[0 .. n-1], pandoc markdown; tabStop is used
   where tabs are kept *)
PROCEDURE Read*(text: PdIO.Text; n: LONGINT; tabStop: INTEGER): A.Doc;
  VAR t: B.Text; i, k: LONGINT; d: A.Doc;
BEGIN
  (* ensureFinalNewlines 3 *)
  k := 0;
  WHILE (k < n) & (k < 3) & (text[n - 1 - k] = 0AX) DO INC(k) END;
  t := B.NewText(n + 3 - k);
  FOR i := 0 TO n - 1 DO t[i] := text[i] END;
  FOR i := n TO n + 2 - k DO t[i] := 0AX END;
  B.Start(t, n + 3 - k, tabStop);
  ids := NIL;
  d := A.NewDoc();
  d.blocks := ParseBlocks();
  RETURN d
END Read;

BEGIN
  ids := NIL
END PdMarkdown.
