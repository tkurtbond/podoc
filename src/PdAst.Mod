MODULE PdAst;
(* PdAst: pandoc's document tree (pandoc-types 1.23), in Oberon.

   A document is metadata and a list of blocks. Blocks and inlines are
   linked lists (next); an empty list is NIL. Every constructor of
   pandoc-types is here, with a kind constant named as pandoc names it,
   so that the JSON writer can print any tree pandoc can. Records of
   the same shape share a type: Emph, Strong and the like are all
   ContInl, Link and Image are both LinkInl.

   Text is held in Ropes; NIL is the empty string. An Attr of NIL is
   the empty attribute ("", [], []).

   A Walker visits every inline and block of a tree, bottom up, as
   pandoc's Lua filters do, and splices in what its methods return. *)

IMPORT Ropes;

CONST
  (* Block kinds *)
  Plain* = 1; Para* = 2; LineBlock* = 3; CodeBlock* = 4; RawBlock* = 5;
  BlockQuote* = 6; OrderedList* = 7; BulletList* = 8;
  DefinitionList* = 9; Header* = 10; HorizontalRule* = 11; Table* = 12;
  Figure* = 13; Div* = 14;

  (* Inline kinds *)
  Str* = 1; Emph* = 2; Underline* = 3; Strong* = 4; Strikeout* = 5;
  Superscript* = 6; Subscript* = 7; SmallCaps* = 8; Quoted* = 9;
  Cite* = 10; Code* = 11; Space* = 12; SoftBreak* = 13; LineBreak* = 14;
  Math* = 15; RawInline* = 16; Link* = 17; Image* = 18; Note* = 19;
  Span* = 20;

  (* QuoteType *)
  SingleQuote* = 0; DoubleQuote* = 1;

  (* MathType *)
  InlineMath* = 0; DisplayMath* = 1;

  (* ListNumberStyle *)
  DefaultStyle* = 0; Example* = 1; Decimal* = 2; LowerRoman* = 3;
  UpperRoman* = 4; LowerAlpha* = 5; UpperAlpha* = 6;

  (* ListNumberDelim *)
  DefaultDelim* = 0; Period* = 1; OneParen* = 2; TwoParens* = 3;

  (* Alignment *)
  AlignLeft* = 0; AlignRight* = 1; AlignCenter* = 2; AlignDefault* = 3;

  (* CitationMode *)
  AuthorInText* = 0; SuppressAuthor* = 1; NormalCitation* = 2;

  (* MetaValue kinds *)
  MetaMap* = 1; MetaList* = 2; MetaBool* = 3; MetaString* = 4;
  MetaInlines* = 5; MetaBlocks* = 6;

TYPE
  Rope* = Ropes.Rope;

  (* Attributes *)

  StrList* = POINTER TO StrListDesc;
  StrListDesc* = RECORD
    s*: Rope;
    next*: StrList
  END;

  KeyVal* = POINTER TO KeyValDesc;
  KeyValDesc* = RECORD
    key*, value*: Rope;
    next*: KeyVal
  END;

  Attr* = POINTER TO AttrDesc;
  AttrDesc* = RECORD
    id*: Rope;
    classes*: StrList;
    attrs*: KeyVal
  END;

  (* Inlines *)

  Inline* = POINTER TO InlineDesc;
  InlineDesc* = RECORD
    kind*: INTEGER;
    next*: Inline
  END;
  (* Space, SoftBreak and LineBreak are plain Inlines. *)

  (* Str *)
  StrInl* = POINTER TO StrInlDesc;
  StrInlDesc* = RECORD (InlineDesc)
    text*: Rope
  END;

  (* Emph, Underline, Strong, Strikeout, Superscript, Subscript,
     SmallCaps; and the base of Quoted, Cite, Link, Image and Span *)
  ContInl* = POINTER TO ContInlDesc;
  ContInlDesc* = RECORD (InlineDesc)
    content*: Inline
  END;

  QuotedInl* = POINTER TO QuotedInlDesc;
  QuotedInlDesc* = RECORD (ContInlDesc)
    quote*: INTEGER (* SingleQuote, DoubleQuote *)
  END;

  Citation* = POINTER TO CitationDesc;
  CitationDesc* = RECORD
    id*: Rope;
    prefix*, suffix*: Inline;
    mode*: INTEGER; (* AuthorInText, SuppressAuthor, NormalCitation *)
    noteNum*, hash*: LONGINT;
    next*: Citation
  END;

  CiteInl* = POINTER TO CiteInlDesc;
  CiteInlDesc* = RECORD (ContInlDesc)
    citations*: Citation
  END;

  (* Link and Image: content is the link text or the image's
     description *)
  LinkInl* = POINTER TO LinkInlDesc;
  LinkInlDesc* = RECORD (ContInlDesc)
    attr*: Attr;
    url*, title*: Rope
  END;

  SpanInl* = POINTER TO SpanInlDesc;
  SpanInlDesc* = RECORD (ContInlDesc)
    attr*: Attr
  END;

  CodeInl* = POINTER TO CodeInlDesc;
  CodeInlDesc* = RECORD (InlineDesc)
    attr*: Attr;
    text*: Rope
  END;

  MathInl* = POINTER TO MathInlDesc;
  MathInlDesc* = RECORD (InlineDesc)
    math*: INTEGER; (* InlineMath, DisplayMath *)
    text*: Rope
  END;

  RawInl* = POINTER TO RawInlDesc;
  RawInlDesc* = RECORD (InlineDesc)
    format*, text*: Rope
  END;

  Block* = POINTER TO BlockDesc;

  NoteInl* = POINTER TO NoteInlDesc;
  NoteInlDesc* = RECORD (InlineDesc)
    blocks*: Block
  END;

  (* Lists of lists *)

  (* [[Inline]]: the lines of a LineBlock *)
  InlineList* = POINTER TO InlineListDesc;
  InlineListDesc* = RECORD
    inlines*: Inline;
    next*: InlineList
  END;

  (* [[Block]]: the items of a list, the definitions of a term *)
  BlockList* = POINTER TO BlockListDesc;
  BlockListDesc* = RECORD
    blocks*: Block;
    next*: BlockList
  END;

  (* Blocks *)

  BlockDesc* = RECORD
    kind*: INTEGER;
    next*: Block
  END;
  (* HorizontalRule is a plain Block. *)

  (* Plain and Para; the base of Header *)
  InlinesBlk* = POINTER TO InlinesBlkDesc;
  InlinesBlkDesc* = RECORD (BlockDesc)
    inlines*: Inline
  END;

  HeaderBlk* = POINTER TO HeaderBlkDesc;
  HeaderBlkDesc* = RECORD (InlinesBlkDesc)
    level*: INTEGER;
    attr*: Attr
  END;

  LineBlk* = POINTER TO LineBlkDesc;
  LineBlkDesc* = RECORD (BlockDesc)
    lines*: InlineList
  END;

  CodeBlk* = POINTER TO CodeBlkDesc;
  CodeBlkDesc* = RECORD (BlockDesc)
    attr*: Attr;
    text*: Rope
  END;

  RawBlk* = POINTER TO RawBlkDesc;
  RawBlkDesc* = RECORD (BlockDesc)
    format*, text*: Rope
  END;

  (* BlockQuote; the base of Div and Figure *)
  BlocksBlk* = POINTER TO BlocksBlkDesc;
  BlocksBlkDesc* = RECORD (BlockDesc)
    blocks*: Block
  END;

  DivBlk* = POINTER TO DivBlkDesc;
  DivBlkDesc* = RECORD (BlocksBlkDesc)
    attr*: Attr
  END;

  (* A caption: an optional short caption (hasShort) and blocks *)
  Caption* = RECORD
    hasShort*: BOOLEAN;
    short*: Inline;
    blocks*: Block
  END;

  FigureBlk* = POINTER TO FigureBlkDesc;
  FigureBlkDesc* = RECORD (BlocksBlkDesc)
    attr*: Attr;
    caption*: Caption
  END;

  (* BulletList; the base of OrderedList *)
  ListBlk* = POINTER TO ListBlkDesc;
  ListBlkDesc* = RECORD (BlockDesc)
    items*: BlockList
  END;

  OrderedBlk* = POINTER TO OrderedBlkDesc;
  OrderedBlkDesc* = RECORD (ListBlkDesc)
    start*: LONGINT;
    style*, delim*: INTEGER
  END;

  DefItem* = POINTER TO DefItemDesc;
  DefItemDesc* = RECORD
    term*: Inline;
    defs*: BlockList;
    next*: DefItem
  END;

  DefListBlk* = POINTER TO DefListBlkDesc;
  DefListBlkDesc* = RECORD (BlockDesc)
    items*: DefItem
  END;

  (* Tables *)

  ColSpec* = POINTER TO ColSpecDesc;
  ColSpecDesc* = RECORD
    align*: INTEGER;
    hasWidth*: BOOLEAN; (* FALSE: ColWidthDefault *)
    width*: LONGREAL;
    next*: ColSpec
  END;

  Cell* = POINTER TO CellDesc;
  CellDesc* = RECORD
    attr*: Attr;
    align*: INTEGER;
    rowSpan*, colSpan*: LONGINT;
    blocks*: Block;
    next*: Cell
  END;

  Row* = POINTER TO RowDesc;
  RowDesc* = RECORD
    attr*: Attr;
    cells*: Cell;
    next*: Row
  END;

  (* TableHead and TableFoot *)
  TablePart* = RECORD
    attr*: Attr;
    rows*: Row
  END;

  TableBody* = POINTER TO TableBodyDesc;
  TableBodyDesc* = RECORD
    attr*: Attr;
    rowHeadColumns*: LONGINT;
    head*, body*: Row;
    next*: TableBody
  END;

  TableBlk* = POINTER TO TableBlkDesc;
  TableBlkDesc* = RECORD (BlockDesc)
    attr*: Attr;
    caption*: Caption;
    colSpecs*: ColSpec;
    head*: TablePart;
    bodies*: TableBody;
    foot*: TablePart
  END;

  (* Metadata *)

  MetaValue* = POINTER TO MetaValueDesc;
  MetaValueDesc* = RECORD
    kind*: INTEGER
  END;

  MetaEntry* = POINTER TO MetaEntryDesc;
  MetaEntryDesc* = RECORD
    key*: Rope;
    value*: MetaValue;
    next*: MetaEntry
  END;

  (* A map, its entries kept in pandoc's order: by key, byte by byte *)
  MetaMapV* = POINTER TO MetaMapVDesc;
  MetaMapVDesc* = RECORD (MetaValueDesc)
    entries*: MetaEntry
  END;

  MetaItem* = POINTER TO MetaItemDesc;
  MetaItemDesc* = RECORD
    value*: MetaValue;
    next*: MetaItem
  END;

  MetaListV* = POINTER TO MetaListVDesc;
  MetaListVDesc* = RECORD (MetaValueDesc)
    items*: MetaItem
  END;

  MetaBoolV* = POINTER TO MetaBoolVDesc;
  MetaBoolVDesc* = RECORD (MetaValueDesc)
    b*: BOOLEAN
  END;

  MetaStringV* = POINTER TO MetaStringVDesc;
  MetaStringVDesc* = RECORD (MetaValueDesc)
    s*: Rope
  END;

  MetaInlinesV* = POINTER TO MetaInlinesVDesc;
  MetaInlinesVDesc* = RECORD (MetaValueDesc)
    inlines*: Inline
  END;

  MetaBlocksV* = POINTER TO MetaBlocksVDesc;
  MetaBlocksVDesc* = RECORD (MetaValueDesc)
    blocks*: Block
  END;

  (* The document *)

  Doc* = POINTER TO DocDesc;
  DocDesc* = RECORD
    meta*: MetaMapV;
    blocks*: Block
  END;

  (* Building lists: first and last of a list, appended to in O(1) *)

  Inlines* = RECORD
    first*, last*: Inline
  END;

  Blocks* = RECORD
    first*, last*: Block
  END;

  (* A walk over a tree. Inline and Block are called for each inline and
     block, after their contents have been walked, with the element
     taken out of its list (next = NIL); what they return, a list,
     possibly empty (NIL), takes its place. Both return what they are
     given by default. *)
  Walker* = POINTER TO WalkerDesc;
  WalkerDesc* = RECORD END;

VAR
  doInlines, doBlocks: BOOLEAN; (* which methods the walk calls now *)
  (* Whether WalkInlines joins what the walker returns with Append, as
     pandoc's Inlines monoid joins inlines, rather than AddInline *)
  mergeWalk*: BOOLEAN;

(* Strings *)

(* The rope of the string s. *)
PROCEDURE S*(s: ARRAY OF CHAR): Rope;
BEGIN
  RETURN Ropes.FromString(s)
END S;

(* Attributes *)

(* A new attribute with the identifier id and no classes or pairs. *)
PROCEDURE NewAttr*(id: Rope): Attr;
  VAR a: Attr;
BEGIN
  NEW(a); a.id := id; a.classes := NIL; a.attrs := NIL;
  RETURN a
END NewAttr;

(* Adds the class c at the end of a's classes. *)
PROCEDURE AddClass*(a: Attr; c: Rope);
  VAR n, p: StrList;
BEGIN
  NEW(n); n.s := c; n.next := NIL;
  IF a.classes = NIL THEN a.classes := n
  ELSE p := a.classes; WHILE p.next # NIL DO p := p.next END; p.next := n
  END
END AddClass;

(* Adds the pair key=value at the end of a's pairs. *)
PROCEDURE AddKeyVal*(a: Attr; key, value: Rope);
  VAR n, p: KeyVal;
BEGIN
  NEW(n); n.key := key; n.value := value; n.next := NIL;
  IF a.attrs = NIL THEN a.attrs := n
  ELSE p := a.attrs; WHILE p.next # NIL DO p := p.next END; p.next := n
  END
END AddKeyVal;

(* Whether a is the empty attribute. *)
PROCEDURE IsEmptyAttr*(a: Attr): BOOLEAN;
BEGIN
  RETURN (a = NIL) OR (Ropes.IsEmpty(a.id) & (a.classes = NIL) & (a.attrs = NIL))
END IsEmptyAttr;

(* Whether a has the class c. *)
PROCEDURE HasClass*(a: Attr; c: ARRAY OF CHAR): BOOLEAN;
  VAR p: StrList;
BEGIN
  IF a = NIL THEN RETURN FALSE END;
  p := a.classes;
  WHILE (p # NIL) & ~Ropes.EqualString(p.s, c) DO p := p.next END;
  RETURN p # NIL
END HasClass;

(* The value of a's pair key, or NIL; found is whether there is one. *)
PROCEDURE GetKeyVal*(a: Attr; key: ARRAY OF CHAR; VAR found: BOOLEAN): Rope;
  VAR p: KeyVal;
BEGIN
  found := FALSE;
  IF a = NIL THEN RETURN NIL END;
  p := a.attrs;
  WHILE (p # NIL) & ~Ropes.EqualString(p.key, key) DO p := p.next END;
  IF p = NIL THEN RETURN NIL END;
  found := TRUE;
  RETURN p.value
END GetKeyVal;

(* Inlines *)

(* A Str of text. *)
PROCEDURE NewStr*(text: Rope): Inline;
  VAR i: StrInl;
BEGIN
  NEW(i); i.kind := Str; i.next := NIL; i.text := text;
  RETURN i
END NewStr;

(* A Space, SoftBreak or LineBreak, by kind. *)
PROCEDURE NewSimple*(kind: INTEGER): Inline;
  VAR i: Inline;
BEGIN
  ASSERT((kind = Space) OR (kind = SoftBreak) OR (kind = LineBreak));
  NEW(i); i.kind := kind; i.next := NIL;
  RETURN i
END NewSimple;

(* An Emph, Underline, Strong, Strikeout, Superscript, Subscript or
   SmallCaps, by kind, of content. *)
PROCEDURE NewCont*(kind: INTEGER; content: Inline): Inline;
  VAR i: ContInl;
BEGIN
  ASSERT((kind >= Emph) & (kind <= SmallCaps));
  NEW(i); i.kind := kind; i.next := NIL; i.content := content;
  RETURN i
END NewCont;

(* A Quoted: quote is SingleQuote or DoubleQuote. *)
PROCEDURE NewQuoted*(quote: INTEGER; content: Inline): Inline;
  VAR i: QuotedInl;
BEGIN
  NEW(i); i.kind := Quoted; i.next := NIL; i.quote := quote;
  i.content := content;
  RETURN i
END NewQuoted;

(* A Citation of id, with no prefix or suffix. *)
PROCEDURE NewCitation*(id: Rope; mode: INTEGER; noteNum: LONGINT): Citation;
  VAR c: Citation;
BEGIN
  NEW(c); c.id := id; c.prefix := NIL; c.suffix := NIL; c.mode := mode;
  c.noteNum := noteNum; c.hash := 0; c.next := NIL;
  RETURN c
END NewCitation;

(* A Cite of the citations, written as content. *)
PROCEDURE NewCite*(citations: Citation; content: Inline): Inline;
  VAR i: CiteInl;
BEGIN
  NEW(i); i.kind := Cite; i.next := NIL; i.citations := citations;
  i.content := content;
  RETURN i
END NewCite;

(* A Code of text. *)
PROCEDURE NewCode*(attr: Attr; text: Rope): Inline;
  VAR i: CodeInl;
BEGIN
  NEW(i); i.kind := Code; i.next := NIL; i.attr := attr; i.text := text;
  RETURN i
END NewCode;

(* A Math: math is InlineMath or DisplayMath. *)
PROCEDURE NewMath*(math: INTEGER; text: Rope): Inline;
  VAR i: MathInl;
BEGIN
  NEW(i); i.kind := Math; i.next := NIL; i.math := math; i.text := text;
  RETURN i
END NewMath;

(* A RawInline of text in format. *)
PROCEDURE NewRawInline*(format, text: Rope): Inline;
  VAR i: RawInl;
BEGIN
  NEW(i); i.kind := RawInline; i.next := NIL; i.format := format;
  i.text := text;
  RETURN i
END NewRawInline;

(* A Link or Image, by kind. *)
PROCEDURE NewLink*(kind: INTEGER; attr: Attr; content: Inline; url, title: Rope): Inline;
  VAR i: LinkInl;
BEGIN
  ASSERT((kind = Link) OR (kind = Image));
  NEW(i); i.kind := kind; i.next := NIL; i.attr := attr;
  i.content := content; i.url := url; i.title := title;
  RETURN i
END NewLink;

(* A Note of blocks. *)
PROCEDURE NewNote*(blocks: Block): Inline;
  VAR i: NoteInl;
BEGIN
  NEW(i); i.kind := Note; i.next := NIL; i.blocks := blocks;
  RETURN i
END NewNote;

(* A Span of content. *)
PROCEDURE NewSpan*(attr: Attr; content: Inline): Inline;
  VAR i: SpanInl;
BEGIN
  NEW(i); i.kind := Span; i.next := NIL; i.attr := attr;
  i.content := content;
  RETURN i
END NewSpan;

(* Blocks *)

(* A Plain or Para, by kind. *)
PROCEDURE NewInlinesBlock*(kind: INTEGER; inlines: Inline): Block;
  VAR b: InlinesBlk;
BEGIN
  ASSERT((kind = Plain) OR (kind = Para));
  NEW(b); b.kind := kind; b.next := NIL; b.inlines := inlines;
  RETURN b
END NewInlinesBlock;

(* A Header of the level. *)
PROCEDURE NewHeader*(level: INTEGER; attr: Attr; inlines: Inline): Block;
  VAR b: HeaderBlk;
BEGIN
  NEW(b); b.kind := Header; b.next := NIL; b.level := level;
  b.attr := attr; b.inlines := inlines;
  RETURN b
END NewHeader;

(* A LineBlock of lines. *)
PROCEDURE NewLineBlock*(lines: InlineList): Block;
  VAR b: LineBlk;
BEGIN
  NEW(b); b.kind := LineBlock; b.next := NIL; b.lines := lines;
  RETURN b
END NewLineBlock;

(* A CodeBlock of text. *)
PROCEDURE NewCodeBlock*(attr: Attr; text: Rope): Block;
  VAR b: CodeBlk;
BEGIN
  NEW(b); b.kind := CodeBlock; b.next := NIL; b.attr := attr;
  b.text := text;
  RETURN b
END NewCodeBlock;

(* A RawBlock of text in format. *)
PROCEDURE NewRawBlock*(format, text: Rope): Block;
  VAR b: RawBlk;
BEGIN
  NEW(b); b.kind := RawBlock; b.next := NIL; b.format := format;
  b.text := text;
  RETURN b
END NewRawBlock;

(* A BlockQuote of blocks. *)
PROCEDURE NewBlockQuote*(blocks: Block): Block;
  VAR b: BlocksBlk;
BEGIN
  NEW(b); b.kind := BlockQuote; b.next := NIL; b.blocks := blocks;
  RETURN b
END NewBlockQuote;

(* A Div of blocks. *)
PROCEDURE NewDiv*(attr: Attr; blocks: Block): Block;
  VAR b: DivBlk;
BEGIN
  NEW(b); b.kind := Div; b.next := NIL; b.attr := attr; b.blocks := blocks;
  RETURN b
END NewDiv;

(* A Figure of blocks, with the caption of blocks and no short caption. *)
PROCEDURE NewFigure*(attr: Attr; caption, blocks: Block): Block;
  VAR b: FigureBlk;
BEGIN
  NEW(b); b.kind := Figure; b.next := NIL; b.attr := attr;
  b.caption.hasShort := FALSE; b.caption.short := NIL;
  b.caption.blocks := caption; b.blocks := blocks;
  RETURN b
END NewFigure;

(* A BulletList of items. *)
PROCEDURE NewBulletList*(items: BlockList): Block;
  VAR b: ListBlk;
BEGIN
  NEW(b); b.kind := BulletList; b.next := NIL; b.items := items;
  RETURN b
END NewBulletList;

(* An OrderedList of items. *)
PROCEDURE NewOrderedList*(start: LONGINT; style, delim: INTEGER; items: BlockList): Block;
  VAR b: OrderedBlk;
BEGIN
  NEW(b); b.kind := OrderedList; b.next := NIL; b.start := start;
  b.style := style; b.delim := delim; b.items := items;
  RETURN b
END NewOrderedList;

(* A DefinitionList of items. *)
PROCEDURE NewDefinitionList*(items: DefItem): Block;
  VAR b: DefListBlk;
BEGIN
  NEW(b); b.kind := DefinitionList; b.next := NIL; b.items := items;
  RETURN b
END NewDefinitionList;

(* A HorizontalRule. *)
PROCEDURE NewHorizontalRule*(): Block;
  VAR b: Block;
BEGIN
  NEW(b); b.kind := HorizontalRule; b.next := NIL;
  RETURN b
END NewHorizontalRule;

(* An empty Table, to be filled in by its builder. *)
PROCEDURE NewTable*(attr: Attr): TableBlk;
  VAR b: TableBlk;
BEGIN
  NEW(b); b.kind := Table; b.next := NIL; b.attr := attr;
  b.caption.hasShort := FALSE; b.caption.short := NIL;
  b.caption.blocks := NIL; b.colSpecs := NIL;
  b.head.attr := NIL; b.head.rows := NIL; b.bodies := NIL;
  b.foot.attr := NIL; b.foot.rows := NIL;
  RETURN b
END NewTable;

(* Lists *)

(* The last element of the non-empty list i. *)
PROCEDURE LastInline*(i: Inline): Inline;
BEGIN
  WHILE i.next # NIL DO i := i.next END;
  RETURN i
END LastInline;

(* The last element of the non-empty list b. *)
PROCEDURE LastBlock*(b: Block): Block;
BEGIN
  WHILE b.next # NIL DO b := b.next END;
  RETURN b
END LastBlock;

(* Empties l. *)
PROCEDURE InitInlines*(VAR l: Inlines);
BEGIN
  l.first := NIL; l.last := NIL
END InitInlines;

(* Appends i, an inline or a list of them, to l. *)
PROCEDURE AddInline*(VAR l: Inlines; i: Inline);
BEGIN
  IF i # NIL THEN
    IF l.first = NIL THEN l.first := i ELSE l.last.next := i END;
    l.last := LastInline(i)
  END
END AddInline;

PROCEDURE IsBreak(k: INTEGER): BOOLEAN;
BEGIN
  RETURN (k = Space) OR (k = SoftBreak) OR (k = LineBreak)
END IsBreak;

PROCEDURE Mergeable(k: INTEGER): BOOLEAN;
BEGIN
  RETURN (k = Emph) OR (k = Underline) OR (k = Strong)
    OR (k = Subscript) OR (k = Superscript) OR (k = Strikeout)
END Mergeable;

(* Appends the list i to l, the last of l and the first of i joined as
   pandoc-types' Inlines monoid joins them: two Strs become one, two
   spaces or breaks one (the stronger), and two emphases of one kind
   one, their contents joined likewise. *)
PROCEDURE Append*(VAR l: Inlines; i: Inline);
  VAR x, y, rest: Inline;
BEGIN
  IF i = NIL THEN RETURN END;
  IF l.last = NIL THEN AddInline(l, i); RETURN END;
  x := l.last; rest := i.next;
  IF IsBreak(x.kind) & IsBreak(i.kind) THEN
    IF (x.kind = LineBreak) & (i.kind = LineBreak) THEN
      AddInline(l, i); RETURN
    ELSIF (x.kind = LineBreak) OR (i.kind = LineBreak) THEN
      x.kind := LineBreak
    ELSIF (x.kind = SoftBreak) OR (i.kind = SoftBreak) THEN
      x.kind := SoftBreak
    END
  ELSIF (x.kind = Str) & (i.kind = Str) THEN
    x(StrInl).text := Ropes.Cat(x(StrInl).text, i(StrInl).text)
  ELSIF (x.kind = i.kind) & Mergeable(x.kind) THEN
    (* the contents are concatenated as lists, not melded: pandoc-types'
       Emph i1 <> Emph i2 is Emph (i1 ++ i2) *)
    IF x(ContInl).content = NIL THEN
      x(ContInl).content := i(ContInl).content
    ELSE
      y := LastInline(x(ContInl).content); y.next := i(ContInl).content
    END
  ELSE
    AddInline(l, i); RETURN
  END;
  IF rest # NIL THEN AddInline(l, rest) END
END Append;

(* A copy of the list of inlines i and of the inlines in them. The
   blocks of notes and the citations of cites are shared, not copied;
   an inline of a type declared outside PdAst is copied as its base. *)
PROCEDURE CopyInlines*(i: Inline): Inline;
  VAR l: Inlines; n: Inline; s: StrInl; q: QuotedInl; ci: CiteInl;
    lk: LinkInl; sp: SpanInl; c: ContInl; cd: CodeInl; m: MathInl;
    r: RawInl; nt: NoteInl; x: Inline;
BEGIN
  InitInlines(l);
  WHILE i # NIL DO
    WITH
      i: StrInl DO NEW(s); s^ := i^; n := s
    | i: QuotedInl DO NEW(q); q^ := i^; n := q
    | i: CiteInl DO NEW(ci); ci^ := i^; n := ci
    | i: LinkInl DO NEW(lk); lk^ := i^; n := lk
    | i: SpanInl DO NEW(sp); sp^ := i^; n := sp
    | i: ContInl DO NEW(c); c.kind := i.kind; c.content := i.content; n := c
    | i: CodeInl DO NEW(cd); cd^ := i^; n := cd
    | i: MathInl DO NEW(m); m^ := i^; n := m
    | i: RawInl DO NEW(r); r^ := i^; n := r
    | i: NoteInl DO NEW(nt); nt^ := i^; n := nt
    ELSE NEW(x); x.kind := i.kind; n := x
    END;
    IF n IS ContInl THEN n(ContInl).content := CopyInlines(n(ContInl).content) END;
    n.next := NIL;
    AddInline(l, n);
    i := i.next
  END;
  RETURN l.first
END CopyInlines;

(* Empties l. *)
PROCEDURE InitBlocks*(VAR l: Blocks);
BEGIN
  l.first := NIL; l.last := NIL
END InitBlocks;

(* Appends b, a block or a list of them, to l. *)
PROCEDURE AddBlock*(VAR l: Blocks; b: Block);
BEGIN
  IF b # NIL THEN
    IF l.first = NIL THEN l.first := b ELSE l.last.next := b END;
    l.last := LastBlock(b)
  END
END AddBlock;

(* Metadata *)

(* A new, empty map. *)
PROCEDURE NewMetaMap*(): MetaMapV;
  VAR m: MetaMapV;
BEGIN
  NEW(m); m.kind := MetaMap; m.entries := NIL;
  RETURN m
END NewMetaMap;

(* A new, empty list. *)
PROCEDURE NewMetaList*(): MetaListV;
  VAR l: MetaListV;
BEGIN
  NEW(l); l.kind := MetaList; l.items := NIL;
  RETURN l
END NewMetaList;

(* Appends v to the list l. *)
PROCEDURE AddMetaItem*(l: MetaListV; v: MetaValue);
  VAR n, p: MetaItem;
BEGIN
  NEW(n); n.value := v; n.next := NIL;
  IF l.items = NIL THEN l.items := n
  ELSE p := l.items; WHILE p.next # NIL DO p := p.next END; p.next := n
  END
END AddMetaItem;

(* A MetaBool. *)
PROCEDURE NewMetaBool*(b: BOOLEAN): MetaValue;
  VAR v: MetaBoolV;
BEGIN
  NEW(v); v.kind := MetaBool; v.b := b;
  RETURN v
END NewMetaBool;

(* A MetaString. *)
PROCEDURE NewMetaString*(s: Rope): MetaValue;
  VAR v: MetaStringV;
BEGIN
  NEW(v); v.kind := MetaString; v.s := s;
  RETURN v
END NewMetaString;

(* A MetaInlines. *)
PROCEDURE NewMetaInlines*(inlines: Inline): MetaValue;
  VAR v: MetaInlinesV;
BEGIN
  NEW(v); v.kind := MetaInlines; v.inlines := inlines;
  RETURN v
END NewMetaInlines;

(* A MetaBlocks. *)
PROCEDURE NewMetaBlocks*(blocks: Block): MetaValue;
  VAR v: MetaBlocksV;
BEGIN
  NEW(v); v.kind := MetaBlocks; v.blocks := blocks;
  RETURN v
END NewMetaBlocks;

(* Sets the map m's key to v, in key order, replacing any value it
   had. *)
PROCEDURE SetMeta*(m: MetaMapV; key: Rope; v: MetaValue);
  VAR p, prev, n: MetaEntry; c: INTEGER;
BEGIN
  prev := NIL; p := m.entries; c := 1;
  WHILE p # NIL DO
    c := Ropes.Compare(p.key, key);
    IF c >= 0 THEN
      IF c = 0 THEN p.value := v; RETURN END;
      p := NIL
    ELSE
      prev := p; p := p.next
    END
  END;
  NEW(n); n.key := key; n.value := v;
  IF prev = NIL THEN n.next := m.entries; m.entries := n
  ELSE n.next := prev.next; prev.next := n
  END
END SetMeta;

(* The value of the map m's key, or NIL. *)
PROCEDURE GetMeta*(m: MetaMapV; key: ARRAY OF CHAR): MetaValue;
  VAR p: MetaEntry;
BEGIN
  p := m.entries;
  WHILE (p # NIL) & ~Ropes.EqualString(p.key, key) DO p := p.next END;
  IF p = NIL THEN RETURN NIL END;
  RETURN p.value
END GetMeta;

(* Removes the map m's key, if it is there. *)
PROCEDURE DeleteMeta*(m: MetaMapV; key: ARRAY OF CHAR);
  VAR p, prev: MetaEntry;
BEGIN
  prev := NIL; p := m.entries;
  WHILE (p # NIL) & ~Ropes.EqualString(p.key, key) DO prev := p; p := p.next END;
  IF p # NIL THEN
    IF prev = NIL THEN m.entries := p.next ELSE prev.next := p.next END
  END
END DeleteMeta;

(* A new document with no metadata and no blocks. *)
PROCEDURE NewDoc*(): Doc;
  VAR d: Doc;
BEGIN
  NEW(d); d.meta := NewMetaMap(); d.blocks := NIL;
  RETURN d
END NewDoc;

(* Walking *)

(* Called for each inline; returns what takes its place. *)
PROCEDURE (w: Walker) Inline*(i: Inline): Inline;
BEGIN
  RETURN i
END Inline;

(* Called for each block; returns what takes its place. *)
PROCEDURE (w: Walker) Block*(b: Block): Block;
BEGIN
  RETURN b
END Block;

PROCEDURE^ WalkInlines*(w: Walker; list: Inline): Inline;
PROCEDURE^ WalkBlocks*(w: Walker; list: Block): Block;

PROCEDURE WalkBlockList(w: Walker; l: BlockList);
BEGIN
  WHILE l # NIL DO l.blocks := WalkBlocks(w, l.blocks); l := l.next END
END WalkBlockList;

PROCEDURE WalkCaption(w: Walker; VAR c: Caption);
BEGIN
  c.short := WalkInlines(w, c.short);
  c.blocks := WalkBlocks(w, c.blocks)
END WalkCaption;

PROCEDURE WalkRows(w: Walker; r: Row);
  VAR c: Cell;
BEGIN
  WHILE r # NIL DO
    c := r.cells;
    WHILE c # NIL DO c.blocks := WalkBlocks(w, c.blocks); c := c.next END;
    r := r.next
  END
END WalkRows;

(* Walks what i holds. *)
PROCEDURE WalkInlineContents(w: Walker; i: Inline);
  VAR c: Citation;
BEGIN
  IF i IS ContInl THEN
    IF i IS CiteInl THEN
      c := i(CiteInl).citations;
      WHILE c # NIL DO
        c.prefix := WalkInlines(w, c.prefix);
        c.suffix := WalkInlines(w, c.suffix);
        c := c.next
      END
    END;
    i(ContInl).content := WalkInlines(w, i(ContInl).content)
  ELSIF i IS NoteInl THEN
    i(NoteInl).blocks := WalkBlocks(w, i(NoteInl).blocks)
  END
END WalkInlineContents;

(* Walks the list of inlines with w; returns the new list. *)
PROCEDURE WalkInlines*(w: Walker; list: Inline): Inline;
  VAR l: Inlines; i, next: Inline;
BEGIN
  InitInlines(l);
  i := list;
  WHILE i # NIL DO
    next := i.next; i.next := NIL;
    WalkInlineContents(w, i);
    IF doInlines THEN i := w.Inline(i) END;
    IF mergeWalk THEN Append(l, i) ELSE AddInline(l, i) END;
    i := next
  END;
  RETURN l.first
END WalkInlines;

(* Walks what b holds. *)
PROCEDURE WalkBlockContents(w: Walker; b: Block);
  VAR il: InlineList; d: DefItem; t: TableBlk; tb: TableBody;
BEGIN
  WITH
    b: InlinesBlk DO b.inlines := WalkInlines(w, b.inlines)
  | b: LineBlk DO
      il := b.lines;
      WHILE il # NIL DO il.inlines := WalkInlines(w, il.inlines); il := il.next END
  | b: FigureBlk DO
      WalkCaption(w, b.caption);
      b.blocks := WalkBlocks(w, b.blocks)
  | b: BlocksBlk DO b.blocks := WalkBlocks(w, b.blocks)
  | b: ListBlk DO WalkBlockList(w, b.items)
  | b: DefListBlk DO
      d := b.items;
      WHILE d # NIL DO
        d.term := WalkInlines(w, d.term);
        WalkBlockList(w, d.defs);
        d := d.next
      END
  | b: TableBlk DO
      t := b;
      WalkCaption(w, t.caption);
      WalkRows(w, t.head.rows);
      tb := t.bodies;
      WHILE tb # NIL DO WalkRows(w, tb.head); WalkRows(w, tb.body); tb := tb.next END;
      WalkRows(w, t.foot.rows)
  ELSE (* CodeBlock, RawBlock, HorizontalRule: nothing inside *)
  END
END WalkBlockContents;

(* Walks the list of blocks with w; returns the new list. *)
PROCEDURE WalkBlocks*(w: Walker; list: Block): Block;
  VAR l: Blocks; b, next: Block;
BEGIN
  InitBlocks(l);
  b := list;
  WHILE b # NIL DO
    next := b.next; b.next := NIL;
    WalkBlockContents(w, b);
    IF doBlocks THEN AddBlock(l, w.Block(b)) ELSE AddBlock(l, b) END;
    b := next
  END;
  RETURN l.first
END WalkBlocks;

(* Walks the inlines and blocks in the metadata value v. *)
PROCEDURE WalkMetaValue*(w: Walker; v: MetaValue);
  VAR e: MetaEntry; it: MetaItem;
BEGIN
  WITH
    v: MetaMapV DO
      e := v.entries;
      WHILE e # NIL DO WalkMetaValue(w, e.value); e := e.next END
  | v: MetaListV DO
      it := v.items;
      WHILE it # NIL DO WalkMetaValue(w, it.value); it := it.next END
  | v: MetaInlinesV DO v.inlines := WalkInlines(w, v.inlines)
  | v: MetaBlocksV DO v.blocks := WalkBlocks(w, v.blocks)
  ELSE
  END
END WalkMetaValue;

(* Walks the document d as pandoc runs a Lua filter: first every inline,
   in the metadata and then the blocks, with w.Inline; then every block,
   likewise, with w.Block. *)
PROCEDURE WalkDoc*(w: Walker; d: Doc);
BEGIN
  doInlines := TRUE; doBlocks := FALSE;
  WalkMetaValue(w, d.meta);
  d.blocks := WalkBlocks(w, d.blocks);
  doInlines := FALSE; doBlocks := TRUE;
  WalkMetaValue(w, d.meta);
  d.blocks := WalkBlocks(w, d.blocks);
  doInlines := TRUE; doBlocks := TRUE
END WalkDoc;

BEGIN
  doInlines := TRUE; doBlocks := TRUE; mergeWalk := FALSE
END PdAst.
