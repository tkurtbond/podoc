MODULE PdOrgInline;

(* The Org reader's inlines, as pandoc's Readers/Org/Inlines.hs reads
   them, and the starts of blocks that end a paragraph, its
   Readers/Org/BlockStarts.hs.

   Phase 27.1 reads text and its markup: Str, Space, SoftBreak, and
   LineBreak for \\ at the end of a line or every new line under \n:t;
   emphasis, verbatim and code, with pandoc's pre and post
   characters, forbidden border characters and one new line inside,
   under *:; subscripts and superscripts under ^:; special
   strings under -: and smart quotes under ':. The text read is
   PdMdBase's.

   Phase 27.2 reads links: [[target][description]], [[target]], plain
   and angle links, images and <<anchor>> targets. As pandoc's F monad
   resolves them against the state at the end, a link is read as a
   placeholder Span (PendAttr) and Resolve replaces it once the
   document's anchors and #+LINK formats are known.

   pandoc's parser state is kept in st: the positions of the last pre
   character, forbidden character and Str, the emphasis characters
   open and the new lines allowed. PdOrg's blocks set it as pandoc's
   do, through Newline, SetPre, Enter and Leave (Org's
   parseFromString), and Save and Restore where an alternative fails. *)

IMPORT Utf8, Unicode, Ropes, A := PdAst, B := PdMdBase, MI := PdMdInline,
  M := PdOrgMeta;

