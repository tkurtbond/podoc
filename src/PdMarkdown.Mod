MODULE PdMarkdown;
(* PdMarkdown: the markdown reader's blocks (Text.Pandoc.Readers.Markdown,
   parseBlocks and block), and Read, which reads a document.

   The blocks are tried in pandoc's order. So far: blank lines, fenced
   code, bullet, ordered and definition lists, HTML and fenced divs,
   setext and ATX headings (with attributes and identifiers), raw HTML
   blocks, indented code, line blocks, block quotes, horizontal rules,
   notes, reference keys, paragraphs (with implicit figures) and plain
   text, pipe, simple, multiline and grid tables (PdGridTable), and
   YAML metadata blocks. The title block and raw TeX blocks are in
   PLAN.md's Later.

   A YAML block's strings are read as markdown, as pandoc reads them
   (Text.Pandoc.Readers.Metadata); ReadMetaFile reads a metadata file
   so.

   Reference links and note references are resolved when the whole
   document has been read, as pandoc resolves them (its F monad). *)

IMPORT Ropes, PdIO, PdSource, A := PdAst, B := PdMdBase, I := PdMdInline,
  G := PdGridTable, Y := PdYaml, SH := PdShared;

CONST
  (* what starts a list item *)
  BulletItem = 1; OrderedItem = 2; DefItem = 3;

  TableSize = 4093; (* the number of buckets in a HashTable: a prime, since
    Ropes.Hash modulo a power of two leaves most buckets empty for keys
    that differ only in their last characters *)

