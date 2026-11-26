MODULE PdOrg;

(* The Org reader, -f org, as pandoc 3.14's Readers/Org reads Org:
   its blocks (Blocks.hs), the document's tree (DocumentTree.hs) and
   the passes after parsing. Inlines are PdOrgInline's, the export
   settings and the metadata PdOrgMeta's.

   Phase 26.1: paragraphs and Plain, blank lines, horizontal rules,
   fixed-width lines, comment lines, raw export lines, keywords and
   #+OPTIONS; headlines only as headers with their identifiers, until
   Phase 26.5. Phase 26.2: bullet, ordered and definition lists, with
   checkboxes. *)

IMPORT Ropes, PdIO, A := PdAst, B := PdMdBase, MI := PdMdInline,
  I := PdOrgInline, M := PdOrgMeta, SH := PdShared;

CONST
  Quiet* = 0; WarnUnknown* = 1; FailUnknown* = 2; (* unknown *)
  KeySize = 64;

  (* the keywords pandoc's keywordHandlers know *)
  Keywords = " author bibliography creator date description email exclude_tags header-includes html_head html_head_extra institute keywords language latex_class latex_class_options latex_header latex_header_extra link macro nocite options pandoc-emphasis-post pandoc-emphasis-pre result select_tags seq_todo subtitle title todo typ_todo ";

TYPE
  Key = ARRAY KeySize OF CHAR;

VAR
  (* the extensions *)
  autoIds*, asciiIds*, gfmIds*, citations*, specialStrings*, taskLists*,
  smart*, smartQuotes*, fancyLists*, eastAsian*: BOOLEAN;
  standalone*: BOOLEAN; (* -s *)
  unknown*: INTEGER; (* --unknown: Quiet, WarnUnknown or FailUnknown *)

  ids: A.StrList; (* the identifiers used so far *)
  inList: BOOLEAN; (* in a list item: the context ListItemState *)

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
  B.pos := p;
  RETURN TRUE
END Example;

(* keywordLine: a keyword pandoc knows, after #+ and the key. Phase
   26.1 reads #+OPTIONS and passes over the rest of the others' lines:
   what they set comes in later phases. *)
PROCEDURE KeywordLine(VAR k: Key; p: LONGINT): BOOLEAN;
BEGIN
  IF ~InList(k, Keywords) THEN RETURN FALSE END;
  IF k = "options" THEN B.pos := M.Options(p)
  ELSE B.pos := NextLine(p)
  END;
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
      B.pos := NextLine(e);
      RETURN TRUE
    END;
    IF B.Looking(B.SkipSpaces(p), "#+print_bibliography:") THEN
      A.AddBlock(l, A.NewDiv(A.NewAttr(A.S("refs")), NIL));
      B.pos := NextLine(p);
      RETURN TRUE
    END;
    IF (q >= 0) & KeywordLine(k, q) THEN RETURN TRUE END
  END;
  IF I.CommentLineStart(p) >= 0 THEN
    B.pos := NextLine(p);
    RETURN TRUE
  END;
  RETURN FALSE
END SpecialLine;

(* rawOrgLine: any other #+ line, a RawBlock org of it from its #+ *)
PROCEDURE RawOrgLine(VAR l: A.Blocks): BOOLEAN;
  VAR q, e: LONGINT;
BEGIN
  q := I.MetaLineStart(B.pos);
  IF q < 0 THEN RETURN FALSE END;
  e := B.LineEnd(q);
  A.AddBlock(l, A.NewRawBlock(A.S("org"), B.Rope(q - 2, e)));
  B.pos := NextLine(e);
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
    INC(B.pos);
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
    r := ListLine(p, n);
    IF r < 0 THEN EXIT END;
    REPEAT
      e := B.LineEnd(r); B.Put(b, r, e); B.PutChar(b, 0AX);
      p := NextLine(e); r := ListLine(p, n)
    UNTIL r < 0;
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
  B.Enter(f, b.t, b.len);
  A.InitBlocks(l);
  IF ParaOrPlain(l) THEN END;
  Blocks(l);
  B.Leave(f);
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
  B.Enter(f, b.t, b.len);
  i := I.Inlines();
  ok := B.pos > 0;
  B.Leave(f);
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
  ItemText(DefinitionMarker(r), n, b);
  B.Enter(f, b.t, b.len);
  A.InitBlocks(l);
  Blocks(l);
  B.Leave(f);
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

(* block: one block at B.pos, added to l; FALSE if there is none *)
PROCEDURE Block(VAR l: A.Blocks): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  q := B.BlankLines(B.pos);
  IF q >= 0 THEN B.pos := q; RETURN TRUE END;
  IF Example(l) OR SpecialLine(l) THEN RETURN TRUE END;
  q := I.Hline(B.pos);
  IF q >= 0 THEN
    A.AddBlock(l, A.NewHorizontalRule()); B.pos := q;
    RETURN TRUE
  END;
  RETURN DefinitionList(l) OR List(FALSE, l) OR List(TRUE, l)
    OR RawOrgLine(l) OR ParaOrPlain(l)
END Block;

(* blocks: blocks up to a headline or the end of the text *)
PROCEDURE Blocks(VAR l: A.Blocks);
  VAR n: LONGINT;
BEGIN
  WHILE (B.pos < B.len) & (I.HeaderStart(B.pos, n) < 0) & Block(l) DO END
END Blocks;

(* The headline tree *)

(* uniqueIdent: id, or id-1, id-2, ... if it has been used; section
   if id is empty *)
PROCEDURE UniqueId(id: A.Rope): A.Rope;
  VAR s: A.StrList; base: A.Rope; n: LONGINT;

  PROCEDURE Used(r: A.Rope): BOOLEAN;
    VAR s: A.StrList;
  BEGIN
    s := ids;
    WHILE (s # NIL) & ~Ropes.Equal(s.s, r) DO s := s.next END;
    RETURN s # NIL
  END Used;

BEGIN
  IF Ropes.Length(id) = 0 THEN id := A.S("section") END;
  base := id; n := 0;
  WHILE Used(id) DO
    INC(n); id := Ropes.Cat(Ropes.Cat(base, A.S("-")), SH.IntRope(n))
  END;
  NEW(s); s.s := id; s.next := ids; ids := s;
  RETURN id
END UniqueId;

(* A headline at B.pos, a Header of its title. Phase 26.5 reads the
   rest: TODO keywords, priorities, tags, property drawers and the
   tree's sections. *)
PROCEDURE Headline(VAR l: A.Blocks);
  VAR level: LONGINT; t: A.Inlines; i: A.Inline; id: A.Rope;
BEGIN
  B.pos := I.HeaderStart(B.pos, level);
  A.InitInlines(t);
  WHILE (B.pos < B.len) & (B.t[B.pos] # 0AX) & I.Inline(t) DO END;
  IF B.C(B.pos) = 0AX THEN INC(B.pos) END;
  i := MI.Trim(t);
  id := A.S("");
  IF autoIds THEN id := UniqueId(MI.Identifier(i)) END;
  IF level > MAX(INTEGER) THEN level := MAX(INTEGER) END;
  A.AddBlock(l, A.NewHeader(SHORT(level), A.NewAttr(id), i))
END Headline;

(* documentTree: the blocks before the first headline, then the
   headlines and the blocks after each *)
PROCEDURE DocumentTree(VAR l: A.Blocks);
  VAR n: LONGINT;
BEGIN
  Blocks(l);
  WHILE (B.pos < B.len) & (I.HeaderStart(B.pos, n) >= 0) DO
    Headline(l); Blocks(l)
  END
END DocumentTree;

(* Reads the Org text text[0 .. n-1], its tabs already expanded at
   tabStop. *)
PROCEDURE Read*(text: PdIO.Text; n: LONGINT; tabStop: INTEGER): A.Doc;
  VAR t: B.Text; i, k: LONGINT; d: A.Doc; l: A.Blocks;
BEGIN
  (* ensureFinalNewlines 2 *)
  k := 0;
  WHILE (k < n) & (k < 2) & (text[n - 1 - k] = 0AX) DO INC(k) END;
  t := B.NewText(n + 2 - k);
  FOR i := 0 TO n - 1 DO t[i] := text[i] END;
  FOR i := n TO n + 1 - k DO t[i] := 0AX END;
  B.Start(t, n + 2 - k, tabStop);
  M.Reset(smart, smartQuotes, specialStrings);
  I.fancyLists := fancyLists;
  ids := NIL; inList := FALSE;
  d := A.NewDoc();
  A.InitBlocks(l);
  DocumentTree(l);
  d.blocks := l.first;
  ids := NIL;
  RETURN d
END Read;

BEGIN
  autoIds := TRUE; asciiIds := FALSE; gfmIds := FALSE; citations := TRUE;
  specialStrings := TRUE; taskLists := TRUE; smart := FALSE;
  smartQuotes := FALSE; fancyLists := FALSE; eastAsian := FALSE;
  standalone := FALSE; unknown := Quiet
END PdOrg.
