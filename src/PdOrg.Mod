MODULE PdOrg;

(* The Org reader, -f org, as pandoc 3.14's Readers/Org reads Org:
   its blocks (Blocks.hs), the document's tree (DocumentTree.hs) and
   the passes after parsing. Inlines are PdOrgInline's, the export
   settings and the metadata PdOrgMeta's.

   Phase 26.1: paragraphs and Plain, blank lines, horizontal rules,
   fixed-width lines, comment lines, raw export lines, keywords and
   #+OPTIONS; headlines only as headers with their identifiers, until
   Phase 26.5. Phase 26.2: bullet, ordered and definition lists, with
   checkboxes. Phase 26.3: block attributes and figures, #+begin_
   blocks (source, example, quote, verse, export and raw, comment,
   admonitions, abstract and the rest as Divs), dynamic blocks,
   drawers, LaTeX environments and footnote definitions, kept until
   Phase 27.3 resolves their references. *)

IMPORT Ropes, PdIO, A := PdAst, B := PdMdBase, MI := PdMdInline,
  I := PdOrgInline, M := PdOrgMeta, SH := PdShared;

CONST
  Quiet* = 0; WarnUnknown* = 1; FailUnknown* = 2; (* unknown *)
  KeySize = 64;

  (* the keywords pandoc's keywordHandlers know *)
  Keywords = " author bibliography creator date description email exclude_tags header-includes html_head html_head_extra institute keywords language latex_class latex_class_options latex_header latex_header_extra link macro nocite options pandoc-emphasis-post pandoc-emphasis-pre result select_tags seq_todo subtitle title todo typ_todo ";

TYPE
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

  (* a footnote's definition *)
  Note = POINTER TO RECORD
    ref: A.Rope; (* 1 or fn:name *)
    blocks: A.Block;
    next: Note
  END;

VAR
  (* the extensions *)
  autoIds*, asciiIds*, gfmIds*, citations*, specialStrings*, taskLists*,
  smart*, smartQuotes*, fancyLists*, eastAsian*: BOOLEAN;
  standalone*: BOOLEAN; (* -s *)
  unknown*: INTEGER; (* --unknown: Quiet, WarnUnknown or FailUnknown *)

  ids: A.StrList; (* the identifiers used so far *)
  inList: BOOLEAN; (* in a list item: the context ListItemState *)
  meta: A.MetaMapV; (* the document's *)
  notes: Note; (* the footnotes' definitions, the last first *)

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

PROCEDURE ^ Block(VAR l: A.Blocks): BOOLEAN;

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

(* orgArgWord: letters, digits, - and _; where it ends, or -1 *)
PROCEDURE ArgWord(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := p;
  WHILE (q < B.len) & ((B.t[q] = "-") OR (B.t[q] = "_") OR MI.AlnumAt(q)) DO
    q := MI.RuneEnd(q)
  END;
  IF q = p THEN RETURN -1 END;
  RETURN q
END ArgWord;

(* orgArgKey: spaces, a colon and an orgArgWord, the key, which starts
   at from; where it ends, or -1 *)
PROCEDURE ArgKey(p: LONGINT; VAR from: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF B.C(p) # ":" THEN RETURN -1 END;
  from := p + 1;
  RETURN ArgWord(p + 1)
END ArgKey;

(* orgParamValue's endOfValue at p *)
PROCEDURE ValueEnd(p: LONGINT): BOOLEAN;
  VAR q, f: LONGINT;
BEGIN
  q := B.SkipSpaces(p);
  IF (B.C(q) = 0AX) OR (B.C(q) = 0DX) THEN RETURN TRUE END;
  RETURN (q > p) & (ArgKey(q, f) >= 0)
END ValueEnd;

(* orgParamValue: a value, t[from .. to-1], quoted or up to a key or
   the end of the line, and the spaces after it; where they end, or
   -1 *)
PROCEDURE ParamValue(p: LONGINT; VAR from, to: LONGINT): LONGINT;
  VAR q, f: LONGINT; ch: CHAR;
BEGIN
  q := B.SkipSpaces(p);
  IF ArgKey(q, f) >= 0 THEN RETURN -1 END;
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
  q := ArgKey(p, f);
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
    r := ArgKey(q, f);
    IF r < 0 THEN EXIT END;
    q := ParamValue(r, vf, vt);
    IF q < 0 THEN EXIT END;
    A.AddKeyVal(t, B.Rope(f, r), B.Rope(vf, vt))
  END;
  t := A.NewAttr(NIL); q := p;
  LOOP
    IF B.C(q) = 0AX THEN AddPairs(a, t); RETURN q + 1 END;
    WHILE (q < B.len) & B.IsWhite(B.t[q]) DO INC(q) END;
    f := q; r := ArgWord(q);
    IF (r < 0) OR (B.C(r) # "=") THEN EXIT END;
    vf := r + 1; vt := ArgWord(vf);
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
  B.Enter(f, b.t, b.len);
  i := I.Inlines();
  B.Leave(f);
  RETURN i
END BufInlines;

(* The blocks of b's text and a new line, into out
   (parseFromString blocks) *)
PROCEDURE ParseBlocks(VAR b: B.Buf; VAR out: A.Blocks);
  VAR f: B.Frame;
BEGIN
  B.PutChar(b, 0AX);
  B.Enter(f, b.t, b.len);
  A.InitBlocks(out);
  Blocks(out);
  B.Leave(f)
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
  VAR q, r, v, e: LONGINT; first, last, x: AttrLine; cap, kv: B.Buf;
    f: B.Frame; ok: BOOLEAN;
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
      IF ba.hasCaption THEN B.PutChar(cap, " ") END;
      B.Put(cap, x.from, x.to); ba.hasCaption := TRUE
    ELSIF x.key = "attr_html" THEN
      IF kv.len > 0 THEN B.PutChar(kv, " ") END;
      B.Put(kv, x.from, x.to)
    END;
    x := x.next
  END;
  IF ba.hasCaption THEN ba.caption := BufInlines(cap) END;
  B.PutChar(kv, 0AX);
  B.Enter(f, kv.t, kv.len);
  ok := KeyValues(ba.kv);
  B.Leave(f);
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

(* translateLang: pandoc's name for an Org language, or NIL if it is
   the same *)
PROCEDURE TranslateLang(from, to: LONGINT): A.Rope;
BEGIN
  IF Is(from, to, "C") THEN RETURN A.S("c")
  ELSIF Is(from, to, "emacs-lisp") OR Is(from, to, "lisp") THEN
    RETURN A.S("commonlisp")
  ELSIF Is(from, to, "js") THEN RETURN A.S("javascript")
  ELSIF Is(from, to, "R") THEN RETURN A.S("r")
  ELSIF Is(from, to, "sh") THEN RETURN A.S("bash")
  ELSIF Is(from, to, "sqlite") THEN RETURN A.S("sql")
  END;
  RETURN NIL
END TranslateLang;

(* codeHeaderArgs: the language, switches and options, into a; where
   the line ends, past its new line, or -1 *)
PROCEDURE CodeHeaderArgs(p: LONGINT; a: A.Attr; VAR noTrim: BOOLEAN): LONGINT;
  VAR q, r: LONGINT; lang: A.Rope;
BEGIN
  q := B.SkipSpaces(p); r := ArgWord(q);
  IF r < 0 THEN RETURN -1 END;
  lang := TranslateLang(q, r);
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
  VAR q, r, saved: LONGINT;
BEGIN
  A.InitBlocks(res);
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
  saved := B.pos; B.pos := q;
  IF Block(res) THEN r := B.pos ELSE A.InitBlocks(res); r := p END;
  B.pos := saved;
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
  VAR e, i, j, k, m: LONGINT; b, nb, lb: B.Buf; f: B.Frame; il: A.Inlines;
    first, last, x: A.InlineList;
BEGIN
  e := RawContent(p, FALSE, ts, te, TRUE, b);
  IF e < 0 THEN RETURN -1 END;
  first := NIL; last := NIL; i := 0;
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
    B.Enter(f, lb.t, lb.len);
    A.Append(il, I.Inlines());
    B.Leave(f);
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
    q := B.SkipSpaces(te); r := ArgWord(q);
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

(* Whether t[p .. to-1] is absolute as a Windows path is: two
   separators, or a letter, a colon and a separator *)
PROCEDURE WinAbs(p, to: LONGINT): BOOLEAN;

  PROCEDURE Sep(p: LONGINT): BOOLEAN;
  BEGIN
    RETURN (p < to) & ((B.t[p] = "/") OR (B.t[p] = "\"))
  END Sep;

BEGIN
  RETURN Sep(p) & Sep(p + 1)
    OR (p + 2 < to) & (CAP(B.t[p]) >= "A") & (CAP(B.t[p]) <= "Z")
       & (B.t[p + 1] = ":") & Sep(p + 2)
END WinAbs;

(* toFileSchema: t[p .. to-1] as a file: URL, or NIL if it is not
   absolute *)
PROCEDURE Schema(p, to: LONGINT): A.Rope;
BEGIN
  IF WinAbs(p, to) THEN RETURN Ropes.Cat(A.S("file:///"), B.Rope(p, to))
  ELSIF (p < to) & (B.t[p] = "/") THEN RETURN Ropes.Cat(A.S("file://"), B.Rope(p, to))
  END;
  RETURN NIL
END Schema;

(* cleanLinkText: t[from .. to-1] as a link; ok FALSE if it is not
   one *)
PROCEDURE CleanLink(from, to: LONGINT; VAR ok: BOOLEAN): A.Rope;
  VAR p: LONGINT; r: A.Rope;
BEGIN
  ok := TRUE;
  r := Schema(from, to);
  IF r # NIL THEN RETURN r END;
  IF B.Looking(from, "./") OR B.Looking(from, "../") THEN RETURN B.Rope(from, to)
  ELSIF B.Looking(from, "file:") THEN
    IF B.Looking(from + 5, "//") THEN RETURN B.Rope(from, to) END;
    r := Schema(from + 5, to);
    IF r # NIL THEN RETURN r END;
    RETURN B.Rope(from + 5, to)
  END;
  p := from; (* isUrl *)
  WHILE (p < to) & (B.t[p] # ":") DO
    IF ~MI.AlnumAt(p) & (B.t[p] # ".") & (B.t[p] # "-") THEN
      ok := FALSE; RETURN NIL
    END;
    p := MI.RuneEnd(p)
  END;
  ok := p < to;
  RETURN B.Rope(from, to)
END CleanLink;

(* isImageFilename: whether the last part of the path t[from .. to-1]
   has the extension of an image *)
PROCEDURE IsImage(from, to: LONGINT): BOOLEAN;
  VAR p: LONGINT; k: Key;
BEGIN
  p := to;
  WHILE (p > from) & (B.t[p - 1] # "/") & (B.t[p - 1] # ".") DO DEC(p) END;
  IF (p = from) OR (B.t[p - 1] # ".") THEN RETURN FALSE END;
  LowerKey(p, to, k);
  RETURN InList(k, " jpeg jpg png gif svg webp jxl avif pdf ")
END IsImage;

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
  src := CleanLink(s, e, ok);
  IF ~ok OR ~IsImage(s, e) THEN RETURN FALSE END;
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
  B.pos := r + 1;
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
  r := ArgWord(q);
  IF r >= 0 THEN A.AddClass(a, B.Rope(q, r)); q := r END;
  r := BlockParameters(q, a);
  IF r < 0 THEN RETURN FALSE END;
  e := RawContent(r, TRUE, 0, 0, TRUE, b);
  IF e < 0 THEN RETURN FALSE END;
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
    ParseBlocks(b, out);
    a := A.NewAttr(NIL); A.AddClass(a, name); A.AddClass(a, A.S("drawer"));
    A.AddBlock(l, A.NewDiv(a, out.first))
  END;
  B.pos := DrawerEnd(r);
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
  VAR p, q, n, r: LONGINT; nl: A.Blocks; note: Note;
BEGIN
  p := B.pos;
  q := I.NoteMarker(p);
  IF q < 0 THEN RETURN FALSE END;
  B.pos := B.SkipSpaces(q);
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
  NEW(note); note.ref := B.Rope(p + 1, q - 1); note.blocks := nl.first;
  note.next := notes; notes := note;
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
  IF DynamicBlock(l) OR OrgBlock(l) OR Figure(l) OR Example(l) OR Drawer(l)
      OR SpecialLine(l) THEN
    RETURN TRUE
  END;
  q := I.Hline(B.pos);
  IF q >= 0 THEN
    A.AddBlock(l, A.NewHorizontalRule()); B.pos := q;
    RETURN TRUE
  END;
  RETURN DefinitionList(l) OR List(FALSE, l) OR List(TRUE, l)
    OR LatexFragment(l) OR NoteBlock(l) OR RawOrgLine(l) OR ParaOrPlain(l)
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
  d := A.NewDoc(); meta := d.meta; notes := NIL;
  A.InitBlocks(l);
  DocumentTree(l);
  d.blocks := l.first;
  ids := NIL; meta := NIL; notes := NIL;
  RETURN d
END Read;

BEGIN
  autoIds := TRUE; asciiIds := FALSE; gfmIds := FALSE; citations := TRUE;
  specialStrings := TRUE; taskLists := TRUE; smart := FALSE;
  smartQuotes := FALSE; fancyLists := FALSE; eastAsian := FALSE;
  standalone := FALSE; unknown := Quiet
END PdOrg.
