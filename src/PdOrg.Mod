MODULE PdOrg;

(* The Org reader, -f org, as pandoc 3.14's Readers/Org reads Org:
   its blocks (Blocks.hs), the document's tree (DocumentTree.hs) and
   the passes after parsing. Inlines are PdOrgInline's, the export
   settings and the metadata PdOrgMeta's.

   Phase 26.1: paragraphs and Plain, blank lines, horizontal rules,
   fixed-width lines, comment lines, raw export lines, keywords and
   #+OPTIONS; headlines only as headers with their identifiers, until
   Phase 26.5. *)

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

(* paraOrPlain: inlines, a Para if a new line ends them, else Plain *)
PROCEDURE ParaOrPlain(VAR l: A.Blocks): BOOLEAN;
  VAR n: LONGINT; i: A.Inline; p: LONGINT;
BEGIN
  p := B.pos;
  IF I.HeaderStart(p, n) >= 0 THEN RETURN FALSE END;
  i := I.Inlines();
  IF B.pos = p THEN RETURN FALSE END;
  IF B.C(B.pos) = 0AX THEN
    INC(B.pos);
    A.AddBlock(l, A.NewInlinesBlock(A.Para, i))
  ELSE
    A.AddBlock(l, A.NewInlinesBlock(A.Plain, i))
  END;
  RETURN TRUE
END ParaOrPlain;

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
  RETURN RawOrgLine(l) OR ParaOrPlain(l)
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
  ids := NIL;
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
