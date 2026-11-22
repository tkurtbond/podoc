MODULE PdCodeAlign;
(* PdCodeAlign: the layout of aligned code in the proportional style
   (PLAN.md Phase 24.4; docs/research/syntax-highlighting-small.md
   §12.3; docs/research/vgrind.md §8).

   Layout cuts a code block, with the spans PdCode found in it, into
   lines, each line into segments and each segment into pieces:

   - a line's leading spaces give its indentation, the source column
     of its first segment;
   - inside a line, a run of two or more spaces ends a segment, and
     the next one starts at its source column; a single space stays in
     the segment; trailing spaces are dropped;
   - a string is never cut: its spaces are its own (decision 44);
   - a piece is a run of text of one kind (PdCode's Plain, Reserved,
     Comment or String) inside one segment, so a comment cut by a run
     of spaces or a line end is two pieces, each closed by the writer.

   Columns are counted in characters (UTF-8 code points), from 0.

   Groups, for the elastic and hybrid alignments: consecutive lines,
   with no blank line between them, that have a later segment (not the
   first) at the same column. Every later segment is in a group, of one
   line if need be. Groups are numbered from 1 in the order of their
   column, and of their first line for the same column, which is the
   order a writer must place them in: the text before a group's
   segment holds only segments at smaller columns.

   The writers turn columns into lengths: the column times code-column,
   at least code-gap after the text before it (decision 32). *)

IMPORT Ropes, PdCode;

CONST
  (* alignments: --code-align (decision 33) *)
  None* = 0; Fixed* = 1; Elastic* = 2; Hybrid* = 3;

