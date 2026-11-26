MODULE PdOrgInline;

(* The Org reader's inlines, as pandoc's Readers/Org/Inlines.hs reads
   them, and the starts of blocks that end a paragraph, its
   Readers/Org/BlockStarts.hs.

   Phase 26.1 reads text: Str, Space, SoftBreak, and LineBreak for \\ at
   the end of a line or every new line under \n:t. The text read is
   PdMdBase's. *)

IMPORT A := PdAst, B := PdMdBase, MI := PdMdInline, M := PdOrgMeta;

VAR
  fancyLists*: BOOLEAN; (* the extension fancy_lists *)

(* Block starts. Each takes the start of a line, p, and returns where
   what it matched ends, or -1. *)

(* exampleLineStart: a colon, and a space or the end of the line *)
PROCEDURE ExampleLineStart*(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF B.C(p) # ":" THEN RETURN -1 END;
  IF B.C(p + 1) = " " THEN RETURN p + 2
  ELSIF B.C(p + 1) = 0AX THEN RETURN p + 1
  END;
  RETURN -1
END ExampleLineStart;

(* hline: five or more dashes alone on a line *)
PROCEDURE Hline*(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF ~B.Looking(p, "-----") THEN RETURN -1 END;
  INC(p, 5);
  WHILE B.C(p) = "-" DO INC(p) END;
  p := B.SkipSpaces(p);
  IF B.C(p) = 0AX THEN RETURN p + 1 END;
  RETURN -1
END Hline;

(* headerStart: one or more stars and one or more spaces; level is the
   number of stars *)
PROCEDURE HeaderStart*(p: LONGINT; VAR level: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := p;
  WHILE B.C(q) = "*" DO INC(q) END;
  IF (q = p) OR (B.C(q) # " ") THEN RETURN -1 END;
  level := q - p;
  WHILE B.C(q) = " " DO INC(q) END;
  RETURN q
END HeaderStart;

(* metaLineStart: #+ *)
PROCEDURE MetaLineStart*(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF B.Looking(p, "#+") THEN RETURN p + 2 END;
  RETURN -1
END MetaLineStart;

(* commentLineStart: # before a space or a new line *)
PROCEDURE CommentLineStart*(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF (B.C(p) = "#") & ((B.C(p + 1) = " ") OR (B.C(p + 1) = 0AX)) THEN
    RETURN p + 1
  END;
  RETURN -1
END CommentLineStart;

(* gridTableStart: +- *)
PROCEDURE GridTableStart*(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF B.Looking(p, "+-") THEN RETURN p + 2 END;
  RETURN -1
END GridTableStart;

(* tableStart: | *)
PROCEDURE TableStart*(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF B.C(p) = "|" THEN RETURN p + 1 END;
  RETURN -1
END TableStart;

(* noteMarker: [digits] or [fn:name] *)
PROCEDURE NoteMarker*(p: LONGINT): LONGINT;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  IF B.C(p) # "[" THEN RETURN -1 END;
  q := p + 1;
  IF B.IsDigit(B.C(q)) THEN
    INC(q);
    WHILE B.IsDigit(B.C(q)) DO INC(q) END;
    IF B.C(q) = "]" THEN RETURN q + 1 END
  END;
  IF B.Looking(p + 1, "fn:") THEN
    q := p + 4;
    ch := B.C(q);
    IF (q >= B.len) OR (ch = 0AX) OR (ch = 0DX) OR (ch = 09X) OR (ch = " ") THEN
      RETURN -1
    END;
    INC(q);
    LOOP
      ch := B.C(q);
      IF ch = "]" THEN RETURN q + 1 END;
      IF (q >= B.len) OR (ch = 0AX) OR (ch = 0DX) OR (ch = 09X) OR (ch = " ") THEN
        RETURN -1
      END;
      INC(q)
    END
  END;
  RETURN -1
END NoteMarker;

(* drawerStart: :NAME: alone on a line *)
PROCEDURE DrawerStart*(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  p := B.SkipSpaces(p);
  IF B.C(p) # ":" THEN RETURN -1 END;
  INC(p);
  LOOP
    ch := B.C(p);
    IF ch = ":" THEN EXIT END;
    IF (p >= B.len) OR (ch <= " ") THEN RETURN -1 END;
    INC(p)
  END;
  p := B.SkipSpaces(p + 1);
  IF B.C(p) = 0AX THEN RETURN p + 1 END;
  RETURN -1
END DrawerStart;

(* Whether t[from .. to-1] is one of the math environments pandoc's
   LaTeX reader reads inline (inlineEnvironmentNames). *)
PROCEDURE InlineEnvironment(from, to: LONGINT): BOOLEAN;
  CONST Names = " displaymath math equation equation* gather gather* multline multline* eqnarray eqnarray* align align* alignat alignat* flalign flalign* dmath dmath* dgroup dgroup* darray darray* subequations ";
  VAR names: ARRAY 256 OF CHAR; i, j, n: LONGINT;
BEGIN
  names := Names; n := to - from;
  i := 0;
  WHILE names[i] # 0X DO
    IF names[i] = " " THEN
      j := 0;
      WHILE (j < n) & (names[i + 1 + j] = B.t[from + j]) DO INC(j) END;
      IF (j = n) & (names[i + 1 + j] = " ") THEN RETURN TRUE END
    END;
    INC(i)
  END;
  RETURN FALSE
END InlineEnvironment;

(* latexEnvStart: \begin{name}, name not a math environment read
   inline *)
PROCEDURE LatexEnvStart*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF ~B.Looking(p, "\begin{") THEN RETURN -1 END;
  INC(p, 7); q := p;
  WHILE B.IsAlnum(B.C(q)) OR (B.C(q) >= 80X) DO INC(q) END;
  IF q = p THEN RETURN -1 END;
  IF B.C(q) = "*" THEN INC(q) END;
  IF (B.C(q) # "}") OR InlineEnvironment(p, q) THEN RETURN -1 END;
  RETURN q + 1
END LatexEnvStart;

(* skipSpaces1 <|> lookAhead eol, after a list marker *)
PROCEDURE AfterMarker(p: LONGINT): LONGINT;
BEGIN
  IF B.IsSpace(B.C(p)) THEN RETURN B.SkipSpaces(p)
  ELSIF B.C(p) = 0AX THEN RETURN p
  END;
  RETURN -1
END AfterMarker;

(* bulletListStart: - or +, or * when indented; indent is the marker's
   column plus one *)
PROCEDURE BulletListStart*(p: LONGINT; VAR indent: LONGINT): LONGINT;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  q := B.SkipSpaces(p);
  ch := B.C(q);
  IF (ch = "-") OR (ch = "+") OR (ch = "*") & (q > p) THEN
    indent := q - p + 1;
    RETURN AfterMarker(q + 1)
  END;
  RETURN -1
END BulletListStart;

(* orderedListStart: digits, or with fancy_lists a letter, then . or ) *)
PROCEDURE OrderedListStart*(p: LONGINT; VAR indent: LONGINT): LONGINT;
  VAR q, r: LONGINT; ch: CHAR;
BEGIN
  q := B.SkipSpaces(p); r := q;
  WHILE B.IsDigit(B.C(r)) DO INC(r) END;
  ch := B.C(r);
  IF (r = q) & fancyLists & ((ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z")) THEN
    INC(r)
  END;
  IF r = q THEN RETURN -1 END;
  ch := B.C(r);
  IF (ch # ".") & (ch # ")") THEN RETURN -1 END;
  indent := q - p + 1;
  RETURN AfterMarker(r + 1)
END OrderedListStart;

(* listCounterCookie at p: [@n] or [@a], and any spaces after it; the
   number, or a letter's place in the alphabet, in n. Where it ends,
   or -1. *)
PROCEDURE CounterCookie(p: LONGINT; VAR n: LONGINT): LONGINT;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  IF ~B.Looking(p, "[@") THEN RETURN -1 END;
  q := p + 2; ch := B.C(q);
  IF B.IsDigit(ch) THEN
    n := 0;
    WHILE B.IsDigit(B.C(q)) DO
      IF n <= (MAX(LONGINT) - 9) DIV 10 THEN
        n := n * 10 + ORD(B.C(q)) - ORD("0")
      END;
      INC(q)
    END
  ELSIF (ch >= "a") & (ch <= "z") THEN n := ORD(ch) - ORD("a") + 1; INC(q)
  ELSIF (ch >= "A") & (ch <= "Z") THEN n := ORD(ch) - ORD("A") + 1; INC(q)
  ELSE RETURN -1
  END;
  IF B.C(q) # "]" THEN RETURN -1 END;
  RETURN B.SkipSpaces(q + 1)
END CounterCookie;

(* A list item's marker at p, the start of a line: bulletListStart,
   or orderedListStart if ordered, with its counter cookie. indent is
   the marker's column plus one; start, style and delim are an ordered
   list's attributes. Where the marker ends, or -1. *)
PROCEDURE ListMarker*(p: LONGINT; ordered: BOOLEAN; VAR indent, start: LONGINT;
    VAR style, delim: INTEGER): LONGINT;
  VAR q, r, n: LONGINT; ch: CHAR;
BEGIN
  start := 1; style := A.DefaultStyle; delim := A.DefaultDelim;
  IF ordered THEN
    q := OrderedListStart(p, indent);
    IF q < 0 THEN RETURN -1 END;
    IF fancyLists THEN
      r := B.SkipSpaces(p); ch := B.C(r);
      IF B.IsDigit(ch) THEN style := A.Decimal
      ELSIF (ch >= "a") & (ch <= "z") THEN style := A.LowerAlpha
      ELSE style := A.UpperAlpha
      END;
      IF B.IsDigit(ch) THEN WHILE B.IsDigit(B.C(r)) DO INC(r) END ELSE INC(r) END;
      IF B.C(r) = "." THEN delim := A.Period ELSE delim := A.OneParen END
    END
  ELSE
    q := BulletListStart(p, indent);
    IF q < 0 THEN RETURN -1 END
  END;
  r := CounterCookie(q, n);
  IF r >= 0 THEN q := r; start := n END;
  RETURN q
END ListMarker;

(* endOfBlock: whether a blank line or a block starts at p, the start
   of a line *)
PROCEDURE EndOfBlock*(p: LONGINT): BOOLEAN;
  VAR n: LONGINT;
BEGIN
  RETURN (B.BlankLine(p) >= 0) OR (ExampleLineStart(p) >= 0)
    OR (Hline(p) >= 0) OR (MetaLineStart(p) >= 0)
    OR (CommentLineStart(p) >= 0) OR (GridTableStart(p) >= 0)
    OR (NoteMarker(p) >= 0) OR (TableStart(p) >= 0)
    OR (DrawerStart(p) >= 0) OR (HeaderStart(p, n) >= 0)
    OR (LatexEnvStart(p) >= 0) OR (BulletListStart(p, n) >= 0)
    OR (OrderedListStart(p, n) >= 0)
END EndOfBlock;

(* Inlines *)

(* isStrEnd: the characters that end a word: white space and the
   special characters *)
PROCEDURE IsStrEnd(ch: CHAR): BOOLEAN;
BEGIN
  CASE ch OF
  | " ", 0AX, 0DX, 22X, "$", "'", "(", ")", "*", "+", "-", ",", ".", "/",
    ":", ";", "<", "=", ">", "@", "[", "\", "]", "^", "_", "{", "|", "}",
    "~": RETURN TRUE
  ELSE RETURN FALSE
  END
END IsStrEnd;

(* inline: one inline at B.pos, added to l; FALSE, with B.pos where it
   was, if there is none. *)
PROCEDURE Inline*(VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT; ch: CHAR;
BEGIN
  p := B.pos;
  IF p >= B.len THEN RETURN FALSE END;
  ch := B.t[p];
  IF ~IsStrEnd(ch) THEN (* str: a tab, not a special character, is
      part of a word *)
    q := p;
    WHILE (q < B.len) & ~IsStrEnd(B.t[q]) DO INC(q) END;
    MI.AddText(l, p, q); p := q
  ELSIF ch = " " THEN (* whitespace *)
    WHILE B.IsSpace(B.C(p)) DO INC(p) END;
    A.Append(l, A.NewSimple(A.Space))
  ELSIF (ch = "\") & (B.C(p + 1) = "\")
      & (B.C(B.SkipSpaces(p + 2)) = 0AX) THEN (* linebreak *)
    p := B.SkipSpaces(p + 2) + 1;
    A.Append(l, A.NewSimple(A.LineBreak))
  ELSIF ch = 0AX THEN (* endline *)
    IF EndOfBlock(p + 1) THEN RETURN FALSE END;
    INC(p);
    IF M.preserveBreaks THEN A.Append(l, A.NewSimple(A.LineBreak))
    ELSE A.Append(l, A.NewSimple(A.SoftBreak))
    END
  ELSIF ch = 0DX THEN
    RETURN FALSE
  ELSE (* symbol *)
    MI.AddText(l, p, p + 1); INC(p)
  END;
  B.pos := p;
  RETURN TRUE
END Inline;

(* inlines: one or more inlines at B.pos, trimmed (trimInlinesF):
   NIL, with B.pos where it was, if there are none. *)
PROCEDURE Inlines*(): A.Inline;
  VAR l: A.Inlines;
BEGIN
  A.InitInlines(l);
  WHILE Inline(l) DO END;
  RETURN MI.Trim(l)
END Inlines;

BEGIN
  fancyLists := FALSE
END PdOrgInline.
