(* PdRst: pandoc's reStructuredText reader (Text.Pandoc.Readers.RST),
   for -f rst. The inlines are PdRstInline's; this module has the
   blocks, the directives, and the resolution of references,
   substitutions and notes. *)
MODULE PdRst;

IMPORT Ropes, PdIO, PdSource, A := PdAst, B := PdMdBase, MI := PdMdInline,
  RI := PdRstInline, SH := PdShared;

CONST
  MaxStyles = 64;

TYPE
  Style = RECORD c: CHAR; double: BOOLEAN END;
  Note = POINTER TO NoteDesc;
  NoteDesc = RECORD ref, raw: A.Rope; next: Note END;
  Name = POINTER TO NameDesc;
  NameDesc = RECORD name: A.Rope; next: Name END;
  Message = ARRAY 1024 OF CHAR;
  RefWalker = POINTER TO RefWalkerDesc;
  RefWalkerDesc = RECORD (A.WalkerDesc) END;
  Id = POINTER TO IdDesc;
  IdDesc = RECORD id: A.Rope; next: Id END;

VAR
  autoIds*: BOOLEAN; (* auto_identifiers, on by default *)
  lhs*: BOOLEAN; (* the extension literate_haskell *)
  styles: ARRAY MaxStyles OF Style;
  nStyles: INTEGER;
  ids: Id; (* the header identifiers used *)
  highlight: A.Rope; (* the highlight directive's language, or NIL *)
  main: B.Text; mainLen: LONGINT;
  notes, notesLast: Note; (* stateNotes, in document order *)
  citations: Note; (* stateCitations, sorted by ref *)

PROCEDURE^ Block(VAR l: A.Blocks): BOOLEAN;
PROCEDURE^ ParseBlocks(): A.Block;

(* The column of p, counted in characters from the start of its line *)
PROCEDURE Column(p: LONGINT): LONGINT;
  VAR q, n: LONGINT; c: CHAR;
BEGIN
  q := p;
  WHILE (q > 0) & (B.t[q - 1] # 0AX) DO DEC(q) END;
  n := 0;
  WHILE q < p DO
    c := B.t[q];
    IF (c < 80X) OR (c >= 0C0X) THEN INC(n) END;
    INC(q)
  END;
  RETURN n
END Column;

(* The level of a header in the style c, double: the order in which the
   style was first seen *)
PROCEDURE Level(c: CHAR; double: BOOLEAN): INTEGER;
  VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (i < nStyles) & ((styles[i].c # c) OR (styles[i].double # double)) DO
    INC(i)
  END;
  IF (i = nStyles) & (nStyles < MaxStyles) THEN
    styles[i].c := c; styles[i].double := double; INC(nStyles)
  END;
  RETURN i + 1
END Level;

PROCEDURE Used(id: A.Rope): BOOLEAN;
  VAR p: Id;
BEGIN
  p := ids;
  WHILE (p # NIL) & ~Ropes.Equal(p.id, id) DO p := p.next END;
  RETURN p # NIL
END Used;

PROCEDURE Use(id: A.Rope);
  VAR p: Id;
BEGIN
  NEW(p); p.id := id; p.next := ids; ids := p
END Use;

(* registerHeader: the attribute of a header with the text inl, with an
   identifier made unique if auto_identifiers is on *)
PROCEDURE HeaderAttr(inl: A.Inline): A.Attr;
  VAR id, try: A.Rope; n: LONGINT;
BEGIN
  IF ~autoIds THEN RETURN NIL END;
  id := MI.Identifier(inl);
  IF id = NIL THEN id := Ropes.FromString("section") END;
  try := id; n := 0;
  WHILE Used(try) DO
    INC(n);
    try := Ropes.Cat(Ropes.Cat(id, Ropes.FromString("-")), SH.IntRope(n))
  END;
  Use(try);
  RETURN A.NewAttr(try)
END HeaderAttr;

(* The inlines of one line from B.pos: many1 (notFollowedBy blankline
   >> inline); NIL if there are none *)
PROCEDURE LineInlines(): A.Inline;
  VAR l: A.Inlines;
BEGIN
  A.InitInlines(l);
  WHILE (B.BlankLine(B.pos) < 0) & RI.Inline(l) DO END;
  RETURN MI.Trim(l)
END LineInlines;

(* singleHeader *)
PROCEDURE SingleHeader(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, r, n: LONGINT; c: CHAR; inl: A.Inline;
BEGIN
  p := B.pos;
  IF B.IsSpace(B.C(p)) THEN RETURN FALSE END;
  q := B.AnyLine(p);
  IF (q < 0) OR ~RI.IsUnderlineChar(B.C(q)) THEN RETURN FALSE END;
  inl := LineInlines();
  IF inl = NIL THEN B.pos := p; RETURN FALSE END;
  n := Column(B.pos);
  q := B.BlankLine(B.pos);
  IF q < 0 THEN B.pos := p; RETURN FALSE END;
  c := B.C(q);
  IF ~RI.IsUnderlineChar(c) THEN B.pos := p; RETURN FALSE END;
  r := q;
  WHILE B.C(q) = c DO INC(q) END;
  IF q - r < n THEN B.pos := p; RETURN FALSE END;
  q := B.BlankLines(q);
  IF q < 0 THEN B.pos := p; RETURN FALSE END;
  B.pos := q;
  A.AddBlock(l, A.NewHeader(Level(c, FALSE), HeaderAttr(inl), inl));
  RETURN TRUE
END SingleHeader;

(* doubleHeader *)
PROCEDURE DoubleHeader(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, top, n: LONGINT; c: CHAR; inl: A.Inline;
BEGIN
  p := B.pos; c := B.C(p);
  IF ~RI.IsUnderlineChar(c) THEN RETURN FALSE END;
  q := p;
  WHILE B.C(q) = c DO INC(q) END;
  top := q - p;
  WHILE B.IsSpace(B.C(q)) DO INC(q) END;
  IF B.C(q) # 0AX THEN RETURN FALSE END;
  B.pos := q + 1;
  inl := LineInlines();
  IF inl = NIL THEN B.pos := p; RETURN FALSE END;
  n := Column(B.pos);
  q := B.BlankLine(B.pos);
  IF (n > top) OR (q < 0) THEN B.pos := p; RETURN FALSE END;
  n := 0;
  WHILE (n < top) & (B.C(q) = c) DO INC(q); INC(n) END;
  IF n < top THEN B.pos := p; RETURN FALSE END;
  q := B.BlankLines(q);
  IF q < 0 THEN B.pos := p; RETURN FALSE END;
  B.pos := q;
  A.AddBlock(l, A.NewHeader(Level(c, TRUE), HeaderAttr(inl), inl));
  RETURN TRUE
END DoubleHeader;

(* hrule *)
PROCEDURE Hrule(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  q := RI.Hrule(B.pos);
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  A.AddBlock(l, A.NewHorizontalRule());
  RETURN TRUE
END Hrule;


(* The number of LFs in t[from .. to-1] put into b *)
PROCEDURE PutLFs(VAR b: B.Buf; from, to: LONGINT);
BEGIN
  WHILE from < to DO
    IF B.t[from] = 0AX THEN B.PutChar(b, 0AX) END;
    INC(from)
  END
END PutLFs;

(* indentedBlock at p: its text in b; the position after it, or -1 *)
PROCEDURE IndentedBlock(p: LONGINT; VAR b: B.Buf): LONGINT;
  VAR n, q, r, e, cnt, lines: LONGINT;
BEGIN
  n := 0; q := p;
  WHILE B.IsSpace(B.C(q)) DO INC(q); INC(n) END;
  IF n = 0 THEN RETURN -1 END;
  B.InitBuf(b); lines := 0;
  LOOP
    q := p;
    r := B.BlankLines(q);
    IF r >= 0 THEN q := r END;
    IF ~B.IsSpace(B.C(q)) THEN EXIT END;
    r := B.GobbleAtMost(q, n, cnt);
    e := B.AnyLine(r);
    IF e < 0 THEN EXIT END;
    PutLFs(b, p, q);
    B.Put(b, r, e - 1); B.PutChar(b, 0AX);
    p := e; INC(lines)
  END;
  IF lines = 0 THEN RETURN -1 END;
  RETURN B.SkipBlankLines(p)
END IndentedBlock;

(* quotedBlock at p: its text in b; the position after it, or -1 *)
PROCEDURE QuotedBlock(p: LONGINT; VAR b: B.Buf): LONGINT;
  VAR c: CHAR; e: LONGINT;
BEGIN
  c := B.C(p);
  IF (c <= " ") OR (c >= 7FX) OR B.IsAlnum(c) THEN RETURN -1 END;
  B.InitBuf(b);
  WHILE B.C(p) = c DO
    e := B.AnyLine(p);
    IF e < 0 THEN RETURN -1 END;
    B.Put(b, p, e - 1); B.PutChar(b, 0AX); p := e
  END;
  RETURN B.SkipBlankLines(p)
END QuotedBlock;

(* stripTrailingNewlines *)
PROCEDURE StripNewlines(VAR b: B.Buf);
BEGIN
  WHILE (b.len > 0) & (b.t[b.len - 1] = 0AX) DO DEC(b.len) END
END StripNewlines;

(* codeBlockBody *)
PROCEDURE CodeBlockBody(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT; b: B.Buf; a: A.Attr; r: A.Rope;
BEGIN
  q := IndentedBlock(B.pos, b);
  IF q < 0 THEN q := QuotedBlock(B.pos, b) END;
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  StripNewlines(b);
  a := NIL;
  IF highlight # NIL THEN a := A.NewAttr(NIL); A.AddClass(a, highlight) END;
  r := B.BufRope(b);
  IF r = NIL THEN r := Ropes.FromString("") END;
  A.AddBlock(l, A.NewCodeBlock(a, r));
  RETURN TRUE
END CodeBlockBody;

(* codeBlock: :: and two blank lines, then the body *)
PROCEDURE CodeBlock(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "::") THEN RETURN FALSE END;
  q := B.BlankLine(p + 2);
  IF q >= 0 THEN q := B.BlankLine(q) END;
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  IF CodeBlockBody(l) THEN RETURN TRUE END;
  B.pos := p;
  RETURN FALSE
END CodeBlock;

(* parseFromString' parseBlocks: the blocks of the text in b *)
PROCEDURE BlocksOf(VAR b: B.Buf): A.Block;
  VAR f: B.Frame; r: A.Block;
BEGIN
  B.Enter(f, b.t, b.len);
  r := ParseBlocks();
  B.Leave(f);
  RETURN r
END BlocksOf;

(* blockQuote *)
PROCEDURE BlockQuote(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT; b: B.Buf;
BEGIN
  q := IndentedBlock(B.pos, b);
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  B.PutChar(b, 0AX); B.PutChar(b, 0AX);
  A.AddBlock(l, A.NewBlockQuote(BlocksOf(b)));
  RETURN TRUE
END BlockQuote;

(* comment *)
PROCEDURE Comment(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; b: B.Buf;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "..") THEN RETURN FALSE END;
  q := p + 2;
  IF B.IsSpace(B.C(q)) THEN
    WHILE B.IsSpace(B.C(q)) DO INC(q) END
  ELSIF B.C(q) # 0AX THEN RETURN FALSE
  END;
  q := B.AnyLine(q);
  IF q < 0 THEN RETURN FALSE END;
  p := IndentedBlock(q, b);
  IF p >= 0 THEN q := p END;
  B.pos := B.SkipBlankLines(q);
  RETURN TRUE
END Comment;

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
    NEW(line); line.inlines := RI.ParseInlines(b.t^, 0, b.len); line.next := NIL;
    IF first = NIL THEN first := line ELSE last.next := line END;
    last := line
  END;
  IF first = NIL THEN RETURN FALSE END;
  B.pos := B.SkipBlankLines(p);
  A.AddBlock(l, A.NewLineBlock(first));
  RETURN TRUE
END LineBlock;

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
  IF last.blocks # NIL THEN final := A.LastBlock(last.blocks) ELSE final := NIL END;
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

(* The list marker at p of the kind ordered (with style and delim) or
   bullet, and the white space after it; the position after them, or
   -1; width is their length in columns *)
PROCEDURE MarkerStart(p: LONGINT; ordered: BOOLEAN; style, delim: INTEGER;
                      VAR width: LONGINT): LONGINT;
  VAR q, num: LONGINT; s, d: INTEGER;
BEGIN
  IF ~ordered THEN RETURN RI.BulletStart(p, width) END;
  s := style; d := delim;
  q := B.ListMarker(p, FALSE, num, s, d);
  IF q < 0 THEN RETURN -1 END;
  width := Column(q) - Column(p);
  IF B.IsSpace(B.C(q)) THEN
    WHILE B.IsSpace(B.C(q)) DO INC(q); INC(width) END
  ELSIF B.C(q) # 0AX THEN RETURN -1
  END;
  RETURN q
END MarkerStart;

(* listItem: the item at B.pos, its blocks in blocks *)
PROCEDURE ListItem(ordered: BOOLEAN; style, delim: INTEGER;
                   VAR blocks: A.Block): BOOLEAN;
  VAR p, q, r, e, w, dummy: LONGINT; b: B.Buf; save: INTEGER;
    first: A.Block;
BEGIN
  p := B.pos;
  q := MarkerStart(p, ordered, style, delim, w);
  IF q < 0 THEN RETURN FALSE END;
  B.InitBuf(b);
  e := B.AnyLine(q);
  IF e < 0 THEN RETURN FALSE END;
  B.Put(b, q, e); q := e;
  LOOP (* listLine and listContinuation *)
    r := q;
    WHILE B.BlankLine(r) >= 0 DO r := B.BlankLine(r) END;
    IF B.BlankLine(r) >= 0 THEN EXIT END;
    e := B.GobbleSpaces(r, w);
    IF e < 0 THEN EXIT END;
    e := B.AnyLine(e);
    IF e < 0 THEN EXIT END;
    PutLFs(b, q, r);
    B.Put(b, B.GobbleSpaces(r, w), e); q := e
  END;
  r := B.BlankLines(q);
  IF r >= 0 THEN q := r
  ELSIF MarkerStart(q, ordered, style, delim, dummy) < 0 THEN RETURN FALSE
  END;
  B.pos := q;
  B.PutChar(b, 0AX);
  save := B.context; B.context := B.ListItemState;
  blocks := BlocksOf(b);
  B.context := save;
  first := blocks;
  IF (first # NIL) & (first.kind = A.Para) & ((first.next = NIL)
      OR (first.next.next = NIL) & ((first.next.kind = A.BulletList)
        OR (first.next.kind = A.OrderedList) OR (first.next.kind = A.DefinitionList))) THEN
    first.kind := A.Plain
  END;
  RETURN TRUE
END ListItem;

(* bulletList and orderedList *)
PROCEDURE List(VAR l: A.Blocks; ordered: BOOLEAN): BOOLEAN;
  VAR first, last, it: A.BlockList; blocks: A.Block; num, q, w: LONGINT;
    style, delim: INTEGER; save: LONGINT;
BEGIN
  style := 0; delim := 0; num := 1;
  IF ordered THEN
    save := B.nextExample;
    q := B.ListMarker(B.pos, TRUE, num, style, delim);
    B.nextExample := save;
    IF (q < 0) OR (style = A.Example) OR ~B.IsSpace(B.C(q)) THEN RETURN FALSE END
  ELSIF RI.BulletStart(B.pos, w) < 0 THEN RETURN FALSE
  END;
  first := NIL; last := NIL;
  WHILE ListItem(ordered, style, delim, blocks) DO
    NEW(it); it.blocks := blocks; it.next := NIL;
    IF first = NIL THEN first := it ELSE last.next := it END;
    last := it
  END;
  IF first = NIL THEN RETURN FALSE END;
  Compactify(first);
  IF ordered THEN A.AddBlock(l, A.NewOrderedList(num, style, delim, first))
  ELSE A.AddBlock(l, A.NewBulletList(first))
  END;
  RETURN TRUE
END List;

(* definitionListItem *)
PROCEDURE DefItem(VAR item: A.DefItem): BOOLEAN;
  VAR p, q: LONGINT; il, tmp: A.Inlines; b: B.Buf; 
BEGIN
  p := B.pos;
  IF B.Looking(p, "..") THEN RETURN FALSE END;
  A.InitInlines(il);
  LOOP
    IF B.C(B.pos) = 0AX THEN
      A.InitInlines(tmp);
      IF RI.Endline(tmp) & (il.first # NIL) THEN EXIT END;
      B.pos := p; RETURN FALSE
    END;
    IF ~RI.Inline(il) THEN B.pos := p; RETURN FALSE END
  END;
  q := IndentedBlock(B.pos, b);
  IF q < 0 THEN B.pos := p; RETURN FALSE END;
  B.pos := q;
  B.PutChar(b, 0AX);
  NEW(item); item.term := MI.Trim(il); item.next := NIL;
  NEW(item.defs); item.defs.blocks := BlocksOf(b); item.defs.next := NIL;
  RETURN TRUE
END DefItem;

(* definitionList *)
PROCEDURE DefinitionList(VAR l: A.Blocks): BOOLEAN;
  VAR first, last, it: A.DefItem;
BEGIN
  first := NIL; last := NIL;
  WHILE DefItem(it) DO
    IF first = NIL THEN first := it ELSE last.next := it END;
    last := it
  END;
  IF first = NIL THEN RETURN FALSE END;
  A.AddBlock(l, A.NewDefinitionList(first));
  RETURN TRUE
END DefinitionList;


(* Messages *)

PROCEDURE Cat(VAR m: ARRAY OF CHAR; s: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE m[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (s[j] # 0X) & (i < LEN(m) - 1) DO m[i] := s[j]; INC(i); INC(j) END;
  m[i] := 0X
END Cat;

PROCEDURE CatRope(VAR m: ARRAY OF CHAR; r: A.Rope);
  VAR i, j, n: LONGINT;
BEGIN
  i := 0; WHILE m[i] # 0X DO INC(i) END;
  IF r # NIL THEN n := Ropes.Length(r) ELSE n := 0 END;
  j := 0;
  WHILE (j < n) & (i < LEN(m) - 1) DO m[i] := Ropes.Fetch(r, j); INC(i); INC(j) END;
  m[i] := 0X
END CatRope;

PROCEDURE CatNum(VAR m: ARRAY OF CHAR; n: LONGINT);
  VAR d: ARRAY 24 OF CHAR; i, k: INTEGER;
BEGIN
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  k := 0; WHILE m[k] # 0X DO INC(k) END;
  WHILE (i > 0) & (k < LEN(m) - 1) DO DEC(i); m[k] := d[i]; INC(k) END;
  m[k] := 0X
END CatNum;

(* Warns as pandoc's log message msg, at the end of the document, where
   pandoc's resolution of references reports *)
PROCEDURE WarnAtEnd(msg: ARRAY OF CHAR);
  VAR m: Message; name: ARRAY 512 OF CHAR; line: LONGINT;
BEGIN
  COPY(msg, m); Cat(m, " at ");
  name[0] := 0X; line := 1;
  IF (main # NIL) & (mainLen > 0) THEN
    PdSource.Locate(main^, mainLen - 1, name, line); INC(line)
  END;
  IF (name # "") & (name # "-") THEN Cat(m, name); Cat(m, " ") END;
  Cat(m, "line "); CatNum(m, line); Cat(m, " column 1");
  PdIO.Warn(m)
END WarnAtEnd;

(* Appends c's text to b *)
PROCEDURE PutBuf(VAR b: B.Buf; VAR c: B.Buf);
  VAR i: LONGINT;
BEGIN
  FOR i := 0 TO c.len - 1 DO B.PutChar(b, c.t[i]) END
END PutBuf;

PROCEDURE IsAlnumAt(p: LONGINT): BOOLEAN;
BEGIN
  RETURN B.IsAlnum(B.C(p)) OR (B.C(p) >= 80X)
END IsAlnumAt;

(* noteBlock' with noteMarker (cite FALSE) or citationMarker *)
PROCEDURE NoteBlock0(cite: BOOLEAN; VAR ref, raw: A.Rope): BOOLEAN;
  VAR p, q, e, r: LONGINT; b, c: B.Buf;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "..") OR ~B.IsSpace(B.C(p + 2)) THEN RETURN FALSE END;
  q := p + 2;
  WHILE B.IsSpace(B.C(q)) DO INC(q) END;
  IF cite THEN e := RI.CitationMarker(q) ELSE e := RI.NoteMarker(q) END;
  IF e < 0 THEN RETURN FALSE END;
  ref := B.Rope(q + 1, e - 1);
  B.InitBuf(b);
  IF B.IsSpace(B.C(e)) THEN
    WHILE B.IsSpace(B.C(e)) DO INC(e) END;
    q := B.AnyLine(e);
    IF q < 0 THEN RETURN FALSE END;
    B.Put(b, e, q - 1)
  ELSIF B.C(e) = 0AX THEN q := e + 1
  ELSE RETURN FALSE
  END;
  B.PutChar(b, 0AX);
  r := B.BlankLines(q);
  IF r >= 0 THEN PutLFs(b, q, r); q := r END;
  r := IndentedBlock(q, c);
  IF r >= 0 THEN PutBuf(b, c); q := r END;
  B.PutChar(b, 0AX);
  B.pos := q;
  raw := B.BufRope(b);
  RETURN TRUE
END NoteBlock0;

(* noteBlock *)
PROCEDURE NoteBlock(VAR l: A.Blocks): BOOLEAN;
  VAR n: Note;
BEGIN
  NEW(n);
  IF ~NoteBlock0(FALSE, n.ref, n.raw) THEN RETURN FALSE END;
  n.next := NIL;
  IF notes = NIL THEN notes := n ELSE notesLast.next := n END;
  notesLast := n;
  RETURN TRUE
END NoteBlock;

(* citationBlock *)
PROCEDURE CitationBlock(VAR l: A.Blocks): BOOLEAN;
  VAR n, p, prev: Note; a: A.Attr; c: INTEGER;
BEGIN
  NEW(n);
  IF ~NoteBlock0(TRUE, n.ref, n.raw) THEN RETURN FALSE END;
  prev := NIL; p := citations; c := -1;
  WHILE (p # NIL) & (Ropes.Compare(p.ref, n.ref) < 0) DO prev := p; p := p.next END;
  IF (p # NIL) & (Ropes.Compare(p.ref, n.ref) = 0) THEN p.raw := n.raw
  ELSE
    n.next := p;
    IF prev = NIL THEN citations := n ELSE prev.next := n END
  END;
  a := A.NewAttr(NIL); A.AddClass(a, A.S("citation"));
  RI.SetKey(RI.RopeKey(n.ref), Ropes.Cat(A.S("#"), n.ref), NIL, a);
  RETURN TRUE
END CitationBlock;

(* referenceNames at B.pos: the names in first; the position after
   them, or -1 *)
PROCEDURE ReferenceNames(VAR first: Name): LONGINT;
  VAR p, q, e: LONGINT; b: B.Buf; n, last: Name; c: CHAR;
BEGIN
  p := B.pos; first := NIL; last := NIL;
  LOOP
    IF ~B.Looking(p, ".. _") THEN EXIT END;
    q := p + 4;
    B.InitBuf(b);
    e := RI.QuotedName(q);
    IF e >= 0 THEN B.Put(b, q + 1, e - 1); q := e
    ELSE
      LOOP
        c := B.C(q);
        IF (c = "\") & (B.C(q + 1) = ":") THEN B.PutChar(b, ":"); INC(q, 2)
        ELSIF (c = 0AX) & B.Looking(q + 1, "   ") & (B.BlankLine(q + 4) < 0) THEN
          B.PutChar(b, 0AX); INC(q, 4)
        ELSIF (c = ":") & IsAlnumAt(q + 1) THEN B.PutChar(b, ":"); INC(q)
        ELSIF (c = "\") OR (c = ":") OR (c = 0AX) OR (q >= B.len) THEN EXIT
        ELSE B.PutChar(b, c); INC(q)
        END
      END
    END;
    IF B.C(q) # ":" THEN EXIT END;
    NEW(n); n.name := B.BufRope(b); n.next := NIL;
    IF n.name = NIL THEN n.name := A.S("") END;
    IF first = NIL THEN first := n ELSE last.next := n END;
    last := n;
    p := q + 1;
    e := B.BlankLines(p);
    IF (e < 0) OR ~B.Looking(e, ".. _") THEN EXIT END;
    p := e
  END;
  IF first = NIL THEN RETURN -1 END;
  RETURN p
END ReferenceNames;

(* targetURI at p: the target in src; the position after it, or -1 *)
PROCEDURE TargetURI(p: LONGINT; VAR src: A.Rope): LONGINT;
  VAR q, r: LONGINT; b, e: B.Buf; c: CHAR; i, j: LONGINT;
BEGIN
  q := p;
  WHILE B.IsSpace(B.C(q)) DO INC(q) END;
  IF (B.C(q) = 0AX) & (B.BlankLine(q + 1) < 0) THEN INC(q) END;
  B.InitBuf(b);
  LOOP
    c := B.C(q);
    IF (c # 0AX) & (q < B.len) THEN B.PutChar(b, c); INC(q)
    ELSIF (c = 0AX) & B.IsSpace(B.C(q + 1)) THEN
      r := q + 1;
      WHILE B.IsSpace(B.C(r)) DO INC(r) END;
      IF (B.C(r) = 0AX) OR (r >= B.len) THEN EXIT END;
      B.PutChar(b, B.C(r)); q := r + 1
    ELSE EXIT
    END
  END;
  IF b.len = 0 THEN RETURN -1 END;
  q := B.BlankLines(q);
  IF q < 0 THEN RETURN -1 END;
  RI.TrimBuf(b);
  i := b.len;
  IF (i >= 2) & (b.t[i - 1] = "_") & (b.t[i - 2] = "`") THEN
    j := 0;
    WHILE (j < i - 2) & (b.t[j] = "`") DO INC(j) END;
    src := Ropes.Cat(Ropes.FromSubchars(b.t^, j, i - 2 - j), A.S("_"))
  ELSIF (i >= 1) & (b.t[i - 1] = "_") THEN src := B.BufRope(b)
  ELSE
    B.InitBuf(e); MI.EscapeURI(b.t^, b.len, e); src := B.BufRope(e)
  END;
  IF src = NIL THEN src := A.S("") END;
  RETURN q
END TargetURI;

(* anonymousKey and regularKey *)
PROCEDURE ReferenceKey(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; src: A.Rope; names: Name; m: ARRAY 8 OF CHAR;
    n: LONGINT; i: INTEGER;
BEGIN
  p := B.pos; q := -1;
  IF B.Looking(p, ".. __:") THEN q := p + 6
  ELSIF B.Looking(p, "__") THEN q := p + 2
  END;
  IF (q >= 0) & B.IsSpace(B.C(q)) THEN
    q := TargetURI(q, src);
    IF q >= 0 THEN
      n := RI.keyCount; m := "_0000"; i := 4;
      WHILE (i > 0) & (n > 0) DO m[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; DEC(i) END;
      RI.SetKey(RI.RopeKey(A.S(m)), src, NIL, NIL);
      B.pos := B.SkipBlankLines(q);
      RETURN TRUE
    END
  END;
  q := ReferenceNames(names);
  IF q < 0 THEN RETURN FALSE END;
  q := TargetURI(q, src);
  IF (q < 0) OR (Ropes.Length(src) = 0) THEN RETURN FALSE END;
  WHILE names # NIL DO
    RI.SetKey(RI.RopeKey(names.name), src, NIL, NIL);
    names := names.next
  END;
  B.pos := B.SkipBlankLines(q);
  RETURN TRUE
END ReferenceKey;

(* anchor *)
PROCEDURE Anchor(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; names, n, rev: Name; bl: A.Blocks; b: A.Block;
    h: A.HeaderBlk; il: A.Inlines;
BEGIN
  p := B.pos;
  q := ReferenceNames(names);
  IF q < 0 THEN RETURN FALSE END;
  q := B.BlankLines(q);
  IF q < 0 THEN RETURN FALSE END;
  n := names;
  WHILE n # NIL DO
    RI.SetKey(RI.RopeKey(n.name), Ropes.Cat(A.S("#"), n.name), NIL, NIL);
    n := n.next
  END;
  B.pos := q;
  A.InitBlocks(bl);
  IF ~Block(bl) THEN B.pos := p; RETURN FALSE END;
  b := bl.first;
  IF (b # NIL) & (b.next = NIL) & (b.kind = A.Header) THEN
    rev := NIL; n := names;
    WHILE n # NIL DO
      NEW(names); names^ := n^; names.next := rev; rev := names; n := n.next
    END;
    h := b(A.HeaderBlk);
    IF h.attr = NIL THEN h.attr := A.NewAttr(rev.name) ELSE h.attr.id := rev.name END;
    A.InitInlines(il); A.AddInline(il, h.inlines);
    n := rev.next;
    WHILE n # NIL DO
      A.AddInline(il, A.NewSpan(A.NewAttr(n.name), NIL));
      n := n.next
    END;
    h.inlines := il.first;
    A.AddBlock(l, b)
  ELSE
    (* foldr addDiv b refs *)
    rev := NIL; n := names;
    WHILE n # NIL DO
      NEW(names); names^ := n^; names.next := rev; rev := names; n := n.next
    END;
    n := rev;
    WHILE n # NIL DO
      b := A.NewDiv(A.NewAttr(n.name), b);
      n := n.next
    END;
    A.AddBlock(l, b)
  END;
  RETURN TRUE
END Anchor;


(* A single Para in bl becomes Plain (pandoc's #7766) *)
PROCEDURE PlainIfPara(bl: A.Block);
BEGIN
  IF (bl # NIL) & (bl.next = NIL) & (bl.kind = A.Para) THEN bl.kind := A.Plain END
END PlainIfPara;

(* fieldListItem minIndent *)
PROCEDURE FieldItem(minIndent: LONGINT; VAR item: A.DefItem): BOOLEAN;
  VAR p, q, ns, e, r, f, indent, i: LONGINT; b, c: B.Buf; bl: A.Block;
BEGIN
  p := B.pos; q := p; indent := 0;
  WHILE B.C(q) = " " DO INC(q); INC(indent) END;
  IF (indent < minIndent) OR (B.C(q) # ":") THEN RETURN FALSE END;
  ns := q + 1; e := ns;
  IF (B.C(e) = 0AX) OR (e >= B.len) THEN RETURN FALSE END;
  INC(e);
  WHILE (B.C(e) # ":") & (B.C(e) # 0AX) & (e < B.len) DO INC(e) END;
  IF B.C(e) # ":" THEN RETURN FALSE END;
  r := e + 1;
  IF B.C(r) # 0AX THEN
    IF ~B.IsSpace(B.C(r)) THEN RETURN FALSE END;
    WHILE B.IsSpace(B.C(r)) DO INC(r) END
  END;
  f := B.AnyLine(r);
  IF f < 0 THEN RETURN FALSE END;
  B.InitBuf(b);
  IF f - 1 > r THEN B.Put(b, r, f - 1); B.PutChar(b, 0AX) END;
  i := 0;
  WHILE (i < indent) & (B.C(f + i) = " ") DO INC(i) END;
  IF (i = indent) & B.IsSpace(B.C(f + i)) THEN
    q := IndentedBlock(f, c);
    IF q >= 0 THEN PutBuf(b, c); f := q END
  END;
  IF b.len > 0 THEN B.PutChar(b, 0AX) END;
  NEW(item); item.next := NIL;
  item.term := RI.ParseInlines(B.t^, ns, e - ns);
  B.pos := B.SkipBlankLines(f);
  bl := BlocksOf(b);
  PlainIfPara(bl);
  NEW(item.defs); item.defs.blocks := bl; item.defs.next := NIL;
  RETURN TRUE
END FieldItem;

(* fieldList *)
PROCEDURE FieldList(VAR l: A.Blocks): BOOLEAN;
  VAR first, last, it: A.DefItem; indent: LONGINT;
BEGIN
  indent := 0;
  WHILE B.IsSpace(B.C(B.pos + indent)) DO INC(indent) END;
  first := NIL; last := NIL;
  WHILE FieldItem(indent, it) DO
    IF first = NIL THEN first := it ELSE last.next := it END;
    last := it
  END;
  IF first = NIL THEN RETURN FALSE END;
  A.AddBlock(l, A.NewDefinitionList(first));
  RETURN TRUE
END FieldList;

PROCEDURE IsOptChar(p: LONGINT): BOOLEAN;
BEGIN
  RETURN IsAlnumAt(p) OR (B.C(p) = "_") OR (B.C(p) = "-")
END IsOptChar;

(* optArg at p: the position after it, or -1 *)
PROCEDURE OptArg(p: LONGINT): LONGINT;
BEGIN
  IF B.C(p) = "<" THEN
    INC(p);
    WHILE (B.C(p) # "<") & (B.C(p) # ">") & (p < B.len) DO INC(p) END;
    IF B.C(p) # ">" THEN RETURN -1 END;
    RETURN p + 1
  ELSIF B.IsLetter(B.C(p)) OR (B.C(p) >= 80X) THEN
    INC(p);
    WHILE IsOptChar(p) DO INC(p) END;
    RETURN p
  END;
  RETURN -1
END OptArg;

(* shortOpt, longOpt or dosOpt at p: the position after it, or -1 *)
PROCEDURE AnyOpt(p: LONGINT): LONGINT;
  VAR q, r: LONGINT;
BEGIN
  IF (B.C(p) = "-") & IsAlnumAt(p + 1) THEN (* shortOpt *)
    q := p + 2;
    r := q; IF B.C(r) = " " THEN INC(r) END;
    r := OptArg(r);
    IF r >= 0 THEN q := r END;
    RETURN q
  ELSIF B.Looking(p, "--") & IsAlnumAt(p + 2) & IsOptChar(p + 3) THEN
    q := p + 4;
    WHILE IsOptChar(q) DO INC(q) END;
    IF (B.C(q) = " ") OR (B.C(q) = "=") THEN
      r := OptArg(q + 1);
      IF r >= 0 THEN q := r END
    END;
    RETURN q
  ELSIF (B.C(p) = "/") & (IsAlnumAt(p + 1) OR (B.C(p + 1) = "?")) THEN
    q := p + 2;
    IF B.C(q) = " " THEN
      r := OptArg(q + 1);
      IF r >= 0 THEN q := r END
    END;
    RETURN q
  END;
  RETURN -1
END AnyOpt;

(* optionListItem *)
PROCEDURE OptionItem(VAR item: A.DefItem): BOOLEAN;
  VAR p, q, r, e: LONGINT; b, c: B.Buf; opts: A.Rope;
BEGIN
  p := B.pos;
  q := AnyOpt(p);
  IF q < 0 THEN RETURN FALSE END;
  LOOP
    IF B.C(q) # "," THEN EXIT END;
    r := q + 1;
    WHILE B.IsSpace(B.C(r)) DO INC(r) END;
    r := AnyOpt(r);
    IF r < 0 THEN EXIT END;
    q := r
  END;
  opts := B.Rope(p, q);
  B.InitBuf(b);
  IF (B.C(q) = " ") & (B.C(q + 1) = " ") THEN
    r := q;
    WHILE B.C(r) = " " DO INC(r) END;
    e := B.AnyLine(r);
    IF e < 0 THEN RETURN FALSE END;
    B.Put(b, r, e - 1); B.PutChar(b, 0AX); q := e
  ELSE
    WHILE B.IsSpace(B.C(q)) DO INC(q) END;
    IF B.C(q) # 0AX THEN RETURN FALSE END;
    INC(q)
  END;
  r := IndentedBlock(q, c);
  IF r >= 0 THEN PutBuf(b, c); q := r END;
  B.PutChar(b, 0AX); B.PutChar(b, 0AX);
  B.pos := B.SkipBlankLines(q);
  NEW(item); item.next := NIL;
  item.term := A.NewCode(A.NewAttr(NIL), opts);
  NEW(item.defs); item.defs.blocks := BlocksOf(b); item.defs.next := NIL;
  RETURN TRUE
END OptionItem;

(* optionList *)
PROCEDURE OptionList(VAR l: A.Blocks): BOOLEAN;
  VAR first, last, it: A.DefItem;
BEGIN
  first := NIL; last := NIL;
  WHILE OptionItem(it) DO
    IF first = NIL THEN first := it ELSE last.next := it END;
    last := it
  END;
  IF first = NIL THEN RETURN FALSE END;
  A.AddBlock(l, A.NewDefinitionList(first));
  RETURN TRUE
END OptionList;


(* latexBlockLine s at p: the position after it, or -1 *)
PROCEDURE LatexLine(p: LONGINT; s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  WHILE B.IsSpace(B.C(p)) DO INC(p) END;
  IF ~B.Looking(p, s) THEN RETURN -1 END;
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  RETURN B.BlankLine(p + n)
END LatexLine;

(* lhsCodeBlock *)
PROCEDURE LhsCodeBlock(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, e, r, n: LONGINT; b: B.Buf; a: A.Attr; space: BOOLEAN;
BEGIN
  p := B.pos;
  IF ~lhs OR (p > 0) & (B.C(p - 1) # 0AX) THEN RETURN FALSE END;
  IF B.Looking(p, "::") THEN
    q := B.BlankLine(p + 2);
    IF q >= 0 THEN q := B.BlankLine(q) END;
    IF q >= 0 THEN p := q END
  END;
  B.InitBuf(b);
  q := LatexLine(p, "\begin{code}");
  IF q >= 0 THEN
    n := 0;
    LOOP
      r := LatexLine(q, "\end{code}");
      IF (r >= 0) & (n > 0) THEN q := r; EXIT END;
      e := B.AnyLine(q);
      IF e < 0 THEN RETURN FALSE END;
      IF n > 0 THEN B.PutChar(b, 0AX) END;
      B.Put(b, q, e - 1); q := e; INC(n)
    END
  ELSIF B.C(p) = ">" THEN
    (* filterSpace: drop a space after each > if every line has one or
       is empty *)
    q := p; space := TRUE;
    WHILE B.C(q) = ">" DO
      IF (B.C(q + 1) # " ") & (B.C(q + 1) # 0AX) THEN space := FALSE END;
      e := B.AnyLine(q); IF e < 0 THEN RETURN FALSE END;
      q := e
    END;
    q := p; n := 0;
    WHILE B.C(q) = ">" DO
      e := B.AnyLine(q);
      IF n > 0 THEN B.PutChar(b, 0AX) END;
      r := q + 1;
      IF space & (B.C(r) = " ") THEN INC(r) END;
      B.Put(b, r, e - 1); q := e; INC(n)
    END
  ELSE RETURN FALSE
  END;
  q := B.BlankLines(q);
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  a := A.NewAttr(NIL); A.AddClass(a, A.S("haskell")); A.AddClass(a, A.S("literate"));
  A.AddBlock(l, A.NewCodeBlock(a, B.BufRope(b)));
  RETURN TRUE
END LhsCodeBlock;

(* Whether r ends with :: *)
PROCEDURE EndsColons(r: A.Rope): BOOLEAN;
  VAR n: LONGINT;
BEGIN
  n := Ropes.Length(r);
  RETURN (n >= 2) & (Ropes.Fetch(r, n - 1) = ":") & (Ropes.Fetch(r, n - 2) = ":")
END EndsColons;

(* para: inlines up to a blank line; Para if one follows, else Plain *)
PROCEDURE Para(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; il: A.Inlines; inl, last: A.Inline;
BEGIN
  p := B.pos;
  A.InitInlines(il);
  WHILE RI.Inline(il) DO END;
  IF B.pos = p THEN RETURN FALSE END;
  inl := MI.Trim(il);
  q := -1;
  IF B.C(B.pos) = 0AX THEN q := B.BlankLines(B.pos + 1) END;
  IF q >= 0 THEN
    B.pos := q;
    last := A.LastInline(inl);
    IF (last # NIL) & (last.kind = A.Str) & EndsColons(last(A.StrInl).text) THEN
      last(A.StrInl).text := Ropes.Substring(last(A.StrInl).text, 0,
        Ropes.Length(last(A.StrInl).text) - 1);
      A.AddBlock(l, A.NewInlinesBlock(A.Para, inl));
      IF CodeBlockBody(l) THEN END
    ELSE
      A.AddBlock(l, A.NewInlinesBlock(A.Para, inl))
    END
  ELSE
    A.AddBlock(l, A.NewInlinesBlock(A.Plain, inl))
  END;
  RETURN TRUE
END Para;

(* block *)
PROCEDURE Block(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  q := B.BlankLines(B.pos);
  IF q >= 0 THEN B.pos := q; RETURN TRUE END;
  RETURN CodeBlock(l) OR BlockQuote(l) OR FieldList(l) OR OptionList(l)
    OR ReferenceKey(l) OR NoteBlock(l)
    OR CitationBlock(l) OR Anchor(l) OR Comment(l)
    OR DoubleHeader(l) OR SingleHeader(l) OR Hrule(l) OR LineBlock(l)
    OR List(l, FALSE) OR List(l, TRUE) OR DefinitionList(l) OR LhsCodeBlock(l) OR Para(l)
END Block;

PROCEDURE ParseBlocks(): A.Block;
  VAR l: A.Blocks; e: LONGINT;
BEGIN
  A.InitBlocks(l);
  WHILE B.pos < B.len DO
    IF ~Block(l) THEN
      (* pandoc would stop with a parse error; a line as plain text *)
      e := B.LineEnd(B.pos);
      A.AddBlock(l, A.NewInlinesBlock(A.Plain,
        RI.ParseInlines(B.t^, B.pos, e - B.pos)));
      B.pos := e;
      IF B.pos < B.len THEN INC(B.pos) END
    END
  END;
  RETURN l.first
END ParseBlocks;


(* Resolution of references *)

PROCEDURE Prefix(r: A.Rope; pre: ARRAY OF CHAR; VAR rest: A.Rope): BOOLEAN;
  VAR i, n: LONGINT;
BEGIN
  IF r = NIL THEN RETURN FALSE END;
  n := 0; WHILE pre[n] # 0X DO INC(n) END;
  IF Ropes.Length(r) < n THEN RETURN FALSE END;
  FOR i := 0 TO n - 1 DO
    IF Ropes.Fetch(r, i) # pre[i] THEN RETURN FALSE END
  END;
  rest := Ropes.Substring(r, n, Ropes.Length(r) - n);
  RETURN TRUE
END Prefix;

(* The blocks of the raw text r *)
PROCEDURE RopeBlocks(r: A.Rope): A.Block;
  VAR b: B.Buf;
BEGIN
  B.InitBuf(b); MI.PutRope(b, r);
  RETURN BlocksOf(b)
END RopeBlocks;

(* lookupKey: the key k, following keys whose targets are other
   references (name_); NIL if there is none *)
PROCEDURE LookupKey(key: A.Rope): RI.Key;
  CONST Max = 64;
  VAR k: RI.Key; old: ARRAY Max OF A.Rope; n, i, len: LONGINT; m: Message;
BEGIN
  n := 0;
  LOOP
    k := RI.FindKey(key);
    IF k = NIL THEN
      m := "Reference not found for '"; CatRope(m, key); Cat(m, "'");
      WarnAtEnd(m); RETURN NIL
    END;
    IF k.src = NIL THEN len := 0 ELSE len := Ropes.Length(k.src) END;
    IF ((k.title = NIL) OR (Ropes.Length(k.title) = 0)) & (len > 1)
        & (Ropes.Fetch(k.src, len - 1) = "_") & (Ropes.Fetch(k.src, 0) # "#") THEN
      IF n < Max THEN old[n] := key; INC(n) END;
      key := RI.RopeKey(Ropes.Substring(k.src, 0, len - 1));
      i := 0; WHILE (i < n) & ~Ropes.Equal(old[i], key) DO INC(i) END;
      IF i < n THEN
        m := "Circular reference '"; CatRope(m, Ropes.Substring(k.src, 0, len - 1));
        Cat(m, "'"); WarnAtEnd(m); RETURN NIL
      END
    ELSE RETURN k
    END
  END
END LookupKey;

PROCEDURE NotFound(ref: A.Rope);
  VAR m: Message;
BEGIN
  m := "Reference not found for '"; CatRope(m, ref); Cat(m, "'"); WarnAtEnd(m)
END NotFound;

PROCEDURE (w: RefWalker) Inline*(i: A.Inline): A.Inline;
  VAR l: A.LinkInl; ref, key: A.Rope; k: RI.Key; n, prev: Note; nl: A.LinkInl;
    saved, savedLast: Note; c: CHAR;
BEGIN
  IF ~(i IS A.LinkInl) OR (i.kind # A.Link) THEN RETURN i END;
  l := i(A.LinkInl);
  IF Prefix(l.url, "##REF##", ref) THEN
    IF (Ropes.Length(ref) = 1) & (Ropes.Fetch(ref, 0) = "_") THEN
      key := RI.FirstAnonymous();
      IF key = NIL THEN
        PdIO.Warn("Anonymous reference with no target"); RETURN i
      END
    ELSE key := RI.RopeKey(ref)
    END;
    k := LookupKey(key);
    NEW(nl); nl^ := l^;
    IF k = NIL THEN nl.attr := A.NewAttr(NIL); nl.url := A.S(""); nl.title := A.S("")
    ELSE
      IF k.attr = NIL THEN nl.attr := A.NewAttr(NIL) ELSE nl.attr := k.attr END;
      nl.url := k.src; nl.title := k.title;
      IF nl.url = NIL THEN nl.url := A.S("") END;
      IF nl.title = NIL THEN nl.title := A.S("") END
    END;
    IF (Ropes.Length(key) > 0) & (Ropes.Fetch(key, 0) = "_") THEN RI.DeleteKey(key) END;
    RETURN nl
  ELSIF Prefix(l.url, "##NOTE##", ref) THEN
    prev := NIL; n := notes;
    WHILE (n # NIL) & ~Ropes.Equal(n.ref, ref) DO prev := n; n := n.next END;
    IF n = NIL THEN NotFound(ref); RETURN i END;
    saved := notes; savedLast := notesLast; notes := NIL; notesLast := NIL;
    i := A.NewNote(RopeBlocks(n.raw));
    notes := saved; notesLast := savedLast;
    IF Ropes.Length(ref) = 1 THEN
      c := Ropes.Fetch(ref, 0);
      IF (c = "*") OR (c = "#") THEN
        IF prev = NIL THEN notes := n.next ELSE prev.next := n.next END;
        IF notesLast = n THEN notesLast := prev END
      END
    END;
    RETURN i
  END;
  RETURN i
END Inline;

(* The citations Div, or NIL *)
PROCEDURE CitationsDiv(): A.Block;
  VAR n: Note; items, last, d: A.DefItem; bl: A.BlockList; dl: A.Block;
    a: A.Attr;
BEGIN
  IF citations = NIL THEN RETURN NIL END;
  items := NIL; last := NIL; n := citations;
  WHILE n # NIL DO
    NEW(d); a := A.NewAttr(n.ref); A.AddClass(a, A.S("citation-label"));
    d.term := A.NewSpan(a, A.NewStr(n.ref));
    NEW(bl); bl.blocks := RopeBlocks(n.raw); bl.next := NIL; d.defs := bl;
    d.next := NIL;
    IF items = NIL THEN items := d ELSE last.next := d END;
    last := d; n := n.next
  END;
  dl := A.NewDefinitionList(items);
  RETURN A.NewDiv(A.NewAttr(A.S("citations")), dl)
END CitationsDiv;

(* Appends the citations, and resolves references in d *)
PROCEDURE Resolve(d: A.Doc);
  VAR w: RefWalker; l: A.Blocks; c: A.Block;
BEGIN
  c := CitationsDiv();
  IF c # NIL THEN
    A.InitBlocks(l); A.AddBlock(l, d.blocks); A.AddBlock(l, c);
    d.blocks := l.first
  END;
  NEW(w);
  A.WalkMetaValue(w, d.meta);
  d.blocks := A.WalkBlocks(w, d.blocks)
END Resolve;

(* Reads text[0 .. n-1] as reStructuredText with tab stop tabStop *)
PROCEDURE Read*(text: PdIO.Text; n: LONGINT; tabStop: INTEGER): A.Doc;
  VAR t: B.Text; i, k: LONGINT; d: A.Doc;
BEGIN
  (* ensureFinalNewlines 2 *)
  k := 0;
  WHILE (k < n) & (k < 2) & (text[n - 1 - k] = 0AX) DO INC(k) END;
  t := B.NewText(n + 2 - k);
  FOR i := 0 TO n - 1 DO t[i] := text[i] END;
  FOR i := n TO n + 1 - k DO t[i] := 0AX END;
  B.Start(t, n + 2 - k, tabStop);
  main := B.t; mainLen := n + 2 - k;
  notes := NIL; notesLast := NIL; citations := NIL;
  nStyles := 0; ids := NIL; highlight := NIL;
  RI.Reset;
  d := A.NewDoc();
  B.pos := B.SkipBlankLines(0);
  d.blocks := ParseBlocks();
  Resolve(d);
  ids := NIL; main := NIL; notes := NIL; notesLast := NIL; citations := NIL;
  RETURN d
END Read;

BEGIN
  autoIds := TRUE
END PdRst.