TYPE
  (* A reference key and its target *)
  Key = POINTER TO KeyDesc;
  KeyDesc = RECORD
    key, url, title: A.Rope;
    attr: A.Attr;
    next: Key
  END;

  (* A hash table of ropes: each slot holds one rope and, for reference
     keys, its target; a bucket's last added slot comes first *)
  Slot = POINTER TO SlotDesc;
  SlotDesc = RECORD
    key: A.Rope;
    k: Key;
    n: LONGINT; (* suffixes: the last suffix tried *)
    next: Slot
  END;
  HashTable = POINTER TO ARRAY TableSize OF Slot;

  (* A note's text *)
  Note = POINTER TO NoteDesc;
  NoteDesc = RECORD
    ref: A.Rope;
    blocks: A.Block;
    next: Note
  END;

  Longs = POINTER TO ARRAY OF LONGINT;
  Reals = POINTER TO ARRAY OF LONGREAL;

  (* A table's columns, from the dashed line under its header *)
  Columns = RECORD
    n: LONGINT; (* how many *)
    align: Longs; (* each one's alignment *)
    len: Longs; (* the length of each one's dashes (and colons) *)
    index: Longs; (* simple and multiline tables: the n+1 indices *)
    width: Reals (* each one's relative width; 0 for the default *)
  END;

  (* A line of a table, split into cells: t[s[k] .. f[k]-1] *)
  RawLine = POINTER TO RawLineDesc;
  RawLineDesc = RECORD
    s, f: Longs;
    m: LONGINT; (* how many cells *)
    next: RawLine
  END;

  (* Resolves reference links and notes *)
  Resolver = POINTER TO ResolverDesc;
  ResolverDesc = RECORD (A.WalkerDesc)
    inNote: BOOLEAN (* note references are not resolved *)
  END;

  (* A YAML node in a map being built, waiting to be read *)
  NodeV = POINTER TO NodeVDesc;
  NodeVDesc = RECORD (A.MetaValueDesc)
    node: Y.Node
  END;

  (* Blocks that become inlines once resolved: normalizeMetaValue's
     MetaBlocks read as MetaInlines *)
  PendingV = POINTER TO PendingVDesc;
  PendingVDesc = RECORD (A.MetaBlocksVDesc) END;

  Message = ARRAY 1024 OF CHAR;

  (* A list item, for taskListItemFromAscii after resolving *)
  Item = POINTER TO RECORD
    item: A.BlockList;
    next: Item
  END;

VAR
  gridTables*: BOOLEAN; (* the grid_tables extension: grid tables are
    read; TRUE unless podoc is told otherwise *)
  titleBlock*: BOOLEAN; (* the pandoc_title_block extension: % lines at
    the start give the title, authors and date; TRUE unless podoc is
    told otherwise *)
  columns*: LONGINT; (* pandoc's readerColumns, from --columns: 72 unless
    podoc is told otherwise; the widths of tables are relative to it *)
  ids: A.StrList; (* the header identifiers used so far *)
  keys: Key; (* the reference keys; the last defined first *)
  headerKeys: Key; (* the implicit header references *)
  (* ids, keys and headerKeys hashed, so that they are found without
     walking the lists, which are kept so that TableAt can go back *)
  idTable, keyTable, headerTable: HashTable;
  suffixes: HashTable; (* for each base in it, the last suffix tried, in
    the slot's n: none below it is free; NIL when TableAt took
    identifiers out again *)
  notes: Note; (* the notes; the last defined first *)
  listItems: Item; (* the list items *)
  meta: A.MetaMapV; (* the document's metadata so far *)
  main: B.Text; (* the document's text, for the places in messages *)

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

(* Hash tables *)

PROCEDURE NewTable(): HashTable;
  VAR t: HashTable; i: LONGINT;
BEGIN
  NEW(t);
  FOR i := 0 TO TableSize - 1 DO t[i] := NIL END;
  RETURN t
END NewTable;

PROCEDURE Bucket(key: A.Rope): LONGINT;
BEGIN
  IF key = NIL THEN RETURN 0 END;
  RETURN SHORT(Ropes.Hash(key) MOD TableSize)
END Bucket;

(* The last added slot in t whose rope equals key, NIL if none does or
   t is NIL *)
PROCEDURE Find(t: HashTable; key: A.Rope): Slot;
  VAR s: Slot;
BEGIN
  IF t = NIL THEN RETURN NIL END;
  s := t[Bucket(key)];
  WHILE (s # NIL) & ~Ropes.Equal(s.key, key) DO s := s.next END;
  RETURN s
END Find;

PROCEDURE Add(t: HashTable; key: A.Rope; k: Key);
  VAR s: Slot; b: LONGINT;
BEGIN
  b := Bucket(key);
  NEW(s); s.key := key; s.k := k; s.n := 0; s.next := t[b]; t[b] := s
END Add;

(* The last added slot in t for the rope key itself (not one equal to
   it) taken out again *)
PROCEDURE Remove(t: HashTable; key: A.Rope);
  VAR s, p: Slot; b: LONGINT;
BEGIN
  b := Bucket(key); s := t[b]; p := NIL;
  WHILE (s # NIL) & (s.key # key) DO p := s; s := s.next END;
  IF s # NIL THEN
    IF p = NIL THEN t[b] := s.next ELSE p.next := s.next END
  END
END Remove;

(* Identifiers *)

PROCEDURE Used(id: A.Rope): BOOLEAN;
BEGIN
  RETURN Find(idTable, id) # NIL
END Used;

PROCEDURE Use(id: A.Rope);
  VAR s: A.StrList;
BEGIN
  NEW(s); s.s := id; s.next := ids; ids := s;
  Add(idTable, id, NIL)
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
  VAR base, id: A.Rope; n: LONGINT; s: Slot;
BEGIN
  IF attr.id = NIL THEN
    base := I.Identifier(inl);
    IF base = NIL THEN base := A.S("section") END;
    id := base;
    IF Used(id) THEN
      IF suffixes = NIL THEN suffixes := NewTable() END;
      s := Find(suffixes, base);
      IF s = NIL THEN Add(suffixes, base, NIL); s := suffixes[Bucket(base)] END;
      n := s.n;
      LOOP
        IF n >= 60000 THEN id := base; EXIT END;
        INC(n); id := Ropes.Cat(Ropes.AppendChar(base, "-"), Number(n));
        IF ~Used(id) THEN EXIT END
      END;
      s.n := n
    END;
    attr.id := id
  END;
  Use(attr.id)
END RegisterHeader;

(* The last added key in t equal to key, NIL if there is none *)
PROCEDURE FindKey(t: HashTable; key: A.Rope): Key;
  VAR s: Slot;
BEGIN
  s := Find(t, key);
  IF s = NIL THEN RETURN NIL END;
  RETURN s.k
END FindKey;

(* registerImplicitHeader: the header whose raw text is t[from .. to-1]
   and whose identifier is id is the target of a reference with its
   text, unless an earlier header is *)
PROCEDURE RegisterImplicitHeader(from, to: LONGINT; id: A.Rope);
  VAR k: Key; key: A.Rope;
BEGIN
  IF to <= from THEN RETURN END;
  key := I.Key(B.t^, from, to, FALSE);
  IF FindKey(headerTable, key) = NIL THEN
    NEW(k); k.key := key; k.url := Ropes.Cat(A.S("#"), id); k.title := NIL;
    k.attr := NIL; k.next := headerKeys; headerKeys := k;
    Add(headerTable, key, k)
  END
END RegisterImplicitHeader;

(* Metadata *)

(* Appends s to the message m. *)
PROCEDURE Cat(VAR m: ARRAY OF CHAR; s: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE m[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (j < LEN(s)) & (s[j] # 0X) & (i < LEN(m) - 1) DO
    m[i] := s[j]; INC(i); INC(j)
  END;
  m[i] := 0X
END Cat;

(* Appends the number n to the message m. *)
PROCEDURE CatNum(VAR m: ARRAY OF CHAR; n: LONGINT);
  VAR d: ARRAY 24 OF CHAR; r: ARRAY 24 OF CHAR; k, i: INTEGER;
BEGIN
  k := 0;
  REPEAT d[k] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(k) UNTIL n = 0;
  i := 0;
  WHILE k > 0 DO DEC(k); r[i] := d[k]; INC(i) END;
  r[i] := 0X;
  Cat(m, r)
END CatNum;

(* The input and line of the place p in the current text, as pandoc
   names them: a text read from part of another is a "chunk" of it,
   its lines counted from its start. *)
PROCEDURE Where(p: LONGINT; VAR name: ARRAY OF CHAR; VAR line: LONGINT);
  VAR i: LONGINT; d: INTEGER;
BEGIN
  name[0] := 0X; line := 1;
  IF main = NIL THEN RETURN END;
  IF B.depth = 0 THEN PdSource.Locate(main^, p, name, line)
  ELSE
    PdSource.Locate(main^, B.outerPos, name, line);
    FOR d := 1 TO B.depth DO Cat(name, "_chunk") END;
    line := 1;
    FOR i := 0 TO p - 1 DO
      IF B.t[i] = 0AX THEN INC(line) END
    END
  END
END Where;

(* Ends podoc with the YAML parse error PdYaml found, in a block or file
   at line in the input name *)
PROCEDURE YamlError(name: ARRAY OF CHAR; line: LONGINT);
  VAR m: Message;
BEGIN
  m := "Error parsing YAML metadata at ";
  IF name # "" THEN Cat(m, 22X); Cat(m, name); Cat(m, '" ') END;
  Cat(m, "(line "); CatNum(m, line); Cat(m, ", column 1):");
  Cat(m, 0AX); Cat(m, "YAML parse exception at line "); CatNum(m, Y.errLine);
  Cat(m, ", column "); CatNum(m, Y.errCol); Cat(m, ":"); Cat(m, 0AX);
  Cat(m, Y.error);
  IF Y.error = "bad indentation of a mapping entry" THEN
    (* libyaml's "did not find expected key", for which pandoc adds: *)
    Cat(m, 0AX); Cat(m, "Consider enclosing the entire field in 'single quotes'")
  END;
  PdIO.Fail("", m, PdIO.ParseError)
END YamlError;

(* Writes the warnings PdYaml found, for a block or file at line in the
   input name *)
PROCEDURE YamlWarnings(name: ARRAY OF CHAR; line: LONGINT);
  VAR w: Y.Warning; m: Message;
BEGIN
  w := Y.warnings;
  WHILE w # NIL DO
    m := "YAML warning (";
    IF name # "" THEN Cat(m, name); Cat(m, " ") END;
    Cat(m, "line "); CatNum(m, line); Cat(m, " column 1): ");
    Cat(m, w.text^);
    PdIO.Warn(m);
    w := w.next
  END
END YamlWarnings;

(* parseFromString' parseBlocks: the blocks of b, read with no last
   Str *)
PROCEDURE MetaBlocksOf(VAR b: B.Buf): A.Block;
  VAR sp, st: LONGINT; r: A.Block;
BEGIN
  sp := B.lastStrPos; st := B.lastStrText; B.lastStrPos := -1;
  r := BlocksOf(b);
  B.lastStrPos := sp; B.lastStrText := st;
  RETURN r
END MetaBlocksOf;

(* normalizeMetaValue: the string s[0 .. len-1] read as markdown. A
   string that ends in a new line (a block scalar's) is blocks; another
   is the blocks of it without its leading white space, as inlines. *)
PROCEDURE MetaText(VAR s: ARRAY OF CHAR; len: LONGINT): A.MetaValue;
  VAR i, e: LONGINT; b: B.Buf; v: PendingV;
BEGIN
  e := len;
  WHILE (e > 0) & ((s[e - 1] = " ") OR (s[e - 1] = 09X)) DO DEC(e) END;
  B.InitBuf(b);
  IF (e > 0) & (s[e - 1] = 0AX) THEN
    FOR i := 0 TO len - 1 DO B.PutChar(b, s[i]) END;
    B.PutChar(b, 0AX); B.PutChar(b, 0AX);
    RETURN A.NewMetaBlocks(MetaBlocksOf(b))
  END;
  i := 0;
  WHILE (i < len) & ((s[i] = " ") OR (s[i] = 09X) OR (s[i] = 0DX) OR (s[i] = 0AX)) DO
    INC(i)
  END;
  WHILE i < len DO B.PutChar(b, s[i]); INC(i) END;
  NEW(v); v.kind := A.MetaBlocks; v.blocks := MetaBlocksOf(b);
  RETURN v
END MetaText;

PROCEDURE^ MetaMapOf(nd: Y.Node): A.MetaMapV;

(* yamlToMetaValue: the YAML node nd as a metadata value *)
PROCEDURE MetaOf(nd: Y.Node): A.MetaValue;
  VAR v: A.MetaValue; l: A.MetaListV; p: Y.Pair; s: Y.Text; n: LONGINT;
    b: BOOLEAN;
BEGIN
  IF nd = NIL THEN RETURN A.NewMetaString(NIL) END;
  CASE nd.kind OF
    Y.Scalar:
      CASE Y.Resolve(nd, b) OF
        Y.Null: v := A.NewMetaString(NIL)
      | Y.Bool: v := A.NewMetaBool(b)
      | Y.Number: Y.NumberText(nd, s, n); v := MetaText(s^, n)
      ELSE
        IF nd.text = NIL THEN v := A.NewMetaInlines(NIL)
        ELSE v := MetaText(nd.text^, nd.len)
        END
      END
  | Y.Sequence:
      l := A.NewMetaList(); p := nd.items;
      WHILE p # NIL DO A.AddMetaItem(l, MetaOf(p.value)); p := p.next END;
      v := l
  | Y.Mapping: v := MetaMapOf(nd)
  END;
  RETURN v
END MetaOf;

(* yamlMap: the YAML mapping nd as a metadata map, without the keys
   that end in "_". The values are read in the order of their keys, as
   pandoc reads them. *)
PROCEDURE MetaMapOf(nd: Y.Node): A.MetaMapV;
  VAR m: A.MetaMapV; p: Y.Pair; b: B.Buf; i: LONGINT; nv: NodeV;
    e: A.MetaEntry;
BEGIN
  m := A.NewMetaMap(); p := nd.items;
  WHILE p # NIL DO
    B.InitBuf(b);
    IF p.key # NIL THEN
      FOR i := 0 TO p.key.len - 1 DO B.PutChar(b, p.key.text[i]) END
    END;
    IF (b.len = 0) OR (b.t[b.len - 1] # "_") THEN
      NEW(nv); nv.kind := 0; nv.node := p.value;
      A.SetMeta(m, B.BufRope(b), nv)
    END;
    p := p.next
  END;
  e := m.entries;
  WHILE e # NIL DO e.value := MetaOf(e.value(NodeV).node); e := e.next END;
  RETURN m
END MetaMapOf;

(* Whether the YAML document doc is null: no metadata *)
PROCEDURE IsNull(doc: Y.Node): BOOLEAN;
  VAR b: BOOLEAN;
BEGIN
  RETURN (doc = NIL) OR (doc.kind = Y.Scalar) & (Y.Resolve(doc, b) = Y.Null)
END IsNull;

(* yamlMetaBlock: a YAML block, its keys set in the document's metadata,
   replacing those of earlier blocks. One whose YAML is not a mapping
   (or null) is not a metadata block. *)
PROCEDURE YamlBlock(): BOOLEAN;
  VAR p, q, s, e, i, n, line: LONGINT; y: Y.Text; doc: Y.Node;
    m: A.MetaMapV; en: A.MetaEntry; name: Message;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "---") THEN RETURN FALSE END;
  q := B.BlankLine(p + 3);
  IF (q < 0) OR (B.BlankLine(q) >= 0) THEN RETURN FALSE END;
  s := q;
  LOOP
    IF q >= B.len THEN RETURN FALSE END;
    IF B.Looking(q, "---") OR B.Looking(q, "...") THEN
      e := B.BlankLine(q + 3);
      IF e >= 0 THEN EXIT END
    END;
    q := B.LineEnd(q);
    IF q >= B.len THEN RETURN FALSE END;
    INC(q)
  END;
  (* "---", the lines, and "..." *)
  n := q - s + 8;
  NEW(y, n + 1);
  y[0] := "-"; y[1] := "-"; y[2] := "-"; y[3] := 0AX;
  FOR i := s TO q - 1 DO y[i - s + 4] := B.t[i] END;
  y[n - 4] := "."; y[n - 3] := "."; y[n - 2] := "."; y[n - 1] := 0AX;
  y[n] := 0X;
  e := B.SkipBlankLines(e);
  Where(p, name, line);
  IF ~Y.Parse(y^, n, doc) THEN YamlError(name, line) END;
  YamlWarnings(name, line);
  IF ~IsNull(doc) THEN
    IF doc.kind # Y.Mapping THEN RETURN FALSE END;
    B.pos := e;
    m := MetaMapOf(doc);
    en := m.entries;
    WHILE en # NIL DO A.SetMeta(meta, en.key, en.value); en := en.next END
  END;
  B.pos := e;
  RETURN TRUE
END YamlBlock;

(* The title block *)

(* rawTitleBlockLine: the line at B.pos, which starts with %, and its
   continuation lines (each starting with a space or tab and not blank),
   put in b without the % and the spaces that start each line, joined
   by new lines and trimmed. B.pos is left after them. FALSE if there
   is no % line at B.pos. *)
PROCEDURE RawTitleLine(VAR b: B.Buf): BOOLEAN;
  VAR p, e, i: LONGINT;
BEGIN
  p := B.pos;
  IF (p >= B.len) OR (B.C(p) # "%") THEN RETURN FALSE END;
  B.InitBuf(b);
  p := B.SkipSpaces(p + 1);
  LOOP
    e := B.LineEnd(p);
    B.Put(b, p, e); B.PutChar(b, 0AX);
    IF e >= B.len THEN p := e; EXIT END;
    p := e + 1;
    IF ~B.IsSpace(B.C(p)) OR (B.BlankLine(p + 1) >= 0) THEN EXIT END;
    p := B.SkipSpaces(p + 1)
  END;
  B.pos := p;
  (* trim *)
  WHILE (b.len > 0) & B.IsWhite(b.t[b.len - 1]) DO DEC(b.len) END;
  b.t[b.len] := 0X;
  i := 0;
  WHILE (i < b.len) & B.IsWhite(b.t[i]) DO INC(i) END;
  IF i > 0 THEN
    FOR e := i TO b.len DO b.t[e - i] := b.t[e] END;
    DEC(b.len, i)
  END;
  RETURN TRUE
END RawTitleLine;

(* Where the authors line's authors stop: ; or a new line *)
PROCEDURE AuthorStop(p: LONGINT): BOOLEAN;
BEGIN
  RETURN (B.C(p) = ";") OR (B.C(p) = 0AX)
END AuthorStop;

(* authorsLine's authors in the text in b: inlines separated by ; and
   any white space after it, or by a new line, each trimmed; an empty
   one after a separator too *)
PROCEDURE AuthorsOf(VAR b: B.Buf): A.MetaListV;
  VAR f: B.Frame; l: A.Inlines; r: A.MetaListV; any: BOOLEAN;
BEGIN
  r := A.NewMetaList();
  B.Enter(f, b.t, b.len);
  LOOP
    A.InitInlines(l);
    any := I.Inlines(l, AuthorStop);
    A.AddMetaItem(r, A.NewMetaInlines(I.Trim(l)));
    IF B.pos >= B.len THEN EXIT
    ELSIF B.C(B.pos) = ";" THEN
      INC(B.pos);
      WHILE (B.pos < B.len) & B.IsWhite(B.C(B.pos)) DO INC(B.pos) END
    ELSIF B.C(B.pos) = 0AX THEN INC(B.pos)
    ELSE EXIT
    END
  END;
  B.Leave(f);
  RETURN r
END AuthorsOf;

(* pandocTitleBlock: the title, authors and date lines at the start of
   the document, and the blank lines after them, set in its metadata.
   An empty title or date sets nothing. *)
PROCEDURE TitleBlock;
  VAR b: B.Buf; inl: A.Inline;
BEGIN
  IF RawTitleLine(b) THEN
    inl := InlinesOf(b);
    IF inl # NIL THEN A.SetMeta(meta, A.S("title"), A.NewMetaInlines(inl)) END
  END;
  IF RawTitleLine(b) THEN A.SetMeta(meta, A.S("author"), AuthorsOf(b)) END;
  IF RawTitleLine(b) THEN
    inl := InlinesOf(b);
    IF inl # NIL THEN A.SetMeta(meta, A.S("date"), A.NewMetaInlines(inl)) END
  END;
  B.pos := B.SkipBlankLines(B.pos)
END TitleBlock;

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
  VAR p, q, start, s, e: LONGINT; level: INTEGER; inl: A.Inline; a: A.Attr;
    ch: CHAR;
BEGIN
  start := B.pos; p := start; level := 0;
  WHILE B.C(p) = "#" DO INC(p); INC(level) END;
  ch := B.C(p);
  IF (level = 0) OR (ch = ".") OR (ch = ")")
      OR (p < B.len) & ~B.IsWhite(ch) THEN
    RETURN FALSE
  END;
  B.pos := B.SkipSpaces(p); s := B.pos;
  inl := HeaderInlines(AtxStop);
  e := B.pos;
  q := AtxClosing(B.pos, a);
  IF q < 0 THEN B.pos := start; RETURN FALSE END;
  B.pos := q;
  RegisterHeader(a, inl);
  RegisterImplicitHeader(s, e, a.id);
  A.AddBlock(l, A.NewHeader(level, a, inl));
  RETURN TRUE
END AtxHeader;

(* setextHeader *)
PROCEDURE SetextHeader(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, start, s, e: LONGINT; level: INTEGER; inl: A.Inline; a: A.Attr;
    ch: CHAR;
BEGIN
  start := B.pos;
  p := B.AnyLine(start);
  IF p < 0 THEN RETURN FALSE END;
  q := p;
  WHILE (B.C(q) = "=") OR (B.C(q) = "-") DO INC(q) END;
  IF (q = p) OR (B.BlankLine(q) < 0) THEN RETURN FALSE END;
  B.pos := B.SkipSpaces(start); s := B.pos;
  inl := HeaderInlines(SetextStop);
  e := B.pos;
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
        RegisterImplicitHeader(s, e, a.id);
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

(* taskListItemFromAscii, applied to the item's blocks after resolving,
   as pandoc applies it *)
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
  VAR b: B.Buf; p, q, ci: LONGINT; old: INTEGER; blocks: A.Block; it: Item;
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
  NEW(items); items.blocks := blocks; items.next := NIL;
  NEW(it); it.item := items; it.next := listItems;
  listItems := it;
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

PROCEDURE^ Table(VAR l: A.Blocks): BOOLEAN;

(* Whether a table starts at p; the identifiers and implicit
   references of headings in its cells (a grid table's) are forgotten
   again *)
PROCEDURE TableAt(p: LONGINT): BOOLEAN;
  VAR save, sp, st: LONGINT; tmp: A.Blocks; found: BOOLEAN;
    saveIds: A.StrList; saveKeys: Key;
BEGIN
  save := B.pos; sp := B.lastStrPos; st := B.lastStrText; saveIds := ids;
  saveKeys := headerKeys;
  B.pos := p; A.InitBlocks(tmp);
  found := Table(tmp);
  B.pos := save; B.lastStrPos := sp; B.lastStrText := st;
  IF ids # saveIds THEN suffixes := NIL END;
  WHILE ids # saveIds DO Remove(idTable, ids.s); ids := ids.next END;
  WHILE headerKeys # saveKeys DO
    Remove(headerTable, headerKeys.key); headerKeys := headerKeys.next
  END;
  RETURN found
END TableAt;

(* definitionList; a line and a blank line before a table (whose
   caption starts with ":") start none *)
PROCEDURE DefinitionList(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; first, last, item: A.DefItem;
BEGIN
  p := B.AnyLine(B.pos);
  IF p < 0 THEN RETURN FALSE END;
  q := B.BlankLine(p);
  IF (q >= 0) & ~TableAt(q) THEN p := q END;
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
  A.AddBlock(l, A.NewDiv(B.HtmlTagAttr(tag), blocks));
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

(* Notes and reference keys *)

(* rawLines at p, appended to b with their new lines: the position
   after them, or -1 *)
PROCEDURE RawLines(VAR b: B.Buf; p: LONGINT): LONGINT;
  VAR q, e, n: LONGINT;
BEGIN
  e := B.AnyLine(p);
  IF e < 0 THEN RETURN -1 END;
  B.Put(b, p, e); p := e;
  LOOP
    IF (B.BlankLine(p) >= 0) OR B.DivCloser(p) THEN EXIT END;
    q := B.NonindentSpaces(p, n);
    IF (q >= 0) & (I.NoteMarker(q) >= 0) THEN EXIT END;
    q := B.IndentSpaces(p);
    IF q < 0 THEN q := p END;
    e := B.AnyLine(q);
    IF e < 0 THEN EXIT END;
    B.Put(b, q, e); p := e
  END;
  RETURN p
END RawLines;

(* noteBlock: a note's text, [^ref]: text, kept for its references *)
PROCEDURE NoteBlock(): BOOLEAN;
  VAR p, q, r, n, sp, st: LONGINT; b: B.Buf; nt: Note;
BEGIN
  p := B.NonindentSpaces(B.pos, n);
  IF p < 0 THEN RETURN FALSE END;
  q := I.NoteMarker(p);
  IF (q < 0) OR (B.C(q) # ":") THEN RETURN FALSE END;
  NEW(nt); nt.ref := B.Rope(p + 2, q - 1);
  p := q + 1;
  r := B.BlankLine(p);
  IF r >= 0 THEN p := r END;
  r := B.IndentSpaces(p);
  IF r >= 0 THEN p := r END;
  B.InitBuf(b);
  p := RawLines(b, p);
  IF p < 0 THEN RETURN FALSE END;
  B.PutChar(b, 0AX);
  LOOP
    r := B.BlankLines(p);
    IF r < 0 THEN EXIT END;
    r := B.IndentSpaces(r);
    IF r < 0 THEN EXIT END;
    r := RawLines(b, r);
    IF r < 0 THEN EXIT END;
    B.PutChar(b, 0AX); p := r
  END;
  B.PutChar(b, 0AX);
  r := B.BlankLines(p);
  IF r >= 0 THEN p := r END;
  B.pos := p;
  sp := B.lastStrPos; st := B.lastStrText; B.lastStrPos := -1;
  nt.blocks := BlocksOf(b);
  B.lastStrPos := sp; B.lastStrText := st;
  nt.next := notes; notes := nt;
  RETURN TRUE
END NoteBlock;

(* referenceKey *)
PROCEDURE ReferenceKey(): BOOLEAN;
  VAR k: Key;
BEGIN
  NEW(k);
  IF ~I.ReferenceKey(k.key, k.url, k.title, k.attr) THEN RETURN FALSE END;
  k.next := keys; keys := k;
  Add(keyTable, k.key, k);
  RETURN TRUE
END ReferenceKey;

(* Paragraphs *)

(* B.text: the inlines of the text r, its words separated by spaces
   and soft breaks *)
PROCEDURE TextInlines(r: A.Rope): A.Inline;
  VAR l: A.Inlines; b: B.Buf; i, n: LONGINT; ch: CHAR; nl, sp: BOOLEAN;
BEGIN
  A.InitInlines(l); B.InitBuf(b);
  n := Ropes.Length(r); i := 0;
  WHILE i < n DO
    ch := Ropes.Fetch(r, i);
    IF (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX) THEN
      nl := FALSE; sp := TRUE;
      WHILE (i < n) & sp DO
        ch := Ropes.Fetch(r, i);
        sp := (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX);
        IF sp THEN nl := nl OR (ch = 0AX); INC(i) END
      END;
      IF b.len > 0 THEN A.Append(l, A.NewStr(B.BufRope(b))); B.InitBuf(b) END;
      IF nl THEN A.Append(l, A.NewSimple(A.SoftBreak))
      ELSE A.Append(l, A.NewSimple(A.Space))
      END
    ELSE
      B.PutChar(b, ch); INC(i)
    END
  END;
  IF b.len > 0 THEN A.Append(l, A.NewStr(B.BufRope(b))) END;
  RETURN l.first
END TextInlines;

(* implicitFigure: a Plain or Para of inl, whose only inline is an image
   with a description, as a Figure; else NIL *)
PROCEDURE Figure(inl: A.Inline): A.Block;
  VAR img: A.LinkInl; alt: A.Inline; fa, ia: A.Attr; kv: A.KeyVal;
    v: A.Rope; found: BOOLEAN;
BEGIN
  IF (inl = NIL) OR (inl.next # NIL) OR (inl.kind # A.Image)
      OR (inl(A.LinkInl).content = NIL) THEN
    RETURN NIL
  END;
  img := inl(A.LinkInl);
  v := A.GetKeyVal(img.attr, "alt", found);
  IF found THEN alt := TextInlines(v) ELSE alt := A.CopyInlines(img.content) END;
  fa := A.NewAttr(img.attr.id);
  v := A.GetKeyVal(img.attr, "latex-placement", found);
  IF found THEN A.AddKeyVal(fa, A.S("latex-placement"), v) END;
  ia := A.NewAttr(NIL); ia.classes := img.attr.classes;
  kv := img.attr.attrs;
  WHILE kv # NIL DO
    IF ~Ropes.EqualString(kv.key, "alt")
        & ~Ropes.EqualString(kv.key, "latex-placement") THEN
      A.AddKeyVal(ia, kv.key, kv.value)
    END;
    kv := kv.next
  END;
  RETURN A.NewFigure(fa, A.NewInlinesBlock(A.Plain, img.content),
    A.NewInlinesBlock(A.Plain,
      A.NewLink(A.Image, ia, alt, img.url, img.title)))
END Figure;

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
  (* B.plain drops a Plain with no inlines; B.para keeps an empty Para *)
  IF (kind = A.Para) OR (inl # NIL) THEN A.AddBlock(l, A.NewInlinesBlock(kind, inl)) END;
  RETURN TRUE
END Para;

(* Tables *)

(* isWS: a space, tab, carriage return or new line *)
PROCEDURE IsWS(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X) OR (ch = 0DX) OR (ch = 0AX)
END IsWS;

(* trim: t[from .. to-1] without the white space around it *)
PROCEDURE TrimRange(VAR from, to: LONGINT);
BEGIN
  WHILE (from < to) & IsWS(B.t[from]) DO INC(from) END;
  WHILE (to > from) & IsWS(B.t[to - 1]) DO DEC(to) END
END TrimRange;

(* The number of characters in t[from .. to-1] *)
PROCEDURE CharCount(from, to: LONGINT): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0;
  WHILE from < to DO
    IF (ORD(B.t[from]) < 80H) OR (ORD(B.t[from]) >= 0C0H) THEN INC(n) END;
    INC(from)
  END;
  RETURN n
END CharCount;

(* splitAtWidth: where the first part of width w of t[p .. e-1] ends *)
PROCEDURE SplitAt(p, e, w: LONGINT): LONGINT;
  VAR n, q: LONGINT;
BEGIN
  n := 0;
  WHILE (n < w) & (p < e) DO INC(n, I.CharWidth(p, q)); p := q END;
  IF p > e THEN p := e END;
  RETURN p
END SplitAt;

(* Sets a[i] to v, making a longer if it must be *)
PROCEDURE SetLong(VAR a: Longs; i, v: LONGINT);
  VAR b: Longs; k: LONGINT;
BEGIN
  IF a = NIL THEN NEW(a, 8) END;
  IF i >= LEN(a^) THEN
    NEW(b, 2 * LEN(a^));
    FOR k := 0 TO LEN(a^) - 1 DO b[k] := a[k] END;
    a := b
  END;
  a[i] := v
END SetLong;

(* A new line of no cells *)
PROCEDURE NewRawLine(): RawLine;
  VAR r: RawLine;
BEGIN
  NEW(r); r.s := NIL; r.f := NIL; r.m := 0; r.next := NIL;
  RETURN r
END NewRawLine;

PROCEDURE AddRawCell(r: RawLine; from, to: LONGINT);
BEGIN
  SetLong(r.s, r.m, from); SetLong(r.f, r.m, to); INC(r.m)
END AddRawCell;

(* splitTextByIndices (init indices), drop 1: t[p .. e-1] split into
   c.n cells *)
PROCEDURE SplitLine(p, e: LONGINT; VAR c: Columns): RawLine;
  VAR r: RawLine; k, q: LONGINT;
BEGIN
  r := NewRawLine();
  p := SplitAt(p, e, c.index[0]);
  FOR k := 0 TO c.n - 1 DO
    IF k < c.n - 1 THEN q := SplitAt(p, e, c.index[k + 1] - c.index[k])
    ELSE q := e
    END;
    AddRawCell(r, p, q); p := q
  END;
  RETURN r
END SplitLine;

(* alignType: a column's alignment, from its header's lines, cell k of
   each of the lines l, and len, the length of its dashes *)
PROCEDURE AlignType(l: RawLine; k, len: LONGINT): INTEGER;
  VAR s, e, bs, be, bn, n: LONGINT; left, right: BOOLEAN;
BEGIN
  bs := -1; bn := 0; be := 0;
  WHILE l # NIL DO
    s := l.s[k]; e := l.f[k];
    WHILE (e > s) & IsWS(B.t[e - 1]) DO DEC(e) END;
    IF e > s THEN
      n := CharCount(s, e);
      IF (bs < 0) OR (n < bn) THEN bs := s; be := e; bn := n END
    END;
    l := l.next
  END;
  IF bs < 0 THEN RETURN A.AlignDefault END;
  left := B.IsSpace(B.t[bs]); right := I.RealLength(bs, be) < len;
  IF left & right THEN RETURN A.AlignCenter
  ELSIF left THEN RETURN A.AlignRight
  ELSIF right THEN RETURN A.AlignLeft
  END;
  RETURN A.AlignDefault
END AlignType;

(* parseFromString' (mconcat <$> many plain): a cell of the text in b *)
PROCEDURE CellOf(VAR b: B.Buf): A.Cell;
  VAR c: A.Cell; sp, st: LONGINT; inl: A.Inline;
BEGIN
  NEW(c); c.attr := NIL; c.align := A.AlignDefault;
  c.rowSpan := 1; c.colSpan := 1; c.blocks := NIL; c.next := NIL;
  IF b.len > 0 THEN
    sp := B.lastStrPos; st := B.lastStrText; B.lastStrPos := -1;
    inl := InlinesOf(b);
    B.lastStrPos := sp; B.lastStrText := st;
    IF inl # NIL THEN c.blocks := A.NewInlinesBlock(A.Plain, inl) END
  END;
  RETURN c
END CellOf;

(* A cell of t[from .. to-1], trimmed *)
PROCEDURE RangeCell(from, to: LONGINT): A.Cell;
  VAR b: B.Buf;
BEGIN
  TrimRange(from, to);
  B.InitBuf(b); B.Put(b, from, to);
  RETURN CellOf(b)
END RangeCell;

(* A row of the cells of l, trimmed, at most n of them *)
PROCEDURE LineRow(l: RawLine; n: LONGINT): A.Row;
  VAR r: A.Row; c, last: A.Cell; k: LONGINT;
BEGIN
  NEW(r); r.attr := NIL; r.cells := NIL; r.next := NIL; last := NIL;
  k := 0;
  WHILE (k < l.m) & (k < n) DO
    c := RangeCell(l.s[k], l.f[k]);
    IF last = NIL THEN r.cells := c ELSE last.next := c END;
    last := c; INC(k)
  END;
  RETURN r
END LineRow;

(* Whether all of r's cells are empty *)
PROCEDURE EmptyRow(r: A.Row): BOOLEAN;
  VAR c: A.Cell;
BEGIN
  c := r.cells;
  WHILE (c # NIL) & (c.blocks = NIL) DO c := c.next END;
  RETURN c = NIL
END EmptyRow;

(* Makes r n cells long, as pandoc's table builder does *)
PROCEDURE PadRow(r: A.Row; n: LONGINT);
  VAR c: A.Cell; b: B.Buf; k: LONGINT;
BEGIN
  B.InitBuf(b);
  IF n = 0 THEN r.cells := NIL; RETURN END;
  IF r.cells = NIL THEN r.cells := CellOf(b) END;
  c := r.cells; k := 1;
  WHILE k < n DO
    IF c.next = NIL THEN c.next := CellOf(b) END;
    c := c.next; INC(k)
  END;
  c.next := NIL
END PadRow;

(* The rows in l, a list in the reverse order, in order, each made c.n
   cells long *)
PROCEDURE Rows(l: A.Row; n: LONGINT): A.Row;
  VAR r, next: A.Row;
BEGIN
  r := NIL;
  WHILE l # NIL DO
    next := l.next; PadRow(l, n); l.next := r; r := l; l := next
  END;
  RETURN r
END Rows;

(* a / b in LONGREAL; a / b of two integers is only a REAL *)
PROCEDURE Ratio(a, b: LONGINT): LONGREAL;
  VAR x: LONGREAL;
BEGIN
  x := a;
  RETURN x / b
END Ratio;

(* toTableComponents' NormalizeHeader: the table of the columns c, the
   header row head (NIL for none) and the rows rows, in the reverse
   order *)
PROCEDURE MakeTable(VAR c: Columns; head, rows: A.Row): A.TableBlk;
  VAR t: A.TableBlk; cs, last: A.ColSpec; tb: A.TableBody; k: LONGINT;
    total: LONGREAL;
BEGIN
  t := A.NewTable(NIL);
  total := 0;
  FOR k := 0 TO c.n - 1 DO total := total + c.width[k] END;
  last := NIL;
  FOR k := 0 TO c.n - 1 DO
    NEW(cs); cs.align := SHORT(c.align[k]); cs.next := NIL;
    IF total >= 1 THEN cs.width := c.width[k] / total
    ELSE cs.width := c.width[k]
    END;
    cs.hasWidth := cs.width > 0;
    IF last = NIL THEN t.colSpecs := cs ELSE last.next := cs END;
    last := cs
  END;
  IF (head # NIL) & ~EmptyRow(head) THEN
    PadRow(head, c.n); t.head.rows := head
  END;
  NEW(tb); tb.attr := NIL; tb.rowHeadColumns := 0; tb.head := NIL;
  tb.body := Rows(rows, c.n); tb.next := NIL;
  t.bodies := tb;
  RETURN t
END MakeTable;

(* blanklines' *)
PROCEDURE BlankLinesP(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := B.BlankLines(p);
  IF (q < 0) & (B.divLevel >= 1) & (B.DivFenceEnd(p) >= 0) THEN q := p END;
  RETURN q
END BlankLinesP;

(* nonindentSpaces, many1 (dashedLine '-'), newline: where they end,
   or -1. If fill, c.len and c.index are set. *)
PROCEDURE DashRow(p: LONGINT; VAR c: Columns; fill: BOOLEAN): LONGINT;
  VAR sp, n, q: LONGINT;
BEGIN
  p := B.NonindentSpaces(p, sp);
  IF p < 0 THEN RETURN -1 END;
  IF fill THEN c.index[0] := sp END;
  n := 0;
  WHILE B.C(p) = "-" DO
    q := p;
    WHILE B.C(p) = "-" DO INC(p) END;
    IF fill THEN c.len[n] := p - q END;
    WHILE B.IsSpace(B.C(p)) DO INC(p) END;
    IF fill THEN c.index[n + 1] := c.index[n] + p - q END;
    INC(n)
  END;
  IF (n = 0) OR (B.C(p) # 0AX) THEN RETURN -1 END;
  c.n := n;
  RETURN p + 1
END DashRow;

(* The dashed line under a simple or multiline table's header, at p:
   where it ends, or -1. Sets c. *)
PROCEDURE Dashes(p: LONGINT; VAR c: Columns): LONGINT;
  VAR q, k: LONGINT;
BEGIN
  q := DashRow(p, c, FALSE);
  IF q >= 0 THEN
    NEW(c.len, c.n); NEW(c.index, c.n + 1);
    NEW(c.align, c.n); NEW(c.width, c.n);
    FOR k := 0 TO c.n - 1 DO c.align[k] := A.AlignDefault; c.width[k] := 0 END;
    q := DashRow(p, c, TRUE)
  END;
  RETURN q
END Dashes;

(* tableFooter *)
PROCEDURE TableFooter(p: LONGINT): LONGINT;
  VAR sp: LONGINT;
BEGIN
  p := B.NonindentSpaces(p, sp);
  IF (p < 0) OR (B.C(p) # "-") THEN RETURN -1 END;
  WHILE (B.C(p) = "-") OR B.IsSpace(B.C(p)) DO INC(p) END;
  RETURN BlankLinesP(p)
END TableFooter;

(* rawTableLine: a line of a simple or multiline table, at p, split
   into l; where it ends, or -1 *)
PROCEDURE RawTableLine(p: LONGINT; VAR c: Columns; VAR l: RawLine): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF (BlankLinesP(p) >= 0) OR (TableFooter(p) >= 0) THEN RETURN -1 END;
  q := B.AnyLine(p);
  IF q >= 0 THEN l := SplitLine(p, q - 1, c) END;
  RETURN q
END RawTableLine;

(* widthsFromIndices columns *)
PROCEDURE WidthsFromIndices(VAR c: Columns);
  VAR len: Longs; k, total, cols: LONGINT; q: LONGREAL;
BEGIN
  NEW(len, c.n + 1);
  len[0] := c.index[0];
  FOR k := 1 TO c.n DO len[k] := c.index[k] - c.index[k - 1] END;
  IF (c.n >= 1) & (len[c.n] < len[c.n - 1])
      & (len[c.n - 1] - len[c.n] <= 2) THEN
    len[c.n] := len[c.n - 1]
  END;
  cols := columns;
  IF c.index[c.n] > cols THEN cols := c.index[c.n] END;
  total := 0;
  FOR k := 0 TO c.n DO INC(total, len[k]) END;
  IF total > cols THEN q := total ELSE q := cols END;
  FOR k := 0 TO c.n - 1 DO c.width[k] := len[k + 1] / q END
END WidthsFromIndices;

(* simpleTable headless at p: where it ends, or -1; the table in t *)
PROCEDURE SimpleTable(p: LONGINT; headless: BOOLEAN; VAR t: A.TableBlk): LONGINT;
  VAR c: Columns; q, k: LONGINT; heads, l: RawLine; head, rows, r: A.Row;
BEGIN
  IF headless THEN
    q := Dashes(p, c);
    IF q < 0 THEN RETURN -1 END;
    k := B.AnyLine(q);
    IF k < 0 THEN RETURN -1 END;
    heads := SplitLine(q, k - 1, c)
  ELSE
    k := B.AnyLine(p);
    IF k < 0 THEN RETURN -1 END;
    q := Dashes(k, c);
    IF q < 0 THEN RETURN -1 END;
    heads := SplitLine(p, k - 1, c)
  END;
  FOR k := 0 TO c.n - 1 DO c.align[k] := AlignType(heads, k, c.len[k]) END;
  rows := NIL;
  LOOP
    k := RawTableLine(q, c, l);
    IF k < 0 THEN EXIT END;
    r := LineRow(l, c.n); r.next := rows; rows := r; q := k
  END;
  IF rows = NIL THEN RETURN -1 END;
  k := TableFooter(q);
  IF (k < 0) & ~headless THEN k := BlankLinesP(q) END;
  IF k < 0 THEN RETURN -1 END;
  IF headless THEN head := NIL ELSE head := LineRow(heads, c.n) END;
  FOR q := 0 TO c.n - 1 DO c.width[q] := 0 END;
  t := MakeTable(c, head, rows);
  RETURN k
END SimpleTable;

(* A multiline cell: cell k of each of the lines l, trimmed, each
   followed by a new line; if trim, the whole trimmed too *)
PROCEDURE MultilineCell(l: RawLine; k: LONGINT; trim: BOOLEAN): A.Cell;
  VAR b: B.Buf; s, e: LONGINT;
BEGIN
  B.InitBuf(b);
  WHILE l # NIL DO
    s := l.s[k]; e := l.f[k]; TrimRange(s, e);
    IF ~trim OR (b.len > 0) OR (e > s) THEN
      B.Put(b, s, e); B.PutChar(b, 0AX)
    END;
    l := l.next
  END;
  IF trim THEN
    WHILE (b.len > 0) & IsWS(b.t[b.len - 1]) DO DEC(b.len) END;
    b.t[b.len] := 0X
  END;
  RETURN CellOf(b)
END MultilineCell;

(* Appends l to the list first .. last *)
PROCEDURE AppendLine(VAR first, last: RawLine; l: RawLine);
BEGIN
  l.next := NIL;
  IF last = NIL THEN first := l ELSE last.next := l END;
  last := l
END AppendLine;

(* A multiline row of the lines l *)
PROCEDURE MultilineRow(l: RawLine; VAR c: Columns; trim: BOOLEAN): A.Row;
  VAR r: A.Row; cell, last: A.Cell; k: LONGINT;
BEGIN
  NEW(r); r.attr := NIL; r.cells := NIL; r.next := NIL; last := NIL;
  FOR k := 0 TO c.n - 1 DO
    cell := MultilineCell(l, k, trim);
    IF last = NIL THEN r.cells := cell ELSE last.next := cell END;
    last := cell
  END;
  RETURN r
END MultilineRow;

(* multilineTable headless at p: where it ends, or -1; the table in t *)
PROCEDURE MultilineTable(p: LONGINT; headless: BOOLEAN; VAR t: A.TableBlk): LONGINT;
  VAR c: Columns; q, k, n: LONGINT; starts: Longs;
    heads, hlast, lines, llast, l: RawLine; head, rows, r: A.Row;
BEGIN
  heads := NIL; hlast := NIL;
  IF headless THEN
    q := Dashes(p, c);
    IF q < 0 THEN RETURN -1 END;
    INC(c.index[c.n]);
    k := B.AnyLine(q);
    IF k < 0 THEN RETURN -1 END;
    heads := SplitLine(q, k - 1, c)
  ELSE
    q := DashRow(p, c, FALSE);
    IF (q < 0) OR (B.BlankLine(q) >= 0) THEN RETURN -1 END;
    n := 0; starts := NIL;
    WHILE DashRow(q, c, FALSE) < 0 DO
      SetLong(starts, n, q); INC(n);
      q := B.AnyLine(q);
      IF q < 0 THEN RETURN -1 END
    END;
    IF n = 0 THEN RETURN -1 END;
    q := Dashes(q, c);
    INC(c.index[c.n]);
    FOR k := 0 TO n - 1 DO
      AppendLine(heads, hlast,
        SplitLine(starts[k], B.LineEnd(starts[k]), c))
    END
  END;
  FOR k := 0 TO c.n - 1 DO c.align[k] := AlignType(heads, k, c.len[k]) END;
  rows := NIL;
  LOOP
    lines := NIL; llast := NIL;
    LOOP
      k := RawTableLine(q, c, l);
      IF k < 0 THEN EXIT END;
      AppendLine(lines, llast, l); q := k
    END;
    IF lines = NIL THEN EXIT END;
    r := MultilineRow(lines, c, FALSE); r.next := rows; rows := r;
    k := B.BlankLines(q);
    IF k < 0 THEN EXIT END;
    q := k
  END;
  IF rows = NIL THEN RETURN -1 END;
  k := TableFooter(q);
  IF k < 0 THEN RETURN -1 END;
  IF headless THEN head := NIL ELSE head := MultilineRow(heads, c, TRUE) END;
  WidthsFromIndices(c);
  t := MakeTable(c, head, rows);
  RETURN k
END MultilineTable;

(* scanForPipe: whether the line at p has a pipe *)
PROCEDURE ScanForPipe(p: LONGINT): BOOLEAN;
BEGIN
  WHILE (p < B.len) & (B.t[p] # 0AX) & (B.t[p] # "|") DO INC(p) END;
  RETURN B.C(p) = "|"
END ScanForPipe;

(* pipeTableRow at p, its raw cells in l: where it ends, or -1 *)
PROCEDURE PipeTableRow(p: LONGINT; VAR l: RawLine): LONGINT;
  VAR open: BOOLEAN; s, q: LONGINT; ch: CHAR;
BEGIN
  IF ~ScanForPipe(p) THEN RETURN -1 END;
  p := B.SkipSpaces(p);
  open := B.C(p) = "|";
  IF open THEN INC(p) END;
  l := NewRawLine();
  LOOP
    s := p;
    LOOP
      ch := B.C(p);
      IF (p >= B.len) OR (ch = "|") OR (ch = 0AX) OR (ch = 0DX) THEN EXIT END;
      q := I.Chunk(p);
      IF q > p THEN p := q ELSE INC(p) END
    END;
    AddRawCell(l, s, p);
    IF B.C(p) # "|" THEN EXIT END;
    INC(p)
  END;
  IF (l.m = 1) & ~open THEN RETURN -1 END;
  RETURN B.BlankLine(p)
END PipeTableRow;

(* pipeTableHeaderPart at p: where it ends, or -1; its alignment and
   length in c's column k *)
PROCEDURE PipeHeaderPart(p: LONGINT; VAR c: Columns; k: LONGINT): LONGINT;
  VAR left, right: BOOLEAN; s: LONGINT; al: INTEGER;
BEGIN
  p := B.SkipSpaces(p);
  left := B.C(p) = ":";
  IF left THEN INC(p) END;
  IF B.C(p) # "-" THEN RETURN -1 END;
  s := p;
  WHILE B.C(p) = "-" DO INC(p) END;
  SetLong(c.len, k, p - s);
  right := B.C(p) = ":";
  IF right THEN INC(p) END;
  IF left THEN INC(c.len[k]) END;
  IF right THEN INC(c.len[k]) END;
  IF left & right THEN al := A.AlignCenter
  ELSIF left THEN al := A.AlignLeft
  ELSIF right THEN al := A.AlignRight
  ELSE al := A.AlignDefault
  END;
  SetLong(c.align, k, al);
  RETURN B.SkipSpaces(p)
END PipeHeaderPart;

(* pipeBreak at p: where it ends, or -1; the columns in c *)
PROCEDURE PipeBreak(p: LONGINT; VAR c: Columns): LONGINT;
  VAR sp, q: LONGINT; open: BOOLEAN; ch: CHAR;
BEGIN
  c.len := NIL; c.align := NIL; c.n := 0;
  p := B.NonindentSpaces(p, sp);
  IF p < 0 THEN RETURN -1 END;
  open := B.C(p) = "|";
  IF open THEN INC(p) END;
  p := PipeHeaderPart(p, c, 0);
  IF p < 0 THEN RETURN -1 END;
  c.n := 1;
  LOOP
    ch := B.C(p);
    IF ((ch = "|") OR (ch = "+")) & (B.BlankLine(p + 1) < 0) THEN
      q := PipeHeaderPart(p + 1, c, c.n);
      IF q < 0 THEN EXIT END;
      p := q; INC(c.n)
    ELSE
      EXIT
    END
  END;
  IF B.C(p) = "|" THEN INC(p)
  ELSIF (c.n = 1) & ~open THEN RETURN -1
  END;
  RETURN B.BlankLine(p)
END PipeBreak;

(* The width of the first n raw cells of l *)
PROCEDURE LineWidth(l: RawLine; n: LONGINT): LONGINT;
  VAR k, w: LONGINT;
BEGIN
  w := 0; k := 0;
  WHILE (k < l.m) & (k < n) DO INC(w, I.RealLength(l.s[k], l.f[k])); INC(k) END;
  RETURN w
END LineWidth;

(* pipeTable at p: where it ends, or -1; the table in t *)
PROCEDURE PipeTable(p: LONGINT; VAR t: A.TableBlk): LONGINT;
  VAR c: Columns; sp, k, sum, max, w: LONGINT; heads, lines, l: RawLine;
    rows, r, head: A.Row; ch: CHAR;
BEGIN
  p := B.NonindentSpaces(p, sp);
  IF p < 0 THEN RETURN -1 END;
  ch := B.C(p);
  IF (p >= B.len) OR IsWS(ch) THEN RETURN -1 END;
  p := PipeTableRow(p, heads);
  IF p < 0 THEN RETURN -1 END;
  p := PipeBreak(p, c);
  IF p < 0 THEN RETURN -1 END;
  lines := NIL;
  LOOP
    k := PipeTableRow(p, l);
    IF k < 0 THEN EXIT END;
    l.next := lines; lines := l; p := k
  END;
  sum := 0;
  FOR k := 0 TO c.n - 1 DO INC(sum, c.len[k]) END;
  max := LineWidth(heads, c.n);
  l := lines;
  WHILE l # NIL DO
    w := LineWidth(l, c.n);
    IF w > max THEN max := w END;
    l := l.next
  END;
  IF sum > max THEN max := sum END;
  NEW(c.width, c.n);
  FOR k := 0 TO c.n - 1 DO
    IF max + c.n + 1 > columns THEN c.width[k] := Ratio(c.len[k], sum)
    ELSE c.width[k] := 0
    END
  END;
  rows := NIL; l := lines; (* both in the reverse order *)
  WHILE l # NIL DO
    r := LineRow(l, c.n); r.next := rows; rows := r; l := l.next
  END;
  (* rows is in order; MakeTable wants it reversed *)
  lines := NIL; r := rows; rows := NIL;
  WHILE r # NIL DO head := r.next; r.next := rows; rows := r; r := head END;
  t := MakeTable(c, LineRow(heads, c.n), rows);
  RETURN p
END PipeTable;

(* Grid tables *)

(* The rows of t, from row from to row to-1, in order *)
PROCEDURE GridRows(VAR t: G.Table; from, to: LONGINT): A.Row;
  VAR first, last, r: A.Row; c, clast: A.Cell; x: G.Cell; i, j: LONGINT;
    b: A.Block;
BEGIN
  first := NIL; last := NIL;
  FOR i := from TO to - 1 DO
    NEW(r); r.attr := NIL; r.cells := NIL; r.next := NIL; clast := NIL;
    FOR j := 0 TO t.cols - 1 DO
      x := t.cells[i * t.cols + j];
      IF x # NIL THEN
        c := SH.EmptyCell(); c.rowSpan := x.rowSpan; c.colSpan := x.colSpan;
        b := MetaBlocksOf(x.text);
        (* plainify *)
        IF (b # NIL) & (b.next = NIL) & (b IS A.InlinesBlk)
            & (b(A.InlinesBlk).kind = A.Para) THEN
          b := A.NewInlinesBlock(A.Plain, b(A.InlinesBlk).inlines)
        END;
        c.blocks := b;
        IF clast = NIL THEN r.cells := c ELSE clast.next := c END;
        clast := c
      END
    END;
    IF last = NIL THEN first := r ELSE last.next := r END;
    last := r
  END;
  RETURN first
END GridRows;

(* Whether the row r has a cell and only empty cells *)
PROCEDURE NullHeader(r: A.Row): BOOLEAN;
  VAR c: A.Cell;
BEGIN
  c := r.cells;
  IF c = NIL THEN RETURN TRUE END;
  WHILE c # NIL DO
    IF (c.blocks # NIL) OR (c.rowSpan # 1) OR (c.colSpan # 1) THEN
      RETURN FALSE
    END;
    c := c.next
  END;
  RETURN TRUE
END NullHeader;

(* gridTable (gridTableWith' NormalizeHeader parseBlocks) at p: where
   it ends, or -1; the table in t *)
PROCEDURE GridTable(p: LONGINT; VAR t: A.TableBlk): LONGINT;
  VAR g: G.Table; q, indent, k, bodyEnd: LONGINT; cs, last: A.ColSpec;
    tb: A.TableBody; total, norm: LONGINT;
BEGIN
  q := B.NonindentSpaces(p, indent);
  IF q < 0 THEN RETURN -1 END;
  q := G.Trace(p, q - p, g);
  IF q < 0 THEN RETURN -1 END;
  t := A.NewTable(NIL);
  (* fractionalColumnWidths columns *)
  total := 0;
  FOR k := 0 TO g.cols - 1 DO INC(total, g.width[k] + 1) END;
  norm := total + g.cols - 2;
  IF norm < columns THEN norm := columns END;
  last := NIL;
  FOR k := 0 TO g.cols - 1 DO
    NEW(cs); cs.next := NIL;
    CASE g.align[k] OF
      G.AlignLeft: cs.align := A.AlignLeft
    | G.AlignRight: cs.align := A.AlignRight
    | G.AlignCenter: cs.align := A.AlignCenter
    ELSE cs.align := A.AlignDefault
    END;
    cs.width := Ratio(g.width[k] + 1, norm); cs.hasWidth := TRUE;
    IF last = NIL THEN t.colSpecs := cs ELSE last.next := cs END;
    last := cs
  END;
  IF g.headLen > g.rows THEN g.headLen := g.rows END;
  t.head.rows := GridRows(g, 0, g.headLen);
  IF g.foot >= 0 THEN
    bodyEnd := g.foot - 1;
    IF bodyEnd < g.headLen THEN bodyEnd := g.headLen END;
    IF bodyEnd > g.rows THEN bodyEnd := g.rows END
  ELSE
    bodyEnd := g.rows
  END;
  NEW(tb); tb.attr := NIL; tb.rowHeadColumns := 0; tb.head := NIL;
  tb.body := GridRows(g, g.headLen, bodyEnd); tb.next := NIL;
  t.bodies := tb;
  t.foot.rows := GridRows(g, bodyEnd, g.rows);
  IF (t.head.rows # NIL) & (t.head.rows.next = NIL) & NullHeader(t.head.rows) THEN
    t.head.rows := NIL
  END;
  SH.PlaceRows(t.head.rows, g.cols);
  SH.PlaceRows(tb.body, g.cols);
  SH.PlaceRows(t.foot.rows, g.cols);
  RETURN q
END GridTable;

(* Whether attributes and blank lines follow at p: a caption's
   inlines stop there *)
PROCEDURE CaptionStop(p: LONGINT): BOOLEAN;
  VAR a: A.Attr; q: LONGINT;
BEGIN
  q := B.Attributes(p, a);
  RETURN (q >= 0) & (B.BlankLines(q) >= 0)
END CaptionStop;

(* tableCaption at p: where it ends, or -1; its inlines and
   attributes *)
PROCEDURE TableCaption(p: LONGINT; VAR inl: A.Inline; VAR attr: A.Attr): LONGINT;
  VAR sp, sv, st, q: LONGINT; l: A.Inlines; a: A.Attr; ok: BOOLEAN;
BEGIN
  p := B.NonindentSpaces(p, sp);
  IF p < 0 THEN RETURN -1 END;
  IF (B.C(p) = ":") & ~I.PunctAt(p + 1) THEN INC(p)
  ELSIF ((B.C(p) = "T") OR (B.C(p) = "t")) & B.Looking(p + 1, "able:") THEN
    INC(p, 6)
  ELSE
    RETURN -1
  END;
  sv := B.pos; sp := B.lastStrPos; st := B.lastStrText;
  B.pos := p; A.InitInlines(l);
  ok := I.Inlines(l, CaptionStop);
  inl := I.Trim(l); q := B.pos; attr := NIL;
  B.pos := sv;
  p := B.Attributes(q, a);
  IF p >= 0 THEN attr := a; q := p END;
  q := B.BlankLines(q);
  IF q < 0 THEN B.lastStrPos := sp; B.lastStrText := st END;
  RETURN q
END TableCaption;

(* table: a pipe, multiline, simple or grid table, with an optional caption
   before or after it *)
PROCEDURE Table(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, r, sp, st: LONGINT; t: A.TableBlk; inl: A.Inline;
    attr: A.Attr; front: BOOLEAN;
BEGIN
  p := B.pos; sp := B.lastStrPos; st := B.lastStrText;
  q := TableCaption(p, inl, attr); front := q >= 0;
  IF ~front THEN q := p END;
  r := -1;
  IF ScanForPipe(q) THEN r := PipeTable(q, t) END;
  IF r < 0 THEN r := MultilineTable(q, FALSE, t) END;
  IF r < 0 THEN r := SimpleTable(q, TRUE, t) END;
  IF r < 0 THEN r := SimpleTable(q, FALSE, t) END;
  IF r < 0 THEN r := MultilineTable(q, TRUE, t) END;
  IF (r < 0) & gridTables THEN r := GridTable(q, t) END;
  IF r < 0 THEN
    B.lastStrPos := sp; B.lastStrText := st;
    RETURN FALSE
  END;
  r := B.SkipBlankLines(r);
  IF ~front THEN
    q := TableCaption(r, inl, attr);
    IF q >= 0 THEN r := q ELSE inl := NIL; attr := NIL END
  END;
  t.attr := attr;
  IF inl # NIL THEN t.caption.blocks := A.NewInlinesBlock(A.Plain, inl) END;
  A.AddBlock(l, t); B.pos := r;
  RETURN TRUE
END Table;

(* block: one block at B.pos, added to l (blank lines add nothing);
   FALSE if there is none *)
PROCEDURE Block(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  IF B.pos >= B.len THEN RETURN FALSE END;
  q := B.BlankLines(B.pos);
  IF q >= 0 THEN B.pos := q; RETURN TRUE END;
  IF FencedCode(l) OR YamlBlock() OR BulletList(l) OR DivHtml(l) OR DivFenced(l)
      OR SetextHeader(l) OR AtxHeader(l) OR HtmlBlock(l)
      OR Table(l) OR IndentedCode(l) OR LineBlock(l) OR BlockQuote(l) THEN
    RETURN TRUE
  END;
  q := B.Hrule(B.pos);
  IF q >= 0 THEN
    A.AddBlock(l, A.NewHorizontalRule()); B.pos := q;
    RETURN TRUE
  END;
  RETURN OrderedList(l) OR DefinitionList(l) OR NoteBlock()
    OR ReferenceKey() OR Para(l)
END Block;

(* Resolving *)

PROCEDURE HasClass(a: A.Attr; c: A.Rope): BOOLEAN;
  VAR p: A.StrList;
BEGIN
  p := a.classes;
  WHILE (p # NIL) & ~Ropes.Equal(p.s, c) DO p := p.next END;
  RETURN p # NIL
END HasClass;

(* combineAttr a b: a, with b's identifier if it has none, b's classes
   and b's attributes it lacks *)
PROCEDURE CombineAttr(a, b: A.Attr): A.Attr;
  VAR r: A.Attr; c: A.StrList; kv, k2: A.KeyVal; found: BOOLEAN;
BEGIN
  IF b = NIL THEN RETURN a END;
  r := A.NewAttr(a.id);
  IF r.id = NIL THEN r.id := b.id END;
  c := a.classes;
  WHILE c # NIL DO
    IF ~HasClass(r, c.s) THEN A.AddClass(r, c.s) END;
    c := c.next
  END;
  c := b.classes;
  WHILE c # NIL DO
    IF ~HasClass(r, c.s) THEN A.AddClass(r, c.s) END;
    c := c.next
  END;
  kv := b.attrs;
  WHILE kv # NIL DO
    found := FALSE;
    k2 := a.attrs;
    WHILE ~found & (k2 # NIL) DO found := Ropes.Equal(k2.key, kv.key); k2 := k2.next END;
    k2 := kv.next;
    WHILE ~found & (k2 # NIL) DO found := Ropes.Equal(k2.key, kv.key); k2 := k2.next END;
    IF ~found THEN A.AddKeyVal(r, kv.key, kv.value) END;
    kv := kv.next
  END;
  kv := a.attrs;
  WHILE kv # NIL DO A.AddKeyVal(r, kv.key, kv.value); kv := kv.next END;
  RETURN r
END CombineAttr;

PROCEDURE FindNote(ref: A.Rope): Note;
  VAR n: Note;
BEGIN
  n := notes;
  WHILE (n # NIL) & ~Ropes.Equal(n.ref, ref) DO n := n.next END;
  RETURN n
END FindNote;

(* A reference link or a note reference as what it refers to *)
PROCEDURE (r: Resolver) Inline*(i: A.Inline): A.Inline;
  VAR ri: I.RefInl; k: Key; n: Note; kind: INTEGER; b: B.Buf;
BEGIN
  IF i.kind = I.NoteRefKind THEN
    IF ~r.inNote THEN
      n := FindNote(i(I.NoteRefInl).ref);
      IF n # NIL THEN RETURN A.NewNote(n.blocks) END
    END;
    B.InitBuf(b); B.PutString(b, "[^");
    i := A.NewStr(Ropes.Cat(Ropes.Cat(B.BufRope(b), i(I.NoteRefInl).ref), A.S("]")))
  ELSIF i.kind = I.RefKind THEN
    ri := i(I.RefInl);
    IF ri.image THEN kind := A.Image ELSE kind := A.Link END;
    k := FindKey(keyTable, ri.key);
    IF k # NIL THEN
      i := A.NewLink(kind, CombineAttr(ri.attr, k.attr), ri.content, k.url, k.title)
    ELSE
      k := FindKey(headerTable, ri.key);
      IF k # NIL THEN
        i := A.NewLink(kind, ri.attr, ri.content, k.url, k.title)
      ELSE
        i := A.WalkInlines(r, ri.fallback)
      END
    END
  END;
  RETURN i
END Inline;

(* Plain, Para and Header trimmed again, as pandoc trims them after
   resolving; implicit figures *)
PROCEDURE (r: Resolver) Block*(b: A.Block): A.Block;
  VAR l: A.Inlines; fig: A.Block;
BEGIN
  IF (b.kind = A.Plain) OR (b.kind = A.Para) OR (b.kind = A.Header) THEN
    l.first := b(A.InlinesBlk).inlines; l.last := NIL;
    b(A.InlinesBlk).inlines := I.Trim(l);
    IF b.kind # A.Header THEN
      fig := Figure(b(A.InlinesBlk).inlines);
      IF fig # NIL THEN b := fig END
    END
  END;
  RETURN b
END Block;

(* blocksToInlines *)

PROCEDURE^ BlocksInlines(VAR l: A.Inlines; b: A.Block);

(* The inlines of the rows r, each row's after a line break *)
PROCEDURE RowsInlines(VAR l: A.Inlines; r: A.Row; VAR first: BOOLEAN);
  VAR c: A.Cell;
BEGIN
  WHILE r # NIL DO
    IF ~first THEN A.Append(l, A.NewSimple(A.LineBreak)) END;
    first := FALSE;
    c := r.cells;
    WHILE c # NIL DO BlocksInlines(l, c.blocks); c := c.next END;
    r := r.next
  END
END RowsInlines;

(* blockToInlines: the block b as inlines, appended to l *)
PROCEDURE BlockInlines(VAR l: A.Inlines; b: A.Block);
  VAR ln: A.InlineList; it: A.BlockList; d: A.DefItem; tb: A.TableBody;
    first: BOOLEAN;
BEGIN
  CASE b.kind OF
    A.Plain, A.Para, A.Header: A.Append(l, b(A.InlinesBlk).inlines)
  | A.LineBlock:
      ln := b(A.LineBlk).lines; first := TRUE;
      WHILE ln # NIL DO
        IF ~first THEN A.Append(l, A.NewSimple(A.LineBreak)) END;
        first := FALSE;
        A.Append(l, ln.inlines); ln := ln.next
      END
  | A.CodeBlock:
      A.Append(l, A.NewCode(b(A.CodeBlk).attr, b(A.CodeBlk).text))
  | A.RawBlock:
      A.Append(l, A.NewRawInline(b(A.RawBlk).format, b(A.RawBlk).text))
  | A.BlockQuote, A.Div, A.Figure: BlocksInlines(l, b(A.BlocksBlk).blocks)
  | A.OrderedList, A.BulletList:
      it := b(A.ListBlk).items;
      WHILE it # NIL DO BlocksInlines(l, it.blocks); it := it.next END
  | A.DefinitionList:
      d := b(A.DefListBlk).items;
      WHILE d # NIL DO
        A.Append(l, d.term);
        A.Append(l, A.NewStr(A.S(":"))); A.Append(l, A.NewSimple(A.Space));
        it := d.defs;
        WHILE it # NIL DO BlocksInlines(l, it.blocks); it := it.next END;
        d := d.next
      END
  | A.Table:
      first := TRUE;
      RowsInlines(l, b(A.TableBlk).head.rows, first);
      tb := b(A.TableBlk).bodies;
      WHILE tb # NIL DO
        RowsInlines(l, tb.head, first); RowsInlines(l, tb.body, first);
        tb := tb.next
      END;
      RowsInlines(l, b(A.TableBlk).foot.rows, first)
  ELSE (* HorizontalRule: nothing *)
  END
END BlockInlines;

(* blocksToInlines': the blocks b as inlines, a line break between
   each two, appended to l *)
PROCEDURE BlocksInlines(VAR l: A.Inlines; b: A.Block);
  VAR next: A.Block; first: BOOLEAN;
BEGIN
  first := TRUE;
  WHILE b # NIL DO
    next := b.next;
    IF ~first THEN A.Append(l, A.NewSimple(A.LineBreak)) END;
    first := FALSE;
    BlockInlines(l, b);
    b := next
  END
END BlocksInlines;

(* The metadata value v with its pending blocks made inlines *)
PROCEDURE Finish(v: A.MetaValue): A.MetaValue;
  VAR e: A.MetaEntry; it: A.MetaItem; l: A.Inlines;
BEGIN
  IF v = NIL THEN RETURN v END;
  WITH
    v: PendingV DO
      A.InitInlines(l); BlocksInlines(l, v.blocks);
      RETURN A.NewMetaInlines(l.first)
  | v: A.MetaMapV DO
      e := v.entries;
      WHILE e # NIL DO e.value := Finish(e.value); e := e.next END
  | v: A.MetaListV DO
      it := v.items;
      WHILE it # NIL DO it.value := Finish(it.value); it := it.next END
  ELSE
  END;
  RETURN v
END Finish;

(* Resolves the references in the blocks and metadata of d: notes
   first, then the rest *)
PROCEDURE Resolve(d: A.Doc);
  VAR r: Resolver; n: Note; old: BOOLEAN; v: A.MetaValue;
BEGIN
  old := A.mergeWalk; A.mergeWalk := TRUE;
  NEW(r); r.inNote := TRUE;
  n := notes;
  WHILE n # NIL DO n.blocks := A.WalkBlocks(r, n.blocks); n := n.next END;
  r.inNote := FALSE;
  d.blocks := A.WalkBlocks(r, d.blocks);
  A.WalkMetaValue(r, d.meta);
  A.mergeWalk := old;
  WHILE listItems # NIL DO
    TaskItem(listItems.item.blocks); listItems := listItems.next
  END;
  v := Finish(d.meta)
END Resolve;

(* Reading *)

(* Sets the reader's state up for a new text *)
PROCEDURE Reset;
BEGIN
  ids := NIL; keys := NIL; headerKeys := NIL; notes := NIL; listItems := NIL;
  idTable := NewTable(); suffixes := NIL; keyTable := NewTable(); headerTable := NewTable();
  I.Reset
END Reset;

(* The document in text[0 .. n-1], pandoc markdown; tabStop is used
   where tabs are kept. Places in messages are found with PdSource. *)
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
  main := B.t;
  Reset;
  d := A.NewDoc();
  meta := d.meta;
  IF titleBlock & (B.C(B.pos) = "%") THEN TitleBlock END;
  d.blocks := ParseBlocks();
  Resolve(d);
  keys := NIL; headerKeys := NIL; notes := NIL; meta := NIL; main := NIL;
  keyTable := NIL; headerTable := NIL;
  RETURN d
END Read;

(* yamlToMeta: the metadata in the YAML file name, its strings read as
   markdown, with tab stop tabStop, apart from any document. A file
   that cannot be read, is not YAML podoc reads, or is not a mapping
   ends podoc with a message. *)
PROCEDURE ReadMetaFile*(name: ARRAY OF CHAR; tabStop: INTEGER): A.MetaMapV;
  VAR t: PdIO.Text; len: LONGINT; doc: Y.Node; d: A.Doc; m: Message;
BEGIN
  PdIO.ReadFile(name, t, len);
  IF t = NIL THEN PdIO.Reserve(t, 0, 1) END;
  IF ~Y.Parse(t^, len, doc) THEN YamlError(name, 1) END;
  YamlWarnings(name, 1);
  d := A.NewDoc();
  IF IsNull(doc) THEN RETURN d.meta END;
  IF doc.kind # Y.Mapping THEN
    m := "Error at "; Cat(m, 22X); Cat(m, name); Cat(m, '" (line 1, column 1):');
    Cat(m, 0AX); Cat(m, "expected YAML object");
    PdIO.Fail("", m, PdIO.ParseError)
  END;
  B.Start(B.NewText(0), 0, tabStop);
  main := NIL;
  Reset;
  meta := d.meta;
  d.meta := MetaMapOf(doc);
  Resolve(d);
  keys := NIL; headerKeys := NIL; notes := NIL; meta := NIL;
  keyTable := NIL; headerTable := NIL;
  RETURN d.meta
END ReadMetaFile;

BEGIN
  ids := NIL; idTable := NewTable(); suffixes := NIL; gridTables := TRUE; titleBlock := TRUE; columns := 72
END PdMarkdown.
