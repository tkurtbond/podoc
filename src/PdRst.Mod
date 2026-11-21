(* PdRst: pandoc's reStructuredText reader (Text.Pandoc.Readers.RST),
   for -f rst. The inlines are PdRstInline's; this module has the
   blocks, the directives, and the resolution of references,
   substitutions and notes. *)
MODULE PdRst;

IMPORT Ropes, Platform, PdIO, PdSource, A := PdAst, B := PdMdBase, MI := PdMdInline,
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
  Field = POINTER TO FieldDesc;
  FieldDesc = RECORD name, raw: A.Rope; next: Field END;
  Directive = RECORD
    label: ARRAY 64 OF CHAR; (* lower case *)
    top: B.Buf; (* the text after the label *)
    fields, last: Field;
    body: B.Buf (* the indented body *)
  END;
  Subst = POINTER TO SubstDesc;
  SubstDesc = RECORD key: A.Rope; blocks: A.Block; next: Subst END;
  SubstWalker = POINTER TO SubstWalkerDesc;
  SubstWalkerDesc = RECORD (A.WalkerDesc) END;
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
  substs: Subst; (* stateSubstitutions *)

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
(* Directives *)

PROCEDURE Is(r: A.Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN (r # NIL) & Ropes.EqualString(r, s)
END Is;

(* trim of the rope r; "" for NIL *)
PROCEDURE Trim(r: A.Rope): A.Rope;
  VAR b: B.Buf;
BEGIN
  B.InitBuf(b);
  IF r # NIL THEN MI.PutRope(b, r) END;
  RI.TrimBuf(b);
  RETURN Ropes.FromSubchars(b.t^, 0, b.len)
END Trim;

(* trimr of the rope r *)
PROCEDURE TrimR(r: A.Rope): A.Rope;
  VAR b: B.Buf;
BEGIN
  B.InitBuf(b);
  IF r # NIL THEN MI.PutRope(b, r) END;
  WHILE (b.len > 0) & B.IsWhite(b.t[b.len - 1]) DO DEC(b.len) END;
  RETURN Ropes.FromSubchars(b.t^, 0, b.len)
END TrimR;

(* The rope of b, "" if it is empty *)
PROCEDURE BufR(VAR b: B.Buf): A.Rope;
BEGIN
  RETURN Ropes.FromSubchars(b.t^, 0, b.len)
END BufR;

(* rawFieldListItem minIndent at p: the field in f; the position after
   it, or -1 *)
PROCEDURE RawField(p, minIndent: LONGINT; VAR f: Field): LONGINT;
  VAR q, ns, e, r, g, indent, i: LONGINT; b, c: B.Buf;
BEGIN
  q := p; indent := 0;
  WHILE B.C(q) = " " DO INC(q); INC(indent) END;
  IF (indent < minIndent) OR (B.C(q) # ":") THEN RETURN -1 END;
  ns := q + 1; e := ns;
  IF (B.C(e) = 0AX) OR (e >= B.len) THEN RETURN -1 END;
  INC(e);
  WHILE (B.C(e) # ":") & (B.C(e) # 0AX) & (e < B.len) DO INC(e) END;
  IF B.C(e) # ":" THEN RETURN -1 END;
  r := e + 1;
  IF B.C(r) # 0AX THEN
    IF ~B.IsSpace(B.C(r)) THEN RETURN -1 END;
    WHILE B.IsSpace(B.C(r)) DO INC(r) END
  END;
  g := B.AnyLine(r);
  IF g < 0 THEN RETURN -1 END;
  B.InitBuf(b);
  IF g - 1 > r THEN B.Put(b, r, g - 1); B.PutChar(b, 0AX) END;
  i := 0;
  WHILE (i < indent) & (B.C(g + i) = " ") DO INC(i) END;
  IF (i = indent) & B.IsSpace(B.C(g + i)) THEN
    q := IndentedBlock(g, c);
    IF q >= 0 THEN PutBuf(b, c); g := q END
  END;
  IF b.len > 0 THEN B.PutChar(b, 0AX) END;
  NEW(f); f.name := B.Rope(ns, e); f.raw := BufR(b); f.next := NIL;
  RETURN g
END RawField;

(* directive' at p, after the "..": the directive in d; the position
   after it, or -1 *)
PROCEDURE DirectiveAt(p: LONGINT; VAR d: Directive): LONGINT;
  VAR s, q, r, indent: LONGINT; f: Field; c: CHAR; i: INTEGER;
BEGIN
  IF ~B.IsSpace(B.C(p)) THEN RETURN -1 END;
  WHILE B.IsSpace(B.C(p)) DO INC(p) END;
  s := p;
  WHILE B.IsLetter(B.C(p)) OR (B.C(p) = "-") DO INC(p) END;
  IF (p = s) OR ~B.Looking(p, "::") OR (p - s >= LEN(d.label)) THEN RETURN -1 END;
  i := 0;
  WHILE s < p DO
    c := B.C(s);
    IF (c >= "A") & (c <= "Z") THEN c := CHR(ORD(c) + 32) END;
    d.label[i] := c; INC(i); INC(s)
  END;
  d.label[i] := 0X;
  INC(p, 2);
  WHILE B.IsSpace(B.C(p)) DO INC(p) END;
  B.InitBuf(d.top);
  LOOP
    WHILE (p < B.len) & (B.C(p) # 0AX) DO B.PutChar(d.top, B.C(p)); INC(p) END;
    IF p >= B.len THEN RETURN -1 END;
    q := p + 1;
    IF (B.C(q) = " ") & (RawField(q, 1, f) < 0) THEN
      r := q; WHILE B.C(r) = " " DO INC(r) END;
      IF B.BlankLine(r) >= 0 THEN EXIT END;
      B.PutChar(d.top, 0AX); p := r
    ELSE EXIT
    END
  END;
  INC(p);
  d.fields := NIL; d.last := NIL;
  indent := 0;
  WHILE B.C(p + indent) = " " DO INC(indent) END;
  IF indent > 0 THEN
    LOOP
      q := RawField(p, indent, f);
      IF q < 0 THEN EXIT END;
      IF d.fields = NIL THEN d.fields := f ELSE d.last.next := f END;
      d.last := f; p := q
    END
  END;
  B.InitBuf(d.body);
  q := B.BlankLines(p);
  IF q >= 0 THEN
    r := IndentedBlock(q, d.body);
    IF r >= 0 THEN p := r ELSE B.InitBuf(d.body) END
  END;
  q := B.BlankLines(p);
  IF q >= 0 THEN p := q END;
  RETURN p
END DirectiveAt;

(* lookup name fields: the raw value of d's first field name, or NIL *)
PROCEDURE FieldVal(VAR d: Directive; name: ARRAY OF CHAR): A.Rope;
  VAR f: Field;
BEGIN
  f := d.fields;
  WHILE (f # NIL) & ~Is(f.name, name) DO f := f.next END;
  IF f = NIL THEN RETURN NIL END;
  RETURN f.raw
END FieldVal;

(* The words of r, added to a's classes *)
PROCEDURE AddWords(a: A.Attr; r: A.Rope);
  VAR b: B.Buf; i, s: LONGINT;
BEGIN
  IF r = NIL THEN RETURN END;
  B.InitBuf(b); MI.PutRope(b, r); i := 0;
  WHILE i < b.len DO
    WHILE (i < b.len) & B.IsWhite(b.t[i]) DO INC(i) END;
    s := i;
    WHILE (i < b.len) & ~B.IsWhite(b.t[i]) DO INC(i) END;
    IF i > s THEN A.AddClass(a, Ropes.FromSubchars(b.t^, s, i - s)) END
  END
END AddWords;

(* The attribute (name, label:classes, keyvals) of d; label is left out
   if it is "" *)
PROCEDURE DirAttr(VAR d: Directive; label: ARRAY OF CHAR): A.Attr;
  VAR a: A.Attr; f: Field;
BEGIN
  a := A.NewAttr(Trim(FieldVal(d, "name")));
  IF label # "" THEN A.AddClass(a, A.S(label)) END;
  AddWords(a, Trim(FieldVal(d, "class")));
  f := d.fields;
  WHILE f # NIL DO
    IF ~Is(f.name, "name") & ~Is(f.name, "class") THEN
      A.AddKeyVal(a, f.name, Trim(f.raw))
    END;
    f := f.next
  END;
  RETURN a
END DirAttr;

(* parseFromString' parseBlocks of top <> "\n\n" <> body' *)
PROCEDURE TopBodyBlocks(VAR d: Directive): A.Block;
  VAR b: B.Buf;
BEGIN
  B.InitBuf(b); PutBuf(b, d.top); B.PutChar(b, 0AX); B.PutChar(b, 0AX);
  PutBuf(b, d.body); B.PutChar(b, 0AX); B.PutChar(b, 0AX);
  RETURN BlocksOf(b)
END TopBodyBlocks;

(* addNewRole top fields; FALSE if top is not a role name *)
PROCEDURE NewRole(VAR d: Directive): BOOLEAN;
  VAR f: B.Frame; b: B.Buf; q, r: LONGINT; role, parent: A.Rope; ok: BOOLEAN;
    fmt, lang, cls: A.Rope;
BEGIN
  B.InitBuf(b); PutBuf(b, d.top); B.PutChar(b, 0AX);
  B.Enter(f, b.t, b.len - 1);
  ok := FALSE; parent := NIL; role := NIL;
  q := RI.RoleName(0);
  IF q > 0 THEN
    role := B.Rope(0, q); ok := TRUE;
    IF B.C(q) = "(" THEN
      r := RI.RoleName(q + 1);
      IF (r > q + 1) & (B.C(r) = ")") THEN parent := B.Rope(q + 1, r) END
    END
  END;
  B.Leave(f);
  IF ~ok THEN RETURN FALSE END;
  fmt := FieldVal(d, "format"); lang := FieldVal(d, "language");
  cls := FieldVal(d, "class");
  IF fmt # NIL THEN fmt := Trim(fmt) END;
  IF lang # NIL THEN lang := Trim(lang) END;
  IF cls # NIL THEN cls := Trim(cls) END;
  RI.AddRole(role, parent, fmt, lang, cls, fmt # NIL, lang # NIL, cls # NIL);
  RETURN TRUE
END NewRole;

(* unicodeTransform of the text in b, in out *)
PROCEDURE UnicodeTransform(VAR b: B.Buf; VAR out: B.Buf);
  VAR i, j, s, v: LONGINT;

  PROCEDURE Hex(c: CHAR): INTEGER;
  BEGIN
    IF (c >= "0") & (c <= "9") THEN RETURN ORD(c) - ORD("0")
    ELSIF (c >= "a") & (c <= "f") THEN RETURN ORD(c) - ORD("a") + 10
    ELSIF (c >= "A") & (c <= "F") THEN RETURN ORD(c) - ORD("A") + 10
    END;
    RETURN -1
  END Hex;

  PROCEDURE Pre(s: ARRAY OF CHAR): BOOLEAN;
    VAR k: LONGINT;
  BEGIN
    k := 0;
    WHILE (s[k] # 0X) & (i + k < b.len) & (b.t[i + k] = s[k]) DO INC(k) END;
    IF s[k] = 0X THEN j := i + k; RETURN TRUE END;
    RETURN FALSE
  END Pre;

  (* extractUnicodeChar at j: the code point in v, j after its digits *)
  PROCEDURE Code(): BOOLEAN;
    VAR k: LONGINT;
  BEGIN
    k := j; v := 0;
    WHILE (k < b.len) & (Hex(b.t[k]) >= 0) DO
      IF v <= 10FFFFH THEN v := v * 16 + Hex(b.t[k]) END;
      INC(k)
    END;
    IF (k = j) OR (v > 10FFFFH) THEN RETURN FALSE END;
    j := k; RETURN TRUE
  END Code;

BEGIN
  B.InitBuf(out); i := 0;
  WHILE i < b.len DO
    IF Pre("..") THEN
      i := j; WHILE (i < b.len) & (b.t[i] # 0AX) DO INC(i) END
    ELSIF Pre("0x") OR Pre("x") OR Pre("\x") OR Pre("U+") OR Pre("u") OR Pre("\u") THEN
      s := i;
      IF Code() THEN B.PutUtf8(out, v)
      ELSE WHILE s < j DO B.PutChar(out, b.t[s]); INC(s) END
      END;
      i := j
    ELSIF Pre("&#x") THEN
      s := i;
      IF Code() THEN
        B.PutUtf8(out, v); i := j; IF i < b.len THEN INC(i) END
      ELSE
        WHILE s < j DO B.PutChar(out, b.t[s]); INC(s) END; i := j
      END
    ELSE B.PutChar(out, b.t[i]); INC(i)
    END
  END
END UnicodeTransform;

(* formatTime defaultTimeLocale fmt of the time getTimestamp gives:
   SOURCE_DATE_EPOCH, or now, in UTC *)
PROCEDURE FormatDate(VAR fmt: B.Buf; VAR out: B.Buf);
  VAR env: ARRAY 32 OF CHAR; secs, usec, days, rem, z, era, doe, yoe, y,
    doy, mp, d, m, wday, yday, i, k: LONGINT; c, pad: CHAR;
    months, wdays: ARRAY 100 OF CHAR;

  PROCEDURE Num(n, width: LONGINT);
    VAR s: ARRAY 24 OF CHAR; j, l: LONGINT;
  BEGIN
    IF n < 0 THEN B.PutChar(out, "-"); n := -n END;
    l := 0;
    REPEAT s[l] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(l) UNTIL n = 0;
    IF pad # "-" THEN
      FOR j := l TO width - 1 DO B.PutChar(out, pad) END
    END;
    FOR j := l - 1 TO 0 BY -1 DO B.PutChar(out, s[j]) END
  END Num;

  (* the n-th word of names, all or its first three letters *)
  PROCEDURE Name(VAR names: ARRAY OF CHAR; n: LONGINT; short: BOOLEAN);
    VAR j, w, cnt: LONGINT;
  BEGIN
    j := 0; w := 0;
    WHILE w < n DO
      WHILE names[j] # " " DO INC(j) END;
      INC(j); INC(w)
    END;
    cnt := 0;
    WHILE (names[j] # " ") & (names[j] # 0X) & (~short OR (cnt < 3)) DO
      B.PutChar(out, names[j]); INC(j); INC(cnt)
    END
  END Name;

  PROCEDURE Str(s: ARRAY OF CHAR);
    VAR j: LONGINT;
  BEGIN
    j := 0; WHILE s[j] # 0X DO B.PutChar(out, s[j]); INC(j) END
  END Str;

BEGIN
  months := "January February March April May June July August September October November December";
  wdays := "Sunday Monday Tuesday Wednesday Thursday Friday Saturday";
  env := ""; Platform.GetEnv("SOURCE_DATE_EPOCH", env);
  IF env[0] # 0X THEN
    secs := 0; i := 0;
    WHILE (env[i] >= "0") & (env[i] <= "9") DO
      secs := secs * 10 + ORD(env[i]) - ORD("0"); INC(i)
    END
  ELSE Platform.GetTimeOfDay(secs, usec)
  END;
  days := secs DIV 86400; rem := secs MOD 86400;
  z := days + 719468; era := z DIV 146097; doe := z - era * 146097;
  yoe := (doe - doe DIV 1460 + doe DIV 36524 - doe DIV 146096) DIV 365;
  y := yoe + era * 400; doy := doe - (365 * yoe + yoe DIV 4 - yoe DIV 100);
  mp := (5 * doy + 2) DIV 153; d := doy - (153 * mp + 2) DIV 5 + 1;
  IF mp < 10 THEN m := mp + 3 ELSE m := mp - 9 END;
  IF m <= 2 THEN INC(y) END;
  IF m >= 3 THEN yday := doy + 59 ELSE yday := doy - 306 END;
  IF (m >= 3) & ((y MOD 4 = 0) & (y MOD 100 # 0) OR (y MOD 400 = 0)) THEN INC(yday) END;
  INC(yday);
  wday := (days + 4) MOD 7;
  B.InitBuf(out); i := 0;
  WHILE i < fmt.len DO
    c := fmt.t[i]; INC(i);
    IF (c = "%") & (i < fmt.len) THEN
      c := fmt.t[i]; INC(i); pad := "0";
      IF ((c = "-") OR (c = "_") OR (c = "0")) & (i < fmt.len) THEN
        IF c = "_" THEN pad := " " ELSE pad := c END;
        c := fmt.t[i]; INC(i)
      END;
      CASE c OF
        "Y": Num(y, 1)
      | "y": Num(y MOD 100, 2)
      | "C": Num(y DIV 100, 2)
      | "m": Num(m, 2)
      | "d": Num(d, 2)
      | "e": IF pad = "0" THEN pad := " " END; Num(d, 2)
      | "j": Num(yday, 3)
      | "H": Num(rem DIV 3600, 2)
      | "k": IF pad = "0" THEN pad := " " END; Num(rem DIV 3600, 2)
      | "I": k := rem DIV 3600 MOD 12; IF k = 0 THEN k := 12 END; Num(k, 2)
      | "l": k := rem DIV 3600 MOD 12; IF k = 0 THEN k := 12 END;
          IF pad = "0" THEN pad := " " END; Num(k, 2)
      | "M": Num(rem DIV 60 MOD 60, 2)
      | "S": Num(rem MOD 60, 2)
      | "s": Num(secs, 1)
      | "u": IF wday = 0 THEN Num(7, 1) ELSE Num(wday, 1) END
      | "w": Num(wday, 1)
      | "B": Name(months, m - 1, FALSE)
      | "b", "h": Name(months, m - 1, TRUE)
      | "A": Name(wdays, wday, FALSE)
      | "a": Name(wdays, wday, TRUE)
      | "p": IF rem < 43200 THEN Str("AM") ELSE Str("PM") END
      | "P": IF rem < 43200 THEN Str("am") ELSE Str("pm") END
      | "F": Num(y, 4); B.PutChar(out, "-"); Num(m, 2); B.PutChar(out, "-"); Num(d, 2)
      | "D": Num(m, 2); B.PutChar(out, "/"); Num(d, 2); B.PutChar(out, "/"); Num(y MOD 100, 2)
      | "T": Num(rem DIV 3600, 2); B.PutChar(out, ":"); Num(rem DIV 60 MOD 60, 2);
          B.PutChar(out, ":"); Num(rem MOD 60, 2)
      | "R": Num(rem DIV 3600, 2); B.PutChar(out, ":"); Num(rem DIV 60 MOD 60, 2)
      | "Z": Str("UTC")
      | "z": Str("+0000")
      | "n": B.PutChar(out, 0AX)
      | "t": B.PutChar(out, 09X)
      | "%": B.PutChar(out, "%")
      ELSE B.PutChar(out, "%"); B.PutChar(out, c)
      END
    ELSE B.PutChar(out, c)
    END
  END
END FormatDate;

(* escapeURI of r *)
PROCEDURE EscapeURIRope(r: A.Rope): A.Rope;
  VAR b, e: B.Buf;
BEGIN
  B.InitBuf(b); MI.PutRope(b, r); B.InitBuf(e);
  MI.EscapeURI(b.t^, b.len, e);
  RETURN BufR(e)
END EscapeURIRope;

(* The image directive *)
PROCEDURE ImageDirective(VAR d: Directive): A.Block;
  VAR a: A.Attr; src, t, cls, al: A.Rope; img: A.Inline;
BEGIN
  src := EscapeURIRope(Trim(BufR(d.top)));
  a := A.NewAttr(Trim(FieldVal(d, "name")));
  cls := FieldVal(d, "class");
  IF cls # NIL THEN cls := Trim(cls) ELSE cls := A.S("") END;
  AddWords(a, cls);
  al := FieldVal(d, "align");
  IF al # NIL THEN cls := Ropes.Cat(cls, Ropes.Cat(A.S("align-"), Trim(al))) END;
  AddWords(a, cls);
  t := FieldVal(d, "alt");
  IF t = NIL THEN t := A.S("image") ELSE t := Trim(t) END;
  img := A.NewLink(A.Image, a, A.NewStr(t), src, A.S(""));
  t := FieldVal(d, "target");
  IF t # NIL THEN
    img := A.NewLink(A.Link, A.NewAttr(NIL), img, EscapeURIRope(Trim(t)), A.S(""))
  END;
  RETURN A.NewInlinesBlock(A.Para, img)
END ImageDirective;

(* Runs the directive d, adding its blocks to l; FALSE if it fails *)
PROCEDURE RunDirective(VAR d: Directive; VAR l: A.Blocks): BOOLEAN;
  VAR b: B.Buf; r: A.Rope;
BEGIN
  IF d.label = "role" THEN RETURN NewRole(d)
  ELSIF d.label = "default-role" THEN
    r := Trim(BufR(d.top));
    IF Ropes.Length(r) = 0 THEN RI.defaultRole := A.S("title-reference")
    ELSE RI.defaultRole := r
    END
  ELSIF d.label = "highlight" THEN
    r := Trim(BufR(d.top));
    IF Ropes.Length(r) = 0 THEN highlight := NIL ELSE highlight := r END
  ELSIF d.label = "replace" THEN
    A.AddBlock(l, A.NewInlinesBlock(A.Para, RI.ParseRope(Trim(BufR(d.top)))))
  ELSIF d.label = "unicode" THEN
    UnicodeTransform(d.top, b);
    A.AddBlock(l, A.NewInlinesBlock(A.Para, RI.ParseRope(Trim(BufR(b)))))
  ELSIF d.label = "date" THEN
    RI.TrimBuf(d.top);
    IF d.top.len = 0 THEN B.InitBuf(d.top); MI.PutRope(d.top, A.S("%Y-%m-%d")) END;
    FormatDate(d.top, b);
    A.AddBlock(l, A.NewInlinesBlock(A.Para, RI.TextOf(BufR(b))))
  ELSIF d.label = "image" THEN A.AddBlock(l, ImageDirective(d))
  ELSIF d.label = "raw" THEN
    StripNewlines(d.body);
    A.AddBlock(l, A.NewRawBlock(Trim(BufR(d.top)), BufR(d.body)))
  ELSE
    (* pandoc logs SkippedContent, an INFO message *)
    A.AddBlock(l, A.NewDiv(DirAttr(d, d.label), TopBodyBlocks(d)))
  END;
  RETURN TRUE
END RunDirective;

(* directive *)
PROCEDURE DirectiveBlock(VAR l: A.Blocks): BOOLEAN;
  VAR d: Directive; q: LONGINT;
BEGIN
  IF ~B.Looking(B.pos, "..") THEN RETURN FALSE END;
  q := DirectiveAt(B.pos + 2, d);
  IF q < 0 THEN RETURN FALSE END;
  IF ~RunDirective(d, l) THEN RETURN FALSE END;
  B.pos := q;
  RETURN TRUE
END DirectiveBlock;

(* substKey: .. |name| directive *)
PROCEDURE SubstKey(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, s: LONGINT; c: A.Inlines; alt: A.Inline; key: A.Rope; d: Directive;
    res: A.Blocks; i: A.Inline; sb: Subst;

  (* whether i is an Image with the alt text [Str "image"] *)
  PROCEDURE DefaultAlt(i: A.Inline): BOOLEAN;
    VAR k: A.Inline;
  BEGIN
    IF (i = NIL) OR (i.next # NIL) OR (i.kind # A.Image) THEN RETURN FALSE END;
    k := i(A.LinkInl).content;
    RETURN (k # NIL) & (k.next = NIL) & (k IS A.StrInl) & Is(k(A.StrInl).text, "image")
  END DefaultAlt;

BEGIN
  p := B.pos;
  IF ~B.Looking(p, "..") OR ~B.IsSpace(B.C(p + 2)) THEN RETURN FALSE END;
  q := p + 2;
  WHILE B.IsSpace(B.C(q)) DO INC(q) END;
  IF B.C(q) # "|" THEN RETURN FALSE END;
  s := q;
  B.pos := q + 1;
  IF B.IsWhite(B.C(B.pos)) THEN B.pos := p; RETURN FALSE END;
  A.InitInlines(c);
  IF ~RI.Inline(c) THEN B.pos := p; RETURN FALSE END;
  WHILE B.C(B.pos) # "|" DO
    IF ~RI.Inline(c) THEN B.pos := p; RETURN FALSE END
  END;
  INC(B.pos);
  key := RI.RopeKey(B.Rope(s + 1, B.pos - 1));
  alt := MI.Trim(c);
  q := DirectiveAt(B.pos, d);
  IF q < 0 THEN B.pos := p; RETURN FALSE END;
  A.InitBlocks(res);
  IF ~RunDirective(d, res) THEN B.pos := p; RETURN FALSE END;
  B.pos := q;
  IF (res.first # NIL) & (res.first.next = NIL) & (res.first.kind = A.Para) THEN
    i := res.first(A.InlinesBlk).inlines;
    IF DefaultAlt(i) THEN i(A.LinkInl).content := alt
    ELSIF (i # NIL) & (i.next = NIL) & (i.kind = A.Link)
        & DefaultAlt(i(A.LinkInl).content) THEN
      i(A.LinkInl).content(A.LinkInl).content := alt
    END
  END;
  sb := substs;
  WHILE (sb # NIL) & ~Ropes.Equal(sb.key, key) DO sb := sb.next END;
  IF sb = NIL THEN NEW(sb); sb.key := key; sb.next := substs; substs := sb END;
  sb.blocks := res.first;
  RETURN TRUE
END SubstKey;

PROCEDURE Block(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  q := B.BlankLines(B.pos);
  IF q >= 0 THEN B.pos := q; RETURN TRUE END;
  RETURN CodeBlock(l) OR BlockQuote(l) OR FieldList(l) OR OptionList(l)
    OR SubstKey(l) OR ReferenceKey(l) OR NoteBlock(l)
    OR CitationBlock(l) OR DirectiveBlock(l) OR Anchor(l) OR Comment(l)
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

(* A copy of the block b, its contents shared, the inlines of a Para
   or Plain copied; next = NIL *)
PROCEDURE CopyBlock(b: A.Block): A.Block;
  VAR h: A.HeaderBlk; ib: A.InlinesBlk; lb: A.LineBlk; cb: A.CodeBlk;
    rb: A.RawBlk; db: A.DivBlk; fb: A.FigureBlk; bb: A.BlocksBlk;
    ob: A.OrderedBlk; li: A.ListBlk; dl: A.DefListBlk; tb: A.TableBlk;
    x, n: A.Block;
BEGIN
  WITH
    b: A.HeaderBlk DO NEW(h); h^ := b^; n := h
  | b: A.InlinesBlk DO
      NEW(ib); ib^ := b^; ib.inlines := A.CopyInlines(b.inlines); n := ib
  | b: A.LineBlk DO NEW(lb); lb^ := b^; n := lb
  | b: A.CodeBlk DO NEW(cb); cb^ := b^; n := cb
  | b: A.RawBlk DO NEW(rb); rb^ := b^; n := rb
  | b: A.DivBlk DO NEW(db); db^ := b^; n := db
  | b: A.FigureBlk DO NEW(fb); fb^ := b^; n := fb
  | b: A.BlocksBlk DO NEW(bb); bb^ := b^; n := bb
  | b: A.OrderedBlk DO NEW(ob); ob^ := b^; n := ob
  | b: A.ListBlk DO NEW(li); li^ := b^; n := li
  | b: A.DefListBlk DO NEW(dl); dl^ := b^; n := dl
  | b: A.TableBlk DO NEW(tb); tb^ := b^; n := tb
  ELSE NEW(x); x^ := b^; n := x
  END;
  n.next := NIL;
  RETURN n
END CopyBlock;

(* The substitution of ref, "|name|", or NIL; warns if there is none *)
PROCEDURE FindSubst(ref: A.Rope): Subst;
  VAR key: A.Rope; sb: Subst; m: Message;
BEGIN
  key := RI.RopeKey(Ropes.Substring(ref, 1, Ropes.Length(ref) - 2));
  sb := substs;
  WHILE (sb # NIL) & ~Ropes.Equal(sb.key, key) DO sb := sb.next END;
  IF sb = NIL THEN
    (* pandoc shows the key with tshow *)
    m := "Reference not found for '"; Cat(m, 22X); CatRope(m, key); Cat(m, 22X);
    Cat(m, "'"); WarnAtEnd(m)
  END;
  RETURN sb
END FindSubst;

(* resolveBlockSubstitutions: a Para holding only a substitution *)
PROCEDURE (w: SubstWalker) Block*(b: A.Block): A.Block;
  VAR i: A.Inline; ref: A.Rope; sb: Subst; bl: A.Block;
BEGIN
  IF (b.kind # A.Para) OR ~(b IS A.InlinesBlk) THEN RETURN b END;
  i := b(A.InlinesBlk).inlines;
  IF (i = NIL) OR (i.next # NIL) OR (i.kind # A.Link)
      OR ~Prefix(i(A.LinkInl).url, "##SUBST##", ref) THEN
    RETURN b
  END;
  sb := FindSubst(ref);
  IF sb = NIL THEN RETURN b END;
  bl := sb.blocks;
  IF (bl # NIL) & (bl.next = NIL) THEN RETURN CopyBlock(bl) END;
  RETURN A.NewDiv(A.NewAttr(NIL), bl)
END Block;

PROCEDURE (w: RefWalker) Inline*(i: A.Inline): A.Inline;
  VAR l: A.LinkInl; ref, key: A.Rope; k: RI.Key; n, prev: Note; nl: A.LinkInl;
    saved, savedLast: Note; c: CHAR; sb: Subst; bl: A.Block; il: A.Inlines;
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
  ELSIF Prefix(l.url, "##SUBST##", ref) THEN
    sb := FindSubst(ref);
    IF sb = NIL THEN RETURN i END;
    bl := sb.blocks;
    IF (bl # NIL) & (bl.next = NIL) & (bl.kind = A.Para) THEN
      i := A.CopyInlines(bl(A.InlinesBlk).inlines);
      IF (i # NIL) & (i.next = NIL) THEN RETURN i END;
      RETURN A.NewSpan(A.NewAttr(NIL), i)
    END;
    A.InitInlines(il); SH.BlocksToInlines(il, bl);
    RETURN A.NewSpan(A.NewAttr(NIL), A.CopyInlines(il.first))
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
  VAR w: RefWalker; sw: SubstWalker; l: A.Blocks; c: A.Block;
BEGIN
  c := CitationsDiv();
  IF c # NIL THEN
    A.InitBlocks(l); A.AddBlock(l, d.blocks); A.AddBlock(l, c);
    d.blocks := l.first
  END;
  NEW(sw);
  A.WalkMetaValue(sw, d.meta);
  d.blocks := A.WalkBlocks(sw, d.blocks);
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
  notes := NIL; notesLast := NIL; citations := NIL; substs := NIL;
  nStyles := 0; ids := NIL; highlight := NIL;
  RI.Reset;
  d := A.NewDoc();
  B.pos := B.SkipBlankLines(0);
  d.blocks := ParseBlocks();
  Resolve(d);
  ids := NIL; main := NIL; notes := NIL; notesLast := NIL; citations := NIL; substs := NIL;
  RETURN d
END Read;

BEGIN
  autoIds := TRUE
END PdRst.