TYPE
  Rope = Ropes.Rope;

  (* A piece: text of one kind, from PdCode (Plain, Reserved, Comment,
     String), inside one segment *)
  Piece* = POINTER TO PieceDesc;
  PieceDesc* = RECORD
    kind*: INTEGER;
    text*: Rope;
    next*: Piece
  END;

  Group* = POINTER TO GroupDesc;

  (* A segment: pieces placed at the source column col; group is NIL
     for a line's first segment; gap is the number of spaces before
     it in the source (the indentation, for the first) *)
  Segment* = POINTER TO SegmentDesc;
  SegmentDesc* = RECORD
    col*: LONGINT;
    gap*: LONGINT;
    group*: Group;
    pieces*: Piece;
    next*: Segment
  END;

  (* A line: its segments, NIL if it is blank; the first segment's
     column is the line's indentation; trail is the number of spaces
     after its last segment, or of a blank line *)
  Line* = POINTER TO LineDesc;
  LineDesc* = RECORD
    segs*: Segment;
    trail*: LONGINT;
    next*: Line
  END;

  (* A member of a group: the line, and its segment in the group *)
  Member* = POINTER TO MemberDesc;
  MemberDesc* = RECORD
    line*: Line;
    seg*: Segment;
    next*: Member
  END;

  GroupDesc* = RECORD
    id*: INTEGER;          (* 1, 2, ... in the order to place them *)
    col*: LONGINT;         (* the source column of its segments *)
    first: LONGINT;        (* its first line's number, for the order *)
    members*: Member;      (* in the order of the lines *)
    next*: Group           (* the next in id order *)
  END;

  (* A block: its lines and its groups, in id order *)
  Block* = POINTER TO BlockDesc;
  BlockDesc* = RECORD
    lines*: Line;
    groups*: Group;
    nGroups*: INTEGER
  END;

  (* The state of Layout's cutting *)
  Cutter = RECORD
    text: Rope;
    b: Block;
    line, lastLine: Line;
    seg, lastSeg: Segment;
    piece: Piece;          (* the last piece of seg, NIL if none *)
    pStart, pEnd: LONGINT; (* the open piece's text, if piece # NIL *)
    col: LONGINT;          (* the column of the next character *)
    spaces: LONGINT;       (* spaces not yet given since the last text *)
    spaceAt: LONGINT;      (* where the last of them is *)
    spaceKind: INTEGER;    (* and its kind *)
    started: BOOLEAN       (* the line has text *)
  END;

(* Closes the open piece, giving it its text *)
PROCEDURE ClosePiece(VAR c: Cutter);
BEGIN
  IF (c.piece # NIL) & (c.piece.text = NIL) THEN
    c.piece.text := Ropes.Substring(c.text, c.pStart, c.pEnd - c.pStart)
  END
END ClosePiece;

(* Adds the byte at i, of the given kind, to the open segment *)
PROCEDURE Add(VAR c: Cutter; i: LONGINT; kind: INTEGER);
  VAR p: Piece;
BEGIN
  IF (c.piece # NIL) & (c.piece.text = NIL) & (c.piece.kind = kind) & (c.pEnd = i) THEN
    c.pEnd := i + 1
  ELSE
    ClosePiece(c);
    NEW(p); p.kind := kind; p.text := NIL; p.next := NIL;
    IF c.piece = NIL THEN c.seg.pieces := p ELSE c.piece.next := p END;
    c.piece := p; c.pStart := i; c.pEnd := i + 1
  END
END Add;

(* Opens a segment at the current column *)
PROCEDURE NewSegment(VAR c: Cutter);
  VAR s: Segment;
BEGIN
  ClosePiece(c);
  NEW(s); s.col := c.col; s.group := NIL;
  IF c.seg = NIL THEN s.gap := c.col ELSE s.gap := c.spaces END; s.pieces := NIL; s.next := NIL;
  IF c.seg = NIL THEN c.line.segs := s ELSE c.seg.next := s END;
  c.seg := s; c.piece := NIL
END NewSegment;

(* Ends the open line, if any: its trailing spaces *)
PROCEDURE EndLine(VAR c: Cutter);
BEGIN
  IF c.line # NIL THEN
    IF c.started THEN c.line.trail := c.spaces ELSE c.line.trail := c.col END
  END
END EndLine;

(* Opens a new line *)
PROCEDURE NewLine(VAR c: Cutter);
  VAR l: Line;
BEGIN
  ClosePiece(c); EndLine(c);
  NEW(l); l.segs := NIL; l.trail := 0; l.next := NIL;
  IF c.line = NIL THEN c.b.lines := l ELSE c.line.next := l END;
  c.line := l; c.seg := NIL; c.piece := NIL;
  c.col := 0; c.spaces := 0; c.started := FALSE
END NewLine;

(* Takes the byte ch at i, of the given kind *)
PROCEDURE Take(VAR c: Cutter; i: LONGINT; ch: CHAR; kind: INTEGER);
BEGIN
  IF ch = 0AX THEN NewLine(c)
  ELSIF (ch = " ") & (kind # PdCode.String) THEN
    IF c.started THEN INC(c.spaces); c.spaceAt := i; c.spaceKind := kind END;
    INC(c.col)
  ELSE
    IF ~c.started THEN c.started := TRUE; NewSegment(c)
    ELSIF c.spaces >= 2 THEN NewSegment(c)
    ELSIF c.spaces = 1 THEN Add(c, c.spaceAt, c.spaceKind)
    END;
    c.spaces := 0;
    Add(c, i, kind);
    IF (ORD(ch) < 80H) OR (ORD(ch) >= 0C0H) THEN INC(c.col) END
  END
END Take;

(* Finds the block's groups: each later segment joins the group of the
   segment at its column on the line before, if that line has one *)
PROCEDURE FindGroups(b: Block);
  VAR l, prev: Line; s, t: Segment; g, p, q: Group; m, mm: Member; n: LONGINT;
    found: BOOLEAN;
BEGIN
  prev := NIL; l := b.lines; n := 0;
  WHILE l # NIL DO
    IF l.segs # NIL THEN
      s := l.segs.next;
      WHILE s # NIL DO
        g := NIL;
        IF prev # NIL THEN
          t := prev.segs.next; found := FALSE;
          WHILE (t # NIL) & ~found DO
            IF t.col = s.col THEN g := t.group; found := TRUE END;
            t := t.next
          END
        END;
        NEW(m); m.line := l; m.seg := s; m.next := NIL;
        IF g = NIL THEN
          NEW(g); g.id := 0; g.col := s.col; g.first := n; g.members := m;
          (* insert in order of column, then of first line *)
          p := NIL; q := b.groups;
          WHILE (q # NIL) & ((q.col < g.col) OR (q.col = g.col) & (q.first < g.first)) DO
            p := q; q := q.next
          END;
          g.next := q;
          IF p = NIL THEN b.groups := g ELSE p.next := g END;
          INC(b.nGroups)
        ELSE
          mm := g.members;
          WHILE mm.next # NIL DO mm := mm.next END;
          mm.next := m
        END;
        s.group := g;
        s := s.next
      END;
      prev := l
    ELSE prev := NIL
    END;
    INC(n); l := l.next
  END;
  g := b.groups; n := 0;
  WHILE g # NIL DO INC(n); g.id := SHORT(n); g := g.next END
END FindGroups;

(* The layout of the code text, with the spans PdCode.Scan gave for it
   (NIL: all plain), cut into lines, segments and pieces, with its
   groups *)
PROCEDURE Layout*(text: Rope; spans: PdCode.Span): Block;
  VAR c: Cutter; i, n, end: LONGINT; sp: PdCode.Span; kind: INTEGER;
BEGIN
  NEW(c.b); c.b.lines := NIL; c.b.groups := NIL; c.b.nGroups := 0;
  c.text := text; c.line := NIL; c.piece := NIL;
  NewLine(c);
  n := Ropes.Length(text); sp := spans; i := 0;
  WHILE i < n DO
    WHILE (sp # NIL) & (sp.start + sp.len <= i) DO sp := sp.next END;
    IF (sp # NIL) & (sp.start <= i) THEN kind := sp.kind; end := sp.start + sp.len
    ELSE kind := PdCode.Plain;
      IF sp # NIL THEN end := sp.start ELSE end := n END
    END;
    WHILE i < end DO Take(c, i, Ropes.Fetch(text, i), kind); INC(i) END
  END;
  ClosePiece(c); EndLine(c);
  FindGroups(c.b);
  RETURN c.b
END Layout;

(* The alignment named s: None, Fixed, Elastic or Hybrid; -1 if s names
   none *)
PROCEDURE AlignOf*(s: ARRAY OF CHAR): INTEGER;
BEGIN
  IF s = "none" THEN RETURN None
  ELSIF s = "fixed" THEN RETURN Fixed
  ELSIF s = "elastic" THEN RETURN Elastic
  ELSIF s = "hybrid" THEN RETURN Hybrid
  END;
  RETURN -1
END AlignOf;

END PdCodeAlign.
