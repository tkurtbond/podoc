MODULE PdShared;
(* PdShared: what pandoc's writers share (Text.Pandoc.Shared,
   Text.Pandoc.Writers.Shared): the text of inlines and blocks
   (stringify), the division of a document into sections
   (makeSections), and the metadata that writers look up. *)

IMPORT Ropes, PdJson, A := PdAst;

CONST
  MaxLevels = 100; (* the most levels a section number has *)

TYPE
  Rope = Ropes.Rope;
  (* A walker that finds the lowest header level *)
  LevelWalker = POINTER TO LevelWalkerDesc;
  LevelWalkerDesc = RECORD (A.WalkerDesc)
    min: INTEGER
  END;
  Pieces* = POINTER TO ARRAY OF A.Block;
  (* A row of toLegacyTable: its pieces, cells[0 .. n-1]; a piece is a
     cell's blocks, or NIL for a place a span covers *)
  LegacyRow* = POINTER TO LegacyRowDesc;
  LegacyRowDesc* = RECORD
    n*: LONGINT;
    cells*: Pieces;
    next*: LegacyRow
  END;
  Longs = POINTER TO ARRAY OF LONGINT;

VAR
  numbering: BOOLEAN; (* MakeSections: whether sections are numbered *)
  baseLevel: INTEGER; (* MakeSections: the level of the top sections; < 0 if they keep theirs *)
  minLevel: INTEGER; (* the lowest header level in the document *)
  lastNum: ARRAY MaxLevels OF LONGINT; (* the last section number *)
  pend: Longs; (* LegacyRows: the pieces still to place in each column *)
  npend: LONGINT; (* the columns pend holds *)
  lastLen: INTEGER; (* its components *)

(* stringify *)

PROCEDURE^ StringifyBlocksTo(VAR r: Rope; b: A.Block);

PROCEDURE Add(VAR r: Rope; s: ARRAY OF CHAR);
BEGIN
  r := Ropes.Cat(r, Ropes.FromString(s))
END Add;

(* Whether the rope r starts with s *)
PROCEDURE StartsWith*(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF (i >= Ropes.Length(r)) OR (Ropes.Fetch(r, i) # s[i]) THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END StartsWith;

PROCEDURE StringifyTo(VAR r: Rope; i: A.Inline);
BEGIN
  WHILE i # NIL DO
    CASE i.kind OF
      A.Str: r := Ropes.Cat(r, i(A.StrInl).text)
    | A.Space, A.SoftBreak, A.LineBreak: Add(r, " ")
    | A.Code: r := Ropes.Cat(r, i(A.CodeInl).text)
    | A.Math: r := Ropes.Cat(r, i(A.MathInl).text)
    | A.RawInline:
      IF Ropes.EqualString(i(A.RawInl).format, "html")
         & StartsWith(i(A.RawInl).text, "<br") THEN
        Add(r, " ")
      END
    | A.Quoted:
      IF i(A.QuotedInl).quote = A.DoubleQuote THEN
        Add(r, "“"); StringifyTo(r, i(A.ContInl).content); Add(r, "”")
      ELSE
        Add(r, "‘"); StringifyTo(r, i(A.ContInl).content); Add(r, "’")
      END
    | A.Note:
    ELSE
      IF i IS A.ContInl THEN StringifyTo(r, i(A.ContInl).content) END
    END;
    i := i.next
  END
END StringifyTo;

(* The text of the inlines i, without their formatting (stringify) *)
PROCEDURE Stringify*(i: A.Inline): Rope;
  VAR r: Rope;
BEGIN
  r := NIL; StringifyTo(r, i);
  RETURN r
END Stringify;

PROCEDURE StringifyRows(VAR r: Rope; row: A.Row);
  VAR c: A.Cell;
BEGIN
  WHILE row # NIL DO
    c := row.cells;
    WHILE c # NIL DO StringifyBlocksTo(r, c.blocks); c := c.next END;
    row := row.next
  END
END StringifyRows;

PROCEDURE StringifyBlocksTo(VAR r: Rope; b: A.Block);
  VAR l: A.InlineList; bl: A.BlockList; d: A.DefItem; t: A.TableBlk;
    tb: A.TableBody;
BEGIN
  WHILE b # NIL DO
    WITH b: A.InlinesBlk DO StringifyTo(r, b.inlines)
    | b: A.LineBlk DO
      l := b.lines;
      WHILE l # NIL DO StringifyTo(r, l.inlines); l := l.next END
    | b: A.FigureBlk DO
      StringifyTo(r, b.caption.short); StringifyBlocksTo(r, b.caption.blocks);
      StringifyBlocksTo(r, b.blocks)
    | b: A.BlocksBlk DO StringifyBlocksTo(r, b.blocks)
    | b: A.ListBlk DO
      bl := b.items;
      WHILE bl # NIL DO StringifyBlocksTo(r, bl.blocks); bl := bl.next END
    | b: A.DefListBlk DO
      d := b.items;
      WHILE d # NIL DO
        StringifyTo(r, d.term);
        bl := d.defs;
        WHILE bl # NIL DO StringifyBlocksTo(r, bl.blocks); bl := bl.next END;
        d := d.next
      END
    | b: A.TableBlk DO
      t := b;
      StringifyTo(r, t.caption.short); StringifyBlocksTo(r, t.caption.blocks);
      StringifyRows(r, t.head.rows);
      tb := t.bodies;
      WHILE tb # NIL DO StringifyRows(r, tb.head); StringifyRows(r, tb.body); tb := tb.next END;
      StringifyRows(r, t.foot.rows)
    ELSE
    END;
    b := b.next
  END
END StringifyBlocksTo;

(* The text of the blocks b, without their formatting, joined with
   nothing between them (stringify) *)
PROCEDURE StringifyBlocks*(b: A.Block): Rope;
  VAR r: Rope;
BEGIN
  r := NIL; StringifyBlocksTo(r, b);
  RETURN r
END StringifyBlocks;

(* makeSections *)

PROCEDURE (w: LevelWalker) Block*(b: A.Block): A.Block;
BEGIN
  IF (b IS A.HeaderBlk) & (b(A.HeaderBlk).level < w.min) THEN
    w.min := b(A.HeaderBlk).level
  END;
  RETURN b
END Block;

(* Whether b is a header of level at most level, or a Div that starts
   with one (headerLtEq) *)
PROCEDURE HeaderLtEq(level: INTEGER; b: A.Block): BOOLEAN;
BEGIN
  WHILE (b # NIL) & (b IS A.DivBlk) DO b := b(A.DivBlk).blocks END;
  RETURN (b # NIL) & (b IS A.HeaderBlk) & (b(A.HeaderBlk).level <= level)
END HeaderLtEq;

(* Whether the list of strings l has s *)
PROCEDURE HasString(l: A.StrList; s: Rope): BOOLEAN;
BEGIN
  WHILE l # NIL DO
    IF Ropes.Equal(l.s, s) THEN RETURN TRUE END;
    l := l.next
  END;
  RETURN FALSE
END HasString;

(* Whether the key-value list l has key *)
PROCEDURE HasKey(l: A.KeyVal; key: Rope): BOOLEAN;
BEGIN
  WHILE l # NIL DO
    IF Ropes.Equal(l.key, key) THEN RETURN TRUE END;
    l := l.next
  END;
  RETURN FALSE
END HasKey;

(* The decimal digits of n *)
PROCEDURE IntRope*(n: LONGINT): Rope;
  VAR s: ARRAY 24 OF CHAR; d: ARRAY 24 OF CHAR; i, k: INTEGER; neg: BOOLEAN;
BEGIN
  neg := n < 0; IF neg THEN n := -n END;
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  k := 0; IF neg THEN s[0] := "-"; k := 1 END;
  WHILE i > 0 DO DEC(i); s[k] := d[i]; INC(k) END;
  s[k] := 0X;
  RETURN Ropes.FromString(s)
END IntRope;

(* combineAttr a b: a's id unless it is empty; the classes of a, then
   those of b, each once; the key-values of b, after those of a whose
   keys b does not have *)
PROCEDURE CombineAttr(a, b: A.Attr): A.Attr;
  VAR r: A.Attr; l: A.StrList; kv: A.KeyVal;
BEGIN
  r := A.NewAttr(NIL);
  IF (a # NIL) & (Ropes.Length(a.id) > 0) THEN r.id := a.id
  ELSIF b # NIL THEN r.id := b.id
  END;
  IF a # NIL THEN
    l := a.classes;
    WHILE l # NIL DO IF ~HasString(r.classes, l.s) THEN A.AddClass(r, l.s) END; l := l.next END
  END;
  IF b # NIL THEN
    l := b.classes;
    WHILE l # NIL DO IF ~HasString(r.classes, l.s) THEN A.AddClass(r, l.s) END; l := l.next END
  END;
  IF a # NIL THEN
    kv := a.attrs;
    WHILE kv # NIL DO
      IF (b = NIL) OR ~HasKey(b.attrs, kv.key) THEN A.AddKeyVal(r, kv.key, kv.value) END;
      kv := kv.next
    END
  END;
  IF b # NIL THEN
    kv := b.attrs;
    WHILE kv # NIL DO A.AddKeyVal(r, kv.key, kv.value); kv := kv.next END
  END;
  RETURN r
END CombineAttr;

PROCEDURE^ Go(b: A.Block): A.Block;

(* Whether the Div d may become a section: it starts with a header,
   none of its other blocks is a header of the same or a lower level,
   and it is not a column or a fragment *)
PROCEDURE SectionDiv(d: A.DivBlk): BOOLEAN;
  VAR h: A.HeaderBlk; b: A.Block;
BEGIN
  IF (d.blocks = NIL) OR ~(d.blocks IS A.HeaderBlk)
     OR A.HasClass(d.attr, "column") OR A.HasClass(d.attr, "columns")
     OR A.HasClass(d.attr, "fragment") THEN
    RETURN FALSE
  END;
  h := d.blocks(A.HeaderBlk); b := h.next;
  WHILE b # NIL DO
    IF (b IS A.HeaderBlk) & (b(A.HeaderBlk).level <= h.level) THEN RETURN FALSE END;
    b := b.next
  END;
  RETURN TRUE
END SectionDiv;

(* The section that starts with the header h, its contents those of
   the list contents *)
PROCEDURE Section(h: A.HeaderBlk; contents: A.Block): A.Block;
  VAR level, i, n: INTEGER; newNum: ARRAY MaxLevels OF LONGINT;
    unnumbered, found: BOOLEAN; num, role: Rope; dattr, hattr: A.Attr;
    kv: A.KeyVal; l: A.StrList; nh: A.HeaderBlk; d: A.DivBlk;
BEGIN
  level := h.level;
  unnumbered := A.HasClass(h.attr, "unnumbered");
  n := 0;
  FOR i := minLevel TO level DO
    IF n < MaxLevels THEN
      IF n < lastLen THEN newNum[n] := lastNum[n] ELSE newNum[n] := 0 END;
      IF i = level THEN INC(newNum[n]) ELSIF i > level THEN newNum[n] := 0 END;
      INC(n)
    END
  END;
  IF (n > 0) & ~unnumbered THEN
    FOR i := 0 TO n - 1 DO lastNum[i] := newNum[i] END;
    lastLen := n
  END;
  contents := Go(contents);
  dattr := A.NewAttr(NIL); hattr := A.NewAttr(NIL);
  IF h.attr # NIL THEN dattr.id := h.attr.id END;
  A.AddClass(dattr, A.S("section"));
  IF h.attr # NIL THEN
    l := h.attr.classes;
    WHILE l # NIL DO A.AddClass(dattr, l.s); A.AddClass(hattr, l.s); l := l.next END
  END;
  num := A.GetKeyVal(h.attr, "number", found);
  IF ~found & numbering & ~unnumbered THEN
    num := NIL;
    FOR i := 0 TO n - 1 DO
      IF i > 0 THEN num := Ropes.Cat(num, Ropes.FromString(".")) END;
      num := Ropes.Cat(num, IntRope(newNum[i]))
    END;
    A.AddKeyVal(dattr, A.S("number"), num);
    A.AddKeyVal(hattr, A.S("number"), num)
  END;
  IF h.attr # NIL THEN
    kv := h.attr.attrs;
    WHILE kv # NIL DO
      A.AddKeyVal(dattr, kv.key, kv.value);
      IF Ropes.EqualString(kv.key, "epub:type") THEN
      ELSIF Ropes.EqualString(kv.key, "role") THEN
        role := kv.value;
        IF Ropes.EqualString(role, "tab") OR Ropes.EqualString(role, "presentation")
           OR Ropes.EqualString(role, "none") OR Ropes.EqualString(role, "treeitem")
           OR Ropes.EqualString(role, "menuitem") OR Ropes.EqualString(role, "button")
           OR Ropes.EqualString(role, "heading") THEN
          A.AddKeyVal(hattr, kv.key, kv.value)
        END
      ELSE A.AddKeyVal(hattr, kv.key, kv.value)
      END;
      kv := kv.next
    END
  END;
  NEW(nh); nh^ := h^;
  IF baseLevel >= 0 THEN nh.level := baseLevel + level - minLevel END;
  nh.attr := hattr; nh.next := contents;
  NEW(d); d.kind := A.Div; d.attr := dattr; d.blocks := nh; d.next := NIL;
  RETURN d
END Section;

(* The blocks of the list b, divided into sections (makeSections' go) *)
PROCEDURE Go(b: A.Block): A.Block;
  VAR out: A.Blocks; next, x, inner, contents, last: A.Block; h: A.HeaderBlk;
    d, nd, id: A.DivBlk;
BEGIN
  A.InitBlocks(out);
  WHILE b # NIL DO
    IF b IS A.HeaderBlk THEN
      h := b(A.HeaderBlk);
      (* the section's contents: up to a header of the same or a lower level *)
      contents := h.next; last := NIL; x := contents;
      WHILE (x # NIL) & ~HeaderLtEq(h.level, x) DO last := x; x := x.next END;
      next := x;
      IF last = NIL THEN contents := NIL ELSE last.next := NIL END;
      A.AddBlock(out, Section(h, contents));
      b := next
    ELSIF b IS A.DivBlk THEN
      d := b(A.DivBlk); next := b.next;
      NEW(nd); nd^ := d^; nd.next := NIL;
      IF SectionDiv(d) THEN
        inner := Go(d.blocks);
        IF (inner # NIL) & (inner.next = NIL) & (inner IS A.DivBlk) THEN
          id := inner(A.DivBlk);
          IF (d.attr = NIL) OR (Ropes.Length(d.attr.id) = 0)
             OR (id.attr = NIL) OR (Ropes.Length(id.attr.id) = 0)
             OR Ropes.Equal(d.attr.id, id.attr.id) THEN
            nd.attr := CombineAttr(id.attr, d.attr); nd.blocks := id.blocks
          ELSE nd.blocks := inner
          END
        ELSE nd.blocks := inner
        END
      ELSE nd.blocks := Go(d.blocks)
      END;
      A.AddBlock(out, nd);
      b := next
    ELSE
      next := b.next; b.next := NIL;
      A.AddBlock(out, b);
      b := next
    END
  END;
  RETURN out.first
END Go;

(* The blocks b divided into sections, as pandoc's makeSections divides
   them: each header, with the blocks after it up to the next header of
   the same or a lower level, becomes a Div with the class "section"
   and the header's id, classes and attributes; with numbering, an
   attribute "number" holds its section number. If base >= 0, the top
   sections' headers get level base, and those below them follow. The
   list b is used up. *)
PROCEDURE MakeSections*(number: BOOLEAN; base: INTEGER; b: A.Block): A.Block;
  VAR w: LevelWalker;
BEGIN
  NEW(w); w.min := 99;
  b := A.WalkBlocks(w, b);
  minLevel := w.min;
  numbering := number; baseLevel := base; lastLen := 0;
  RETURN Go(b)
END MakeSections;

(* Metadata *)

(* The inlines of the metadata value of key, as pandoc's docTitle,
   docDate and lookupMetaInlines-like accessors see them: a string as
   a Str, inlines, or the inlines of a single Plain or Para *)
PROCEDURE DocMeta*(meta: A.MetaMapV; key: ARRAY OF CHAR): A.Inline;
  VAR v: A.MetaValue; b: A.Block;
BEGIN
  v := A.GetMeta(meta, key);
  IF v = NIL THEN RETURN NIL END;
  WITH
    v: A.MetaStringV DO RETURN A.NewStr(v.s)
  | v: A.MetaInlinesV DO RETURN v.inlines
  | v: A.MetaBlocksV DO
    b := v.blocks;
    IF (b # NIL) & (b.next = NIL) & ((b.kind = A.Plain) OR (b.kind = A.Para)) THEN
      RETURN b(A.InlinesBlk).inlines
    END
  ELSE
  END;
  RETURN NIL
END DocMeta;

PROCEDURE AddLine(VAR first, last: A.InlineList; i: A.Inline);
  VAR l: A.InlineList;
BEGIN
  NEW(l); l.inlines := i; l.next := NIL;
  IF first = NIL THEN first := l ELSE last.next := l END;
  last := l
END AddLine;

(* The authors, as pandoc's docAuthors finds and orders them: a list's
   inlines, then its items that are a single Plain, then those that
   are a single Para, then its strings *)
PROCEDURE DocAuthors*(meta: A.MetaMapV): A.InlineList;
  VAR v, x: A.MetaValue; first, last: A.InlineList; it: A.MetaItem; pass: INTEGER;
    b: A.Block;
BEGIN
  first := NIL; last := NIL;
  v := A.GetMeta(meta, "author");
  IF v = NIL THEN RETURN NIL END;
  WITH
    v: A.MetaStringV DO AddLine(first, last, A.NewStr(v.s))
  | v: A.MetaInlinesV DO AddLine(first, last, v.inlines)
  | v: A.MetaListV DO
    FOR pass := 0 TO 3 DO
      it := v.items;
      WHILE it # NIL DO
        x := it.value;
        IF (pass = 0) & (x IS A.MetaInlinesV) THEN AddLine(first, last, x(A.MetaInlinesV).inlines)
        ELSIF (pass = 1) OR (pass = 2) THEN
          IF x IS A.MetaBlocksV THEN
            b := x(A.MetaBlocksV).blocks;
            IF (b # NIL) & (b.next = NIL)
               & ((pass = 1) & (b.kind = A.Plain) OR (pass = 2) & (b.kind = A.Para)) THEN
              AddLine(first, last, b(A.InlinesBlk).inlines)
            END
          END
        ELSIF (pass = 3) & (x IS A.MetaStringV) THEN AddLine(first, last, A.NewStr(x(A.MetaStringV).s))
        END;
        it := it.next
      END
    END
  ELSE
  END;
  RETURN first
END DocAuthors;

(* Dimensions *)

PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "0") & (ch <= "9")
END IsDigit;

(* Splits s, a dimension such as "2.5in", into the digits before and
   after its point (frac NIL if it has no point) and its unit; FALSE
   if its number is not one *)
PROCEDURE NumUnit*(s: Rope; VAR int, frac, unit: Rope): BOOLEAN;
  VAR b: POINTER TO ARRAY OF CHAR; n, i, e, p: LONGINT;
BEGIN
  n := Ropes.Length(s); NEW(b, n + 1);
  IF n > 0 THEN Ropes.Blit(s, 0, b^, 0, n) END;
  b[n] := 0X; e := 0;
  WHILE (e < n) & (IsDigit(b[e]) OR (b[e] = ".")) DO INC(e) END;
  i := 0; WHILE (i < e) & IsDigit(b[i]) DO INC(i) END;
  IF i = 0 THEN RETURN FALSE END;
  int := Ropes.FromSubchars(b^, 0, i); frac := NIL;
  IF i < e THEN
    p := i + 1; i := p;
    WHILE (i < e) & IsDigit(b[i]) DO INC(i) END;
    IF (i = p) OR (i < e) THEN RETURN FALSE END;
    frac := Ropes.FromSubchars(b^, p, i - p)
  END;
  unit := Ropes.FromSubchars(b^, e, n - e);
  RETURN TRUE
END NumUnit;

(* The digits of int without leading zeros, "0" if they are all zeros *)
PROCEDURE StripZeros*(int: Rope): Rope;
  VAR i, n: LONGINT;
BEGIN
  i := 0; n := Ropes.Length(int);
  WHILE (i < n - 1) & (Ropes.Fetch(int, i) = "0") DO INC(i) END;
  RETURN Ropes.Substring(int, i, n - i)
END StripZeros;

(* int.frac as pandoc's showFl writes it: rounded to 5 decimals,
   without trailing zeros or point *)
PROCEDURE ShowFl*(int, frac: Rope): Rope;
  VAR d: ARRAY 6 OF INTEGER; b: POINTER TO ARRAY OF CHAR; i, k, n: LONGINT; carry: BOOLEAN;
    r: Rope; s: ARRAY 8 OF CHAR;
BEGIN
  FOR i := 0 TO 5 DO
    IF i < Ropes.Length(frac) THEN d[i] := ORD(Ropes.Fetch(frac, i)) - ORD("0") ELSE d[i] := 0 END
  END;
  carry := d[5] >= 5;
  i := 4;
  WHILE carry & (i >= 0) DO
    IF d[i] = 9 THEN d[i] := 0 ELSE INC(d[i]); carry := FALSE END;
    DEC(i)
  END;
  IF carry THEN (* add one to int *)
    n := Ropes.Length(int); NEW(b, n + 1);
    IF n > 0 THEN Ropes.Blit(int, 0, b^, 0, n) END;
    k := n - 1;
    WHILE carry & (k >= 0) DO
      IF b[k] = "9" THEN b[k] := "0" ELSE b[k] := CHR(ORD(b[k]) + 1); carry := FALSE END;
      DEC(k)
    END;
    int := Ropes.FromSubchars(b^, 0, n);
    IF carry THEN int := Ropes.Cat(Ropes.FromChar("1"), int) END
  END;
  r := StripZeros(int);
  n := 5; WHILE (n > 0) & (d[n - 1] = 0) DO DEC(n) END;
  IF n > 0 THEN
    FOR i := 0 TO n - 1 DO s[i] := CHR(d[i] + ORD("0")) END;
    s[n] := 0X;
    r := Ropes.Cat(Ropes.Cat(r, Ropes.FromChar(".")), Ropes.FromString(s))
  END;
  RETURN r
END ShowFl;

(* printf "%0.<dec>f" x, as GHC writes it, for x >= 0: the shortest
   digits of x rounded, half to even, to dec decimals (0 < dec < 10) *)
PROCEDURE Fixed*(x: LONGREAL; dec: INTEGER): Rope;
  CONST max = 400;
  VAR digits: ARRAY 24 OF CHAR; is: ARRAY max OF INTEGER; n, e, d, k, c, j, v: INTEGER;
    out: Rope; s: ARRAY max OF CHAR; zero: BOOLEAN;
BEGIN
  IF x <= 0 THEN
    s[0] := "0"; s[1] := "."; FOR k := 1 TO dec DO s[k + 1] := "0" END; s[dec + 2] := 0X;
    RETURN Ropes.FromString(s)
  END;
  PdJson.ShortestDigits(x, digits, n, e);
  IF (e > max - 30) OR (-e > max - 30) THEN RETURN Fixed(0, dec) END; (* not a width *)
  (* the digits, with -e zeros before them if e < 0 *)
  j := 0;
  IF e < 0 THEN
    FOR k := 1 TO -e DO is[j] := 0; INC(j) END
  END;
  FOR k := 0 TO n - 1 DO is[j] := ORD(digits[k]) - ORD("0"); INC(j) END;
  n := j;
  IF e >= 0 THEN d := dec + e ELSE d := dec END;
  (* roundTo 10 d is *)
  c := 0;
  IF n <= d THEN
    WHILE n < d DO is[n] := 0; INC(n) END
  ELSE
    zero := TRUE;
    FOR k := d + 1 TO n - 1 DO IF is[k] # 0 THEN zero := FALSE END END;
    IF (is[d] = 5) & zero & ((d = 0) OR ~ODD(is[d - 1])) THEN c := 0
    ELSIF is[d] >= 5 THEN c := 1
    END;
    k := d - 1;
    WHILE k >= 0 DO
      v := is[k] + c;
      IF v = 10 THEN is[k] := 0; c := 1 ELSE is[k] := v; c := 0 END;
      DEC(k)
    END
  END;
  (* s: is[0 .. d-1], after a 1 if there is a carry *)
  j := 0;
  IF c = 1 THEN s[0] := "1"; j := 1 END;
  FOR k := 0 TO d - 1 DO s[j] := CHR(ORD("0") + is[k]); INC(j) END;
  IF j > dec THEN out := Ropes.FromSubchars(s, 0, j - dec) ELSE out := Ropes.FromChar("0") END;
  out := Ropes.Cat(out, Ropes.FromChar("."));
  RETURN Ropes.Cat(out, Ropes.FromSubchars(s, j - dec, dec))
END Fixed;

(* Blocks as inlines *)

(* The lines of a line block joined by LineBreaks, copied, appended
   to il *)
PROCEDURE JoinLines*(VAR il: A.Inlines; l: A.InlineList);
BEGIN
  WHILE l # NIL DO
    A.Append(il, A.CopyInlines(l.inlines));
    IF l.next # NIL THEN A.Append(il, A.NewSimple(A.LineBreak)) END;
    l := l.next
  END
END JoinLines;

PROCEDURE^ BlocksToInlines*(VAR l: A.Inlines; b: A.Block);

PROCEDURE BlockToInlines(VAR l: A.Inlines; b: A.Block);
  VAR it: A.BlockList; di: A.DefItem; row: A.Row; c: A.Cell; tb: A.TableBody; t: A.TableBlk;
    pass: INTEGER; firstRow: BOOLEAN;
BEGIN
  CASE b.kind OF
    A.Plain, A.Para, A.Header: A.Append(l, A.CopyInlines(b(A.InlinesBlk).inlines))
  | A.LineBlock: JoinLines(l, b(A.LineBlk).lines)
  | A.CodeBlock: A.Append(l, A.NewCode(b(A.CodeBlk).attr, b(A.CodeBlk).text))
  | A.RawBlock: A.Append(l, A.NewRawInline(b(A.RawBlk).format, b(A.RawBlk).text))
  | A.BlockQuote, A.Div, A.Figure: BlocksToInlines(l, b(A.BlocksBlk).blocks)
  | A.OrderedList, A.BulletList:
    it := b(A.ListBlk).items;
    WHILE it # NIL DO BlocksToInlines(l, it.blocks); it := it.next END
  | A.DefinitionList:
    di := b(A.DefListBlk).items;
    WHILE di # NIL DO
      A.Append(l, A.CopyInlines(di.term));
      A.Append(l, A.NewStr(Ropes.FromChar(":"))); A.Append(l, A.NewSimple(A.Space));
      it := di.defs;
      WHILE it # NIL DO BlocksToInlines(l, it.blocks); it := it.next END;
      di := di.next
    END
  | A.HorizontalRule:
  | A.Table:
    t := b(A.TableBlk); row := t.head.rows; tb := t.bodies; pass := 0; firstRow := TRUE;
    LOOP
      WHILE row # NIL DO
        IF ~firstRow THEN A.Append(l, A.NewSimple(A.LineBreak)) END;
        firstRow := FALSE;
        c := row.cells;
        WHILE c # NIL DO BlocksToInlines(l, c.blocks); c := c.next END;
        row := row.next
      END;
      IF pass = 1 THEN row := tb.body; pass := 2; tb := tb.next
      ELSIF tb # NIL THEN row := tb.head; pass := 1
      ELSIF pass # 3 THEN row := t.foot.rows; pass := 3
      ELSE EXIT
      END
    END
  END
END BlockToInlines;

(* blocksToInlines', appended to l: the blocks, a LineBreak between
   each two *)
PROCEDURE BlocksToInlines*(VAR l: A.Inlines; b: A.Block);
BEGIN
  WHILE b # NIL DO
    BlockToInlines(l, b);
    IF b.next # NIL THEN A.Append(l, A.NewSimple(A.LineBreak)) END;
    b := b.next
  END
END BlocksToInlines;

(* isTightList: whether each of the items starts with a Plain, is
   empty, or is just a tight list *)
PROCEDURE IsTightList*(items: A.BlockList): BOOLEAN;
  VAR b: A.Block;
BEGIN
  WHILE items # NIL DO
    b := items.blocks;
    IF (b # NIL) & (b.kind # A.Plain) THEN
      IF (b.next # NIL) OR (b.kind # A.BulletList) & (b.kind # A.OrderedList)
         OR ~IsTightList(b(A.ListBlk).items) THEN
        RETURN FALSE
      END
    END;
    items := items.next
  END;
  RETURN TRUE
END IsTightList;

(* toLegacyTable's rows *)

PROCEDURE AddPiece(r: LegacyRow; b: A.Block);
  VAR a: Pieces; i: LONGINT;
BEGIN
  IF r.n >= LEN(r.cells^) THEN
    NEW(a, 2 * LEN(r.cells^));
    FOR i := 0 TO r.n - 1 DO a[i] := r.cells[i] END;
    r.cells := a
  END;
  r.cells[r.n] := b; INC(r.n)
END AddPiece;

PROCEDURE SetPend(k, v: LONGINT);
  VAR a: Longs; i: LONGINT;
BEGIN
  IF k >= LEN(pend^) THEN
    NEW(a, 2 * k + 2);
    FOR i := 0 TO npend - 1 DO a[i] := pend[i] END;
    pend := a
  END;
  WHILE npend < k DO pend[npend] := 0; INC(npend) END;
  pend[k] := v;
  IF npend <= k THEN npend := k + 1 END
END SetPend;

(* placeCutCells: the row's cells cut into pieces, a cell spanning w
   columns giving its blocks and w-1 empty pieces, and leaving h-1
   empty pieces for the rows below it in each of its columns *)
PROCEDURE CutRow(row: A.Row): LegacyRow;
  VAR r: LegacyRow; c: A.Cell; k, w, h, i: LONGINT;
BEGIN
  NEW(r); r.n := 0; NEW(r.cells, 8); r.next := NIL;
  c := row.cells; k := 0;
  LOOP
    IF (k < npend) & (pend[k] > 0) THEN
      AddPiece(r, NIL); DEC(pend[k]); INC(k)
    ELSIF c # NIL THEN
      h := c.rowSpan; w := c.colSpan; IF w < 1 THEN w := 1 END;
      AddPiece(r, c.blocks);
      FOR i := 1 TO w - 1 DO AddPiece(r, NIL) END;
      FOR i := 0 TO w - 1 DO
        IF h > 1 THEN SetPend(k + i, h - 1) ELSE SetPend(k + i, 0) END
      END;
      INC(k, w); c := c.next
    ELSE
      npend := k; EXIT
    END
  END;
  RETURN r
END CutRow;

(* toLegacyTable: the table's rows with their spans cut into pieces;
   head is the first row of the head, NIL if there is none; rows the
   others, of the head, each body's head and body, and the foot *)
PROCEDURE LegacyRows*(t: A.TableBlk; VAR head, rows: LegacyRow);
  VAR row: A.Row; b: A.TableBody; last, r: LegacyRow; pass: INTEGER;
BEGIN
  NEW(pend, 16); npend := 0;
  head := NIL; rows := NIL; last := NIL;
  IF t.head.rows # NIL THEN head := CutRow(t.head.rows); row := t.head.rows.next
  ELSE row := NIL
  END;
  b := t.bodies; pass := 0;
  LOOP
    WHILE row # NIL DO
      r := CutRow(row);
      IF last = NIL THEN rows := r ELSE last.next := r END;
      last := r; row := row.next
    END;
    IF pass = 1 THEN row := b.body; pass := 2; b := b.next
    ELSIF b # NIL THEN row := b.head; pass := 1
    ELSIF pass # 3 THEN row := t.foot.rows; pass := 3
    ELSE EXIT
    END
  END;
  pend := NIL
END LegacyRows;

(* An empty cell, as pandoc's table builder adds *)
PROCEDURE EmptyCell*(): A.Cell;
  VAR c: A.Cell;
BEGIN
  NEW(c); c.attr := NIL; c.align := A.AlignDefault;
  c.rowSpan := 1; c.colSpan := 1; c.blocks := NIL; c.next := NIL;
  RETURN c
END EmptyCell;

(* normalizeHeaderSection width: the rows r, in order, clipped
   (clipRows) and placed on a grid width columns wide
   (placeRowSection), as pandoc's table builder does *)
PROCEDURE PlaceRows*(r: A.Row; width: LONGINT);
  VAR hang, newHang: Longs; n, k, pos, w, m: LONGINT; x: A.Row;
    c, next, last: A.Cell;
BEGIN
  n := 0; x := r;
  WHILE x # NIL DO INC(n); x := x.next END;
  NEW(hang, width + 1); NEW(newHang, width + 1);
  FOR k := 0 TO width - 1 DO hang[k] := 1 END;
  WHILE r # NIL DO
    c := r.cells;
    WHILE c # NIL DO
      IF c.rowSpan < 1 THEN c.rowSpan := 1 END;
      IF c.rowSpan > n THEN c.rowSpan := n END;
      c := c.next
    END;
    c := r.cells; r.cells := NIL; last := NIL; pos := 0;
    WHILE pos < width DO
      IF hang[pos] > 1 THEN newHang[pos] := hang[pos] - 1; INC(pos)
      ELSE
        IF c = NIL THEN c := EmptyCell() END;
        next := c.next;
        w := c.colSpan; IF w < 1 THEN w := 1 END;
        m := 0;
        WHILE (m < w) & (pos + m < width) & (hang[pos + m] = 1) DO INC(m) END;
        c.colSpan := m; c.next := NIL;
        FOR k := pos TO pos + m - 1 DO newHang[k] := c.rowSpan END;
        IF last = NIL THEN r.cells := c ELSE last.next := c END;
        last := c; INC(pos, m); c := next
      END
    END;
    FOR k := 0 TO width - 1 DO hang[k] := newHang[k] END;
    DEC(n); r := r.next
  END
END PlaceRows;

END PdShared.
