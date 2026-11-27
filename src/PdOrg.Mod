MODULE PdOrg;

(* The Org reader, -f org, as pandoc 3.14's Readers/Org reads Org:
   its blocks (Blocks.hs), the document's tree (DocumentTree.hs) and
   the passes after parsing. Inlines are PdOrgInline's, the export
   settings PdOrgMeta's.

   Phase 26.1: paragraphs and Plain, blank lines, horizontal rules,
   fixed-width lines, comment lines, raw export lines, keywords and
   #+OPTIONS. Phase 26.2: bullet, ordered and definition lists, with
   checkboxes. Phase 26.3: block attributes and figures, #+begin_
   blocks (source, example, quote, verse, export and raw, comment,
   admonitions, abstract and the rest as Divs), dynamic blocks,
   drawers, LaTeX environments and footnote definitions, kept until
   Phase 27.3 resolves their references. Phase 26.4: Org tables and
   table.el tables (PdGridTable). Phase 26.5: the headline tree, with
   TODO keywords, priorities, tags, planning, property drawers,
   COMMENT, ARCHIVE, select and exclude tags and H:. Phase 27.2: #+LINK formats, and
   PdOrgInline.Resolve's pass over the document for links. Phase 28.1:
   the metadata keywords (Meta.hs's keywordHandlers: #+TITLE,
   #+AUTHOR, #+LATEX_HEADER and the rest), joined as collectLines and
   collectAsList join them, and author:, email: and creator:
   (metaExport). Phase 28.2: #+INCLUDE (include and
   insertIncludedFile). Phase 28.3: --unknown reports unknown
   keywords and #+BEGIN_ blocks (PdOrgInline.Unknown), each nested
   text's origin given to PdOrgInline.Origin for their places. *)

IMPORT Ropes, Utf8, Unicode, PdIO, PdSource, A := PdAst, B := PdMdBase, MI := PdMdInline,
  I := PdOrgInline, M := PdOrgMeta, SH := PdShared, G := PdGridTable;

CONST
  Quiet* = I.Quiet; WarnUnknown* = I.WarnUnknown;
  FailUnknown* = I.FailUnknown; (* unknown *)
  KeySize = 64;
  IdTableSize = 4093; (* the buckets of the identifiers' table, a
    prime, as PdMarkdown's *)

  (* the keywords pandoc's keywordHandlers know *)
  Keywords = " author bibliography creator date description email exclude_tags header-includes html_head html_head_extra institute keywords language latex_class latex_class_options latex_header latex_header_extra link macro nocite options pandoc-emphasis-post pandoc-emphasis-pre result select_tags seq_todo subtitle title todo typ_todo ";

TYPE
  (* the attribute of a Span that stands for the SoftBreak between two
     lines of a metadata key, until the links are resolved, so that
     the walk that resolves them does not merge it with a break next
     to it *)
  LineSepAttr = POINTER TO RECORD (A.AttrDesc) END;
  (* the walk that turns them into SoftBreaks *)
  LineSepWalker = POINTER TO RECORD (A.WalkerDesc) END;

  Key = ARRAY KeySize OF CHAR;

  (* a block attribute's line: #+key: value, value t[from .. to-1] *)
  AttrLine = POINTER TO RECORD
    key: Key;
    from, to: LONGINT;
    next: AttrLine
  END;

  (* blockAttributes *)
  BlockAttrs = RECORD
    name: A.Rope;
    hasCaption: BOOLEAN;
    caption: A.Inline;
    kv: A.Attr (* the pairs of #+attr_html: *)
  END;


  (* a property of a headline's drawer, key in lower case *)
  Prop = POINTER TO RECORD
    key, value: A.Rope;
    next: Prop
  END;

  (* a TODO keyword *)
  Marker = POINTER TO RECORD
    name: A.Rope;
    s: POINTER TO ARRAY OF CHAR; (* name, its bytes *)
    len: LONGINT; (* their number *)
    done: BOOLEAN; (* a done keyword, not a todo one *)
    next: Marker
  END;

  (* a headline and the tree under it *)
  Headline = POINTER TO RECORD
    level: LONGINT;
    marker: Marker; (* its TODO keyword, or NIL *)
    title: A.Inline;
    tags: A.StrList;
    closed, deadline, scheduled: A.Rope; (* its planning, or NIL *)
    props: Prop;
    contents: A.Block;
    children, next: Headline
  END;

  (* an identifier used, in the table's bucket *)
  IdSlot = POINTER TO RECORD
    key: A.Rope;
    n: LONGINT; (* the last suffix tried for key as a base *)
    next: IdSlot
  END;
  IdTable = POINTER TO ARRAY IdTableSize OF IdSlot;

  (* an included file being read *)
  Inc = POINTER TO RECORD
    name: POINTER TO ARRAY OF CHAR; (* as the #+INCLUDE: line gives it *)
    start: LONGINT; (* the line its text starts at *)
    depth: INTEGER; (* B.depth while its text is read *)
    next: Inc (* the file that includes it *)
  END;

  (* the walk of blockFilter: the highest level, then the shift *)
  LevelWalker = POINTER TO RECORD (A.WalkerDesc)
    query: BOOLEAN; (* finding min, not shifting *)
    min, shift: LONGINT
  END;

  Ints = POINTER TO ARRAY OF INTEGER;
  Reals = POINTER TO ARRAY OF LONGREAL;

VAR
  (* the extensions *)
  autoIds*, asciiIds*, gfmIds*, citations*, specialStrings*, taskLists*,
  smart*, smartQuotes*, fancyLists*, eastAsian*: BOOLEAN;
  standalone*: BOOLEAN; (* -s *)
  unknown*: INTEGER; (* --unknown: Quiet, WarnUnknown or FailUnknown *)
  columns*: LONGINT; (* pandoc's readerColumns, from --columns *)

  idTable: IdTable; (* the identifiers used so far *)
  markers: Marker; (* the active TODO keywords, in the order tried *)
  customTodo: BOOLEAN; (* a #+todo line has replaced the default *)
  selectTags, excludeTags: A.StrList;
  selectSet, excludeSet: BOOLEAN; (* a line has set them *)
  inList: BOOLEAN; (* in a list item: the context ListItemState *)
  fresh: BOOLEAN; (* orgStateLastPreCharPos is Nothing: nothing read
    since a parseFromString began or ended, as at an item's start or
    after a list *)
  meta: A.MetaMapV; (* the document's *)
  incs: Inc; (* the files being included, the innermost first *)
  main: B.Text; mainLen: LONGINT; (* the document's text *)
  rawA, rawB: LONGINT; (* RawContent's origin, for I.Origin(I.OrgLines) *)

(* Lines *)

(* metaKey at p: the key, in lower case, up to a colon, a space or a
   new line; then the colon and any spaces. Where it ends, or -1; a
   key too long for k is returned as "". *)
PROCEDURE MetaKey(p: LONGINT; VAR k: Key): LONGINT;
  VAR q, i: LONGINT; ch: CHAR;
BEGIN
  q := p; i := 0;
  LOOP
    ch := B.C(q);
    IF (q >= B.len) OR (ch = ":") OR (ch = " ") OR (ch = 0AX) OR (ch = 0DX) THEN
      EXIT
    END;
    IF i < KeySize - 1 THEN k[i] := B.Lower(ch) END;
    INC(i); INC(q)
  END;
  IF (q = p) OR (ch # ":") THEN RETURN -1 END;
  IF i < KeySize THEN k[i] := 0X ELSE k[0] := 0X END;
  RETURN B.SkipSpaces(q + 1)
END MetaKey;

(* Whether k is one of the space-separated words of list. *)
PROCEDURE InList(VAR k: Key; list: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: LONGINT;
BEGIN
  IF k[0] = 0X THEN RETURN FALSE END;
  i := 0;
  WHILE list[i] # 0X DO
    IF list[i] = " " THEN
      j := 0;
      WHILE (k[j] # 0X) & (list[i + 1 + j] = k[j]) DO INC(j) END;
      IF (k[j] = 0X) & (list[i + 1 + j] = " ") THEN RETURN TRUE END
    END;
    INC(i)
  END;
  RETURN FALSE
END InList;

(* Where the line at p ends, past its new line. *)
PROCEDURE NextLine(p: LONGINT): LONGINT;
BEGIN
  p := B.LineEnd(p);
  IF p < B.len THEN INC(p) END;
  RETURN p
END NextLine;

(* Blocks *)

(* example: one or more fixed-width lines, a CodeBlock of the text
   after their colons, each line ended by a new line *)
PROCEDURE Example(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, e: LONGINT; b: B.Buf;
BEGIN
  p := B.pos; q := I.ExampleLineStart(p);
  IF q < 0 THEN RETURN FALSE END;
  B.InitBuf(b);
  REPEAT
    e := B.LineEnd(q);
    B.Put(b, q, e); B.PutChar(b, 0AX);
    p := NextLine(e); q := I.ExampleLineStart(p)
  UNTIL q < 0;
  A.AddBlock(l, A.NewCodeBlock(A.NewAttr(NIL), B.BufRope(b)));
  B.pos := p; I.Newline;
  RETURN TRUE
END Example;

PROCEDURE ^ TodoSequence(p: LONGINT): BOOLEAN;
PROCEDURE ^ TagList(p: LONGINT; select: BOOLEAN): BOOLEAN;

(* Metadata (Phase 28.1) *)

(* A SoftBreak between lines of metadata, kept apart by a Span *)
PROCEDURE LineSep(): A.Inline;
  VAR a: LineSepAttr;
BEGIN
  NEW(a); a.id := A.S(""); a.classes := NIL; a.attrs := NIL;
  RETURN A.NewSpan(a, NIL)
END LineSep;

PROCEDURE (w: LineSepWalker) Inline*(i: A.Inline): A.Inline;
BEGIN
  IF (i IS A.SpanInl) & (i(A.SpanInl).attr # NIL)
      & (i(A.SpanInl).attr IS LineSepAttr) THEN
    RETURN A.NewSimple(A.SoftBreak)
  END;
  RETURN i
END Inline;

(* The list a, then the list b, as Haskell's ++ joins them: nothing
   merged *)
PROCEDURE Cat(a, b: A.Inline): A.Inline;
  VAR z: A.Inline;
BEGIN
  IF a = NIL THEN RETURN b END;
  z := A.LastInline(a); z.next := b;
  RETURN a
END Cat;

(* collectInlines: the inlines of v, a copy *)
PROCEDURE CollectInlines(v: A.MetaValue): A.Inline;
  VAR l: A.Inlines; r: A.Inline; it: A.MetaItem;
BEGIN
  r := NIL;
  IF v IS A.MetaInlinesV THEN
    r := A.DeepCopyInlines(v(A.MetaInlinesV).inlines)
  ELSIF v IS A.MetaStringV THEN r := A.NewStr(v(A.MetaStringV).s)
  ELSIF v IS A.MetaBlocksV THEN
    A.InitInlines(l); SH.BlocksToInlines(l, v(A.MetaBlocksV).blocks);
    r := l.first
  ELSIF v IS A.MetaListV THEN (* intercalate [SoftBreak] *)
    it := v(A.MetaListV).items;
    WHILE it # NIL DO
      IF it # v(A.MetaListV).items THEN r := Cat(r, LineSep()) END;
      r := Cat(r, CollectInlines(it.value));
      it := it.next
    END
  END;
  RETURN r
END CollectInlines;

(* collectLines: key's inlines, a SoftBreak if there are any, then
   i, as the MetaInlines of key *)
PROCEDURE CollectLines(key: ARRAY OF CHAR; i: A.Inline);
  VAR v: A.MetaValue; c: A.Inline;
BEGIN
  v := A.GetMeta(meta, key); c := NIL;
  IF v # NIL THEN c := CollectInlines(v) END;
  IF c # NIL THEN c := Cat(c, LineSep()) END;
  A.SetMeta(meta, A.S(key), A.NewMetaInlines(Cat(c, i)))
END CollectLines;

(* collectAsList: key's list, or its value as a list of one, with v
   added *)
PROCEDURE CollectAsList(key: ARRAY OF CHAR; v: A.MetaValue);
  VAR cur: A.MetaValue; l: A.MetaListV;
BEGIN
  cur := A.GetMeta(meta, key);
  IF (cur # NIL) & (cur IS A.MetaListV) THEN l := cur(A.MetaListV)
  ELSE
    l := A.NewMetaList();
    IF cur # NIL THEN A.AddMetaItem(l, cur) END;
    A.SetMeta(meta, A.S(key), l)
  END;
  A.AddMetaItem(l, v)
END CollectAsList;

(* lineOfInlines at p: the inlines up to a new line, which is read,
   trimmed; FALSE, with B.pos and the state as they were, if an
   inline fails before it *)
PROCEDURE LineOfInlines(p: LONGINT; VAR i: A.Inline): BOOLEAN;
  VAR s: I.State; l: A.Inlines;
BEGIN
  I.Save(s); B.pos := p; I.SetPre;
  A.InitInlines(l);
  WHILE B.C(B.pos) # 0AX DO
    IF (B.pos >= B.len) OR ~I.Inline(l) THEN I.Restore(s); RETURN FALSE END
  END;
  INC(B.pos);
  i := MI.Trim(l);
  RETURN TRUE
END LineOfInlines;

(* anyLine at p: the text up to the new line, both read *)
PROCEDURE AnyLine(p: LONGINT): A.Rope;
  VAR e: LONGINT;
BEGIN
  e := B.LineEnd(p); B.pos := NextLine(e);
  RETURN B.Rope(p, e)
END AnyLine;

(* The metadata keywords of keywordHandlers, key k, its value at p:
   FALSE if k is not one, or its line fails *)
PROCEDURE MetaKeyword(VAR k: Key; p: LONGINT): BOOLEAN;
  VAR i: A.Inline; r: A.Rope; b: B.Buf; j: LONGINT;
BEGIN
  IF (k = "title") OR (k = "subtitle") OR (k = "author")
      OR (k = "description") OR (k = "keywords") OR (k = "institute")
      OR (k = "nocite") OR (k = "header-includes") OR (k = "date") THEN
    IF ~LineOfInlines(p, i) THEN RETURN FALSE END;
    IF k = "date" THEN A.SetMeta(meta, A.S("date"), A.NewMetaInlines(i))
    ELSE CollectLines(k, i)
    END
  ELSIF (k = "creator") OR (k = "email") THEN
    A.SetMeta(meta, A.S(k), A.NewMetaString(AnyLine(p)))
  ELSIF k = "language" THEN
    A.SetMeta(meta, A.S("lang"), A.NewMetaString(AnyLine(p)))
  ELSIF k = "latex_class" THEN
    A.SetMeta(meta, A.S("documentclass"), A.NewMetaString(AnyLine(p)))
  ELSIF k = "latex_class_options" THEN (* without [ and ] *)
    B.InitBuf(b); j := p;
    WHILE B.C(j) # 0AX DO
      IF (B.C(j) # "[") & (B.C(j) # "]") THEN B.Put(b, j, j + 1) END;
      INC(j)
    END;
    B.pos := NextLine(j);
    A.SetMeta(meta, A.S("classoption"), A.NewMetaString(B.BufRope(b)))
  ELSIF k = "bibliography" THEN
    CollectAsList("bibliography", A.NewMetaString(AnyLine(p)))
  ELSIF (k = "html_head") OR (k = "html_head_extra") THEN
    r := AnyLine(p);
    CollectAsList("header-includes",
      A.NewMetaInlines(A.NewRawInline(A.S("html"), r)))
  ELSIF (k = "latex_header") OR (k = "latex_header_extra") THEN
    r := AnyLine(p);
    CollectAsList("header-includes",
      A.NewMetaInlines(A.NewRawInline(A.S("latex"), r)))
  ELSE RETURN FALSE
  END;
  RETURN TRUE
END MetaKeyword;

(* keywordLine: a keyword pandoc knows, after #+ and the key: the
   metadata keywords, #+OPTIONS, #+pandoc-emphasis-pre and -post,
   #+LINK, #+MACRO, the TODO sequences and #+select_tags and
   #+exclude_tags are read; #+result's line is passed over. *)
PROCEDURE KeywordLine(VAR k: Key; p: LONGINT): BOOLEAN;
BEGIN
  IF ~InList(k, Keywords) THEN RETURN FALSE END;
  IF MetaKeyword(k, p) THEN
  ELSIF (k = "title") OR (k = "subtitle") OR (k = "author")
      OR (k = "description") OR (k = "keywords") OR (k = "institute")
      OR (k = "nocite") OR (k = "header-includes") OR (k = "date") THEN
    RETURN FALSE (* lineOfInlines failed *)
  ELSIF k = "options" THEN B.pos := M.Options(p)
  ELSIF (k = "link") & ~I.LinkFormat(p) THEN RETURN FALSE
  ELSIF (k = "macro") & ~I.AddMacro(p) THEN RETURN FALSE
  ELSIF (k = "todo") OR (k = "seq_todo") OR (k = "typ_todo") THEN
    IF ~TodoSequence(p) THEN RETURN FALSE END
  ELSIF (k = "select_tags") OR (k = "exclude_tags") THEN
    IF ~TagList(p, k = "select_tags") THEN RETURN FALSE END
  ELSE
    IF k = "pandoc-emphasis-pre" THEN I.EmphChars(FALSE, p)
    ELSIF k = "pandoc-emphasis-post" THEN I.EmphChars(TRUE, p)
    END;
    B.pos := NextLine(p)
  END;
  I.Newline;
  RETURN TRUE
END KeywordLine;

(* specialLine: a raw export line, #+print_bibliography:, a keyword,
   or a comment line *)
PROCEDURE SpecialLine(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, e: LONGINT; k: Key;
BEGIN
  p := B.pos;
  q := I.MetaLineStart(p);
  IF q >= 0 THEN
    q := MetaKey(q, k);
    IF (q >= 0) & ((k = "latex") OR (k = "html") OR (k = "texinfo")
        OR (k = "beamer")) THEN (* rawExportLine *)
      e := B.LineEnd(q);
      A.AddBlock(l, A.NewRawBlock(A.S(k), B.Rope(q, e)));
      B.pos := NextLine(e); I.Newline;
      RETURN TRUE
    END;
    IF B.Looking(B.SkipSpaces(p), "#+print_bibliography:") THEN
      A.AddBlock(l, A.NewDiv(A.NewAttr(A.S("refs")), NIL));
      B.pos := NextLine(p); I.Newline;
      RETURN TRUE
    END;
    IF (q >= 0) & KeywordLine(k, q) THEN RETURN TRUE END
  END;
  IF I.CommentLineStart(p) >= 0 THEN
    B.pos := NextLine(p); I.Newline;
    RETURN TRUE
  END;
  RETURN FALSE
END SpecialLine;

(* rawOrgLine: any other #+ line, a RawBlock org of it from its #+ *)
PROCEDURE RawOrgLine(VAR l: A.Blocks): BOOLEAN;
  VAR q, e, k: LONGINT;
BEGIN
  q := I.MetaLineStart(B.pos);
  IF q < 0 THEN RETURN FALSE END;
  e := B.LineEnd(q);
  k := q;
  WHILE (k < e) & (B.t[k] # ":") & ~B.IsWhite(B.t[k]) DO INC(k) END;
  I.Unknown("Unknown keyword", B.Rope(q - 2, k), q - 2);
  A.AddBlock(l, A.NewRawBlock(A.S("org"), B.Rope(q - 2, e)));
  B.pos := NextLine(e); I.Newline;
  RETURN TRUE
END RawOrgLine;

(* paraOrPlain: inlines, a Para if a new line ends them, else Plain;
   Plain too in a list item when an item follows *)
PROCEDURE ParaOrPlain(VAR l: A.Blocks): BOOLEAN;
  VAR n: LONGINT; i: A.Inline; p: LONGINT;
BEGIN
  p := B.pos;
  IF I.HeaderStart(p, n) >= 0 THEN RETURN FALSE END;
  i := I.Inlines();
  IF B.pos = p THEN RETURN FALSE END;
  IF B.C(B.pos) = 0AX THEN
    INC(B.pos); I.Newline;
    IF ~inList OR (I.BulletListStart(B.pos, n) < 0)
        & (I.OrderedListStart(B.pos, n) < 0) THEN
      A.AddBlock(l, A.NewInlinesBlock(A.Para, i))
    ELSIF i # NIL THEN
      A.AddBlock(l, A.NewInlinesBlock(A.Plain, i))
    END
  ELSIF i # NIL THEN (* B.plain drops a Plain with no inlines *)
    A.AddBlock(l, A.NewInlinesBlock(A.Plain, i))
  END;
  RETURN TRUE
END ParaOrPlain;

PROCEDURE ^ Blocks(VAR l: A.Blocks);

(* Lists *)

(* listLine at p: n spaces, and where the rest of the line starts; -1
   if there are fewer, or no line *)
PROCEDURE ListLine(p, n: LONGINT): LONGINT;
  VAR i: LONGINT;
BEGIN
  FOR i := 0 TO n - 1 DO
    IF B.C(p + i) # " " THEN RETURN -1 END
  END;
  IF B.LineEnd(p + n) >= B.len THEN RETURN -1 END;
  RETURN p + n
END ListLine;

PROCEDURE ^ Block(VAR l: A.Blocks): BOOLEAN;
PROCEDURE ^ Include(VAR l: A.Blocks): BOOLEAN;

(* Org blocks: block attributes, #+begin_ blocks, figures, dynamic
   blocks, drawers, LaTeX environments and footnote definitions *)

(* Whether t[p ..] is s, which is in lower case, in any case
   (stringAnyCase) *)
PROCEDURE LookingCI(p: LONGINT; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF (p + i >= B.len) OR (B.Lower(B.t[p + i]) # s[i]) THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END LookingCI;

(* Whether there is a byte at p and it is not white space
   (nonspaceChar) *)
PROCEDURE NonSpace(p: LONGINT): BOOLEAN;
BEGIN
  RETURN (p < B.len) & ~B.IsWhite(B.t[p])
END NonSpace;

(* Whether t[from .. to-1] is s *)
PROCEDURE Is(from, to: LONGINT; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
  RETURN (to - from = i) & B.Looking(from, s)
END Is;

(* t[from .. to-1] in upper case, if upper, else in lower case *)
PROCEDURE CaseRope(from, to: LONGINT; upper: BOOLEAN): A.Rope;
  VAR b: B.Buf; i: LONGINT;
BEGIN
  B.InitBuf(b);
  FOR i := from TO to - 1 DO
    IF upper THEN B.PutChar(b, Ropes.UpperChar(B.t[i]))
    ELSE B.PutChar(b, B.Lower(B.t[i]))
    END
  END;
  RETURN B.BufRope(b)
END CaseRope;

(* t[from .. to-1] into k, in lower case; "" if it is too long *)
PROCEDURE LowerKey(from, to: LONGINT; VAR k: Key);
  VAR i: LONGINT;
BEGIN
  IF to - from < KeySize THEN
    FOR i := 0 TO to - from - 1 DO k[i] := B.Lower(B.t[from + i]) END;
    k[to - from] := 0X
  ELSE k[0] := 0X
  END
END LowerKey;

(* orgParamValue's endOfValue at p *)
PROCEDURE ValueEnd(p: LONGINT): BOOLEAN;
  VAR q, f: LONGINT;
BEGIN
  q := B.SkipSpaces(p);
  IF (B.C(q) = 0AX) OR (B.C(q) = 0DX) THEN RETURN TRUE END;
  RETURN (q > p) & (I.ArgKey(q, f) >= 0)
END ValueEnd;

(* orgParamValue: a value, t[from .. to-1], quoted or up to a key or
   the end of the line, and the spaces after it; where they end, or
   -1 *)
PROCEDURE ParamValue(p: LONGINT; VAR from, to: LONGINT): LONGINT;
  VAR q, f: LONGINT; ch: CHAR;
BEGIN
  q := B.SkipSpaces(p);
  IF I.ArgKey(q, f) >= 0 THEN RETURN -1 END;
  ch := B.C(q);
  IF ch = 22X THEN
    from := q + 1; q := from;
    WHILE (q < B.len) & (B.t[q] # 0AX) & (B.t[q] # 0DX) & (B.t[q] # 22X) DO
      INC(q)
    END;
    IF B.C(q) # 22X THEN RETURN -1 END;
    to := q; INC(q)
  ELSE
    IF (q >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN RETURN -1 END;
    from := q; INC(q);
    WHILE ~ValueEnd(q) DO
      ch := B.C(q);
      IF (q >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN RETURN -1 END;
      INC(q)
    END;
    to := q
  END;
  RETURN B.SkipSpaces(q)
END ParamValue;

(* blockOption: a key and its value, yes if it has none, added to a;
   where it ends, or -1 *)
PROCEDURE BlockOption(p: LONGINT; a: A.Attr): LONGINT;
  VAR q, r, f, vf, vt: LONGINT;
BEGIN
  q := I.ArgKey(p, f);
  IF q < 0 THEN RETURN -1 END;
  r := ParamValue(q, vf, vt);
  IF r >= 0 THEN
    A.AddKeyVal(a, B.Rope(f, q), B.Rope(vf, vt));
    RETURN r
  END;
  A.AddKeyVal(a, B.Rope(f, q), A.S("yes"));
  RETURN q
END BlockOption;

(* Adds t's pairs to a's *)
PROCEDURE AddPairs(a, t: A.Attr);
  VAR p: A.KeyVal;
BEGIN
  p := t.attrs;
  WHILE p # NIL DO A.AddKeyVal(a, p.key, p.value); p := p.next END
END AddPairs;

(* blockParameters: a Lisp-style list of keys and values, words
   joined by =, or else the rest of the line as parameters, added to
   a. Where the line ends, past its new line, or -1. *)
PROCEDURE BlockParameters(p: LONGINT; a: A.Attr): LONGINT;
  VAR q, r, f, vf, vt: LONGINT; t: A.Attr;
BEGIN
  t := A.NewAttr(NIL); q := p;
  LOOP
    IF B.C(q) = 0AX THEN AddPairs(a, t); RETURN q + 1 END;
    r := I.ArgKey(q, f);
    IF r < 0 THEN EXIT END;
    q := ParamValue(r, vf, vt);
    IF q < 0 THEN EXIT END;
    A.AddKeyVal(t, B.Rope(f, r), B.Rope(vf, vt))
  END;
  t := A.NewAttr(NIL); q := p;
  LOOP
    IF B.C(q) = 0AX THEN AddPairs(a, t); RETURN q + 1 END;
    WHILE (q < B.len) & B.IsWhite(B.t[q]) DO INC(q) END;
    f := q; r := I.ArgWord(q);
    IF (r < 0) OR (B.C(r) # "=") THEN EXIT END;
    vf := r + 1; vt := I.ArgWord(vf);
    IF vt < 0 THEN EXIT END;
    A.AddKeyVal(t, B.Rope(f, r), B.Rope(vf, vt));
    q := vt
  END;
  q := B.SkipSpaces(p); r := B.LineEnd(q);
  IF r >= B.len THEN RETURN -1 END;
  IF r > q THEN A.AddKeyVal(a, A.S("parameters"), B.Rope(q, r)) END;
  RETURN r + 1
END BlockParameters;

(* The inlines of b's text and a new line, or NIL if there are none *)
PROCEDURE BufInlines(VAR b: B.Buf): A.Inline;
  VAR f: B.Frame; i: A.Inline;
BEGIN
  B.PutChar(b, 0AX);
  I.Enter(f, b.t, b.len);
  i := I.Inlines();
  I.Leave(f);
  RETURN i
END BufInlines;

(* The blocks of b's text and a new line, into out
   (parseFromString blocks) *)
PROCEDURE ParseBlocks(VAR b: B.Buf; VAR out: A.Blocks);
  VAR f: B.Frame;
BEGIN
  B.PutChar(b, 0AX);
  I.Enter(f, b.t, b.len);
  A.InitBlocks(out);
  fresh := TRUE;
  Blocks(out);
  I.Leave(f)
END ParseBlocks;

(* keyValues: the pairs, :key value, of the current text, added to a;
   FALSE if it is not made of them *)
PROCEDURE KeyValues(a: A.Attr): BOOLEAN;
  VAR p, s, kf, k, v, e, x: LONGINT;

  (* key: spaces, a colon and one or more other bytes *)
  PROCEDURE Key(q: LONGINT; VAR from: LONGINT): LONGINT;
    VAR ch: CHAR;
  BEGIN
    q := B.SkipSpaces(q);
    IF B.C(q) # ":" THEN RETURN -1 END;
    INC(q); from := q;
    LOOP
      ch := B.C(q);
      IF (q >= B.len) OR (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX) THEN
        EXIT
      END;
      INC(q)
    END;
    IF q = from THEN RETURN -1 END;
    RETURN q
  END Key;

BEGIN
  p := 0;
  LOOP
    IF B.C(p) = 0AX THEN RETURN TRUE END;
    k := Key(p, kf);
    IF k < 0 THEN RETURN FALSE END;
    v := B.SkipSpaces(k); e := v;
    LOOP (* manyTillChar anyChar endOfValue *)
      s := B.SkipSpaces(e);
      IF (s > e) & (Key(s, x) >= 0) THEN p := e; EXIT END;
      IF B.C(s) = 0AX THEN p := s; EXIT END;
      IF e >= B.len THEN RETURN FALSE END;
      INC(e)
    END;
    A.AddKeyVal(a, B.Rope(kf, k), B.Rope(v, e))
  END
END KeyValues;

(* blockAttributes: #+name:, #+caption:, #+attr_html: and the other
   attributes a block may have, into ba; where they end, or -1 if one
   of the lines is another keyword or #+attr_html: is not pairs *)
PROCEDURE Attributes(p: LONGINT; VAR ba: BlockAttrs): LONGINT;
  VAR q, r, v, e, capFrom: LONGINT; first, last, x: AttrLine; cap, kv: B.Buf;
    f: B.Frame; ok: BOOLEAN; capKind: INTEGER;
BEGIN
  first := NIL; last := NIL;
  LOOP (* many stringyMetaAttribute *)
    q := I.MetaLineStart(p);
    IF (q < 0) OR LookingCI(q, "begin")
        & ((B.C(q + 5) = ":") OR (B.C(q + 5) = "_")) OR ~NonSpace(q) THEN
      EXIT
    END;
    r := q + 1;
    WHILE B.C(r) # ":" DO
      IF ~NonSpace(r) THEN EXIT END; (* leaves the LOOP *)
      INC(r)
    END;
    v := B.SkipSpaces(r + 1); e := B.LineEnd(v);
    IF e >= B.len THEN EXIT END;
    NEW(x); x.from := v; x.to := e; x.next := NIL;
    LowerKey(q, r, x.key);
    IF first = NIL THEN first := x ELSE last.next := x END;
    last := x; p := e + 1
  END;
  ba.name := NIL; ba.hasCaption := FALSE; ba.caption := NIL;
  ba.kv := A.NewAttr(NIL);
  B.InitBuf(cap); B.InitBuf(kv);
  x := first;
  WHILE x # NIL DO
    IF ~InList(x.key, " name label caption attr_html attr_latex results ") THEN
      RETURN -1
    END;
    IF (x.key = "name") OR (x.key = "label") THEN
      ba.name := B.Rope(x.from, x.to)
    ELSIF x.key = "caption" THEN
      IF ba.hasCaption THEN B.PutChar(cap, " "); capKind := I.OrgAt
      ELSE capKind := I.OrgOffset; capFrom := x.from
      END;
      B.Put(cap, x.from, x.to); ba.hasCaption := TRUE
    ELSIF x.key = "attr_html" THEN
      IF kv.len > 0 THEN B.PutChar(kv, " ") END;
      B.Put(kv, x.from, x.to)
    END;
    x := x.next
  END;
  IF ba.hasCaption THEN
    I.Origin(capKind, capFrom, 0); ba.caption := BufInlines(cap)
  END;
  B.PutChar(kv, 0AX);
  I.Enter(f, kv.t, kv.len);
  ok := KeyValues(ba.kv);
  I.Leave(f);
  IF ~ok THEN RETURN -1 END;
  RETURN p
END Attributes;

(* attrFromBlockAttributes: the identifier from the pair id, the
   classes the words of the pair class, and the other pairs *)
PROCEDURE DivAttr(VAR ba: BlockAttrs): A.Attr;
  VAR a: A.Attr; kv: A.KeyVal; id, cls: BOOLEAN; n, i, j: LONGINT;
BEGIN
  a := A.NewAttr(NIL); id := FALSE; cls := FALSE;
  kv := ba.kv.attrs;
  WHILE kv # NIL DO
    IF Ropes.EqualString(kv.key, "id") THEN
      IF ~id THEN a.id := kv.value; id := TRUE END
    ELSIF Ropes.EqualString(kv.key, "class") THEN
      IF ~cls THEN
        cls := TRUE; n := Ropes.Length(kv.value); i := 0;
        WHILE i < n DO
          WHILE (i < n) & B.IsWhite(Ropes.Fetch(kv.value, i)) DO INC(i) END;
          j := i;
          WHILE (j < n) & ~B.IsWhite(Ropes.Fetch(kv.value, j)) DO INC(j) END;
          IF j > i THEN A.AddClass(a, Ropes.Substring(kv.value, i, j - i)) END;
          i := j
        END
      END
    ELSE A.AddKeyVal(a, kv.key, kv.value)
    END;
    kv := kv.next
  END;
  RETURN a
END DivAttr;

(* The end of a block, at p: #+end_ and the type t[ts .. te-1], or, if
   dynamic, #+end:, in any case. Where the marker ends, or -1. *)
PROCEDURE EndMarker(p: LONGINT; dynamic: BOOLEAN; ts, te: LONGINT): LONGINT;
  VAR i: LONGINT;
BEGIN
  IF dynamic THEN
    p := I.MetaLineStart(p);
    IF (p >= 0) & LookingCI(p, "end:") THEN RETURN p + 4 END;
    RETURN -1
  END;
  p := B.SkipSpaces(p);
  IF ~LookingCI(p, "#+end_") THEN RETURN -1 END;
  INC(p, 6);
  FOR i := 0 TO te - ts - 1 DO
    IF B.Lower(B.C(p + i)) # B.Lower(B.t[ts + i]) THEN RETURN -1 END
  END;
  RETURN p + te - ts
END EndMarker;

(* The indent at q, tabs counted to the tab stop; s where it ends *)
PROCEDURE Indent(q: LONGINT; VAR s: LONGINT): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0; s := q;
  WHILE B.IsSpace(B.C(s)) DO
    IF B.t[s] = 09X THEN INC(n, B.tabStop) ELSE INC(n) END;
    INC(s)
  END;
  RETURN n
END Indent;

(* rawBlockContent: the lines from p to the block's end, into b, each
   with a new line; blank lines empty, the shortest indent taken from
   the others if trim, and a comma before * or #+ taken away. Where
   the end marker ends, or -1. *)
PROCEDURE RawContent(p: LONGINT; dynamic: BOOLEAN; ts, te: LONGINT;
    trim: BOOLEAN; VAR b: B.Buf): LONGINT;
  VAR q, r, s, e, last, n, min: LONGINT;
BEGIN
  min := MAX(LONGINT); q := p;
  LOOP
    e := EndMarker(q, dynamic, ts, te);
    IF e >= 0 THEN EXIT END;
    r := B.BlankLine(q);
    IF r < 0 THEN
      r := B.AnyLine(q);
      IF r < 0 THEN RETURN -1 END;
      n := Indent(q, s);
      IF n < min THEN min := n END
    END;
    q := r
  END;
  last := q; q := p;
  rawA := p; rawB := 0;
  IF trim & (min # MAX(LONGINT)) THEN
    rawB := min;
    IF B.BlankLine(p) < 0 THEN rawA := p + min END
  END;
  I.NewlineAt(last); (* the content's anyLine, or ignHeaders *)
  B.InitBuf(b);
  WHILE q < last DO
    r := B.BlankLine(q);
    IF r >= 0 THEN B.PutChar(b, 0AX); q := r
    ELSE
      n := Indent(q, s);
      IF trim THEN
        WHILE n > min DO B.PutChar(b, " "); DEC(n) END
      ELSE B.Put(b, q, s)
      END;
      IF B.C(s) = "," THEN (* commaEscaped *)
        r := s + 1;
        WHILE B.C(r) = "," DO INC(r) END;
        IF (B.C(r) = "*") OR B.Looking(r, "#+") THEN INC(s) END
      END;
      r := B.LineEnd(s);
      B.Put(b, s, r); B.PutChar(b, 0AX);
      q := r + 1
    END
  END;
  RETURN e
END RawContent;

(* ignHeaders: the rest of the line *)
PROCEDURE IgnHeaders(p: LONGINT): LONGINT;
BEGIN
  IF B.C(p) = 0AX THEN RETURN p + 1 END;
  RETURN B.AnyLine(p)
END IgnHeaders;

(* A switch, -n 10, +n, -l "(ref:%s)", -i or +k, its classes and
   pairs added to a; noTrim set by -i. Where it ends, or -1. *)
PROCEDURE Switch(p: LONGINT; a: A.Attr; VAR noTrim: BOOLEAN): LONGINT;
  VAR q, r: LONGINT; pol, c: CHAR;
BEGIN
  pol := B.C(p);
  IF (pol # "-") & (pol # "+") THEN RETURN -1 END;
  c := B.C(p + 1);
  IF c = "n" THEN (* lineNumberSwitch *)
    q := B.SkipSpaces(p + 2); r := q;
    WHILE B.IsDigit(B.C(r)) DO INC(r) END;
    A.AddClass(a, A.S("numberLines"));
    IF pol = "+" THEN A.AddClass(a, A.S("continuedSourceBlock")) END;
    A.AddKeyVal(a, A.S("startFrom"), B.Rope(q, r));
    RETURN r
  ELSIF c = "l" THEN (* labelSwitch *)
    q := B.SkipSpaces(p + 2);
    IF B.C(q) # 22X THEN RETURN q END;
    r := q + 1;
    IF NonSpace(r) THEN
      INC(r);
      LOOP
        IF B.C(r) = 22X THEN RETURN r + 1 END;
        IF ~NonSpace(r) THEN EXIT END;
        INC(r)
      END
    END
    (* the label fails after its quotation mark: a simple switch, if
       it is +l; -l is then tried as -i, which fails *)
  ELSIF (pol = "-") & (c = "i") THEN (* whitespaceSwitch *)
    noTrim := TRUE;
    RETURN p + 2
  END;
  IF pol = "-" THEN RETURN -1 END;
  IF (c < 80X) & B.IsLetter(c) THEN RETURN p + 2
  ELSIF (c >= 80X) & MI.AlnumAt(p + 1) THEN RETURN MI.RuneEnd(p + 1)
  END;
  RETURN -1
END Switch;

(* switchesAsAttributes: spaces and switches separated by spaces;
   where they end, or -1 if spaces are not followed by a switch *)
PROCEDURE Switches(p: LONGINT; a: A.Attr; VAR noTrim: BOOLEAN): LONGINT;
  VAR q, r, s: LONGINT; nt: BOOLEAN;
BEGIN
  q := B.SkipSpaces(p); nt := FALSE;
  r := Switch(q, a, nt);
  IF r < 0 THEN RETURN q END;
  LOOP
    s := B.SkipSpaces(r);
    IF s = r THEN EXIT END;
    r := Switch(s, a, nt);
    IF r < 0 THEN RETURN -1 END
  END;
  IF nt THEN noTrim := TRUE END;
  RETURN r
END Switches;

(* codeHeaderArgs: the language, switches and options, into a; where
   the line ends, past its new line, or -1 *)
PROCEDURE CodeHeaderArgs(p: LONGINT; a: A.Attr; VAR noTrim: BOOLEAN): LONGINT;
  VAR q, r: LONGINT; lang: A.Rope;
BEGIN
  q := B.SkipSpaces(p); r := I.ArgWord(q);
  IF r < 0 THEN RETURN -1 END;
  lang := I.TranslateLang(q, r);
  IF lang = NIL THEN A.AddClass(a, B.Rope(q, r))
  ELSE
    A.AddClass(a, lang);
    A.AddKeyVal(a, A.S("org-language"), B.Rope(q, r))
  END;
  r := Switches(r, a, noTrim);
  IF r < 0 THEN RETURN -1 END;
  WHILE B.C(r) # 0AX DO
    r := BlockOption(r, a);
    IF r < 0 THEN RETURN -1 END
  END;
  RETURN r + 1
END CodeHeaderArgs;

(* A first class jupyter-x becomes x and code *)
PROCEDURE Jupyter(a: A.Attr);
  VAR c, n: A.StrList; len: LONGINT;
BEGIN
  c := a.classes;
  IF c = NIL THEN RETURN END;
  len := Ropes.Length(c.s);
  IF (len >= 8) & Ropes.EqualString(Ropes.Substring(c.s, 0, 8), "jupyter-") THEN
    c.s := Ropes.Substring(c.s, 8, len - 8);
    NEW(n); n.s := A.S("code"); n.next := c.next; c.next := n
  END
END Jupyter;

(* resultsMarker: #+RESULTS: alone on its line; where it ends, or -1 *)
PROCEDURE ResultsMarker(p: LONGINT): LONGINT;
BEGIN
  IF LookingCI(p, "#+results:") THEN RETURN B.BlankLine(p + 10) END;
  RETURN -1
END ResultsMarker;

(* babelResultsBlock: blank lines and #+RESULTS:, then a block, into
   res; where it ends, or p if there is none *)
PROCEDURE Results(p: LONGINT; VAR res: A.Blocks): LONGINT;
  VAR q, r, saved: LONGINT; s: I.State;
BEGIN
  A.InitBlocks(res);
  I.Save(s);
  q := B.BlankLines(p);
  IF q < 0 THEN RETURN p END;
  r := ResultsMarker(q);
  IF r >= 0 THEN q := r
  ELSE (* looking ahead past #+ lines to the marker *)
    r := q;
    WHILE ResultsMarker(r) < 0 DO
      r := I.MetaLineStart(r);
      IF r >= 0 THEN r := B.AnyLine(r) END;
      IF r < 0 THEN RETURN p END
    END
  END;
  saved := B.pos; B.pos := q; I.Newline;
  IF Block(res) THEN r := B.pos; B.pos := saved
  ELSE A.InitBlocks(res); r := p; I.Restore(s); B.pos := saved
  END;
  RETURN r
END Results;

(* codeBlock: a source block and its results, as exports says, into
   out; where it ends, or -1 *)
PROCEDURE SrcBlock(p, ts, te: LONGINT; VAR ba: BlockAttrs; VAR out: A.Blocks): LONGINT;
  VAR a, c: A.Attr; q, r, e: LONGINT; noTrim, found: BOOLEAN; b: B.Buf;
    res, cap: A.Blocks; v: A.Rope; blk: A.Block;
BEGIN
  q := B.SkipSpaces(p);
  a := A.NewAttr(ba.name); noTrim := FALSE;
  r := CodeHeaderArgs(q, a, noTrim);
  IF r < 0 THEN
    a := A.NewAttr(ba.name); noTrim := FALSE;
    r := IgnHeaders(q);
    IF r < 0 THEN RETURN -1 END
  END;
  e := RawContent(r, FALSE, ts, te, ~noTrim, b);
  IF e < 0 THEN RETURN -1 END;
  Jupyter(a);
  r := Results(e, res);
  v := A.GetKeyVal(a, "exports", found);
  IF ~found OR Ropes.EqualString(v, "code") OR Ropes.EqualString(v, "both") THEN
    blk := A.NewCodeBlock(a, B.BufRope(b));
    IF ba.hasCaption THEN
      A.InitBlocks(cap);
      c := A.NewAttr(NIL); A.AddClass(c, A.S("caption"));
      IF ba.caption = NIL THEN A.AddBlock(cap, A.NewDiv(c, NIL))
      ELSE A.AddBlock(cap, A.NewDiv(c, A.NewInlinesBlock(A.Plain, ba.caption)))
      END;
      A.AddBlock(cap, blk);
      c := A.NewAttr(NIL); A.AddClass(c, A.S("captioned-content"));
      blk := A.NewDiv(c, cap.first)
    END;
    A.AddBlock(out, blk)
  END;
  IF found & (Ropes.EqualString(v, "results") OR Ropes.EqualString(v, "both")) THEN
    A.AddBlock(out, res.first)
  END;
  RETURN r
END SrcBlock;

(* verseBlock: a LineBlock of the lines from p, each line's indent
   kept as no-break spaces, into out; where it ends, or -1 *)
PROCEDURE Verse(p, ts, te: LONGINT; VAR out: A.Blocks): LONGINT;
  VAR e, i, j, k, m, ls: LONGINT; b, nb, lb: B.Buf; f: B.Frame; il: A.Inlines;
    first, last, x: A.InlineList;
BEGIN
  e := RawContent(p, FALSE, ts, te, TRUE, b);
  IF e < 0 THEN RETURN -1 END;
  first := NIL; last := NIL; i := 0; ls := p; (* the line's start *)
  WHILE i < b.len DO
    j := i;
    WHILE b.t[j] # 0AX DO INC(j) END;
    k := i;
    WHILE (k < j) & B.IsWhite(b.t[k]) DO INC(k) END;
    A.InitInlines(il);
    IF k > i THEN
      B.InitBuf(nb);
      FOR m := i TO k - 1 DO B.PutChar(nb, 0C2X); B.PutChar(nb, 0A0X) END;
      A.Append(il, A.NewStr(B.BufRope(nb)))
    END;
    B.InitBuf(lb);
    FOR m := k TO j - 1 DO B.PutChar(lb, b.t[m]) END;
    B.PutChar(lb, 0AX);
    IF ls < e THEN (* the text after the content line's indent *)
      I.Origin(I.OrgOffset, B.SkipSpaces(ls), 0);
      ls := NextLine(B.LineEnd(ls))
    END;
    I.Enter(f, lb.t, lb.len);
    A.Append(il, I.Inlines());
    I.Leave(f);
    NEW(x); x.inlines := MI.Trim(il); x.next := NIL;
    IF first = NIL THEN first := x ELSE last.next := x END;
    last := x;
    i := j + 1
  END;
  A.AddBlock(out, A.NewLineBlock(first));
  RETURN e
END Verse;

(* orgBlock: a block between #+begin_type and #+end_type, at B.pos,
   added to l *)
PROCEDURE OrgBlock(VAR l: A.Blocks): BOOLEAN;
  VAR ba: BlockAttrs; q, r, ts, te, e: LONGINT; k: Key; a: A.Attr;
    b: B.Buf; out, cont: A.Blocks; noTrim: BOOLEAN; fmt: A.Rope; title: A.Block;
BEGIN
  q := Attributes(B.pos, ba);
  IF q < 0 THEN RETURN FALSE END;
  q := I.MetaLineStart(q);
  IF (q < 0) OR ~LookingCI(q, "begin_") THEN RETURN FALSE END;
  ts := q + 6; te := ts;
  WHILE NonSpace(te) DO INC(te) END;
  IF te = ts THEN RETURN FALSE END;
  LowerKey(ts, te, k);
  A.InitBlocks(out); e := -1;
  IF k = "export" THEN
    q := B.SkipSpaces(te); r := I.ArgWord(q);
    IF r >= 0 THEN
      fmt := CaseRope(q, r, FALSE); r := IgnHeaders(r);
      IF r >= 0 THEN
        e := RawContent(r, FALSE, ts, te, TRUE, b);
        IF e >= 0 THEN A.AddBlock(out, A.NewRawBlock(fmt, B.BufRope(b))) END
      END
    END
  ELSIF (k = "comment") OR (k = "html") OR (k = "latex") OR (k = "ascii") THEN
    r := IgnHeaders(te);
    IF r >= 0 THEN
      e := RawContent(r, FALSE, ts, te, TRUE, b);
      IF (e >= 0) & (k # "comment") THEN
        A.AddBlock(out, A.NewRawBlock(A.S(k), B.BufRope(b)))
      END
    END
  ELSIF k = "example" THEN
    a := A.NewAttr(ba.name); noTrim := FALSE;
    r := Switches(te, a, noTrim);
    IF (r >= 0) & (B.C(r) = 0AX) THEN
      e := RawContent(r + 1, FALSE, ts, te, ~noTrim, b);
      IF e >= 0 THEN A.AddBlock(out, A.NewCodeBlock(a, B.BufRope(b))) END
    END
  ELSIF k = "verse" THEN
    r := IgnHeaders(te);
    IF r >= 0 THEN e := Verse(r, ts, te, out) END
  ELSIF k = "src" THEN
    e := SrcBlock(te, ts, te, ba, out)
  ELSE
    a := NIL;
    IF (k = "quote") OR (k = "note") OR (k = "warning") OR (k = "tip")
        OR (k = "caution") OR (k = "important") OR Is(ts, te, "abstract") THEN
      r := IgnHeaders(te)
    ELSE
      a := DivAttr(ba); A.AddClass(a, B.Rope(ts, te));
      r := BlockParameters(te, a)
    END;
    IF r >= 0 THEN e := RawContent(r, FALSE, ts, te, TRUE, b) END;
    IF e >= 0 THEN
      IF a # NIL THEN I.Unknown("Unknown block", B.Rope(ts - 8, te), ts - 8) END;
      I.Origin(I.OrgLines, rawA, rawB);
      ParseBlocks(b, cont);
      IF a # NIL THEN A.AddBlock(out, A.NewDiv(a, cont.first))
      ELSIF k = "quote" THEN A.AddBlock(out, A.NewBlockQuote(cont.first))
      ELSIF Is(ts, te, "abstract") THEN
        A.SetMeta(meta, A.S("abstract"), A.NewMetaBlocks(cont.first))
      ELSE (* admonitionBlock *)
        a := A.NewAttr(NIL); A.AddClass(a, A.S("title"));
        k[0] := CAP(k[0]);
        title := A.NewDiv(a, A.NewInlinesBlock(A.Para, A.NewStr(A.S(k))));
        title.next := cont.first;
        k[0] := B.Lower(k[0]);
        a := A.NewAttr(ba.name); A.AddClass(a, A.S(k));
        A.AddBlock(out, A.NewDiv(a, title))
      END
    END
  END;
  IF e < 0 THEN RETURN FALSE END;
  IF out.first # NIL THEN A.AddBlock(l, out.first) END;
  B.pos := e;
  RETURN TRUE
END OrgBlock;

(* figure: an image alone in its paragraph, [[src]], with its block
   attributes; a Figure if it has a caption *)
PROCEDURE Figure(VAR l: A.Blocks): BOOLEAN;
  VAR ba: BlockAttrs; q, s, e, r: LONGINT; src: A.Rope; ok: BOOLEAN;
    c: A.Block; a: A.Attr; ch: CHAR;
BEGIN
  q := Attributes(B.pos, ba);
  IF q < 0 THEN RETURN FALSE END;
  q := B.SkipSpaces(q);
  IF ~B.Looking(q, "[[") THEN RETURN FALSE END;
  s := q + 2; e := s;
  LOOP
    ch := B.C(e);
    IF (e >= B.len) OR (ch = 0AX) OR (ch = 0DX) OR (ch = "[") OR (ch = "]") THEN
      EXIT
    END;
    INC(e)
  END;
  IF (e = s) OR ~B.Looking(e, "]]") THEN RETURN FALSE END;
  r := B.SkipSpaces(e + 2);
  IF (B.C(r) # 0AX) OR ~I.EndOfBlock(r + 1) THEN RETURN FALSE END;
  src := I.CleanLink(s, e, ok);
  IF ~ok OR ~I.IsImage(s, e) THEN RETURN FALSE END;
  a := A.NewAttr(ba.name); a.attrs := ba.kv.attrs;
  IF ba.hasCaption THEN
    c := NIL;
    IF ba.caption # NIL THEN c := A.NewInlinesBlock(A.Plain, ba.caption) END;
    A.AddBlock(l, A.NewFigure(a, c, A.NewInlinesBlock(A.Plain,
      A.NewLink(A.Image, A.NewAttr(NIL), NIL, src, A.S("")))))
  ELSE
    A.AddBlock(l, A.NewInlinesBlock(A.Para,
      A.NewLink(A.Image, a, NIL, src, ba.name)))
  END;
  B.pos := r + 1; I.Newline;
  RETURN TRUE
END Figure;

(* dynamicBlock: #+begin: name parameters ... #+end:, a Div *)
PROCEDURE DynamicBlock(VAR l: A.Blocks): BOOLEAN;
  VAR q, r, e: LONGINT; a: A.Attr; b: B.Buf; out: A.Blocks;
BEGIN
  q := I.MetaLineStart(B.pos);
  IF (q < 0) OR ~LookingCI(q, "begin:") THEN RETURN FALSE END;
  INC(q, 6);
  WHILE (q < B.len) & B.IsWhite(B.t[q]) DO INC(q) END;
  a := A.NewAttr(NIL);
  r := I.ArgWord(q);
  IF r >= 0 THEN A.AddClass(a, B.Rope(q, r)); q := r END;
  r := BlockParameters(q, a);
  IF r < 0 THEN RETURN FALSE END;
  e := RawContent(r, TRUE, 0, 0, TRUE, b);
  IF e < 0 THEN RETURN FALSE END;
  I.Origin(I.OrgLines, rawA, rawB);
  ParseBlocks(b, out);
  A.AddBlock(l, A.NewDiv(a, out.first));
  B.pos := e;
  RETURN TRUE
END DynamicBlock;

(* drawerEnd: :END: alone on a line, in any case; where it ends, past
   its new line, or -1 *)
PROCEDURE DrawerEnd(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF ~LookingCI(p, ":end:") THEN RETURN -1 END;
  p := B.SkipSpaces(p + 5);
  IF B.C(p) = 0AX THEN RETURN p + 1 END;
  RETURN -1
END DrawerEnd;

(* genericDrawer: :NAME: ... :END:, a Div of its blocks if the
   export setting d: keeps it *)
PROCEDURE Drawer(VAR l: A.Blocks): BOOLEAN;
  VAR q, r, s, e: LONGINT; name: A.Rope; d: A.StrList; b: B.Buf;
    out: A.Blocks; a: A.Attr; keep: BOOLEAN;
BEGIN
  q := I.DrawerStart(B.pos);
  IF q < 0 THEN RETURN FALSE END;
  s := B.SkipSpaces(B.pos) + 1; e := s;
  WHILE B.t[e] # ":" DO INC(e) END;
  r := q;
  LOOP
    IF DrawerEnd(r) >= 0 THEN EXIT END;
    r := B.AnyLine(r);
    IF r < 0 THEN RETURN FALSE END
  END;
  name := CaseRope(s, e, TRUE);
  d := M.drawers;
  WHILE (d # NIL) & ~Ropes.Equal(d.s, name) DO d := d.next END;
  keep := ~Ropes.EqualString(name, "PROPERTIES") & ((d = NIL) = M.drawersExcept);
  IF keep THEN
    B.InitBuf(b); B.Put(b, q, r);
    I.Origin(I.OrgOffset, q, 0);
    ParseBlocks(b, out);
    a := A.NewAttr(NIL); A.AddClass(a, name); A.AddClass(a, A.S("drawer"));
    A.AddBlock(l, A.NewDiv(a, out.first))
  END;
  B.pos := DrawerEnd(r);
  IF ~keep THEN I.Newline END;
  RETURN TRUE
END Drawer;

(* B.text: t[from .. to-1] as words, spaces and soft breaks *)
PROCEDURE TextInlines(from, to: LONGINT): A.Inline;
  VAR l: A.Inlines; p, q: LONGINT; nl: BOOLEAN;
BEGIN
  A.InitInlines(l); p := from;
  WHILE p < to DO
    q := p;
    IF B.IsWhite(B.t[p]) THEN
      nl := FALSE;
      WHILE (q < to) & B.IsWhite(B.t[q]) DO
        IF B.t[q] = 0AX THEN nl := TRUE END;
        INC(q)
      END;
      IF nl THEN A.AddInline(l, A.NewSimple(A.SoftBreak))
      ELSE A.AddInline(l, A.NewSimple(A.Space))
      END
    ELSE
      WHILE (q < to) & ~B.IsWhite(B.t[q]) DO INC(q) END;
      A.AddInline(l, A.NewStr(B.Rope(p, q)))
    END;
    p := q
  END;
  RETURN l.first
END TextInlines;

(* latexFragment: a LaTeX environment, \begin{name} ... \end{name} and
   a blank line, as the export setting tex: says *)
PROCEDURE LatexFragment(VAR l: A.Blocks): BOOLEAN;
  VAR s, q, r, e, n, i: LONGINT; found: BOOLEAN; b: B.Buf;
BEGIN
  q := I.LatexEnvStart(B.pos);
  IF q < 0 THEN RETURN FALSE END;
  s := B.SkipSpaces(B.pos);
  n := q - 1 - (s + 7); (* the name's length *)
  r := q; found := FALSE;
  WHILE ~found & (r < B.len) DO
    IF B.Looking(r, "\end{") & (B.C(r + 5 + n) = "}") THEN
      i := 0;
      WHILE (i < n) & (B.t[r + 5 + i] = B.t[s + 7 + i]) DO INC(i) END;
      found := (i = n) & (B.BlankLine(r + 6 + n) >= 0)
    END;
    IF ~found THEN INC(r) END
  END;
  IF ~found THEN RETURN FALSE END;
  e := r + 6 + n;
  IF M.latex = M.TexExport THEN
    B.InitBuf(b); B.Put(b, s, e); B.PutChar(b, 0AX);
    A.AddBlock(l, A.NewRawBlock(A.S("latex"), B.BufRope(b)))
  ELSIF M.latex = M.TexVerbatim THEN
    A.AddBlock(l, A.NewInlinesBlock(A.Para, TextInlines(s, e)))
  END;
  B.pos := B.BlankLine(e);
  RETURN TRUE
END LatexFragment;

(* noteBlock: a footnote's definition, [fn:name] or [1] and its
   blocks, kept for its references *)
PROCEDURE NoteBlock(VAR l: A.Blocks): BOOLEAN;
  VAR p, q, n, r: LONGINT; nl: A.Blocks;
BEGIN
  p := B.pos;
  q := I.NoteMarker(p);
  IF q < 0 THEN RETURN FALSE END;
  B.pos := B.SkipSpaces(q); I.SetPre;
  A.InitBlocks(nl);
  IF ~Block(nl) THEN B.pos := p; RETURN FALSE END;
  LOOP
    r := B.BlankLine(B.pos);
    IF (B.pos >= B.len) OR (I.NoteMarker(B.pos) >= 0)
        OR (I.HeaderStart(B.pos, n) >= 0)
        OR (r >= 0) & (B.BlankLine(r) >= 0) THEN
      EXIT
    END;
    IF ~Block(nl) THEN B.pos := p; RETURN FALSE END
  END;
  I.AddNote(B.Rope(p + 1, q - 1), nl.first);
  RETURN TRUE
END NoteBlock;

(* blockLines: a #+begin_ block in a list item's continuation at p,
   its attributes and start indented by n spaces, put into b as it
   is; where it ends, before the rest of its last line, or -1 *)
PROCEDURE BlockLines(p, n: LONGINT; VAR b: B.Buf): LONGINT;
  VAR q, r, saved, e: LONGINT; ba: BlockAttrs; l: A.Blocks; ok: BOOLEAN;
BEGIN
  q := ListLine(p, n);
  IF q < 0 THEN RETURN -1 END;
  r := Attributes(q, ba);
  IF r < 0 THEN RETURN -1 END;
  IF A.IsEmptyAttr(DivAttr(ba)) THEN
    IF r >= B.len THEN RETURN -1 END
  ELSIF ListLine(r, n) < 0 THEN RETURN -1
  END;
  saved := B.pos; B.pos := p; A.InitBlocks(l);
  ok := OrgBlock(l); e := B.pos; B.pos := saved;
  IF ~ok THEN RETURN -1 END;
  B.Put(b, p, e);
  RETURN e
END BlockLines;

(* listContinuation': a block's lines, or a line with its first n
   spaces taken away, into b; where it ends, or -1 *)
PROCEDURE Continuation(p, n: LONGINT; VAR b: B.Buf): LONGINT;
  VAR r, e: LONGINT;
BEGIN
  e := BlockLines(p, n, b);
  IF e >= 0 THEN RETURN e END;
  r := ListLine(p, n);
  IF r < 0 THEN RETURN -1 END;
  e := B.LineEnd(r); B.Put(b, r, e); B.PutChar(b, 0AX);
  RETURN NextLine(e)
END Continuation;


(* An item's text into b, from q, the rest of its first line: that
   line, a blank line after it, and its continuation lines, each
   without its first n spaces (listContinuation), with the blank lines
   after them. B.pos is left after them. *)
PROCEDURE ItemText(q, n: LONGINT; VAR b: B.Buf);
  VAR p, r, e: LONGINT;
BEGIN
  B.InitBuf(b);
  e := B.LineEnd(q); B.Put(b, q, e); B.PutChar(b, 0AX);
  p := NextLine(e);
  r := B.BlankLine(p);
  IF r >= 0 THEN B.PutChar(b, 0AX); p := r END;
  LOOP
    IF B.BlankLine(p) >= 0 THEN EXIT END;
    r := Continuation(p, n, b);
    IF r < 0 THEN EXIT END;
    REPEAT p := r; r := Continuation(p, n, b) UNTIL r < 0;
    r := B.BlankLine(p);
    WHILE r >= 0 DO B.PutChar(b, 0AX); p := r; r := B.BlankLine(p) END
  END;
  B.pos := p
END ItemText;

(* Puts box, then a Space, before the first block's inlines if it is a
   Plain or Para, else a Plain of them first (prependInlines). *)
PROCEDURE Prepend(VAR l: A.Blocks; box: ARRAY OF CHAR);
  VAR s, sp: A.Inline; b: A.Block;
BEGIN
  s := A.NewStr(A.S(box)); sp := A.NewSimple(A.Space); s.next := sp;
  b := l.first;
  IF (b # NIL) & ((b.kind = A.Plain) OR (b.kind = A.Para)) THEN
    sp.next := b(A.InlinesBlk).inlines; b(A.InlinesBlk).inlines := s
  ELSE
    b := A.NewInlinesBlock(A.Plain, s);
    b.next := l.first; l.first := b;
    IF l.last = NIL THEN l.last := b END
  END
END Prepend;

(* listItem: an item whose marker is at least minIndent in, its blocks
   in item *)
PROCEDURE ListItem(ordered: BOOLEAN; minIndent: LONGINT; VAR item: A.BlockList): BOOLEAN;
  VAR q, n, start: LONGINT; style, delim: INTEGER; box: CHAR; b: B.Buf;
    f: B.Frame; l: A.Blocks; saved: BOOLEAN;
BEGIN
  q := I.ListMarker(B.pos, ordered, n, start, style, delim);
  IF (q < 0) OR (n < minIndent) OR (B.LineEnd(q) >= B.len) THEN RETURN FALSE END;
  box := 0X;
  IF taskLists & (B.C(q) = "[") & (B.C(q + 2) = "]")
      & ((B.C(q + 1) = " ") OR (B.C(q + 1) = "X") OR (B.C(q + 1) = "-")) THEN
    box := B.C(q + 1); INC(q, 3)
  END;
  ItemText(q, n, b);
  saved := inList; inList := TRUE;
  I.Origin(I.OrgLines, q, n);
  I.Enter(f, b.t, b.len);
  A.InitBlocks(l);
  fresh := TRUE;
  IF ParaOrPlain(l) THEN fresh := FALSE END;
  Blocks(l);
  I.Leave(f);
  inList := saved;
  IF box = "X" THEN Prepend(l, "☒")
  ELSIF box # 0X THEN Prepend(l, "☐")
  END;
  NEW(item); item.blocks := l.first; item.next := NIL;
  RETURN TRUE
END ListItem;

(* Whether b, or a block after it, is a Para *)
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

(* bulletList or orderedList: items at least as far in as the first *)
PROCEDURE List(ordered: BOOLEAN; VAR l: A.Blocks): BOOLEAN;
  VAR n, start: LONGINT; style, delim: INTEGER; first, last, item: A.BlockList;
BEGIN
  IF I.ListMarker(B.pos, ordered, n, start, style, delim) < 0 THEN RETURN FALSE END;
  first := NIL; last := NIL;
  WHILE ListItem(ordered, n, item) DO
    IF first = NIL THEN first := item ELSE last.next := item END;
    last := item
  END;
  IF first = NIL THEN RETURN FALSE END;
  Compactify(first);
  IF ordered THEN A.AddBlock(l, A.NewOrderedList(start, style, delim, first))
  ELSE A.AddBlock(l, A.NewBulletList(first))
  END;
  RETURN TRUE
END List;

(* definitionMarker at p: a space, ::, and a space (consumed) or a new
   line. Where it ends, or -1. *)
PROCEDURE DefinitionMarker(p: LONGINT): LONGINT;
BEGIN
  IF B.IsSpace(B.C(p)) & B.Looking(p + 1, "::") THEN
    IF B.IsSpace(B.C(p + 3)) THEN RETURN p + 4
    ELSIF B.C(p + 3) = 0AX THEN RETURN p + 3
    END
  END;
  RETURN -1
END DefinitionMarker;

(* The inlines of t[from .. to-1] of the current text, or NIL if there
   are none: parseFromString inlines *)
PROCEDURE InlinesOf(from, to: LONGINT; VAR ok: BOOLEAN): A.Inline;
  VAR b: B.Buf; f: B.Frame; i: A.Inline;
BEGIN
  B.InitBuf(b); B.Put(b, from, to);
  I.Origin(I.OrgOffset, from, 0);
  I.Enter(f, b.t, b.len);
  i := I.Inlines();
  ok := B.pos > 0;
  I.Leave(f);
  RETURN i
END InlinesOf;

(* definitionListItem: - term :: definition *)
PROCEDURE DefinitionItem(minIndent: LONGINT; VAR item: A.DefItem): BOOLEAN;
  VAR p, q, r, n, start: LONGINT; style, delim: INTEGER; ch: CHAR; b: B.Buf;
    f: B.Frame; l: A.Blocks; term: A.Inline; ok: BOOLEAN;
BEGIN
  p := B.pos;
  q := I.ListMarker(p, FALSE, n, start, style, delim);
  IF (q < 0) OR (n < minIndent) THEN RETURN FALSE END;
  r := q;
  LOOP
    IF DefinitionMarker(r) >= 0 THEN EXIT END;
    ch := B.C(r);
    IF (r >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN RETURN FALSE END;
    INC(r)
  END;
  IF B.LineEnd(r) >= B.len THEN RETURN FALSE END;
  term := InlinesOf(q, r, ok);
  IF ~ok THEN RETURN FALSE END;
  q := DefinitionMarker(r);
  ItemText(q, n, b);
  I.Origin(I.OrgLines, q, n);
  I.Enter(f, b.t, b.len);
  A.InitBlocks(l);
  fresh := TRUE;
  Blocks(l);
  I.Leave(f);
  NEW(item); item.term := term; item.next := NIL;
  NEW(item.defs); item.defs.blocks := l.first; item.defs.next := NIL;
  RETURN TRUE
END DefinitionItem;

(* compactifyDL: the last item's last definition's last block a Plain
   if it is its only Para *)
PROCEDURE CompactifyDL(items: A.DefItem);
  VAR d: A.BlockList; final, b: A.Block;
BEGIN
  WHILE items.next # NIL DO items := items.next END;
  d := items.defs;
  IF d = NIL THEN RETURN END;
  WHILE d.next # NIL DO d := d.next END;
  IF d.blocks = NIL THEN RETURN END;
  final := A.LastBlock(d.blocks);
  b := d.blocks;
  WHILE (b # final) & (b.kind # A.Para) DO b := b.next END;
  IF (final.kind = A.Para) & (b = final) THEN final.kind := A.Plain END
END CompactifyDL;

(* definitionList *)
PROCEDURE DefinitionList(VAR l: A.Blocks): BOOLEAN;
  VAR n, start: LONGINT; style, delim: INTEGER; first, last, item: A.DefItem;
    p: LONGINT;
BEGIN
  p := B.pos;
  IF I.ListMarker(p, FALSE, n, start, style, delim) < 0 THEN RETURN FALSE END;
  first := NIL; last := NIL;
  WHILE DefinitionItem(n, item) DO
    IF first = NIL THEN first := item ELSE last.next := item END;
    last := item
  END;
  IF first = NIL THEN B.pos := p; RETURN FALSE END;
  CompactifyDL(first);
  A.AddBlock(l, A.NewDefinitionList(first));
  RETURN TRUE
END DefinitionList;

(* Tables *)

(* align and width with room for more than n *)
PROCEDURE Grow(VAR align: Ints; VAR width: Reals; n: LONGINT);
  VAR a: Ints; w: Reals; k: LONGINT;
BEGIN
  NEW(a, 2 * n + 8); NEW(w, 2 * n + 8);
  FOR k := 0 TO n - 1 DO a[k] := align[k]; w[k] := width[k] END;
  align := a; width := w
END Grow;

(* A cell holding the inlines i, as B.simpleCell (B.plain i) *)
PROCEDURE NewCell(i: A.Inline): A.Cell;
  VAR c: A.Cell;
BEGIN
  c := SH.EmptyCell();
  IF i # NIL THEN c.blocks := A.NewInlinesBlock(A.Plain, i) END;
  RETURN c
END NewCell;

(* tableContentRow at p, a table's line: where it ends, past its new
   line, or -1; its cells in r. Each cell is inlines up to a | or the
   new line, trimmed (tableContentCell). *)
PROCEDURE ContentRow(p: LONGINT; VAR r: A.Row): LONGINT;
  VAR il: A.Inlines; c, last: A.Cell; ch: CHAR;
BEGIN
  NEW(r); r.attr := NIL; r.cells := NIL; r.next := NIL; last := NIL;
  B.pos := I.TableStart(p);
  WHILE B.C(B.pos) # 0AX DO
    A.InitInlines(il);
    LOOP (* manyTill inline endOfCell *)
      ch := B.C(B.pos);
      IF ch = "|" THEN INC(B.pos); EXIT
      ELSIF ch = 0AX THEN EXIT
      ELSIF ~I.Inline(il) THEN RETURN -1
      END
    END;
    c := NewCell(MI.Trim(il));
    IF last = NIL THEN r.cells := c ELSE last.next := c END;
    last := c
  END;
  INC(B.pos); I.Newline;
  RETURN B.pos
END ContentRow;

(* tableAlignRow at p, a table's line: where it ends, past its new
   line, or -1 if it is not one or every cell is empty; each cell's
   alignment and width, -1 for none, in align and width, n of them *)
PROCEDURE AlignRow(p: LONGINT; VAR align: Ints; VAR width: Reals; VAR n: LONGINT): LONGINT;
  VAR q, r: LONGINT; a: INTEGER; w: LONGREAL; set: BOOLEAN;
BEGIN
  q := I.TableStart(p); n := 0; set := FALSE;
  REPEAT (* many1Till columnPropertyCell newline *)
    a := A.AlignDefault; w := -1;
    r := B.SkipSpaces(q);
    IF B.C(r) = "<" THEN (* propCell *)
      INC(r);
      CASE B.C(r) OF
        "l": a := A.AlignLeft; INC(r)
      | "c": a := A.AlignCenter; INC(r)
      | "r": a := A.AlignRight; INC(r)
      ELSE
      END;
      IF B.IsDigit(B.C(r)) THEN
        w := 0;
        REPEAT w := w * 10 + (ORD(B.C(r)) - ORD("0")); INC(r) UNTIL ~B.IsDigit(B.C(r))
      END;
      IF B.C(r) # ">" THEN RETURN -1 END;
      r := B.SkipSpaces(r + 1);
      set := set OR (a # A.AlignDefault) OR (w >= 0)
    END;
    (* emptyOrgCell *)
    IF B.C(r) = "|" THEN q := r + 1
    ELSIF B.C(r) = 0AX THEN q := r
    ELSE RETURN -1
    END;
    IF (align = NIL) OR (n >= LEN(align^)) THEN Grow(align, width, n) END;
    align[n] := a; width[n] := w; INC(n)
  UNTIL B.C(q) = 0AX;
  IF ~set THEN RETURN -1 END;
  I.NewlineAt(q + 1);
  RETURN q + 1
END AlignRow;

(* The number of cells of r *)
PROCEDURE CellCount(r: A.Row): LONGINT;
  VAR c: A.Cell; n: LONGINT;
BEGIN
  n := 0;
  IF r # NIL THEN c := r.cells; WHILE c # NIL DO INC(n); c := c.next END END;
  RETURN n
END CellCount;

(* orgTable at p: an Org table's rows, rowsToTable, normalizeTable and
   orgToPandocTable; where it ends, or -1 if no row is read. The rows
   are read in one pass: a rule after the only content row makes it
   the header, other rules are dropped, and the last alignment row
   gives the columns' alignments and widths. *)
PROCEDURE OrgTable(p: LONGINT; VAR t: A.TableBlk): LONGINT;
  VAR head, first, last, r: A.Row; nBody, k, n, cols, q, p0: LONGINT;
    align, al: Ints; width, wd: Reals; total, x: LONGREAL; any: BOOLEAN;
    cs, csLast: A.ColSpec; tb: A.TableBody; s: I.State;
BEGIN
  IF I.TableStart(p) < 0 THEN RETURN -1 END;
  p0 := p; head := NIL; first := NIL; last := NIL; nBody := 0;
  align := NIL; width := NIL; n := 0; al := NIL; wd := NIL;
  LOOP (* tableRows *)
    IF I.TableStart(p) < 0 THEN EXIT END;
    q := AlignRow(p, al, wd, k);
    IF q >= 0 THEN (* setProperties *)
      align := al; width := wd; n := k; al := NIL; wd := NIL
    ELSIF B.C(I.TableStart(p)) = "-" THEN (* tableHline *)
      q := B.AnyLine(I.TableStart(p) + 1);
      IF q < 0 THEN EXIT END;
      I.NewlineAt(q);
      IF (CellCount(head) = 0) & (nBody = 1) THEN
        head := first; first := NIL; last := NIL; nBody := 0
      END
    ELSE
      I.Save(s);
      q := ContentRow(p, r);
      IF q < 0 THEN I.Restore(s); EXIT END;
      IF last = NIL THEN first := r ELSE last.next := r END;
      last := r; INC(nBody)
    END;
    p := q
  END;
  IF p = p0 THEN RETURN -1 END; (* no row: tableRows' many reads nothing *)
  B.pos := p;
  (* normalizeTable *)
  IF CellCount(head) > 0 THEN cols := CellCount(head) ELSE cols := CellCount(first) END;
  any := FALSE; total := 0;
  FOR k := 0 TO cols - 1 DO
    IF (k < n) & (width[k] >= 0) THEN any := TRUE; total := total + width[k]
    ELSE total := total + 1
    END
  END;
  t := A.NewTable(NIL); csLast := NIL;
  FOR k := 0 TO cols - 1 DO
    NEW(cs); cs.next := NIL; cs.align := A.AlignDefault; cs.hasWidth := FALSE;
    IF k < n THEN
      cs.align := align[k];
      (* 0 / 0 is NaN in pandoc: podoc gives ColWidthDefault *)
      IF any & (width[k] >= 0) & (total > 0) THEN
        x := width[k]; cs.width := x / total; cs.hasWidth := TRUE
      END
    END;
    IF csLast = NIL THEN t.colSpecs := cs ELSE csLast.next := cs END;
    csLast := cs
  END;
  IF CellCount(head) > 0 THEN head.next := NIL; t.head.rows := head END;
  NEW(tb); tb.attr := NIL; tb.rowHeadColumns := 0; tb.head := NIL;
  tb.body := first; tb.next := NIL; t.bodies := tb;
  SH.PlaceRows(t.head.rows, cols); SH.PlaceRows(tb.body, cols);
  RETURN p
END OrgTable;

(* The blocks of a grid table cell's text (parseFromString' blocks:
   orgStateLastPreCharPos is kept) *)
PROCEDURE CellBlocks(VAR b: B.Buf): A.Block;
  VAR f: B.Frame; l: A.Blocks; saved: BOOLEAN; str: I.Pos;
BEGIN
  saved := fresh;
  I.ClearStr(str);
  I.Push(f, b.t, b.len);
  A.InitBlocks(l);
  Blocks(l);
  B.Leave(f);
  I.RestoreStr(str);
  fresh := saved;
  RETURN l.first
END CellBlocks;

(* The rows of the traced g, from row from to row to-1, in order *)
PROCEDURE GridRows(VAR g: G.Table; from, to: LONGINT): A.Row;
  VAR first, last, r: A.Row; c, clast: A.Cell; x: G.Cell; i, j: LONGINT;
BEGIN
  first := NIL; last := NIL;
  FOR i := from TO to - 1 DO
    NEW(r); r.attr := NIL; r.cells := NIL; r.next := NIL; clast := NIL;
    FOR j := 0 TO g.cols - 1 DO
      x := g.cells[i * g.cols + j];
      IF x # NIL THEN
        c := SH.EmptyCell(); c.rowSpan := x.rowSpan; c.colSpan := x.colSpan;
        c.blocks := CellBlocks(x.text);
        IF clast = NIL THEN r.cells := c ELSE clast.next := c END;
        clast := c
      END
    END;
    IF last = NIL THEN first := r ELSE last.next := r END;
    last := r
  END;
  RETURN first
END GridRows;

(* gridTableWith blocks at p, a table.el table, and the blank lines
   after it: where it ends, or -1 *)
PROCEDURE GridTable(p: LONGINT; VAR t: A.TableBlk): LONGINT;
  VAR g: G.Table; q, k, bodyEnd, total, norm: LONGINT; cs, last: A.ColSpec;
    tb: A.TableBody; x: LONGREAL;
BEGIN
  IF p >= B.len THEN RETURN -1 END;
  q := G.Trace(p, 0, g);
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
    x := g.width[k] + 1; cs.width := x / norm; cs.hasWidth := TRUE;
    IF last = NIL THEN t.colSpecs := cs ELSE last.next := cs END;
    last := cs
  END;
  IF g.headLen > g.rows THEN g.headLen := g.rows END;
  B.pos := q;
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
  SH.PlaceRows(t.head.rows, g.cols);
  SH.PlaceRows(tb.body, g.cols);
  SH.PlaceRows(t.foot.rows, g.cols);
  q := B.BlankLines(q); IF q < 0 THEN q := B.pos END;
  RETURN q
END GridTable;

(* Whether every cell of the rows r is empty, a Para or a Plain *)
PROCEDURE SimpleRows(r: A.Row): BOOLEAN;
  VAR c: A.Cell;
BEGIN
  WHILE r # NIL DO
    c := r.cells;
    WHILE c # NIL DO
      IF (c.blocks # NIL) & ((c.blocks.next # NIL)
          OR (c.blocks.kind # A.Para) & (c.blocks.kind # A.Plain)) THEN
        RETURN FALSE
      END;
      c := c.next
    END;
    r := r.next
  END;
  RETURN TRUE
END SimpleRows;

(* Each cell's Para of the rows r a Plain *)
PROCEDURE PlainRows(r: A.Row);
  VAR c: A.Cell;
BEGIN
  WHILE r # NIL DO
    c := r.cells;
    WHILE c # NIL DO
      IF c.blocks # NIL THEN c.blocks.kind := A.Plain END;
      c := c.next
    END;
    r := r.next
  END
END PlainRows;

(* compactifyTable: if every cell of t is empty or a lone Para or
   Plain, each Para becomes a Plain *)
PROCEDURE CompactifyTable(t: A.TableBlk);
  VAR tb: A.TableBody;
BEGIN
  IF ~SimpleRows(t.head.rows) OR ~SimpleRows(t.foot.rows) THEN RETURN END;
  tb := t.bodies;
  WHILE tb # NIL DO
    IF ~SimpleRows(tb.head) OR ~SimpleRows(tb.body) THEN RETURN END;
    tb := tb.next
  END;
  PlainRows(t.head.rows); PlainRows(t.foot.rows);
  tb := t.bodies;
  WHILE tb # NIL DO PlainRows(tb.head); PlainRows(tb.body); tb := tb.next END
END CompactifyTable;

(* table: block attributes, then a table.el or an Org table; nothing
   if #+OPTIONS: has |:nil. Not on a list item's first line, nor
   after a list in one (orgStateLastPreCharPos is Nothing). *)
PROCEDURE Table(VAR l: A.Blocks): BOOLEAN;
  VAR p, q: LONGINT; ba: BlockAttrs; t: A.TableBlk;
BEGIN
  IF inList & fresh THEN RETURN FALSE END;
  p := Attributes(B.pos, ba);
  IF p < 0 THEN RETURN FALSE END;
  q := GridTable(p, t);
  IF q < 0 THEN q := OrgTable(p, t) END;
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  IF M.tables THEN
    t.attr := A.NewAttr(ba.name); t.attr.attrs := ba.kv.attrs;
    IF ba.hasCaption & (ba.caption # NIL) THEN
      t.caption.blocks := A.NewInlinesBlock(A.Plain, ba.caption)
    END;
    CompactifyTable(t);
    A.AddBlock(l, t)
  END;
  RETURN TRUE
END Table;

(* block: one block at B.pos, added to l; FALSE if there is none *)
PROCEDURE Block(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT; s: I.State;

  (* The state as it was before an alternative that failed *)
  PROCEDURE R(): BOOLEAN;
  BEGIN
    I.Restore(s); RETURN TRUE
  END R;

BEGIN
  q := B.BlankLines(B.pos);
  IF q >= 0 THEN B.pos := q; I.Newline; fresh := FALSE; RETURN TRUE END;
  I.Save(s);
  IF Table(l) OR R() & DynamicBlock(l) OR R() & OrgBlock(l)
      OR R() & Figure(l) OR R() & Example(l) OR R() & Drawer(l)
      OR R() & Include(l) OR R() & SpecialLine(l) THEN
    fresh := FALSE; RETURN TRUE
  END;
  I.Restore(s);
  q := I.Hline(B.pos);
  IF q >= 0 THEN
    A.AddBlock(l, A.NewHorizontalRule()); B.pos := q; I.Newline;
    fresh := FALSE;
    RETURN TRUE
  END;
  IF DefinitionList(l) OR R() & List(FALSE, l) OR R() & List(TRUE, l) THEN
    fresh := TRUE; RETURN TRUE (* its items' parseFromString *)
  END;
  I.Restore(s);
  IF LatexFragment(l) OR R() & NoteBlock(l) OR R() & RawOrgLine(l)
      OR R() & ParaOrPlain(l) THEN
    fresh := FALSE; RETURN TRUE
  END;
  I.Restore(s);
  RETURN FALSE
END Block;

(* blocks: blocks up to a headline or the end of the text *)
PROCEDURE Blocks(VAR l: A.Blocks);
  VAR n: LONGINT;
BEGIN
  WHILE (B.pos < B.len) & (I.HeaderStart(B.pos, n) < 0) & Block(l) DO END
END Blocks;

(* The headline tree *)

(* Identifiers *)

PROCEDURE Bucket(key: A.Rope): LONGINT;
BEGIN
  RETURN SHORT(Ropes.Hash(key) MOD IdTableSize)
END Bucket;

(* The slot of the identifier id, NIL if it has not been used *)
PROCEDURE Find(id: A.Rope): IdSlot;
  VAR s: IdSlot;
BEGIN
  s := idTable[Bucket(id)];
  WHILE (s # NIL) & ~Ropes.Equal(s.key, id) DO s := s.next END;
  RETURN s
END Find;

(* Records id as used. *)
PROCEDURE Use(id: A.Rope);
  VAR s: IdSlot; b: LONGINT;
BEGIN
  IF Find(id) = NIL THEN
    b := Bucket(id);
    NEW(s); s.key := id; s.n := 0; s.next := idTable[b]; idTable[b] := s
  END
END Use;

(* uniqueIdent: the identifier of title, or it with -1, -2, ... if it
   has been used; section if it is empty. It is recorded as used. *)
PROCEDURE UniqueId(title: A.Inline): A.Rope;
  VAR base, id: A.Rope; s: IdSlot;
BEGIN
  base := MI.IdentifierExt(title, gfmIds, asciiIds);
  IF Ropes.Length(base) = 0 THEN base := A.S("section") END;
  s := Find(base);
  IF s = NIL THEN Use(base); RETURN base END;
  (* the suffixes before s.n + 1 are used already *)
  REPEAT
    INC(s.n);
    id := Ropes.Cat(Ropes.Cat(base, A.S("-")), SH.IntRope(s.n))
  UNTIL (Find(id) = NIL) OR (s.n >= 60000);
  IF Find(id) # NIL THEN RETURN base END;
  Use(id);
  RETURN id
END UniqueId;

(* Parsing *)

(* The default TODO keywords: TODO, then DONE *)
PROCEDURE NewDefaultMarkers(): Marker;
  VAR m: Marker;

  PROCEDURE New(name: ARRAY OF CHAR; done: BOOLEAN; next: Marker): Marker;
    VAR m: Marker; i: LONGINT;
  BEGIN
    NEW(m); m.name := A.S(name); m.done := done; m.next := next;
    i := 0; WHILE name[i] # 0X DO INC(i) END;
    m.len := i; NEW(m.s, i + 1);
    i := 0; WHILE name[i] # 0X DO m.s[i] := name[i]; INC(i) END;
    m.s[i] := 0X;
    RETURN m
  END New;

BEGIN
  m := New("DONE", TRUE, NIL);
  RETURN New("TODO", FALSE, m)
END NewDefaultMarkers;

(* Whether c, not ASCII, is a letter or a number *)
PROCEDURE IsAlnumRune(c: Utf8.Rune): BOOLEAN;
BEGIN
  RETURN Unicode.IsLetter(c) OR Unicode.IsNumber(c)
END IsAlnumRune;

(* orgTagWord: letters, numbers and @%#_; where it ends, or -1 *)
PROCEDURE TagWord(p: LONGINT): LONGINT;
  VAR q, r: LONGINT; ch: CHAR; c: Utf8.Rune;
BEGIN
  q := p;
  LOOP
    IF q >= B.len THEN EXIT END;
    ch := B.t[q];
    IF ch < 80X THEN
      IF B.IsAlnum(ch) OR (ch = "@") OR (ch = "%") OR (ch = "#")
          OR (ch = "_") THEN
        INC(q)
      ELSE EXIT
      END
    ELSE
      r := q;
      IF Utf8.Decode(B.t^, r, c) & (r > q) & IsAlnumRune(c) THEN q := r
      ELSE EXIT
      END
    END
  END;
  IF q = p THEN RETURN -1 END;
  RETURN q
END TagWord;

(* Adds s to the list from first to last. *)
PROCEDURE AddStr(VAR first, last: A.StrList; s: A.Rope);
  VAR n: A.StrList;
BEGIN
  NEW(n); n.s := s; n.next := NIL;
  IF first = NIL THEN first := n ELSE last.next := n END;
  last := n
END AddStr;

(* Whether s is in the list l *)
PROCEDURE Member(s: A.Rope; l: A.StrList): BOOLEAN;
BEGIN
  WHILE (l # NIL) & ~Ropes.Equal(l.s, s) DO l := l.next END;
  RETURN l # NIL
END Member;

(* tagList, for #+select_tags (select) and #+exclude_tags: words up to
   the new line. The first such line replaces the default, export or
   noexport; later ones add to it. *)
PROCEDURE TagList(p: LONGINT; select: BOOLEAN): BOOLEAN;
  VAR q, e: LONGINT; first, last, s: A.StrList;
BEGIN
  q := B.SkipSpaces(p); first := NIL; last := NIL;
  LOOP
    e := TagWord(q);
    IF e < 0 THEN EXIT END;
    AddStr(first, last, B.Rope(q, e));
    q := B.SkipSpaces(e)
  END;
  IF B.C(q) # 0AX THEN RETURN FALSE END;
  IF select & ~selectSet THEN selectTags := first; selectSet := TRUE
  ELSIF ~select & ~excludeSet THEN excludeTags := first; excludeSet := TRUE
  ELSE
    WHILE first # NIL DO
      s := first.next;
      IF select THEN first.next := selectTags; selectTags := first
      ELSE first.next := excludeTags; excludeTags := first
      END;
      first := s
    END
  END;
  B.pos := q + 1;
  RETURN TRUE
END TagList;

(* A marker named t[from .. to-1] *)
PROCEDURE NewMarker(from, to: LONGINT; done: BOOLEAN): Marker;
  VAR m: Marker; i: LONGINT;
BEGIN
  NEW(m); m.name := B.Rope(from, to); m.done := done; m.len := to - from;
  NEW(m.s, to - from + 1);
  FOR i := 0 TO to - from - 1 DO m.s[i] := B.t[from + i] END;
  m.s[to - from] := 0X;
  m.next := NIL;
  RETURN m
END NewMarker;

(* todoSequence, for #+todo, #+seq_todo and #+typ_todo: keywords, then
   | and the done keywords; without |, the last keyword is the done
   one. The sequence comes before those registered earlier, and
   replaces the default TODO and DONE. *)
PROCEDURE TodoSequence(p: LONGINT): BOOLEAN;
  VAR q, r: LONGINT; first, last, m: Marker; hasDone: BOOLEAN;

  (* todoDoneSep: spaces, |, and one or more spaces; where it ends, or
     -1 *)
  PROCEDURE Sep(p: LONGINT): LONGINT;
  BEGIN
    p := B.SkipSpaces(p);
    IF (B.C(p) = "|") & B.IsSpace(B.C(p + 1)) THEN
      RETURN B.SkipSpaces(p + 1)
    END;
    RETURN -1
  END Sep;

  (* todoKeyword at q, added to the list; q past it and its spaces *)
  PROCEDURE Word(done: BOOLEAN): BOOLEAN;
    VAR e, c: LONGINT; ch: CHAR; m: Marker;
  BEGIN
    e := q;
    LOOP
      ch := B.C(e);
      IF (e >= B.len) OR (ch = " ") OR (ch = 09X) OR (ch = 0AX)
          OR (ch = 0DX) THEN
        EXIT
      END;
      INC(e)
    END;
    IF e = q THEN RETURN FALSE END;
    c := q;
    WHILE (c < e) & (B.t[c] # "(") DO INC(c) END;
    m := NewMarker(q, c, done);
    IF first = NIL THEN first := m ELSE last.next := m END;
    last := m;
    q := B.SkipSpaces(e);
    RETURN TRUE
  END Word;

BEGIN
  q := p; first := NIL; last := NIL;
  WHILE (Sep(q) < 0) & (B.C(q) # 0AX) DO
    IF ~Word(FALSE) THEN RETURN FALSE END
  END;
  hasDone := FALSE;
  r := Sep(q);
  IF r >= 0 THEN
    hasDone := TRUE; q := r;
    WHILE B.C(q) # 0AX DO
      IF ~Word(TRUE) THEN RETURN FALSE END;
      r := Sep(q);
      IF r >= 0 THEN q := r END
    END
  END;
  IF B.C(q) # 0AX THEN RETURN FALSE END;
  IF ~hasDone THEN
    IF first = NIL THEN RETURN FALSE END;
    last.done := TRUE
  END;
  IF ~customTodo THEN markers := NIL; customTodo := TRUE END;
  IF first # NIL THEN last.next := markers; markers := first END;
  B.pos := q + 1;
  RETURN TRUE
END TodoSequence;

(* endOfTitle at p: spaces, tags :a:b: and spaces, and a new line;
   where it ends, past the new line, with the tags, or -1 *)
PROCEDURE EndOfTitle(p: LONGINT; VAR tags: A.StrList): LONGINT;
  VAR q, r, e: LONGINT; last: A.StrList; ok: BOOLEAN;
BEGIN
  tags := NIL; last := NIL;
  q := B.SkipSpaces(p);
  IF B.C(q) = ":" THEN (* headerTags *)
    r := q + 1; ok := FALSE;
    LOOP
      e := TagWord(r);
      IF e < 0 THEN EXIT END;
      IF B.C(e) # ":" THEN ok := FALSE; EXIT END;
      AddStr(tags, last, B.Rope(r, e)); ok := TRUE;
      r := e + 1
    END;
    IF ok THEN q := B.SkipSpaces(r) ELSE tags := NIL END
  END;
  IF B.C(q) = 0AX THEN RETURN q + 1 END;
  tags := NIL;
  RETURN -1
END EndOfTitle;

(* planningInfo at p: SCHEDULED:, DEADLINE: and CLOSED: and their
   timestamps, then a new line; where it ends, or -1. The first of each
   kind is kept. *)
PROCEDURE Planning(p: LONGINT; h: Headline): LONGINT;
  VAR q, r, e, n, k: LONGINT; close: CHAR; ts, c, d, s: A.Rope;
BEGIN
  q := p; n := 0; c := NIL; d := NIL; s := NIL;
  LOOP
    r := B.SkipSpaces(q);
    IF B.Looking(r, "SCHEDULED:") THEN k := 0; r := r + 10
    ELSIF B.Looking(r, "DEADLINE:") THEN k := 1; r := r + 9
    ELSIF B.Looking(r, "CLOSED:") THEN k := 2; r := r + 7
    ELSIF (n > 0) & (r = q) & (B.C(q) = 0AX) THEN EXIT
    ELSE RETURN -1
    END;
    r := B.SkipSpaces(r);
    IF B.C(r) = "<" THEN close := ">"
    ELSIF B.C(r) = "[" THEN close := "]"
    ELSE RETURN -1
    END;
    IF r + 1 >= B.len THEN RETURN -1 END;
    e := r + 2;
    WHILE (e < B.len) & (B.t[e] # close) DO INC(e) END;
    IF e >= B.len THEN RETURN -1 END;
    ts := B.Rope(r, e + 1);
    IF (k = 0) & (s = NIL) THEN s := ts
    ELSIF (k = 1) & (d = NIL) THEN d := ts
    ELSIF (k = 2) & (c = NIL) THEN c := ts
    END;
    INC(n); q := e + 1
  END;
  h.scheduled := s; h.deadline := d; h.closed := c;
  RETURN q + 1
END Planning;

(* t[from .. to-1] in lower case, as Text's toLower makes it *)
PROCEDURE LowerRope(from, to: LONGINT): A.Rope;
  VAR b: B.Buf; p, q: LONGINT; c: Utf8.Rune;
BEGIN
  B.InitBuf(b); p := from;
  WHILE p < to DO
    q := p;
    IF ~Utf8.Decode(B.t^, q, c) OR (q <= p) OR (q > to) THEN
      B.PutChar(b, B.t[p]); INC(p)
    ELSE
      B.PutUtf8(b, Unicode.ToLower(c)); p := q
    END
  END;
  RETURN B.BufRope(b)
END LowerRope;

(* Whether there is a byte at p, and it is not a space, a tab or a new
   line (nonspaceChar) *)
PROCEDURE NonSpaceChar(p: LONGINT): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  ch := B.C(p);
  RETURN (p < B.len) & (ch # " ") & (ch # 09X) & (ch # 0AX) & (ch # 0DX)
END NonSpaceChar;

(* propertiesDrawer at p: :PROPERTIES:, lines :key: value, and :END:;
   where it ends, past the new line, with the properties in order, or
   -1 *)
PROCEDURE Properties(p: LONGINT; VAR props: Prop): LONGINT;
  VAR q, s, e, k, v, w: LONGINT; first, last, n: Prop;
BEGIN
  q := I.DrawerStart(p);
  IF q < 0 THEN RETURN -1 END;
  s := B.SkipSpaces(p) + 1; e := s;
  WHILE B.t[e] # ":" DO INC(e) END;
  IF (e - s # 10) OR ~LookingCI(s, "properties") THEN RETURN -1 END;
  first := NIL; last := NIL;
  LOOP
    e := DrawerEnd(q);
    IF e >= 0 THEN EXIT END;
    (* the key: :, a nonspace character, then any up to a : and a
       space *)
    k := B.SkipSpaces(q);
    IF (B.C(k) # ":") OR ~NonSpaceChar(k + 1) THEN RETURN -1 END;
    INC(k); e := k + 1;
    WHILE ~((B.C(e) = ":") & B.IsSpace(B.C(e + 1))) DO
      IF ~NonSpaceChar(e) THEN RETURN -1 END;
      INC(e)
    END;
    (* the value: up to spaces and the new line *)
    v := B.SkipSpaces(e + 2);
    w := B.LineEnd(v);
    IF w >= B.len THEN RETURN -1 END;
    q := w + 1;
    WHILE (w > v) & B.IsSpace(B.t[w - 1]) DO DEC(w) END;
    NEW(n); n.key := LowerRope(k, e); n.value := B.Rope(v, w); n.next := NIL;
    IF first = NIL THEN first := n ELSE last.next := n END;
    last := n
  END;
  props := first;
  RETURN e
END Properties;

(* headline: a headline of level lvl or more, its TODO keyword, title,
   tags, planning, properties, blocks and the headlines under it; NIL,
   with B.pos and the state as they were, if there is none *)
PROCEDURE ParseHeadline(lvl: LONGINT): Headline;
  VAR s: I.State; h, c, last: Headline; level, p, q: LONGINT; m: Marker;
    t: A.Inlines; tags: A.StrList; l: A.Blocks; i: LONGINT; ok: BOOLEAN;
BEGIN
  I.Save(s);
  p := I.HeaderStart(B.pos, level);
  IF (p < 0) OR (level < lvl) THEN RETURN NIL END;
  B.pos := p; I.SetPre;
  NEW(h); h.level := level; h.marker := NIL; h.props := NIL;
  h.closed := NIL; h.deadline := NIL; h.scheduled := NIL;
  h.children := NIL; h.next := NIL;
  (* todoKeyword *)
  m := markers; ok := FALSE;
  WHILE (m # NIL) & ~ok DO
    i := 0;
    WHILE (i < m.len) & (B.C(B.pos + i) = m.s[i]) DO INC(i) END;
    ok := (m.len > 0) & (i = m.len) & B.IsSpace(B.C(B.pos + i));
    IF ~ok THEN m := m.next END
  END;
  IF ok THEN h.marker := m; B.pos := B.pos + m.len + 1; I.SetPre END;
  (* the title, up to endOfTitle *)
  A.InitInlines(t);
  LOOP
    q := EndOfTitle(B.pos, tags);
    IF q >= 0 THEN EXIT END;
    IF ~I.Inline(t) THEN I.Restore(s); RETURN NIL END
  END;
  B.pos := q; I.Newline;
  h.title := MI.Trim(t); h.tags := tags;
  q := Planning(B.pos, h);
  IF q >= 0 THEN B.pos := q; I.Newline END;
  q := Properties(B.pos, h.props);
  IF q >= 0 THEN B.pos := q; I.Newline END;
  A.InitBlocks(l); Blocks(l); h.contents := l.first;
  last := NIL;
  LOOP
    c := ParseHeadline(level + 1);
    IF c = NIL THEN EXIT END;
    IF last = NIL THEN h.children := c ELSE last.next := c END;
    last := c
  END;
  RETURN h
END ParseHeadline;

(* documentTree: comment lines, a properties drawer, the blocks before
   the first headline, and the headlines, as the children of a root of
   level 0 *)
PROCEDURE DocumentTree(): Headline;
  VAR root, h, last: Headline; q: LONGINT; l: A.Blocks;
BEGIN
  NEW(root); root.level := 0; root.marker := NIL; root.title := NIL;
  root.tags := NIL; root.closed := NIL; root.deadline := NIL;
  root.scheduled := NIL; root.props := NIL; root.children := NIL;
  root.next := NIL;
  WHILE (B.pos < B.len) & (I.CommentLineStart(B.pos) >= 0) DO
    B.pos := NextLine(B.pos); I.Newline
  END;
  q := Properties(B.pos, root.props);
  IF q >= 0 THEN B.pos := q; I.Newline END;
  A.InitBlocks(l); Blocks(l); root.contents := l.first;
  last := NIL;
  WHILE B.pos < B.len DO
    h := ParseHeadline(1);
    IF h = NIL THEN (* pandoc fails here; podoc passes over the line *)
      B.pos := NextLine(B.pos); I.Newline
    ELSE
      IF last = NIL THEN root.children := h ELSE last.next := h END;
      last := h
    END
  END;
  RETURN root
END DocumentTree;

(* Conversion to blocks *)

(* Whether one of h's tags is in l *)
PROCEDURE HasTag(h: Headline; l: A.StrList): BOOLEAN;
  VAR t: A.StrList;
BEGIN
  t := h.tags;
  WHILE (t # NIL) & ~Member(t.s, l) DO t := t.next END;
  RETURN t # NIL
END HasTag;

(* docContainsSelectTags *)
PROCEDURE ContainsSelect(h: Headline): BOOLEAN;
  VAR c: Headline;
BEGIN
  IF HasTag(h, selectTags) THEN RETURN TRUE END;
  c := h.children;
  WHILE (c # NIL) & ~ContainsSelect(c) DO c := c.next END;
  RETURN c # NIL
END ContainsSelect;

(* The list of headlines from h kept by includeAncestorsAndSelected:
   those with a select tag, whole, and those with such a headline
   under them, with only their children kept *)
PROCEDURE IncludeSelected(h: Headline): Headline;
  VAR first, last, n: Headline;
BEGIN
  first := NIL; last := NIL;
  WHILE h # NIL DO
    n := h.next;
    IF ~HasTag(h, selectTags) THEN h.children := IncludeSelected(h.children) END;
    IF HasTag(h, selectTags) OR (h.children # NIL) THEN
      h.next := NIL;
      IF first = NIL THEN first := h ELSE last.next := h END;
      last := h
    END;
    h := n
  END;
  RETURN first
END IncludeSelected;

(* removeExplicitlyExcludedNodes: the headlines under h with an
   exclude tag dropped *)
PROCEDURE RemoveExcluded(h: Headline);
  VAR c, first, last, n: Headline;
BEGIN
  c := h.children; first := NIL; last := NIL;
  WHILE c # NIL DO
    n := c.next;
    IF ~HasTag(c, excludeTags) THEN
      c.next := NIL; RemoveExcluded(c);
      IF first = NIL THEN first := c ELSE last.next := c END;
      last := c
    END;
    c := n
  END;
  h.children := first
END RemoveExcluded;

(* The first value of property key, NIL if there is none *)
PROCEDURE Property(props: Prop; key: ARRAY OF CHAR): A.Rope;
BEGIN
  WHILE (props # NIL) & ~Ropes.EqualString(props.key, key) DO
    props := props.next
  END;
  IF props = NIL THEN RETURN NIL END;
  RETURN props.value
END Property;

(* propertiesToAttr: the identifier from custom_id or id, the classes
   from class and unnumbered, the other properties as pairs *)
PROCEDURE PropAttr(props: Prop): A.Attr;
  VAR a: A.Attr; id, v: A.Rope; b: B.Buf; i, j, n: LONGINT; ch: CHAR;
BEGIN
  id := Property(props, "custom_id");
  IF id = NIL THEN id := Property(props, "id") END;
  IF id = NIL THEN id := A.S("") END;
  a := A.NewAttr(id);
  v := Property(props, "class");
  IF v # NIL THEN (* its words *)
    n := Ropes.Length(v); i := 0;
    WHILE i < n DO
      WHILE (i < n) & (Ropes.Fetch(v, i) <= " ") DO INC(i) END;
      j := i;
      WHILE (j < n) & (Ropes.Fetch(v, j) > " ") DO INC(j) END;
      IF j > i THEN A.AddClass(a, Ropes.Substring(v, i, j - i)) END;
      i := j
    END
  END;
  v := Property(props, "unnumbered");
  IF v # NIL THEN (* isNonNil *)
    n := Ropes.Length(v); B.InitBuf(b);
    FOR i := 0 TO n - 1 DO
      ch := Ropes.Fetch(v, i); B.PutChar(b, B.Lower(ch))
    END;
    v := B.BufRope(b);
    IF ~Ropes.EqualString(v, "()") & ~Ropes.EqualString(v, "{}")
        & ~Ropes.EqualString(v, "nil") THEN
      A.AddClass(a, A.S("unnumbered"))
    END
  END;
  WHILE props # NIL DO
    IF ~Ropes.EqualString(props.key, "custom_id")
        & ~Ropes.EqualString(props.key, "id")
        & ~Ropes.EqualString(props.key, "class")
        & ~Ropes.EqualString(props.key, "unnumbered") THEN
      A.AddKeyVal(a, props.key, props.value)
    END;
    props := props.next
  END;
  RETURN a
END PropAttr;

(* headlineToHeader: the Header of h, its identifier registered *)
PROCEDURE Header(h: Headline): A.Block;
  VAR t: A.Inlines; a: A.Attr; tag: A.StrList; level: LONGINT;
    nbsp: ARRAY 3 OF CHAR;
BEGIN
  nbsp[0] := 0C2X; nbsp[1] := 0A0X; nbsp[2] := 0X;
  A.InitInlines(t);
  IF M.todo & (h.marker # NIL) THEN
    a := A.NewAttr(A.S(""));
    IF h.marker.done THEN A.AddClass(a, A.S("done"))
    ELSE A.AddClass(a, A.S("todo"))
    END;
    A.AddClass(a, h.marker.name);
    A.Append(t, A.NewSpan(a, A.NewStr(h.marker.name)));
    A.Append(t, A.NewSimple(A.Space))
  END;
  A.Append(t, A.CopyInlines(h.title));
  IF M.tags & (h.tags # NIL) THEN
    A.Append(t, A.NewSimple(A.Space));
    tag := h.tags;
    WHILE tag # NIL DO
      IF tag # h.tags THEN A.Append(t, A.NewStr(A.S(nbsp))) END;
      a := A.NewAttr(A.S("")); A.AddClass(a, A.S("tag"));
      A.AddKeyVal(a, A.S("tag-name"), tag.s);
      A.Append(t, A.NewSpan(a, A.NewCont(A.SmallCaps, A.NewStr(tag.s))));
      tag := tag.next
    END
  END;
  a := PropAttr(h.props);
  IF Ropes.Length(a.id) = 0 THEN
    IF autoIds THEN a.id := UniqueId(I.ResolvedCopy(h.title)) END
  ELSE Use(a.id)
  END;
  level := h.level;
  IF level > MAX(INTEGER) THEN level := MAX(INTEGER) END;
  RETURN A.NewHeader(SHORT(level), a, t.first)
END Header;

(* planningToBlock *)
PROCEDURE PlanningBlock(h: Headline; VAR l: A.Blocks);
  VAR t: A.Inlines;

  PROCEDURE Datum(ts: A.Rope; name: ARRAY OF CHAR);
  BEGIN
    IF ts # NIL THEN
      IF t.first # NIL THEN A.Append(t, A.NewSimple(A.Space)) END;
      A.Append(t, A.NewCont(A.Strong, A.NewStr(A.S(name))));
      A.Append(t, A.NewSimple(A.Space));
      A.Append(t, A.NewCont(A.Emph, A.NewStr(ts)))
    END
  END Datum;

BEGIN
  IF M.planning THEN
    A.InitInlines(t);
    Datum(h.closed, "CLOSED:"); Datum(h.deadline, "DEADLINE:");
    Datum(h.scheduled, "SCHEDULED:");
    IF t.first # NIL THEN A.AddBlock(l, A.NewInlinesBlock(A.Plain, t.first)) END
  END
END PlanningBlock;

PROCEDURE ^ HeadlineBlocks(h: Headline; VAR l: A.Blocks);

(* headlineToHeaderWithContents *)
PROCEDURE WithContents(h: Headline; VAR l: A.Blocks);
  VAR c: Headline;
BEGIN
  A.AddBlock(l, Header(h));
  PlanningBlock(h, l);
  A.AddBlock(l, h.contents);
  c := h.children;
  WHILE c # NIL DO HeadlineBlocks(c, l); c := c.next END
END WithContents;

(* headlineToHeaderWithList: the headlines under h as an ordered
   list, its header a paragraph below the level of H: *)
PROCEDURE WithList(h: Headline; VAR l: A.Blocks);
  VAR hdr: A.Block; c: Headline; first, last, item: A.BlockList;
    cl: A.Blocks;
BEGIN
  hdr := Header(h);
  first := NIL; last := NIL; c := h.children;
  WHILE c # NIL DO
    A.InitBlocks(cl); HeadlineBlocks(c, cl);
    NEW(item); item.blocks := cl.first; item.next := NIL;
    IF first = NIL THEN first := item ELSE last.next := item END;
    last := item;
    c := c.next
  END;
  IF M.headlineLevels = h.level THEN A.AddBlock(l, hdr)
  ELSE A.AddBlock(l, A.NewInlinesBlock(A.Para, hdr(A.HeaderBlk).inlines))
  END;
  PlanningBlock(h, l);
  A.AddBlock(l, h.contents);
  IF first # NIL THEN
    A.AddBlock(l, A.NewOrderedList(1, A.DefaultStyle, A.DefaultDelim, first))
  END
END WithList;

(* headlineToBlocks *)
PROCEDURE HeadlineBlocks(h: Headline; VAR l: A.Blocks);
BEGIN
  IF Member(A.S("ARCHIVE"), h.tags) THEN
    IF M.archived = M.ArchExport THEN WithContents(h, l)
    ELSIF M.archived = M.ArchHeadline THEN A.AddBlock(l, Header(h))
    END
  ELSIF (h.title # NIL) & (h.title.kind = A.Str)
      & Ropes.EqualString(h.title(A.StrInl).text, "COMMENT") THEN
  ELSIF M.headlineLevels <= h.level THEN WithList(h, l)
  ELSE WithContents(h, l)
  END
END HeadlineBlocks;

(* unprunedHeadlineToBlocks: the blocks of the tree under root, with
   the select and exclude tags; the root's properties, without select
   tags, the document's metadata *)
PROCEDURE TreeBlocks(root: Headline; VAR l: A.Blocks);
  VAR v: A.MetaValue; using: BOOLEAN; t: A.Blocks; c: Headline;
    p, q: Prop;
BEGIN
  v := A.GetMeta(meta, "title");
  IF (v # NIL) & (v IS A.MetaInlinesV) THEN root.title := v(A.MetaInlinesV).inlines END;
  using := ContainsSelect(root);
  IF using THEN root.children := IncludeSelected(root.children) END;
  RemoveExcluded(root);
  IF ~using THEN
    A.InitBlocks(t); HeadlineBlocks(root, t);
    IF t.first # NIL THEN A.AddBlock(l, t.first.next) END;
    p := root.props;
    WHILE p # NIL DO (* the first of a key wins *)
      q := root.props;
      WHILE ~Ropes.Equal(q.key, p.key) DO q := q.next END;
      IF q = p THEN A.SetMeta(meta, p.key, A.NewMetaString(p.value)) END;
      p := p.next
    END
  ELSE
    c := root.children;
    WHILE c # NIL DO HeadlineBlocks(c, l); c := c.next END
  END
END TreeBlocks;

(* Includes *)

(* Appends s to m, as far as m holds it *)
PROCEDURE Append(VAR m: ARRAY OF CHAR; s: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE m[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (j < LEN(s)) & (s[j] # 0X) & (i < LEN(m) - 1) DO
    m[i] := s[j]; INC(i); INC(j)
  END;
  m[i] := 0X
END Append;

(* Appends the number n to m *)
PROCEDURE CatNum(VAR m: ARRAY OF CHAR; n: LONGINT);
  VAR d: ARRAY 24 OF CHAR; i, k: INTEGER;
BEGIN
  IF n < 0 THEN Append(m, "-"); n := -n END;
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  k := 0; WHILE m[k] # 0X DO INC(k) END;
  WHILE (i > 0) & (k < LEN(m) - 1) DO DEC(i); m[k] := d[i]; INC(k) END;
  m[k] := 0X
END CatNum;

(* The name of the source and the line of the place p in the current
   text, as pandoc's positions give them: in a text parseFromString
   reads, the source's name with _chunk for each such text and the
   line counted from that text's start *)
PROCEDURE SourcePos(p: LONGINT; VAR name: ARRAY OF CHAR; VAR line: LONGINT);
  VAR i, k: LONGINT;
BEGIN
  name[0] := 0X; line := 1;
  IF incs # NIL THEN k := B.depth - incs.depth ELSE k := B.depth END;
  IF incs # NIL THEN
    COPY(incs.name^, name);
    IF k = 0 THEN line := incs.start END
  ELSIF k = 0 THEN
    IF p >= mainLen THEN p := mainLen - 1 END;
    PdSource.Locate(main^, p, name, line);
    RETURN
  ELSE PdSource.Locate(main^, B.outerPos, name, i)
  END;
  IF p > B.len THEN p := B.len END;
  FOR i := 0 TO p - 1 DO IF B.t[i] = 0AX THEN INC(line) END END;
  WHILE k > 0 DO Append(name, "_chunk"); DEC(k) END
END SourcePos;

(* safeRead of an Int from r[from .. to-1]: spaces, a minus sign or
   none, digits and spaces *)
PROCEDURE ReadInt(r: A.Rope; from, to: LONGINT; VAR n: LONGINT): BOOLEAN;
  VAR neg: BOOLEAN; d: LONGINT; ch: CHAR;
BEGIN
  WHILE (from < to) & B.IsSpace(Ropes.Fetch(r, from)) DO INC(from) END;
  WHILE (to > from) & B.IsSpace(Ropes.Fetch(r, to - 1)) DO DEC(to) END;
  neg := (from < to) & (Ropes.Fetch(r, from) = "-");
  IF neg THEN INC(from) END;
  IF (from >= to) OR (to - from > 9) THEN RETURN FALSE END;
  n := 0;
  WHILE from < to DO
    ch := Ropes.Fetch(r, from);
    IF (ch < "0") OR (ch > "9") THEN RETURN FALSE END;
    d := ORD(ch) - ORD("0"); n := n * 10 + d; INC(from)
  END;
  IF neg THEN n := -n END;
  RETURN TRUE
END ReadInt;

(* The bounds of :lines "a-b": start a, if a is a number, and end b-1,
   if b is one; the quotes are the value's first and last characters,
   whatever they are *)
PROCEDURE LineBounds(v: A.Rope; VAR hasStart, hasEnd: BOOLEAN; VAR start, end: LONGINT);
  VAR n, i, j: LONGINT;
BEGIN
  hasStart := FALSE; hasEnd := FALSE;
  IF v = NIL THEN RETURN END;
  n := Ropes.Length(v) - 1; (* boundStr is v[1 .. n-1] *)
  i := 1; WHILE (i < n) & (Ropes.Fetch(v, i) # "-") DO INC(i) END;
  hasStart := ReadInt(v, 1, i, start);
  j := n; WHILE (j > 1) & (Ropes.Fetch(v, j - 1) # "-") DO DEC(j) END;
  hasEnd := ReadInt(v, j, n, end);
  IF hasEnd THEN DEC(end) END
END LineBounds;

(* exciseLines: the lines start to end of c's, each with a new line *)
PROCEDURE Excise(VAR c: B.Buf; hasStart, hasEnd: BOOLEAN; start, end: LONGINT);
  VAR o: B.Buf; nlines, i, j, k, s, e, s0: LONGINT;
BEGIN
  nlines := 0; i := 0;
  WHILE i < c.len DO
    WHILE (i < c.len) & (c.t[i] # 0AX) DO INC(i) END;
    INC(nlines); INC(i)
  END;
  IF ~hasStart THEN s := 1 ELSIF start >= 0 THEN s := start ELSE s := nlines + start END;
  IF ~hasEnd THEN e := nlines ELSIF end >= 0 THEN e := end ELSE e := nlines + end END;
  (* take (e - (s-1)) $ drop (s-1) *)
  IF s < 1 THEN s0 := 1 ELSE s0 := s END;
  B.InitBuf(o); k := 1; i := 0;
  WHILE i < c.len DO
    j := i; WHILE (j < c.len) & (c.t[j] # 0AX) DO INC(j) END;
    IF (k >= s) & (k - s0 < e - (s - 1)) THEN
      WHILE i < j DO B.PutChar(o, c.t[i]); INC(i) END;
      B.PutChar(o, 0AX)
    END;
    INC(k); i := j + 1
  END;
  c := o
END Excise;

(* The end of the alphanumeric word at p, or p *)
PROCEDURE AlnumWord(p: LONGINT): LONGINT;
  VAR q, r: LONGINT; ch: CHAR; c: Utf8.Rune;
BEGIN
  q := p;
  LOOP
    IF q >= B.len THEN EXIT END;
    ch := B.t[q];
    IF ch < 80X THEN
      IF B.IsAlnum(ch) THEN INC(q) ELSE EXIT END
    ELSE
      r := q;
      IF Utf8.Decode(B.t^, r, c) & (r > q) & IsAlnumRune(c) THEN q := r
      ELSE EXIT
      END
    END
  END;
  RETURN q
END AlnumWord;

PROCEDURE (w: LevelWalker) Block*(b: A.Block): A.Block;
  VAR h: A.HeaderBlk; n: LONGINT;
BEGIN
  IF b.kind = A.Header THEN
    h := b(A.HeaderBlk);
    IF w.query THEN
      IF (w.min < 0) OR (h.level < w.min) THEN w.min := h.level END
    ELSE
      n := h.level - w.shift;
      IF n <= 0 THEN RETURN A.NewInlinesBlock(A.Para, h.inlines) END;
      IF n > MAX(INTEGER) THEN n := MAX(INTEGER) END;
      h.level := SHORT(n)
    END
  END;
  RETURN b
END Block;

(* blockFilter: the headers of b shifted so that the highest is at
   level lvl; one shifted to level 0 or less becomes a Para *)
PROCEDURE MinLevel(b: A.Block; lvl: LONGINT): A.Block;
  VAR w: LevelWalker;
BEGIN
  NEW(w); w.query := TRUE; w.min := -1;
  b := A.WalkBlocks(w, b);
  IF w.min < 0 THEN w.min := 0 END;
  w.query := FALSE; w.shift := w.min - lvl;
  RETURN A.WalkBlocks(w, b)
END MinLevel;

(* include: #+INCLUDE: "file" args :key value..., the file's text as
   the args ask, its blocks by default (insertIncludedFile) *)
PROCEDURE Include(VAR l: A.Blocks): BOOLEAN;
  VAR q, fs, fe, e, i, j, n, len, line, start, end, nargs, lvl: LONGINT;
    as, ae: ARRAY 2 OF LONGINT; f, dir, path, nm: ARRAY 1024 OF CHAR;
    m: ARRAY 2048 OF CHAR; kv: A.Attr; b, c: B.Buf; fr: B.Frame;
    found, hasStart, hasEnd, ok, savedFresh: BOOLEAN; t: PdIO.Text;
    in, inc: Inc; a: A.Attr; v: A.Rope; root: Headline; il: A.Blocks;
    blks: A.Block;
BEGIN
  q := I.MetaLineStart(B.pos);
  IF (q < 0) OR ~LookingCI(q, "include:") THEN RETURN FALSE END;
  q := B.SkipSpaces(q + 8);
  IF B.C(q) # 22X THEN RETURN FALSE END;
  fs := q + 1; fe := fs;
  WHILE (fe < B.len) & (B.C(fe) # 22X) DO
    IF (B.C(fe) = 0AX) OR (B.C(fe) = 0DX) OR (B.C(fe) = 09X) THEN RETURN FALSE END;
    INC(fe)
  END;
  IF (fe >= B.len) OR (fe - fs >= LEN(f)) THEN RETURN FALSE END;
  q := fe + 1; nargs := 0;
  LOOP
    i := B.SkipSpaces(q); j := AlnumWord(i);
    IF j = i THEN EXIT END;
    IF nargs < 2 THEN as[nargs] := i; ae[nargs] := j END;
    INC(nargs); q := j
  END;
  (* keyValues, in the rest of the line *)
  e := B.LineEnd(q);
  B.InitBuf(b);
  FOR i := q TO e - 1 DO B.PutChar(b, B.t[i]) END;
  B.PutChar(b, 0AX);
  kv := A.NewAttr(NIL);
  I.Push(fr, b.t, b.len); ok := KeyValues(kv); B.Leave(fr);
  IF ~ok THEN RETURN FALSE END;
  FOR i := fs TO fe - 1 DO f[i - fs] := B.t[i] END;
  f[fe - fs] := 0X;
  B.pos := NextLine(e); I.Newline;
  SourcePos(B.pos, nm, line);
  in := incs;
  WHILE in # NIL DO
    IF in.name^ = f THEN
      m := 'Include file loop at "'; Append(m, nm); Append(m, '" (line ');
      CatNum(m, line); Append(m, ", column 1)");
      PdIO.Fail("", m, PdIO.ParseError)
    END;
    in := in.next
  END;
  (* takeDirectory of the source *)
  COPY(nm, dir); i := -1; j := 0;
  WHILE dir[j] # 0X DO IF dir[j] = "/" THEN i := j END; INC(j) END;
  IF i < 0 THEN dir := "." ELSIF i = 0 THEN dir := "/" ELSE dir[i] := 0X END;
  IF f[0] = "/" THEN COPY(f, path)
  ELSE COPY(dir, path); IF dir # "/" THEN Append(path, "/") END; Append(path, f)
  END;
  LineBounds(A.GetKeyVal(kv, "lines", found), hasStart, hasEnd, start, end);
  B.InitBuf(c);
  IF (f # "") & PdIO.Exists(path) THEN
    PdIO.ReadFile(path, t, len);
    i := 0;
    IF (len >= 3) & (t[0] = 0EFX) & (t[1] = 0BBX) & (t[2] = 0BFX) THEN i := 3 END;
    WHILE i < len DO IF t[i] # 0DX THEN B.PutChar(c, t[i]) END; INC(i) END;
    IF hasStart OR hasEnd THEN Excise(c, hasStart, hasEnd, start, end) END
  ELSE
    m := "Could not load include file "; Append(m, f); Append(m, " at ");
    IF (nm # "") & (nm # "-") THEN Append(m, nm); Append(m, " ") END;
    Append(m, "line "); CatNum(m, line); Append(m, " column 1");
    PdIO.Warn(m)
  END;
  IF (nargs >= 1) & Is(as[0], ae[0], "example") THEN
    A.AddBlock(l, A.NewCodeBlock(A.NewAttr(NIL), B.BufRope(c)))
  ELSIF (nargs = 1) & Is(as[0], ae[0], "export") THEN
  ELSIF (nargs = 2) & Is(as[0], ae[0], "export") THEN
    A.AddBlock(l, A.NewRawBlock(B.Rope(as[1], ae[1]), B.BufRope(c)))
  ELSIF (nargs >= 1) & Is(as[0], ae[0], "src") THEN
    a := A.NewAttr(NIL);
    IF nargs = 2 THEN A.AddClass(a, B.Rope(as[1], ae[1])) END;
    A.AddBlock(l, A.NewCodeBlock(a, B.BufRope(c)))
  ELSE (* blockList, with blockFilter *)
    v := A.GetKeyVal(kv, "minlevel", found);
    IF v = NIL THEN found := FALSE ELSE found := ReadInt(v, 0, Ropes.Length(v), lvl) END;
    n := 0; WHILE f[n] # 0X DO INC(n) END;
    NEW(inc); NEW(inc.name, n + 1); COPY(f, inc.name^);
    IF hasStart THEN inc.start := start ELSE inc.start := 1 END;
    inc.next := incs;
    I.FileOrigin(path, inc.start);
    I.Push(fr, c.t, c.len); inc.depth := B.depth; incs := inc;
    savedFresh := fresh; fresh := FALSE;
    root := DocumentTree();
    A.InitBlocks(il); TreeBlocks(root, il);
    fresh := savedFresh;
    B.Leave(fr); incs := inc.next;
    blks := I.ResolveBlocks(il.first);
    IF found THEN blks := MinLevel(blks, lvl) END;
    A.AddBlock(l, blks)
  END;
  RETURN TRUE
END Include;

(* Reads the Org text text[0 .. n-1], its tabs already expanded at
   tabStop. *)
PROCEDURE Read*(text: PdIO.Text; n: LONGINT; tabStop: INTEGER): A.Doc;
  VAR t: B.Text; i, k: LONGINT; d: A.Doc; l: A.Blocks; root: Headline;
    last: A.StrList; sep: LineSepWalker;
BEGIN
  (* ensureFinalNewlines 2 *)
  k := 0;
  WHILE (k < n) & (k < 2) & (text[n - 1 - k] = 0AX) DO INC(k) END;
  t := B.NewText(n + 2 - k);
  FOR i := 0 TO n - 1 DO t[i] := text[i] END;
  FOR i := n TO n + 1 - k DO t[i] := 0AX END;
  B.Start(t, n + 2 - k, tabStop);
  main := B.t; mainLen := n + 2 - k; incs := NIL;
  I.main := main; I.mainLen := mainLen; I.unknown := unknown;
  M.Reset(smart, smartQuotes, specialStrings);
  I.fancyLists := fancyLists; I.citations := citations; I.Reset;
  NEW(idTable);
  FOR i := 0 TO IdTableSize - 1 DO idTable[i] := NIL END;
  markers := NewDefaultMarkers(); customTodo := FALSE;
  selectTags := NIL; AddStr(selectTags, last, A.S("export"));
  excludeTags := NIL; AddStr(excludeTags, last, A.S("noexport"));
  selectSet := FALSE; excludeSet := FALSE;
  inList := FALSE; fresh := FALSE;
  d := A.NewDoc(); meta := d.meta;
  root := DocumentTree();
  A.InitBlocks(l);
  TreeBlocks(root, l);
  d.blocks := l.first;
  (* metaExport *)
  IF ~M.withAuthor THEN A.DeleteMeta(meta, "author") END;
  IF ~M.withCreator THEN A.DeleteMeta(meta, "creator") END;
  IF ~M.withEmail THEN A.DeleteMeta(meta, "email") END;
  I.Resolve(d);
  NEW(sep); A.WalkMetaValue(sep, d.meta);
  idTable := NIL; meta := NIL; markers := NIL; main := NIL;
  selectTags := NIL; excludeTags := NIL;
  RETURN d
END Read;

BEGIN
  autoIds := TRUE; asciiIds := FALSE; gfmIds := FALSE; citations := TRUE;
  specialStrings := TRUE; taskLists := TRUE; smart := FALSE;
  smartQuotes := FALSE; fancyLists := FALSE; eastAsian := FALSE;
  standalone := FALSE; unknown := Quiet; columns := 72
END PdOrg.