CONST
  NoQuote = 0; InSingle = 1; InDouble = 2; (* the quote context *)

  (* How a link is resolved at the end of the document *)
  Explicit = 0; (* [[target][description]]: formatted, then
    linkToInlinesF *)
  ExplicitImage = 1; (* [[target][image]]: formatted only *)
  Internal = 2; (* [[target]], not a URL: internalLink *)

  (* #+LINK formats *)
  FmtPlain = 0; FmtUrl = 1; FmtAppend = 2;

TYPE
  (* A position: Nothing if id < 0 *)
  Pos* = RECORD
    depth: INTEGER; (* B.depth: the name of pandoc's chunk *)
    id, off: LONGINT; (* the text's B.textId, and the offset in it *)
    line, col: LONGINT; (* counted when needed; line < 0 if not yet *)
    t: B.Text
  END;

  (* orgStateEmphasisCharStack, its top first; never changed, so a
     State is saved by copying it *)
  Stack = POINTER TO StackDesc;
  StackDesc = RECORD c: CHAR; next: Stack END;

  State* = RECORD
    pos: LONGINT; (* B.pos, when saved *)
    pre, forb, str: Pos; (* the last pre and forbidden characters', the
      last Str's *)
    stack: Stack;
    count: LONGINT; (* orgStateEmphasisNewlines; -1 for Nothing *)
    quote: INTEGER;
    anchors: A.StrList (* orgStateAnchorIds, the newest first; never
      changed, only added to at its head *)
  END;

  (* A link resolved at the end, when the document's anchors and link
     formats are known, as pandoc's F monad resolves it: the attributes
     of a Span that stands in for it until then, shared by any copy *)
  PendAttr = POINTER TO PendAttrDesc;
  PendAttrDesc = RECORD (A.AttrDesc)
    how: INTEGER; (* Explicit, ExplicitImage, Internal *)
    target: B.Buf (* the target as written *)
  END;

  (* A #+LINK abbreviation, orgStateLinkFormatters: the link type
     name; for FmtPlain and FmtUrl the text before and after %s or %h,
     for FmtAppend the text the rest of the link is appended to *)
  Format = POINTER TO FormatDesc;
  FormatDesc = RECORD
    name, before, after: B.Buf;
    kind: INTEGER;
    next: Format
  END;

  Resolver = POINTER TO ResolverDesc;
  ResolverDesc = RECORD (A.WalkerDesc) END;

VAR
  fancyLists*: BOOLEAN; (* the extension fancy_lists *)
  st: State;
  here: Pos; (* B.pos's line and column, last counted *)
  preChars, postChars: B.Buf; (* UTF-8: the characters allowed
    before and after emphasis *)
  defPre, defPost: B.Buf; (* pandoc's defaults for them *)
  formats: Format; (* the newest first *)

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

(* The parser's state for emphasis: orgStateLastPreCharPos,
   orgStateLastForbiddenCharPos, stateLastStrPos, the emphasis
   characters' stack, the new lines emphasis may still hold and the
   quote context.

   A position is pandoc's SourcePos: a text's name, a line and a
   column. Each parseFromString reads its text as a chunk, named for
   the text it is in, at line 1, column 1, so the texts Enter enters at
   one depth share a name, and a position in one can equal a position
   in another. Positions in one text are compared by their offsets,
   those in two texts of one depth by their lines and columns. *)

PROCEDURE Count(t: B.Text; from, to: LONGINT; VAR line, col: LONGINT);
  VAR ch: CHAR;
BEGIN
  WHILE from < to DO
    ch := t[from];
    IF ch = 0AX THEN INC(line); col := 1
    ELSIF (ch < 80X) OR (ch >= 0C0X) THEN INC(col)
    END;
    INC(from)
  END
END Count;

(* p's line and column, counted if they are not yet *)
PROCEDURE LineCol(VAR p: Pos);
BEGIN
  IF p.line < 0 THEN
    p.line := 1; p.col := 1; Count(p.t, 0, p.off, p.line, p.col)
  END
END LineCol;

(* here: the line and column of B.pos *)
PROCEDURE Here;
BEGIN
  IF (here.id # B.textId) OR (here.off > B.pos) THEN
    here.id := B.textId; here.t := B.t; here.off := 0;
    here.line := 1; here.col := 1
  END;
  Count(B.t, here.off, B.pos, here.line, here.col);
  here.off := B.pos
END Here;

(* Whether p is B.pos: Just pos == p *)
PROCEDURE Match(VAR p: Pos): BOOLEAN;
BEGIN
  IF (p.id < 0) OR (p.depth # B.depth) THEN RETURN FALSE END;
  IF p.id = B.textId THEN RETURN p.off = B.pos END;
  LineCol(p); Here;
  RETURN (p.line = here.line) & (p.col = here.col)
END Match;

(* Sets p to B.pos. *)
PROCEDURE Set(VAR p: Pos);
BEGIN
  p.depth := B.depth; p.id := B.textId; p.off := B.pos; p.line := -1;
  p.t := B.t
END Set;

(* Sets the state for a new document. *)
PROCEDURE Reset*;
BEGIN
  st.pre.id := -1; st.forb.id := -1; st.str.id := -1; st.stack := NIL;
  st.count := -1; st.quote := NoQuote; st.anchors := NIL; here.id := -1;
  preChars := defPre; postChars := defPost; formats := NIL
END Reset;

(* Saves the state, and B.pos, in s. *)
PROCEDURE Save*(VAR s: State);
BEGIN
  s := st; s.pos := B.pos
END Save;

(* Restores the state, and B.pos, saved in s. *)
PROCEDURE Restore*(VAR s: State);
BEGIN
  st := s; B.pos := s.pos
END Restore;

(* Org's newline, blanklines and anyLine: the last pre and forbidden
   characters' positions are B.pos, after the new line just read. *)
PROCEDURE Newline*;
BEGIN
  Set(st.pre); Set(st.forb)
END Newline;

(* Newline at p: the last pre and forbidden characters' positions
   are p, in the current text. *)
PROCEDURE NewlineAt*(p: LONGINT);
  VAR q: LONGINT;
BEGIN
  q := B.pos; B.pos := p; Newline; B.pos := q
END NewlineAt;

(* Sets the last pre character's position to B.pos. *)
PROCEDURE SetPre*;
BEGIN
  Set(st.pre)
END SetPre;

(* The last pre character's position is Nothing. *)
PROCEDURE ClearPre*;
BEGIN
  st.pre.id := -1
END ClearPre;

(* Org's parseFromString: enters the text, of n bytes, as B.Enter
   does, the last pre character's position Nothing *)
PROCEDURE Enter*(VAR f: B.Frame; text: B.Text; n: LONGINT);
BEGIN
  B.Enter(f, text, n); ClearPre
END Enter;

(* Leaves the text Enter entered, the last pre character's position
   Nothing *)
PROCEDURE Leave*(VAR f: B.Frame);
BEGIN
  B.Leave(f); ClearPre
END Leave;

(* parseFromString': the last Str's position, kept in p, is Nothing
   while a text is read; RestoreStr puts it back. *)
PROCEDURE ClearStr*(VAR p: Pos);
BEGIN
  p := st.str; st.str.id := -1
END ClearStr;

PROCEDURE RestoreStr*(VAR p: Pos);
BEGIN
  st.str := p
END RestoreStr;

(* Whether s, UTF-8, holds the character r *)
PROCEDURE In(VAR s: B.Buf; r: Utf8.Rune): BOOLEAN;
  VAR p: LONGINT; c: Utf8.Rune;
BEGIN
  p := 0;
  WHILE p < s.len DO
    p := MI.RuneOf(s.t^, p, s.len, c);
    IF c = r THEN RETURN TRUE END
  END;
  RETURN FALSE
END In;

(* emphasisForbiddenBorderChars *)
PROCEDURE Forbidden(r: Utf8.Rune): BOOLEAN;
BEGIN
  RETURN (r = 9) OR (r = 0AH) OR (r = 0DH) OR (r = 20H) OR (r = 200BH)
END Forbidden;

(* Whether the character at p is forbidden at emphasis's border *)
PROCEDURE ForbiddenAt(p: LONGINT): BOOLEAN;
  VAR r: Utf8.Rune;
BEGIN
  p := MI.RuneAt(p, r);
  RETURN Forbidden(r)
END ForbiddenAt;

(* updatePositions: after the character r, B.pos is the last pre
   character's position if r is a pre character, the last forbidden
   character's if it is forbidden *)
PROCEDURE Update(r: Utf8.Rune);
BEGIN
  IF In(preChars, r) THEN Set(st.pre) END;
  IF Forbidden(r) THEN Set(st.forb) END
END Update;

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

(* isSpaceChar: space, tab, new line, carriage return *)
PROCEDURE IsSpaceChar(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
END IsSpaceChar;

PROCEDURE^ Inline*(VAR l: A.Inlines): BOOLEAN;

(* Sets s to the characters of ascii, a double quote, a tab, a new
   line if nl, and U+200B *)
PROCEDURE Chars(VAR s: B.Buf; ascii: ARRAY OF CHAR; quote, nl: BOOLEAN);
BEGIN
  B.InitBuf(s);
  B.PutString(s, ascii);
  IF quote THEN B.PutChar(s, 22X) END;
  B.PutChar(s, 09X);
  IF nl THEN B.PutChar(s, 0AX) END;
  B.PutUtf8(s, 200BH)
END Chars;

(* Haskell's read of a String, as safeRead reads it, from p to the
   line's end e, into b: white space, a string literal and white
   space. FALSE if it is not one. *)
PROCEDURE ReadString(p, e: LONGINT; VAR b: B.Buf): BOOLEAN;
  CONST Names = " NUL SOH STX ETX EOT ENQ ACK BEL BS HT LF VT FF CR SO SI DLE DC1 DC2 DC3 DC4 NAK SYN ETB CAN EM SUB ESC FS GS RS US SP ";
  VAR ch: CHAR; c, base, d, i, j, n, best, bestLen: LONGINT; ok: BOOLEAN;

  PROCEDURE White(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch = " ") OR (ch = 09X) OR (ch = 0BX) OR (ch = 0CX) OR (ch = 0DX)
  END White;

BEGIN
  WHILE (p < e) & White(B.t[p]) DO INC(p) END;
  IF (p >= e) OR (B.t[p] # 22X) THEN RETURN FALSE END;
  INC(p); B.InitBuf(b);
  LOOP
    IF p >= e THEN RETURN FALSE END;
    ch := B.t[p];
    IF ch = 22X THEN INC(p); EXIT
    ELSIF ch # "\" THEN j := MI.RuneEnd(p); B.Put(b, p, j); p := j
    ELSE
      INC(p);
      IF p >= e THEN RETURN FALSE END;
      ch := B.t[p]; INC(p); c := -1;
      CASE ch OF
        "a": c := 7 | "b": c := 8 | "f": c := 0CH | "n": c := 0AH
      | "r": c := 0DH | "t": c := 9 | "v": c := 0BH
      | "\", 22X, 27X: c := ORD(ch)
      | "&": c := -2
      | "^":
          IF (p < e) & (B.t[p] >= "@") & (B.t[p] <= "_") THEN
            c := ORD(B.t[p]) - 40H; INC(p)
          ELSE RETURN FALSE
          END
      | "0" .. "9", "x", "o":
          IF ch = "x" THEN base := 16 ELSIF ch = "o" THEN base := 8
          ELSE base := 10; DEC(p)
          END;
          c := 0; n := 0;
          LOOP
            IF p >= e THEN EXIT END;
            ch := B.t[p];
            IF (ch >= "0") & (ch <= "9") THEN d := ORD(ch) - ORD("0")
            ELSIF (ch >= "a") & (ch <= "f") THEN d := ORD(ch) - ORD("a") + 10
            ELSIF (ch >= "A") & (ch <= "F") THEN d := ORD(ch) - ORD("A") + 10
            ELSE d := 99
            END;
            IF d >= base THEN EXIT END;
            c := c * base + d; INC(n); INC(p);
            IF c > 10FFFFH THEN RETURN FALSE END
          END;
          IF n = 0 THEN RETURN FALSE END
      | " ", 09X, 0BX, 0CX, 0DX: (* a gap *)
          WHILE (p < e) & White(B.t[p]) DO INC(p) END;
          IF (p >= e) OR (B.t[p] # "\") THEN RETURN FALSE END;
          INC(p); c := -2
      ELSE (* an ASCII name, the longest that matches *)
        DEC(p); best := -1; bestLen := 0; i := 1; n := 0;
        WHILE Names[i] # 0X DO
          j := 0; ok := TRUE;
          WHILE Names[i + j] # " " DO
            IF (p + j >= e) OR (B.t[p + j] # Names[i + j]) THEN ok := FALSE END;
            INC(j)
          END;
          IF ok & (j > bestLen) THEN best := n; bestLen := j END;
          i := i + j + 1; INC(n)
        END;
        IF best < 0 THEN
          IF (p + 3 <= e) & (B.t[p] = "D") & (B.t[p + 1] = "E") & (B.t[p + 2] = "L") THEN
            c := 7FH; INC(p, 3)
          ELSE RETURN FALSE
          END
        ELSIF best = 32 THEN c := 20H; INC(p, bestLen)
        ELSE c := best; INC(p, bestLen)
        END
      END;
      IF c >= 0 THEN B.PutUtf8(b, c) END
    END
  END;
  WHILE (p < e) & White(B.t[p]) DO INC(p) END;
  RETURN p = e
END ReadString;

(* #+pandoc-emphasis-pre: and #+pandoc-emphasis-post:, the value from
   p to the line's end: the characters allowed before or after
   emphasis, or pandoc's defaults if it is not a Haskell string *)
PROCEDURE EmphChars*(post: BOOLEAN; p: LONGINT);
  VAR b: B.Buf; e: LONGINT;
BEGIN
  e := B.LineEnd(p);
  IF ~ReadString(p, e, b) THEN
    IF post THEN b := defPost ELSE b := defPre END
  END;
  IF post THEN postChars := b ELSE preChars := b END
END EmphChars;


(* str: a word, to the next isStrEnd *)
PROCEDURE Str(VAR l: A.Inlines);
  VAR p, q, s: LONGINT; r: Utf8.Rune;
BEGIN
  p := B.pos; q := p;
  WHILE (q < B.len) & ~IsStrEnd(B.t[q]) DO INC(q) END;
  MI.AddText(l, p, q);
  s := q - 1;
  WHILE (s > p) & (B.t[s] >= 80X) & (B.t[s] < 0C0X) DO DEC(s) END;
  s := MI.RuneAt(s, r);
  B.pos := q; Update(r); Set(st.str)
END Str;

(* linebreak: \\, spaces and a new line *)
PROCEDURE Linebreak(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT;
BEGIN
  p := B.pos;
  IF (B.C(p) # "\") OR (B.C(p + 1) # "\") THEN RETURN FALSE END;
  p := B.SkipSpaces(p + 2);
  IF B.C(p) # 0AX THEN RETURN FALSE END;
  B.pos := p + 1; Newline;
  A.Append(l, A.NewSimple(A.LineBreak));
  RETURN TRUE
END Linebreak;

(* endline: a new line that does not end the paragraph, and that the
   emphasis around it may hold *)
PROCEDURE Endline(VAR l: A.Inlines): BOOLEAN;
  VAR s: State;
BEGIN
  Save(s);
  INC(B.pos); Newline;
  IF EndOfBlock(B.pos) THEN Restore(s); RETURN FALSE END;
  IF st.count >= 0 THEN
    DEC(st.count);
    IF st.count < 0 THEN Restore(s); RETURN FALSE END
  END;
  SetPre;
  IF M.preserveBreaks THEN A.Append(l, A.NewSimple(A.LineBreak))
  ELSE A.Append(l, A.NewSimple(A.SoftBreak))
  END;
  RETURN TRUE
END Endline;

(* emphasisStart: c, after a pre character, before a character not
   forbidden at the border *)
PROCEDURE EmphasisStart(c: CHAR): BOOLEAN;
  VAR p: LONGINT; s: Stack;
BEGIN
  p := B.pos;
  IF (st.pre.id >= 0) & ~Match(st.pre) THEN RETURN FALSE END;
  IF (B.C(p) # c) OR (p + 1 >= B.len) OR ForbiddenAt(p + 1) THEN
    RETURN FALSE
  END;
  NEW(s); s.c := c; s.next := st.stack; st.stack := s;
  B.pos := p + 1; Set(st.pre);
  RETURN TRUE
END EmphasisStart;

(* emphasisEnd: c, not after a forbidden character, at the end of the
   text or before a post character or the emphasis character around
   this one *)
PROCEDURE EmphasisEnd(c: CHAR): BOOLEAN;
  VAR p, q: LONGINT; r: Utf8.Rune;
BEGIN
  p := B.pos;
  IF Match(st.forb) OR (B.C(p) # c) THEN RETURN FALSE END;
  INC(p);
  IF p < B.len THEN
    q := MI.RuneAt(p, r);
    IF ~In(postChars, r) & ~((st.stack # NIL) & (st.stack.next # NIL)
        & (r = ORD(st.stack.next.c))) THEN
      RETURN FALSE
    END
  END;
  B.pos := p; Set(st.str);
  IF st.stack # NIL THEN st.stack := st.stack.next END;
  RETURN TRUE
END EmphasisEnd;

(* emphasizedText: /emph/, *strong*, +strikeout+ or _underline_ *)
PROCEDURE Emphasis(c: CHAR; VAR l: A.Inlines): BOOLEAN;
  VAR s: State; cl: A.Inlines; kind: INTEGER;
BEGIN
  IF ~M.emphasis THEN RETURN FALSE END;
  CASE c OF
  | "/": kind := A.Emph
  | "*": kind := A.Strong
  | "+": kind := A.Strikeout
  | "_": kind := A.Underline
  ELSE RETURN FALSE
  END;
  Save(s);
  st.count := 1;
  IF ~EmphasisStart(c) OR MI.SpaceAt(B.pos) THEN Restore(s); RETURN FALSE END;
  A.InitInlines(cl);
  IF ~Inline(cl) THEN Restore(s); RETURN FALSE END;
  LOOP
    IF EmphasisEnd(c) THEN EXIT END;
    IF ~Inline(cl) THEN Restore(s); RETURN FALSE END
  END;
  IF st.stack = NIL THEN st.count := -1 END;
  A.Append(l, A.NewCont(kind, MI.Trim(cl)));
  RETURN TRUE
END Emphasis;

(* finalLine: characters of a line, their positions updated, to
   emphasisEnd c *)
PROCEDURE FinalLine(c: CHAR): BOOLEAN;
  VAR r: Utf8.Rune; ch: CHAR;
BEGIN
  LOOP
    IF EmphasisEnd(c) THEN RETURN TRUE END;
    ch := B.C(B.pos);
    IF (B.pos >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN RETURN FALSE END;
    B.pos := MI.RuneAt(B.pos, r); Update(r)
  END
END FinalLine;

(* verbatimBetween: =verbatim= or ~code~, on one line or two *)
PROCEDURE Verbatim(c: CHAR; VAR l: A.Inlines): BOOLEAN;
  VAR s, s1: State; start, i: LONGINT; r: Utf8.Rune; ch: CHAR;
    b: B.Buf; a: A.Attr;
BEGIN
  Save(s);
  IF ~EmphasisStart(c) THEN RETURN FALSE END;
  start := B.pos;
  Save(s1);
  IF ~FinalLine(c) THEN
    Restore(s1);
    LOOP
      ch := B.C(B.pos);
      IF (B.pos >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN EXIT END;
      B.pos := MI.RuneAt(B.pos, r); Update(r)
    END;
    IF B.C(B.pos) # 0AX THEN Restore(s); RETURN FALSE END;
    INC(B.pos); Newline;
    IF ~FinalLine(c) THEN Restore(s); RETURN FALSE END
  END;
  IF B.pos - 1 = start THEN Restore(s); RETURN FALSE END;
  B.InitBuf(b); B.Put(b, start, B.pos - 1);
  FOR i := 0 TO b.len - 1 DO
    IF b.t[i] = 0AX THEN b.t[i] := " " END
  END;
  a := A.NewAttr(NIL);
  IF c = "=" THEN A.AddClass(a, A.S("verbatim")) END;
  A.Append(l, A.NewCode(a, B.BufRope(b)));
  RETURN TRUE
END Verbatim;

(* simpleSubOrSuperText: *, or a sign and letters and numbers *)
PROCEDURE SimpleScript(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, r: LONGINT;
BEGIN
  p := B.pos;
  IF B.C(p) = "*" THEN MI.AddText(l, p, p + 1); B.pos := p + 1; RETURN TRUE END;
  q := p;
  IF (B.C(q) = "+") OR (B.C(q) = "-") THEN INC(q) END;
  r := q;
  WHILE (r < B.len) & MI.AlnumAt(r) DO r := MI.RuneEnd(r) END;
  IF r = q THEN RETURN FALSE END;
  MI.AddText(l, p, r); B.pos := r;
  RETURN TRUE
END SimpleScript;

(* charsInBalanced open close, on one line, its inside read as inlines
   in a text of its own, enclosed in ( and ) for parentheses *)
PROCEDURE Balanced(open, close: CHAR; VAR l: A.Inlines): BOOLEAN;
  VAR p, q, n: LONGINT; ch: CHAR; b: B.Buf; f: B.Frame;
BEGIN
  p := B.pos;
  IF B.C(p) # open THEN RETURN FALSE END;
  q := p; n := 0;
  LOOP
    ch := B.C(q);
    IF (q >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN RETURN FALSE END;
    IF ch = open THEN INC(n)
    ELSIF ch = close THEN
      DEC(n);
      IF n = 0 THEN EXIT END
    END;
    INC(q)
  END;
  B.InitBuf(b);
  IF open = "(" THEN B.PutChar(b, "(") END;
  B.Put(b, p + 1, q);
  IF open = "(" THEN B.PutChar(b, ")") END;
  B.pos := q + 1;
  Enter(f, b.t, b.len);
  WHILE Inline(l) DO END;
  Leave(f);
  RETURN TRUE
END Balanced;

(* subscript and superscript: _ or ^ after a Str, and what the export
   setting ^: allows *)
PROCEDURE Script(kind: INTEGER; VAR l: A.Inlines): BOOLEAN;
  VAR s: State; cl: A.Inlines;
BEGIN
  IF (M.subSup = M.SubSupNone) OR ~Match(st.str) THEN RETURN FALSE END;
  Save(s); INC(B.pos);
  A.InitInlines(cl);
  IF (M.subSup = M.SubSupAll) & SimpleScript(cl) THEN
  ELSIF Balanced("{", "}", cl) THEN
  ELSIF (M.subSup = M.SubSupAll) & Balanced("(", ")", cl) THEN
  ELSE Restore(s); RETURN FALSE
  END;
  A.Append(l, A.NewCont(kind, cl.first));
  RETURN TRUE
END Script;

(* doubleQuoted: "...", or a left quotation mark and the rest of the
   paragraph if there is no closing " *)
PROCEDURE DoubleQuoted(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; cl: A.Inlines;
BEGIN
  p := B.pos;
  IF (st.quote = InDouble) OR Match(st.str) OR (p + 1 >= B.len)
      OR IsSpaceChar(B.t[p + 1]) THEN
    RETURN FALSE
  END;
  B.pos := p + 1; Update(22H);
  A.InitInlines(cl);
  WHILE (B.C(B.pos) # 22X) & Inline(cl) DO END;
  IF B.C(B.pos) = 22X THEN
    INC(B.pos); Set(st.forb);
    A.Append(l, A.NewQuoted(A.DoubleQuote, MI.Trim(cl)))
  ELSE
    MI.AddChar(l, 201CH); A.Append(l, cl.first)
  END;
  RETURN TRUE
END DoubleQuoted;

(* singleQuoted: '...', its closing ' not before a letter or number *)
PROCEDURE SingleQuoted(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; s: State; cl: A.Inlines; old: INTEGER;
BEGIN
  p := B.pos;
  IF (st.quote = InSingle) OR Match(st.str) OR (p + 1 >= B.len)
      OR IsSpaceChar(B.t[p + 1]) THEN
    RETURN FALSE
  END;
  Save(s);
  B.pos := p + 1; Update(27H);
  old := st.quote; st.quote := InSingle;
  A.InitInlines(cl);
  IF ~Inline(cl) THEN Restore(s); RETURN FALSE END;
  LOOP
    IF (B.C(B.pos) = "'") & ~MI.AlnumAt(B.pos + 1) THEN
      INC(B.pos); Update(27H); EXIT
    END;
    IF ~Inline(cl) THEN Restore(s); RETURN FALSE END
  END;
  st.quote := old;
  A.Append(l, A.NewQuoted(A.SingleQuote, MI.Trim(cl)));
  RETURN TRUE
END SingleQuoted;

(* smartQuotes: doubleQuoted, singleQuoted or an apostrophe, if the
   export setting ': allows them *)
PROCEDURE SmartQuotes(ch: CHAR; VAR l: A.Inlines): BOOLEAN;
BEGIN
  IF ~M.smartQuotes THEN RETURN FALSE END;
  IF ch = 22X THEN RETURN DoubleQuoted(l)
  ELSIF ch = "'" THEN
    IF ~SingleQuoted(l) THEN
      INC(B.pos); Newline; MI.AddChar(l, 2019H)
    END;
    RETURN TRUE
  END;
  RETURN FALSE
END SmartQuotes;

(* specialStrings: dashes, an ellipsis and \- for a soft hyphen, if the
   export setting -: allows them *)
PROCEDURE Special(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT;
BEGIN
  IF ~M.specialStrings THEN RETURN FALSE END;
  p := B.pos;
  IF B.Looking(p, "---") THEN
    MI.AddChar(l, 2014H); B.pos := p + 3; Update(ORD("-"))
  ELSIF B.Looking(p, "--") THEN
    MI.AddChar(l, 2013H); B.pos := p + 2; Update(ORD("-"))
  ELSIF B.Looking(p, "...") THEN
    MI.AddChar(l, 2026H); B.pos := p + 3
  ELSIF B.Looking(p, "\-") THEN
    MI.AddChar(l, 0ADH); B.pos := p + 2; Update(ORD("-"))
  ELSE RETURN FALSE
  END;
  RETURN TRUE
END Special;

(* Links *)

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

(* cleanLinkText: t[from .. to-1] of the current text as a link; ok
   FALSE if it is not one *)
PROCEDURE CleanLink*(from, to: LONGINT; VAR ok: BOOLEAN): A.Rope;
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
   of the current text has the extension of an image *)
PROCEDURE IsImage*(from, to: LONGINT): BOOLEAN;
  CONST Exts = " jpeg jpg png gif svg webp jxl avif pdf ";
  VAR p, i, j, n: LONGINT; e: ARRAY 8 OF CHAR; ext: ARRAY 64 OF CHAR;
BEGIN
  p := to;
  WHILE (p > from) & (B.t[p - 1] # "/") & (B.t[p - 1] # ".") DO DEC(p) END;
  IF (p = from) OR (B.t[p - 1] # ".") OR (to - p > 6) OR (to = p) THEN
    RETURN FALSE
  END;
  n := to - p;
  FOR i := 0 TO n - 1 DO e[i] := B.Lower(B.t[p + i]) END;
  ext := Exts; i := 0;
  WHILE ext[i] # 0X DO
    IF ext[i] = " " THEN
      j := 0;
      WHILE (j < n) & (ext[i + 1 + j] = e[j]) DO INC(j) END;
      IF (j = n) & (ext[i + 1 + j] = " ") THEN RETURN TRUE END
    END;
    INC(i)
  END;
  RETURN FALSE
END IsImage;

(* Enters b's text, with 0X after it *)
PROCEDURE EnterBuf(VAR f: B.Frame; VAR b: B.Buf);
BEGIN
  B.PutChar(b, 0X); DEC(b.len);
  B.Enter(f, b.t, b.len)
END EnterBuf;

(* linkTarget at p: [, one or more characters but new lines and
   brackets, and ]; where it ends, or -1 *)
PROCEDURE LinkTarget(p: LONGINT): LONGINT;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  IF B.C(p) # "[" THEN RETURN -1 END;
  q := p + 1;
  LOOP
    ch := B.C(q);
    IF (q >= B.len) OR (ch = 0AX) OR (ch = 0DX) OR (ch = "[") THEN RETURN -1
    ELSIF ch = "]" THEN EXIT
    END;
    INC(q)
  END;
  IF q = p + 1 THEN RETURN -1 END;
  RETURN q + 1
END LinkTarget;

(* many1TillChar (noneOf "\n\r") (char ']') at p: where the ] is, or
   -1 *)
PROCEDURE OneLine(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  ch := B.C(p);
  IF (p >= B.len) OR (ch = 0AX) OR (ch = 0DX) OR (ch = "]") THEN RETURN -1 END;
  INC(p);
  LOOP
    ch := B.C(p);
    IF (p >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN RETURN -1
    ELSIF ch = "]" THEN RETURN p
    END;
    INC(p)
  END
END OneLine;

(* A Span that stands for a link until Resolve *)
PROCEDURE Pending(how: INTEGER; VAR target: B.Buf; content: A.Inline): A.Inline;
  VAR a: PendAttr;
BEGIN
  NEW(a); a.id := NIL; a.classes := NIL; a.attrs := NIL;
  a.how := how; a.target := target;
  RETURN A.NewSpan(a, content)
END Pending;

(* explicitOrImageLink: [[target][description]] or [[][description]],
   the description on one line or two *)
PROCEDURE ExplicitLink(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, r, e: LONGINT; s: State; target, d: B.Buf; f: B.Frame;
    cl: A.Inlines; src: A.Rope; ok, image: BOOLEAN;
BEGIN
  p := B.pos;
  IF B.C(p) # "[" THEN RETURN FALSE END;
  B.InitBuf(target);
  q := LinkTarget(p + 1);
  IF q >= 0 THEN B.Put(target, p + 2, q - 1)
  ELSIF B.Looking(p + 1, "[]") THEN q := p + 3
  ELSE RETURN FALSE
  END;
  IF B.C(q) # "[" THEN RETURN FALSE END;
  INC(q);
  Save(s);
  B.InitBuf(d);
  r := OneLine(q);
  IF r >= 0 THEN B.Put(d, q, r)
  ELSE (* spanningTwoLines *)
    e := B.LineEnd(q);
    IF B.C(e) # 0AX THEN RETURN FALSE END;
    r := OneLine(e + 1);
    IF r < 0 THEN RETURN FALSE END;
    NewlineAt(e + 1);
    B.Put(d, q, e); B.PutChar(d, " "); B.Put(d, e + 1, r)
  END;
  IF B.C(r + 1) # "]" THEN Restore(s); RETURN FALSE END;
  B.pos := r + 2;
  Enter(f, d.t, d.len);
  src := CleanLink(0, d.len, ok);
  image := ok & IsImage(0, d.len);
  A.InitInlines(cl);
  WHILE Inline(cl) DO END;
  Leave(f);
  IF image THEN
    A.Append(l, Pending(ExplicitImage, target,
      A.NewLink(A.Image, A.NewAttr(NIL), NIL, src, NIL)))
  ELSE
    A.Append(l, Pending(Explicit, target, cl.first))
  END;
  RETURN TRUE
END ExplicitLink;

(* selflinkOrImage: [[target]] *)
PROCEDURE SelfLink(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, s, e: LONGINT; src, t: A.Rope; ok: BOOLEAN; target: B.Buf;
BEGIN
  p := B.pos;
  IF B.C(p) # "[" THEN RETURN FALSE END;
  q := LinkTarget(p + 1);
  IF (q < 0) OR (B.C(q) # "]") THEN RETURN FALSE END;
  s := p + 2; e := q - 1;
  src := CleanLink(s, e, ok); t := B.Rope(s, e);
  IF ~ok THEN
    IF B.t[s] = "#" THEN
      A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), A.NewStr(t), t, NIL))
    ELSE
      B.InitBuf(target); B.Put(target, s, e);
      A.Append(l, Pending(Internal, target, A.NewStr(t)))
    END
  ELSIF IsImage(s, e) THEN
    A.Append(l, A.NewLink(A.Image, A.NewAttr(NIL), NIL, src, NIL))
  ELSE
    A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), A.NewStr(t), src, NIL))
  END;
  B.pos := q + 1;
  RETURN TRUE
END SelfLink;

(* plainLink: a URI with a scheme pandoc knows *)
PROCEDURE PlainLink(VAR l: A.Inlines): BOOLEAN;
  VAR q: LONGINT; orig, src: B.Buf;
BEGIN
  B.InitBuf(orig); B.InitBuf(src);
  q := MI.Uri(B.pos, orig, src);
  IF q < 0 THEN RETURN FALSE END;
  A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), A.NewStr(B.BufRope(orig)),
    B.BufRope(src), NIL));
  B.pos := q;
  RETURN TRUE
END PlainLink;

(* angleLink: <, plainLink and > *)
PROCEDURE AngleLink(VAR l: A.Inlines): BOOLEAN;
  VAR q: LONGINT; orig, src: B.Buf;
BEGIN
  IF B.C(B.pos) # "<" THEN RETURN FALSE END;
  B.InitBuf(orig); B.InitBuf(src);
  q := MI.Uri(B.pos + 1, orig, src);
  IF (q < 0) OR (B.C(q) # ">") THEN RETURN FALSE END;
  A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), A.NewStr(B.BufRope(orig)),
    B.BufRope(src), NIL));
  B.pos := q + 1;
  RETURN TRUE
END AngleLink;

(* anchor: <<id>> and any spaces, an empty Span whose identifier is
   id solidified (org-export-solidify-link-text); id is recorded *)
PROCEDURE Anchor(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, r: LONGINT; ch: CHAR; b: B.Buf; c: Utf8.Rune; s: A.StrList;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "<<") THEN RETURN FALSE END;
  q := p + 2;
  LOOP
    ch := B.C(q);
    IF (q >= B.len) OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX) OR (ch = "<")
        OR (ch = ">") OR (ch = 22X) OR (ch = "'") OR (ch = " ") THEN
      EXIT
    END;
    INC(q)
  END;
  IF (q = p + 2) OR ~B.Looking(q, ">>") THEN RETURN FALSE END;
  NEW(s); s.s := B.Rope(p + 2, q); s.next := st.anchors; st.anchors := s;
  B.InitBuf(b); r := p + 2;
  WHILE r < q DO
    ch := B.t[r];
    IF (ch = "_") OR (ch = ".") OR (ch = "-") OR (ch = ":") OR MI.AlnumAt(r) THEN
      B.Put(b, r, MI.RuneEnd(r))
    ELSE B.PutChar(b, "-")
    END;
    r := MI.RuneAt(r, c)
  END;
  A.Append(l, A.NewSpan(A.NewAttr(B.BufRope(b)), NIL));
  B.pos := B.SkipSpaces(q + 2);
  RETURN TRUE
END Anchor;

(* #+LINK: the line from p, after the key: a link type, spaces and its
   format (addLinkFormatter). FALSE, nothing changed, if there is no
   link type. *)
PROCEDURE LinkFormat*(p: LONGINT): BOOLEAN;
  VAR q, e, s: LONGINT; fm: Format; c: Utf8.Rune;
BEGIN
  q := MI.RuneAt(p, c);
  IF (p >= B.len) OR ~((c < 80H) & B.IsLetter(B.t[p]) OR (c >= 80H) & Unicode.IsLetter(c)) THEN
    RETURN FALSE
  END;
  WHILE (q < B.len) & (MI.AlnumAt(q) OR (B.t[q] = "-") OR (B.t[q] = "_")) DO
    q := MI.RuneEnd(q)
  END;
  NEW(fm); B.InitBuf(fm.name); B.Put(fm.name, p, q);
  B.InitBuf(fm.before); B.InitBuf(fm.after);
  q := B.SkipSpaces(q);
  e := q;
  WHILE (e < B.len) & (B.t[e] # 0AX) & (B.t[e] # 0DX) DO INC(e) END;
  s := q;
  WHILE (s + 1 < e) & ~((B.t[s] = "%") & (B.t[s + 1] = "s")) DO INC(s) END;
  IF s + 1 < e THEN fm.kind := FmtPlain
  ELSE
    s := q;
    WHILE (s + 1 < e) & ~((B.t[s] = "%") & (B.t[s + 1] = "h")) DO INC(s) END;
    IF s + 1 < e THEN fm.kind := FmtUrl ELSE fm.kind := FmtAppend END
  END;
  IF fm.kind = FmtAppend THEN B.Put(fm.before, q, e)
  ELSE B.Put(fm.before, q, s); B.Put(fm.after, s + 2, e)
  END;
  fm.next := formats; formats := fm;
  RETURN TRUE
END LinkFormat;

(* %h's encoding, as pandoc 3.14 does it: letters, digits and -_.~
   kept, every other byte (space too) percent encoded *)
PROCEDURE UrlEncode(VAR s: B.Buf; from, to: LONGINT; VAR out: B.Buf);
  VAR ch: CHAR; hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789ABCDEF";
  WHILE from < to DO
    ch := s.t[from];
    IF (ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z")
        OR (ch >= "0") & (ch <= "9") OR (ch = "-") OR (ch = "_")
        OR (ch = ".") OR (ch = "~") THEN
      B.PutChar(out, ch)
    ELSE
      B.PutChar(out, "%");
      B.PutChar(out, hex[ORD(ch) DIV 16]);
      B.PutChar(out, hex[ORD(ch) MOD 16])
    END;
    INC(from)
  END
END UrlEncode;

(* Appends s[from .. to-1] to out *)
PROCEDURE PutPart(VAR out: B.Buf; VAR s: B.Buf; from, to: LONGINT);
BEGIN
  WHILE from < to DO B.PutChar(out, s.t[from]); INC(from) END
END PutPart;

(* applyCustomLinkFormat: t with the #+LINK format for its link type,
   the text before its first colon, applied to the rest, in out *)
PROCEDURE ApplyFormat(VAR t: B.Buf; VAR out: B.Buf);
  VAR i, n, r: LONGINT; fm: Format; same: BOOLEAN;
BEGIN
  n := 0;
  WHILE (n < t.len) & (t.t[n] # ":") DO INC(n) END;
  fm := formats;
  LOOP
    IF fm = NIL THEN EXIT END;
    IF fm.name.len = n THEN
      same := TRUE; i := 0;
      WHILE same & (i < n) DO same := fm.name.t[i] = t.t[i]; INC(i) END;
      IF same THEN EXIT END
    END;
    fm := fm.next
  END;
  B.InitBuf(out);
  IF fm = NIL THEN PutPart(out, t, 0, t.len); RETURN END;
  r := n + 1;
  IF r > t.len THEN r := t.len END;
  PutPart(out, fm.before, 0, fm.before.len);
  IF fm.kind = FmtUrl THEN UrlEncode(t, r, t.len, out)
  ELSE PutPart(out, t, r, t.len)
  END;
  PutPart(out, fm.after, 0, fm.after.len)
END ApplyFormat;

(* internalLink: a link to an anchor of the document, or an Emph in a
   spurious-link Span if there is none *)
PROCEDURE InternalLink(link: A.Rope; title: A.Inline): A.Inline;
  VAR s: A.StrList; a: A.Attr;
BEGIN
  s := st.anchors;
  WHILE (s # NIL) & ~Ropes.Equal(s.s, link) DO s := s.next END;
  IF s # NIL THEN
    RETURN A.NewLink(A.Link, A.NewAttr(NIL), title,
      Ropes.Cat(A.S("#"), link), NIL)
  END;
  a := A.NewAttr(NIL);
  A.AddClass(a, A.S("spurious-link"));
  A.AddKeyVal(a, A.S("target"), link);
  RETURN A.NewSpan(a, A.NewCont(A.Emph, title))
END InternalLink;

(* The link that a Span made by Pending stands for *)
PROCEDURE Resolved(a: PendAttr; content: A.Inline): A.Inline;
  VAR src: B.Buf; r, c: A.Rope; ok: BOOLEAN; f: B.Frame;
BEGIN
  IF a.how = Internal THEN RETURN InternalLink(B.BufRope(a.target), content) END;
  ApplyFormat(a.target, src);
  r := B.BufRope(src);
  IF (a.how = ExplicitImage) OR (src.len = 0) OR (src.t[0] = "#") THEN
    RETURN A.NewLink(A.Link, A.NewAttr(NIL), content, r, NIL)
  END;
  EnterBuf(f, src);
  c := CleanLink(0, src.len, ok);
  B.Leave(f);
  IF ok THEN RETURN A.NewLink(A.Link, A.NewAttr(NIL), content, c, NIL) END;
  RETURN InternalLink(r, content)
END Resolved;

PROCEDURE (w: Resolver) Inline*(i: A.Inline): A.Inline;
BEGIN
  IF (i IS A.SpanInl) & (i(A.SpanInl).attr # NIL)
      & (i(A.SpanInl).attr IS PendAttr) THEN
    RETURN Resolved(i(A.SpanInl).attr(PendAttr), i(A.SpanInl).content)
  END;
  RETURN i
END Inline;

(* Resolves the links of the document d, read last, against its
   anchors and #+LINK formats, as pandoc's F monad does at the end *)
PROCEDURE Resolve*(d: A.Doc);
  VAR w: Resolver;
BEGIN
  NEW(w); A.WalkDoc(w, d)
END Resolve;

(* inline: one inline at B.pos, added to l; FALSE, with B.pos and the
   state as they were, if there is none. *)
PROCEDURE Inline*(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; ch: CHAR;
BEGIN
  p := B.pos;
  IF p >= B.len THEN RETURN FALSE END;
  ch := B.t[p];
  IF ~IsStrEnd(ch) THEN (* a tab, not a special character, is part of
      a word *)
    IF ~((ch < 80X) & B.IsLetter(ch) & PlainLink(l)) THEN Str(l) END
  ELSIF ch = " " THEN (* whitespace *)
    WHILE B.IsSpace(B.C(p)) DO INC(p) END;
    B.pos := p; Newline;
    A.Append(l, A.NewSimple(A.Space))
  ELSIF (ch = "\") & Linebreak(l) THEN
  ELSIF (ch = "[") & (ExplicitLink(l) OR SelfLink(l)) THEN
  ELSIF (ch = "<") & (AngleLink(l) OR Anchor(l)) THEN
  ELSIF ch = 0AX THEN RETURN Endline(l)
  ELSIF ch = 0DX THEN RETURN FALSE
  ELSIF (ch = "_") & Script(A.Subscript, l)
      OR (ch = "^") & Script(A.Superscript, l)
      OR Emphasis(ch, l)
      OR ((ch = "~") OR (ch = "=")) & Verbatim(ch, l)
      OR SmartQuotes(ch, l) OR Special(l) THEN
  ELSE (* symbol *)
    MI.AddText(l, p, p + 1); B.pos := p + 1; Update(ORD(ch))
  END;
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
  fancyLists := FALSE;
  (* -\t ('"{ and U+200B; -\t\n .,:!?;'")}[ and U+200B *)
  Chars(defPre, "- ('{", TRUE, FALSE);
  Chars(defPost, "- .,:!?;')}[", TRUE, TRUE);
  Reset
END PdOrgInline.
