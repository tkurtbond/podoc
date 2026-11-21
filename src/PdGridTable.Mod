MODULE PdGridTable;
(* PdGridTable: grid tables, traced as the gridtables package traces
   them (Text.GridTable 0.1.1.0, its Parse and Trace), for pandoc's
   gridTableWith' (Text.Pandoc.Parsing.GridTable). Trace reads a table
   in the markdown reader's current text (PdMdBase's) and gives its
   cells on a grid of rows and columns, each cell's text ready to be
   read as blocks.

   The table's lines are laid out on a grid of character columns, East
   Asian wide characters taking two, as doclayout measures them
   (PdMdInline.CharWidth), the grid as wide as the widest line's
   realLength (PdMdInline.RealLength). Cells are traced from their
   top-left corners, in order, as gridtables traces them, misaligned
   last columns included. *)

IMPORT Utf8, Unicode, B := PdMdBase, I := PdMdInline;

CONST
  (* Alignments, as gridtables' *)
  AlignDefault* = 0; AlignLeft* = 1; AlignCenter* = 2; AlignRight* = 3;

  (* What is at a grid position, when it is not an ASCII character *)
  Missing = 0X; (* padding at the end of a short line *)
  Other = 1X; (* a character that is not ASCII *)
  Zero = 2X; (* zero-width characters and the one after them *)
  Pad = 3X; (* the second column of a wide character *)
  Out = 4X; (* outside the grid *)

TYPE
  Longs = POINTER TO ARRAY OF LONGINT;
  Bools = POINTER TO ARRAY OF BOOLEAN;
  Chars = POINTER TO ARRAY OF CHAR;

  (* A cell *)
  Cell* = POINTER TO CellDesc;
  CellDesc* = RECORD
    rowSpan*, colSpan*: LONGINT;
    text*: B.Buf; (* its lines, as pandoc gives them to its block
      parser: each without white space at its end, a leading space
      taken from each if all have one, each followed by a new line,
      and a new line after them *)
    top, left, bottom, right: LONGINT; (* its borders on the grid *)
    next: Cell
  END;

  Cells* = POINTER TO ARRAY OF Cell;

  (* A traced table *)
  Table* = RECORD
    rows*, cols*: LONGINT;
    cells*: Cells; (* row r, column c at r * cols + c, from 0; NIL
      where a cell spanning rows or columns continues *)
    headLen*: LONGINT; (* how many rows are the head *)
    foot*: LONGINT; (* the row index, from 1, of the separator above
      the foot, or -1 for no foot *)
    align*: Longs; (* each column's alignment *)
    width*: Longs (* each column's width in characters *)
  END;

VAR
  (* The grid: nr rows of nc columns, from 1 *)
  nr, nc: LONGINT;
  kind: Chars; (* an ASCII character, or Missing .. Pad *)
  gs, ge: Longs; (* the bytes of Other and Zero positions *)
  pending: Bools; (* corners not yet traced *)
  rowSep, colSep: Bools; (* separator rows and columns *)
  rs, cs: Longs; nrs, ncs: LONGINT; (* separators found tracing a cell *)
  first, last: Cell; (* the cells traced, in order *)

(* Haskell's isSpace *)
PROCEDURE IsHsSpace(r: Utf8.Rune): BOOLEAN;
BEGIN
  RETURN (r >= 9) & (r <= 13) OR (r = 20H) OR (r >= 80H) & (Unicode.Category(r) = Unicode.Zs)
END IsHsSpace;

(* Where t[from .. to-1], of the current text, ends without the white
   space at its end (T.stripEnd) *)
PROCEDURE StripEnd(from, to: LONGINT): LONGINT;
  VAR e, q: LONGINT; r: Utf8.Rune;
BEGIN
  e := from;
  WHILE from < to DO
    q := I.RuneAt(from, r);
    IF q <= from THEN q := from + 1 END;
    IF ~IsHsSpace(r) THEN e := q END;
    from := q
  END;
  IF e > to THEN e := to END;
  RETURN e
END StripEnd;

(* The lines *)

(* gridPart '-' at p: where it ends, or -1 *)
PROCEDURE GridPart(p: LONGINT): LONGINT;
BEGIN
  IF B.C(p) = ":" THEN INC(p) END;
  IF B.C(p) # "-" THEN RETURN -1 END;
  WHILE B.C(p) = "-" DO INC(p) END;
  IF B.C(p) = ":" THEN INC(p) END;
  IF B.C(p) # "+" THEN RETURN -1 END;
  RETURN p + 1
END GridPart;

(* The table's first line at p: where its last "+" ends, or -1 *)
PROCEDURE FirstLine(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF B.C(p) # "+" THEN RETURN -1 END;
  q := GridPart(p + 1);
  IF q < 0 THEN RETURN -1 END;
  WHILE (B.C(q) = ":") OR (B.C(q) = "-") DO
    q := GridPart(q);
    IF q < 0 THEN RETURN -1 END
  END;
  p := q;
  WHILE (B.C(q) = " ") OR (B.C(q) = 09X) DO INC(q) END;
  IF B.C(q) # 0AX THEN RETURN -1 END;
  RETURN p
END FirstLine;

(* Whether the line at p is indent spaces and then "+" or "|" *)
PROCEDURE GridLine(p, indent: LONGINT): BOOLEAN;
  VAR k: LONGINT;
BEGIN
  FOR k := 0 TO indent - 1 DO
    IF B.C(p + k) # " " THEN RETURN FALSE END
  END;
  RETURN (B.C(p + indent) = "+") OR (B.C(p + indent) = "|")
END GridLine;

(* Sets a[i] to v, making a longer if it must be *)
PROCEDURE SetLong(VAR a: Longs; i, v: LONGINT);
  VAR b: Longs; k: LONGINT;
BEGIN
  IF a = NIL THEN NEW(a, 16) END;
  IF i >= LEN(a^) THEN
    NEW(b, 2 * LEN(a^));
    FOR k := 0 TO LEN(a^) - 1 DO b[k] := a[k] END;
    a := b
  END;
  a[i] := v
END SetLong;

(* The grid *)

(* The grid position of row r, column c *)
PROCEDURE G(r, c: LONGINT): LONGINT;
BEGIN
  RETURN (r - 1) * nc + c - 1
END G;

(* What is at row r, column c *)
PROCEDURE K(r, c: LONGINT): CHAR;
BEGIN
  IF (r < 1) OR (r > nr) OR (c < 1) OR (c > nc) THEN RETURN Out END;
  RETURN kind[G(r, c)]
END K;

(* toCharGrid: the lines from s[k] to e[k], for k < n, on the grid *)
PROCEDURE CharGrid(s, e: Longs; n: LONGINT);
  VAR k, w, p, q, z, c, g, end: LONGINT; wd: INTEGER;

  PROCEDURE Put(ch: CHAR; from, to: LONGINT);
  BEGIN
    IF c <= nc THEN
      g := G(k + 1, c); kind[g] := ch; gs[g] := from; ge[g] := to
    END;
    INC(c)
  END Put;

  PROCEDURE PutChar(from, to: LONGINT);
  BEGIN
    IF (to = from + 1) & (ORD(B.t[from]) < 80H) THEN Put(B.t[from], from, to)
    ELSE Put(Other, from, to)
    END
  END PutChar;

BEGIN
  nr := n; nc := 0;
  FOR k := 0 TO n - 1 DO
    w := I.RealLength(s[k], e[k]); (* toCharGrid's realLength *)
    IF w > nc THEN nc := w END
  END;
  NEW(kind, nr * nc + 1); NEW(gs, nr * nc + 1); NEW(ge, nr * nc + 1);
  FOR g := 0 TO nr * nc - 1 DO kind[g] := Missing; gs[g] := 0; ge[g] := 0 END;
  FOR k := 0 TO n - 1 DO
    c := 1; p := s[k]; end := e[k];
    WHILE (p < end) & (c <= nc) DO
      wd := I.CharWidth(p, q); IF q > end THEN q := end END;
      IF wd = 2 THEN PutChar(p, q); Put(Pad, q, q); p := q
      ELSIF wd = 1 THEN PutChar(p, q); p := q
      ELSE
        z := p; p := q;
        WHILE (p < end) & (I.CharWidth(p, q) = 0) DO p := q; IF p > end THEN p := end END END;
        IF p >= end THEN Put(Zero, z, end)
        ELSE
          wd := I.CharWidth(p, q); IF q > end THEN q := end END;
          Put(Zero, z, q); p := q;
          IF wd = 2 THEN Put(Pad, q, q) END
        END
      END
    END
  END
END CharGrid;

(* colSpecsInLine ch on row i: whether it is a separator line of ch;
   the alignment of each of its parts in a[0 .. n-1] *)
PROCEDURE ColSpecs(ch: CHAR; i: LONGINT; VAR a: Longs; VAR n: LONGINT): BOOLEAN;
  VAR j, k, end: LONGINT; leftMark, rightMark: BOOLEAN; x: CHAR;
BEGIN
  n := 0;
  IF K(i, 1) # "+" THEN RETURN FALSE END;
  j := 2;
  WHILE j < nc DO
    k := j + 1;
    LOOP
      x := K(i, k);
      IF x = "+" THEN end := k; rightMark := FALSE; EXIT
      ELSIF x = ":" THEN
        IF K(i, k + 1) = "+" THEN end := k + 1; rightMark := TRUE; EXIT END;
        RETURN FALSE
      ELSIF x = ch THEN INC(k)
      ELSE RETURN FALSE
      END
    END;
    leftMark := K(i, j) = ":";
    IF leftMark & rightMark THEN SetLong(a, n, AlignCenter)
    ELSIF leftMark THEN SetLong(a, n, AlignLeft)
    ELSIF rightMark THEN SetLong(a, n, AlignRight)
    ELSE SetLong(a, n, AlignDefault)
    END;
    INC(n);
    j := end + 1
  END;
  RETURN TRUE
END ColSpecs;

(* convertToNormalLines for row i: "=" and ":" become "-" *)
PROCEDURE Normal(i: LONGINT);
  VAR j: LONGINT;
BEGIN
  FOR j := 1 TO nc DO
    IF (kind[G(i, j)] = "=") OR (kind[G(i, j)] = ":") THEN kind[G(i, j)] := "-" END
  END
END Normal;

(* Tracing *)

PROCEDURE PushRow(i: LONGINT);
BEGIN
  SetLong(rs, nrs, i); INC(nrs)
END PushRow;

PROCEDURE PushCol(j: LONGINT);
BEGIN
  SetLong(cs, ncs, j); INC(ncs)
END PushCol;

(* scanLeft and scanUp from the bottom-right corner (bottom, right)
   back to the top-left corner (top, left) *)
PROCEDURE ScanLeft(top, left, bottom, right: LONGINT): BOOLEAN;
  VAR i, j: LONGINT; x: CHAR;
BEGIN
  IF K(bottom, left) # "+" THEN RETURN FALSE END;
  FOR j := left + 1 TO right - 1 DO
    x := K(bottom, j);
    IF (x # "+") & (x # "-") THEN RETURN FALSE END
  END;
  FOR i := top + 1 TO bottom - 1 DO
    x := K(i, left);
    IF (x # "+") & (x # "|") THEN RETURN FALSE END
  END;
  FOR j := left + 1 TO right - 1 DO
    IF K(bottom, j) = "+" THEN PushCol(j) END
  END;
  FOR i := top + 1 TO bottom - 1 DO
    IF K(i, left) = "+" THEN PushRow(i) END
  END;
  RETURN TRUE
END ScanLeft;

(* scanDown in the column right, from the top-left corner (top, left):
   the cell's bottom *)
PROCEDURE ScanDown(top, left, right: LONGINT; VAR bottom: LONGINT): BOOLEAN;
  VAR i, mark: LONGINT; x: CHAR;
BEGIN
  mark := nrs; i := top + 1;
  LOOP
    x := K(i, right);
    IF x = Out THEN nrs := mark; RETURN FALSE
    ELSIF x = "+" THEN
      PushRow(i);
      IF ScanLeft(top, left, i, right) THEN bottom := i; RETURN TRUE END
    ELSIF (x # "|") & (right # nc) THEN nrs := mark; RETURN FALSE
    END;
    INC(i)
  END
END ScanDown;

(* scanRestOfLines: lastCellInRow's cell from (top, left), its right
   at the grid's end *)
PROCEDURE RestOfLines(top, left: LONGINT; VAR bottom: LONGINT): BOOLEAN;
  VAR i, j: LONGINT; ok: BOOLEAN; x: CHAR;
BEGIN
  FOR i := top + 1 TO nr DO
    IF K(i, left) = "+" THEN
      ok := TRUE; j := left + 1;
      WHILE ok & (j <= nc) DO
        x := K(i, j); ok := (x = "+") OR (x = "-") OR (x = Missing); INC(j)
      END;
      IF ok THEN bottom := i; RETURN TRUE END
    END
  END;
  RETURN FALSE
END RestOfLines;

(* scanRight's loop from column j: the cell from (top, left) *)
PROCEDURE ScanRight(top, left, j: LONGINT; VAR bottom, right: LONGINT): BOOLEAN;
  VAR mark: LONGINT;
BEGIN
  mark := ncs;
  WHILE K(top, j) = "-" DO INC(j) END;
  IF K(top, j) # "+" THEN RETURN FALSE END;
  PushCol(j);
  IF ScanDown(top, left, j, bottom) THEN right := j; RETURN TRUE END;
  IF ScanRight(top, left, j + 1, bottom, right) THEN RETURN TRUE END;
  ncs := mark;
  (* lastCellInRow, whose separators replace those found so far *)
  IF (K(top, j + 1) = Missing) & RestOfLines(top, left, bottom) THEN
    nrs := 0; ncs := 0; PushRow(bottom); PushCol(nc);
    right := nc; RETURN TRUE
  END;
  RETURN FALSE
END ScanRight;

(* traceCharGrid *)
PROCEDURE TraceGrid;
  VAR r, c, k, bottom, right: LONGINT; cell: Cell;
BEGIN
  NEW(pending, nr * nc + 1); NEW(rowSep, nr + 2); NEW(colSep, nc + 2);
  FOR k := 0 TO nr * nc DO pending[k] := FALSE END;
  FOR k := 0 TO nr + 1 DO rowSep[k] := FALSE END;
  FOR k := 0 TO nc + 1 DO colSep[k] := FALSE END;
  pending[0] := TRUE; rowSep[1] := TRUE; colSep[1] := TRUE;
  first := NIL; last := NIL;
  FOR r := 1 TO nr DO
    FOR c := 1 TO nc DO
      IF pending[G(r, c)] THEN
        nrs := 0; ncs := 0;
        IF ScanRight(r, c, c + 1, bottom, right) THEN
          NEW(cell); cell.top := r; cell.left := c;
          cell.bottom := bottom; cell.right := right; cell.next := NIL;
          IF last = NIL THEN first := cell ELSE last.next := cell END;
          last := cell;
          FOR k := 0 TO nrs - 1 DO rowSep[rs[k]] := TRUE END;
          FOR k := 0 TO ncs - 1 DO colSep[cs[k]] := TRUE END;
          IF right <= nc THEN pending[G(r, right)] := TRUE END;
          pending[G(bottom, c)] := TRUE
        END
      END
    END
  END
END TraceGrid;

(* A cell's text *)

(* Where b.t[from .. to-1] ends without white space at its end *)
PROCEDURE BufStripEnd(VAR b: B.Buf; from, to: LONGINT): LONGINT;
  VAR e, q: LONGINT; r: Utf8.Rune;
BEGIN
  e := from;
  WHILE from < to DO
    q := from;
    IF ORD(b.t[from]) < 80H THEN r := ORD(b.t[from]); q := from + 1
    ELSIF ~Utf8.Decode(b.t^, q, r) OR (q <= from) OR (q > to) THEN
      r := 0FFFDH; q := from + 1
    END;
    IF ~IsHsSpace(r) THEN e := q END;
    from := q
  END;
  RETURN e
END BufStripEnd;

(* getLines and gridTableWith''s mapCells: the text of cell x *)
PROCEDURE CellText(x: Cell);
  VAR raw: B.Buf; s, e: Longs; n, i, j, k, g: LONGINT; drop: BOOLEAN;
    ch: CHAR;
BEGIN
  B.InitBuf(raw); n := 0; s := NIL; e := NIL; drop := TRUE;
  FOR i := x.top + 1 TO x.bottom - 1 DO
    SetLong(s, n, raw.len);
    FOR j := x.left + 1 TO x.right - 1 DO
      g := G(i, j); ch := kind[g];
      IF ch >= " " THEN B.PutChar(raw, ch)
      ELSIF (ch = Other) OR (ch = Zero) THEN
        FOR k := gs[g] TO ge[g] - 1 DO B.PutChar(raw, B.t[k]) END
      END
    END;
    SetLong(e, n, BufStripEnd(raw, s[n], raw.len));
    IF (e[n] > s[n]) & (raw.t[s[n]] # " ") THEN drop := FALSE END;
    INC(n)
  END;
  B.InitBuf(x.text);
  FOR k := 0 TO n - 1 DO
    i := s[k];
    IF drop & (e[k] > i) THEN INC(i) END;
    WHILE i < e[k] DO B.PutChar(x.text, raw.t[i]); INC(i) END;
    B.PutChar(x.text, 0AX)
  END;
  B.PutChar(x.text, 0AX)
END CellText;

(* An empty cell, for a place no cell covers *)
PROCEDURE EmptyCell(): Cell;
  VAR x: Cell;
BEGIN
  NEW(x); x.rowSpan := 1; x.colSpan := 1; x.next := NIL;
  B.InitBuf(x.text); B.PutChar(x.text, 0AX);
  RETURN x
END EmptyCell;

(* tableFromTraceInfo *)
PROCEDURE MakeTable(VAR t: Table; seps: Longs; nseps: LONGINT;
    a1: Longs; n1: LONGINT; ok1: BOOLEAN; aSep: Longs; nSep: LONGINT);
  VAR rowIdx, colIdx, colPos, contd: Longs; i, j, k, n, rnum, cnum, lastRow: LONGINT;
    x: Cell;
BEGIN
  NEW(rowIdx, nr + 2); NEW(colIdx, nc + 2);
  n := 0; lastRow := 0;
  FOR i := 1 TO nr DO
    rowIdx[i] := 0;
    IF rowSep[i] THEN INC(n); rowIdx[i] := n; lastRow := i END
  END;
  t.rows := n - 1;
  n := 0; NEW(colPos, nc + 2);
  FOR j := 1 TO nc DO
    colIdx[j] := 0;
    IF colSep[j] THEN INC(n); colIdx[j] := n; colPos[n] := j END
  END;
  t.cols := n - 1;
  NEW(t.align, t.cols + 1); NEW(t.width, t.cols + 1);
  FOR k := 0 TO t.cols - 1 DO
    t.width[k] := colPos[k + 2] - colPos[k + 1] - 1;
    t.align[k] := AlignDefault;
    IF nseps > 0 THEN
      IF k < nSep THEN t.align[k] := aSep[k] END
    ELSIF ok1 & (k < n1) THEN t.align[k] := a1[k]
    END
  END;
  t.headLen := 0; t.foot := -1;
  IF nseps > 0 THEN
    IF rowSep[seps[0]] THEN t.headLen := rowIdx[seps[0]] - 1 END;
    IF (nseps >= 2) & (seps[nseps - 1] = lastRow) & rowSep[seps[nseps - 2]] THEN
      t.foot := rowIdx[seps[nseps - 2]]
    END
  END;
  NEW(t.cells, t.rows * t.cols + 1); NEW(contd, t.rows * t.cols + 1);
  FOR k := 0 TO t.rows * t.cols DO t.cells[k] := NIL; contd[k] := 0 END;
  x := first;
  WHILE x # NIL DO
    rnum := rowIdx[x.top] - 1; cnum := colIdx[x.left] - 1;
    x.rowSpan := rowIdx[x.bottom] - 1 - rnum;
    x.colSpan := colIdx[x.right] - 1 - cnum;
    FOR i := rnum TO rnum + x.rowSpan - 1 DO
      FOR j := cnum TO cnum + x.colSpan - 1 DO
        t.cells[i * t.cols + j] := NIL; contd[i * t.cols + j] := 1
      END
    END;
    t.cells[rnum * t.cols + cnum] := x; contd[rnum * t.cols + cnum] := 0;
    x := x.next
  END;
  FOR k := 0 TO t.rows * t.cols - 1 DO
    IF t.cells[k] # NIL THEN CellText(t.cells[k])
    ELSIF contd[k] = 0 THEN t.cells[k] := EmptyCell()
    END
  END
END MakeTable;

(* gridTable, with the table indented by indent spaces, at p, the
   start of a line: where it ends, after the new line of its last
   line, or -1; the table in t *)
PROCEDURE Trace*(p, indent: LONGINT; VAR t: Table): LONGINT;
  VAR s, e, seps, a1, aSep, a: Longs; n, q, k, i, nseps, n1, nSep, na: LONGINT;
    ok1: BOOLEAN;
BEGIN
  IF ~GridLine(p, indent) THEN RETURN -1 END;
  q := FirstLine(p + indent);
  IF q < 0 THEN RETURN -1 END;
  s := NIL; e := NIL;
  SetLong(s, 0, p + indent); SetLong(e, 0, q); n := 1;
  p := B.AnyLine(p);
  LOOP
    IF (p < 0) OR ~GridLine(p, indent) THEN EXIT END;
    q := B.LineEnd(p);
    IF q >= B.len THEN EXIT END;
    k := p + indent;
    WHILE (k < q) & (B.t[k] # 0DX) DO INC(k) END;
    IF k < q THEN EXIT END;
    SetLong(s, n, p + indent); SetLong(e, n, StripEnd(p + indent, q)); INC(n);
    p := q + 1
  END;
  IF n < 2 THEN RETURN -1 END;
  CharGrid(s, e, n);
  a1 := NIL; ok1 := ColSpecs("-", 1, a1, n1);
  seps := NIL; nseps := 0; aSep := NIL; nSep := 0; a := NIL;
  FOR i := 1 TO nr DO
    IF ColSpecs("=", i, a, na) THEN
      IF nseps = 0 THEN aSep := a; nSep := na; a := NIL END;
      SetLong(seps, nseps, i); INC(nseps)
    END
  END;
  Normal(1);
  FOR k := 0 TO nseps - 1 DO Normal(seps[k]) END;
  TraceGrid;
  IF first = NIL THEN RETURN -1 END;
  MakeTable(t, seps, nseps, a1, n1, ok1, aSep, nSep);
  first := NIL; last := NIL; kind := NIL; gs := NIL; ge := NIL;
  pending := NIL; rowSep := NIL; colSep := NIL;
  RETURN p
END Trace;

BEGIN
  rs := NIL; cs := NIL; first := NIL; last := NIL
END PdGridTable.
