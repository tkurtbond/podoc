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

   Phase 27.3 reads footnote references and inline notes, resolved
   the same way against PdOrg's note definitions (AddNote); org-cite
   and org-ref citations, under the citations extension; #+MACRO
   definitions (AddMacro) and {{{macro(args)}}} calls, the expansion
   read again as inlines; export snippets @@format:text@@; and inline
   source src_lang[options]{code}.

   Phase 27.4 reads math, $x$ and $$x$$ with Org's border rules,
   \(x\) and \[x\]; Org entities (\alpha, \alpha{}), looked up in
   PdEntities with texmath's six exceptions; the math environments
   (\begin{equation}...\end{equation}) as raw LaTeX; and every other
   LaTeX command as RawInline latex, ending where PdMdInline.RawTeXEnd
   ends it, as tex:t, tex:nil and tex:verbatim say (decision 57).

   Phase 28.3: --unknown (Unknown) reports undefined macros and the
   LaTeX commands kept raw, and PdOrg's unknown keywords and blocks,
   at their places in the files (Loc), which Push records for each
   text entered from what Origin and FileOrigin say.

   pandoc's parser state is kept in st: the positions of the last pre
   character, forbidden character and Str, the emphasis characters
   open and the new lines allowed. PdOrg's blocks set it as pandoc's
   do, through Newline, SetPre, Enter and Leave (Org's
   parseFromString), and Save and Restore where an alternative fails. *)

IMPORT Utf8, Unicode, Ropes, PdIO, PdSource, A := PdAst, B := PdMdBase,
  MI := PdMdInline, M := PdOrgMeta, PdEntities;

CONST
  NoQuote = 0; InSingle = 1; InDouble = 2; (* the quote context *)

  (* How a link is resolved at the end of the document *)
  Explicit = 0; (* [[target][description]]: formatted, then
    linkToInlinesF *)
  ExplicitImage = 1; (* [[target][image]]: formatted only *)
  Internal = 2; (* [[target]], not a URL: internalLink *)
  NoteRef = 3; (* [fn:name] or [1]: referencedNote *)

  (* org-cite styles that change a citation *)
  NilStyle = 0; TextStyle = 1; NoAuthorStyle = 2; OtherStyle = 3;

  (* #+LINK formats *)
  FmtPlain = 0; FmtUrl = 1; FmtAppend = 2;

  (* --unknown *)
  Quiet* = 0; WarnUnknown* = 1; FailUnknown* = 2;

  (* Where a text Enter entered came from, for --unknown's places *)
  MaxDepth = 64;
  OrgUnknown* = 0; (* not known: where the text it was entered from
    had got to *)
  OrgOffset* = 1; (* a copy of that text from a *)
  OrgLines* = 2; (* its lines, line for line: the first from a, the
    others with b columns taken from their starts *)
  OrgAt* = 3; (* made from what is at a *)
  OrgFile* = 4; (* the file name, from its line a *)

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

  (* orgStateNotes': a footnote's definition, its key fn:name or a
     number, and its blocks *)
  Note = POINTER TO NoteDesc;
  NoteDesc = RECORD
    ref: A.Rope;
    blocks: A.Block;
    next: Note
  END;

  (* A #+MACRO definition, orgStateMacros: its text, parts of it
     with the number of the argument after each, 0 after the last *)
  Part = POINTER TO PartDesc;
  PartDesc = RECORD
    text: B.Buf;
    n: LONGINT;
    next: Part
  END;
  Macro = POINTER TO MacroDesc;
  MacroDesc = RECORD
    name: A.Rope;
    parts: Part;
    next: Macro
  END;

  (* A macro's argument *)
  Arg = POINTER TO ArgDesc;
  ArgDesc = RECORD
    text: B.Buf;
    next: Arg
  END;

  (* A place --unknown has reported *)
  Report = POINTER TO RECORD
    line, col: LONGINT;
    name: A.Rope;
    next: Report
  END;

  Resolver = POINTER TO ResolverDesc;
  ResolverDesc = RECORD (A.WalkerDesc)
    notes: BOOLEAN (* FALSE inside a referenced note's contents *)
  END;

VAR
  fancyLists*: BOOLEAN; (* the extension fancy_lists *)
  citations*: BOOLEAN; (* the extension citations *)
  st: State;
  here: Pos; (* B.pos's line and column, last counted *)
  preChars, postChars: B.Buf; (* UTF-8: the characters allowed
    before and after emphasis *)
  defPre, defPost: B.Buf; (* pandoc's defaults for them *)
  formats: Format; (* the newest first *)
  notes: Note; (* the newest first *)
  macros: Macro; (* the newest first *)
  macroDepth: INTEGER; (* orgStateMacroDepth *)
  unknown*: INTEGER; (* --unknown: Quiet, WarnUnknown or FailUnknown *)
  main*: B.Text; (* the document's text, as PdSource read it *)
  mainLen*: LONGINT;
  (* each text Enter entered, by B.depth: the one it was entered from
     and where that had got to, and where it came from *)
  orgParent: ARRAY MaxDepth OF B.Text;
  orgPos, orgA, orgB: ARRAY MaxDepth OF LONGINT;
  orgKind: ARRAY MaxDepth OF INTEGER;
  orgName: ARRAY MaxDepth OF A.Rope;
  nextKind: INTEGER; nextA, nextB: LONGINT; nextName: A.Rope;
  reported: Report; (* the places --unknown has reported *)

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
  preChars := defPre; postChars := defPost; formats := NIL; notes := NIL;
  macros := NIL; macroDepth := 0;
  nextKind := OrgUnknown; nextName := NIL; reported := NIL
END Reset;

(* addToNotesTable: ref, fn:name or a number, is defined as blocks *)
PROCEDURE AddNote*(ref: A.Rope; blocks: A.Block);
  VAR n: Note;
BEGIN
  NEW(n); n.ref := ref; n.blocks := blocks; n.next := notes; notes := n
END AddNote;

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

(* Where the text the next Enter or Push enters came from: kind, one
   of OrgUnknown, OrgOffset, OrgLines and OrgAt, with a and b *)
PROCEDURE Origin*(kind: INTEGER; a, b: LONGINT);
BEGIN
  nextKind := kind; nextA := a; nextB := b; nextName := NIL
END Origin;

(* The text the next Enter or Push enters is the file name's, from its
   line line; a leading ./ is left out *)
PROCEDURE FileOrigin*(name: ARRAY OF CHAR; line: LONGINT);
  VAR i: LONGINT;
BEGIN
  nextKind := OrgFile; nextA := line; nextB := 0; nextName := A.S(name);
  i := 0;
  WHILE (name[i] = ".") & (name[i + 1] = "/") DO INC(i, 2) END;
  IF i > 0 THEN
    nextName := Ropes.Substring(nextName, i, Ropes.Length(nextName) - i)
  END
END FileOrigin;

(* B.Enter, the text's origin recorded as Origin or FileOrigin gave it *)
PROCEDURE Push*(VAR f: B.Frame; text: B.Text; n: LONGINT);
  VAR d: INTEGER; t: B.Text; p: LONGINT;
BEGIN
  t := B.t; p := B.pos;
  B.Enter(f, text, n);
  d := B.depth;
  IF d < MaxDepth THEN
    orgParent[d] := t; orgPos[d] := p; orgKind[d] := nextKind;
    orgA[d] := nextA; orgB[d] := nextB; orgName[d] := nextName
  END;
  nextKind := OrgUnknown; nextName := NIL
END Push;

(* The input's name, and the line and column, counted from 1 in
   characters, of p in B.t, following the texts entered back to the
   document or an included file *)
PROCEDURE Loc*(p: LONGINT; VAR name: ARRAY OF CHAR; VAR line, col: LONGINT);
  VAR d, i, k, ls, c: LONGINT; t, pt: B.Text;
BEGIN
  d := B.depth; t := B.t;
  IF d >= MaxDepth THEN (* where the deepest recorded had got to *)
    WHILE d >= MaxDepth DO DEC(d) END;
    p := orgPos[d]; t := orgParent[d]; DEC(d)
  END;
  LOOP
    IF (d > 0) & (orgKind[d] = OrgFile) OR (d <= 0) THEN EXIT END;
    pt := orgParent[d];
    CASE orgKind[d] OF
    | OrgOffset: p := orgA[d] + p
    | OrgAt: p := orgA[d]
    | OrgLines:
      k := 1; ls := 0; i := 0;
      WHILE (i < p) & (i < LEN(t^)) DO
        IF t[i] = 0AX THEN INC(k); ls := i + 1 END;
        INC(i)
      END;
      c := p - ls; i := orgA[d];
      IF k = 1 THEN p := i + c
      ELSE
        WHILE (k > 1) & (i < LEN(pt^)) & (pt[i] # 0X) DO
          IF pt[i] = 0AX THEN DEC(k) END;
          INC(i)
        END;
        p := i + orgB[d] + c
      END
    ELSE p := orgPos[d]
    END;
    t := pt; DEC(d)
  END;
  IF p < 0 THEN p := 0 END;
  IF d > 0 THEN (* an included file's text *)
    Ropes.ToString(orgName[d], name);
    line := orgA[d]; i := 0;
    WHILE (i < p) & (i < LEN(t^)) DO
      IF t[i] = 0AX THEN INC(line) END;
      INC(i)
    END
  ELSE
    t := main;
    IF p >= mainLen THEN p := mainLen - 1 END;
    IF p < 0 THEN p := 0 END;
    PdSource.Locate(main^, p, name, line)
  END;
  ls := p;
  WHILE (ls > 0) & (t[ls - 1] # 0AX) DO DEC(ls) END;
  col := 1;
  FOR i := ls TO p - 1 DO
    IF (ORD(t[i]) < 80H) OR (ORD(t[i]) >= 0C0H) THEN INC(col) END
  END
END Loc;

(* Appends s to m, as far as it goes *)
PROCEDURE AppendTo(VAR m: ARRAY OF CHAR; s: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE m[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (s[j] # 0X) & (i < LEN(m) - 1) DO m[i] := s[j]; INC(i); INC(j) END;
  m[i] := 0X
END AppendTo;

(* Appends n, not negative, to m *)
PROCEDURE AppendNum(VAR m: ARRAY OF CHAR; n: LONGINT);
  VAR d: ARRAY 24 OF CHAR; i, k: LONGINT;
BEGIN
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  k := 0; WHILE m[k] # 0X DO INC(k) END;
  WHILE (i > 0) & (k < LEN(m) - 1) DO DEC(i); m[k] := d[i]; INC(k) END;
  m[k] := 0X
END AppendNum;

(* Reports, as --unknown asks, what at p in B.t the reader does not
   know or keeps unread: what, then 'r' quoted, then the place. Each
   place is reported once, though the parser may read it again. *)
PROCEDURE Unknown*(what: ARRAY OF CHAR; r: A.Rope; p: LONGINT);
  VAR m: ARRAY 1024 OF CHAR; name: ARRAY 512 OF CHAR; s: ARRAY 256 OF CHAR;
    line, col: LONGINT; x: Report;
BEGIN
  IF unknown = Quiet THEN RETURN END;
  Loc(p, name, line, col);
  x := reported;
  WHILE (x # NIL) & ~((x.line = line) & (x.col = col)
      & Ropes.Equal(x.name, A.S(name))) DO
    x := x.next
  END;
  IF x # NIL THEN RETURN END;
  NEW(x); x.line := line; x.col := col; x.name := A.S(name);
  x.next := reported; reported := x;
  COPY(what, m); AppendTo(m, " '");
  Ropes.ToString(r, s); AppendTo(m, s); AppendTo(m, "' at ");
  IF (name # "") & (name # "-") THEN AppendTo(m, name); AppendTo(m, " ") END;
  AppendTo(m, "line "); AppendNum(m, line);
  AppendTo(m, " column "); AppendNum(m, col);
  IF unknown = FailUnknown THEN PdIO.Fail("", m, PdIO.ParseError)
  ELSE PdIO.Warn(m)
  END
END Unknown;

(* Org's parseFromString: enters the text, of n bytes, as B.Enter
   does, the last pre character's position Nothing *)
PROCEDURE Enter*(VAR f: B.Frame; text: B.Text; n: LONGINT);
BEGIN
  Push(f, text, n); ClearPre
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
  IF open = "(" THEN Origin(OrgOffset, p, 0) ELSE Origin(OrgOffset, p + 1, 0) END;
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
  Push(f, b.t, b.len)
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
  Origin(OrgOffset, q, 0); (* a new line made a space, byte for byte *)
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

(* orgArgWord: letters, digits, - and _; where it ends, or -1 *)
PROCEDURE ArgWord*(p: LONGINT): LONGINT;
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
PROCEDURE ArgKey*(p: LONGINT; VAR from: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF B.C(p) # ":" THEN RETURN -1 END;
  from := p + 1;
  RETURN ArgWord(p + 1)
END ArgKey;

(* Whether t[from .. to-1] is s *)
PROCEDURE IsText(from, to: LONGINT; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
  RETURN (to - from = i) & B.Looking(from, s)
END IsText;

(* translateLang: pandoc's name for an Org language, or NIL if it is
   the same *)
PROCEDURE TranslateLang*(from, to: LONGINT): A.Rope;
BEGIN
  IF IsText(from, to, "C") THEN RETURN A.S("c")
  ELSIF IsText(from, to, "emacs-lisp") OR IsText(from, to, "lisp") THEN
    RETURN A.S("commonlisp")
  ELSIF IsText(from, to, "js") THEN RETURN A.S("javascript")
  ELSIF IsText(from, to, "R") THEN RETURN A.S("r")
  ELSIF IsText(from, to, "sh") THEN RETURN A.S("bash")
  ELSIF IsText(from, to, "sqlite") THEN RETURN A.S("sql")
  END;
  RETURN NIL
END TranslateLang;

(* inlineCodeBlock: src_lang[options]{code}, a Code, or nothing if
   its first exports option is neither code nor both *)
PROCEDURE InlineCode(VAR l: A.Inlines): BOOLEAN;
  VAR q, r, e, from, v: LONGINT; a: A.Attr; lang, key, val: A.Rope;
    exports, seen: BOOLEAN; ch: CHAR;
BEGIN
  IF ~B.Looking(B.pos, "src_") THEN RETURN FALSE END;
  q := ArgWord(B.pos + 4);
  IF q < 0 THEN RETURN FALSE END;
  a := A.NewAttr(NIL);
  lang := TranslateLang(B.pos + 4, q);
  IF lang = NIL THEN A.AddClass(a, B.Rope(B.pos + 4, q))
  ELSE
    A.AddClass(a, lang);
    A.AddKeyVal(a, A.S("org-language"), B.Rope(B.pos + 4, q))
  END;
  exports := TRUE; seen := FALSE; r := q;
  IF B.C(r) = "[" THEN
    INC(r);
    LOOP
      IF (r < B.len) & (B.t[r] = "]") THEN INC(r); EXIT END;
      e := ArgKey(r, from);
      IF e < 0 THEN RETURN FALSE END;
      key := B.Rope(from, e);
      v := B.SkipSpaces(e); r := v;
      LOOP
        ch := B.C(r);
        IF (r >= B.len) OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
            OR (ch = " ") OR (ch = "]") THEN EXIT
        END;
        INC(r)
      END;
      IF (r = v) OR (B.t[v] = ":") THEN val := A.S("yes"); r := e
      ELSE val := B.Rope(v, r); r := B.SkipSpaces(r)
      END;
      A.AddKeyVal(a, key, val);
      IF ~seen & IsText(from, e, "exports") THEN
        seen := TRUE;
        exports := Ropes.EqualString(val, "code")
          OR Ropes.EqualString(val, "both")
      END
    END
  END;
  IF B.C(r) # "{" THEN RETURN FALSE END;
  e := r + 1;
  IF (e >= B.len) OR (B.t[e] = 0AX) OR (B.t[e] = 0DX) OR (B.t[e] = "}") THEN
    RETURN FALSE
  END;
  INC(e);
  LOOP
    ch := B.C(e);
    IF (e >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN RETURN FALSE
    ELSIF ch = "}" THEN EXIT
    END;
    INC(e)
  END;
  IF exports THEN A.Append(l, A.NewCode(a, B.Rope(r + 1, e))) END;
  B.pos := e + 1;
  RETURN TRUE
END InlineCode;

(* exportSnippet: @@format:text@@, a RawInline *)
PROCEDURE ExportSnippet(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, r: LONGINT;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "@@") THEN RETURN FALSE END;
  q := p + 2;
  WHILE (q < B.len) & (MI.AlnumAt(q) OR (B.t[q] = "-")) DO
    q := MI.RuneEnd(q)
  END;
  IF (q = p + 2) OR (B.C(q) # ":") THEN RETURN FALSE END;
  r := q + 1;
  WHILE (r + 1 < B.len) & ~B.Looking(r, "@@") DO INC(r) END;
  IF r + 1 >= B.len THEN RETURN FALSE END;
  A.Append(l, A.NewRawInline(B.Rope(p + 2, q), B.Rope(q + 1, r)));
  B.pos := r + 2;
  RETURN TRUE
END ExportSnippet;

(* #+MACRO: the line from p, after the key: a name, spaces and the
   text, with $1, $2 and so on for its arguments (macroDefinition).
   FALSE, nothing changed, if there is no name. *)
PROCEDURE AddMacro*(p: LONGINT): BOOLEAN;
  VAR q: LONGINT; ch: CHAR; m: Macro; pt, last: Part;
BEGIN
  q := p;
  LOOP
    ch := B.C(q);
    IF (q >= B.len) OR (ch = " ") OR (ch = 09X) OR (ch = 0AX)
        OR (ch = 0DX) THEN EXIT
    END;
    INC(q)
  END;
  IF q = p THEN RETURN FALSE END;
  NEW(m); m.name := B.Rope(p, q); m.parts := NIL; last := NIL;
  q := B.SkipSpaces(q);
  LOOP
    NEW(pt); B.InitBuf(pt.text); pt.n := 0; pt.next := NIL;
    IF last = NIL THEN m.parts := pt ELSE last.next := pt END;
    last := pt;
    LOOP
      ch := B.C(q);
      IF (q >= B.len) OR (ch = 0AX) OR (ch = 0DX) THEN EXIT
      ELSIF (ch = "$") & B.IsDigit(B.C(q + 1)) & (q + 1 < B.len) THEN EXIT
      END;
      B.PutChar(pt.text, ch); INC(q)
    END;
    IF (q >= B.len) OR (B.t[q] # "$") THEN EXIT END;
    INC(q);
    WHILE (q < B.len) & B.IsDigit(B.t[q]) DO
      IF pt.n < 1000000 THEN pt.n := pt.n * 10 + ORD(B.t[q]) - ORD("0") END;
      INC(q)
    END;
    IF pt.n < 1 THEN pt.n := 1 END (* drop (n - 1) of the arguments *)
  END;
  m.next := macros; macros := m;
  RETURN TRUE
END AddMacro;

(* macro: {{{name}}} or {{{name(arguments)}}}, a macro defined, its
   text, with the arguments, read as inlines *)
PROCEDURE MacroCall(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, i: LONGINT; ch: CHAR; m: Macro; args, a, last, sel, s: Arg;
    pt: Part; name: A.Rope; text: B.Buf; f: B.Frame; cl: A.Inlines;
BEGIN
  p := B.pos;
  IF (macroDepth >= 15) OR ~B.Looking(p, "{{{") THEN RETURN FALSE END;
  q := p + 3;
  WHILE (q < B.len) & MI.AlnumAt(q) DO q := MI.RuneEnd(q) END;
  name := B.Rope(p + 3, q);
  args := NIL;
  IF B.Looking(q, "}}}") THEN INC(q, 3)
  ELSIF B.C(q) = "(" THEN
    INC(q); last := NIL;
    LOOP
      NEW(a); B.InitBuf(a.text); a.next := NIL;
      IF last = NIL THEN args := a ELSE last.next := a END;
      last := a;
      LOOP
        IF q >= B.len THEN RETURN FALSE END;
        ch := B.t[q];
        IF B.Looking(q, ")}}}") OR (ch = ",") THEN EXIT
        ELSIF (ch = "\") & ((B.C(q + 1) = ",") OR (B.C(q + 1) = "\"))
            & (q + 1 < B.len) THEN
          B.PutChar(a.text, B.t[q + 1]); INC(q, 2)
        ELSE B.PutChar(a.text, ch); INC(q)
        END
      END;
      IF B.t[q] = "," THEN INC(q)
      ELSE INC(q, 4); EXIT
      END
    END
  ELSE RETURN FALSE
  END;
  m := macros;
  WHILE (m # NIL) & ~Ropes.Equal(m.name, name) DO m := m.next END;
  IF m = NIL THEN Unknown("Unknown macro", name, p); RETURN FALSE END;
  (* the parts alternate with the arguments their numbers name, those
     there are *)
  sel := NIL; last := NIL; pt := m.parts;
  WHILE pt # NIL DO
    IF pt.n > 0 THEN
      a := args; i := 1;
      WHILE (a # NIL) & (i < pt.n) DO a := a.next; INC(i) END;
      IF a # NIL THEN
        NEW(s); s.text := a.text; s.next := NIL;
        IF last = NIL THEN sel := s ELSE last.next := s END;
        last := s
      END
    END;
    pt := pt.next
  END;
  B.InitBuf(text); pt := m.parts;
  WHILE pt # NIL DO
    PutPart(text, pt.text, 0, pt.text.len);
    IF sel # NIL THEN PutPart(text, sel.text, 0, sel.text.len); sel := sel.next END;
    pt := pt.next
  END;
  B.PutChar(text, 0X); DEC(text.len);
  B.pos := q;
  INC(macroDepth);
  Origin(OrgAt, p, 0);
  Enter(f, text.t, text.len);
  A.InitInlines(cl);
  WHILE Inline(cl) DO END;
  Leave(f);
  DEC(macroDepth);
  A.Append(l, cl.first);
  RETURN TRUE
END MacroCall;

(* Citations *)

(* B.text: the text from .. to-1 as Strs, Spaces and SoftBreaks *)
PROCEDURE BText(from, to: LONGINT): A.Inline;
  VAR l: A.Inlines; q: LONGINT; nl: BOOLEAN;

  PROCEDURE IsSpace(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
  END IsSpace;

BEGIN
  A.InitInlines(l);
  WHILE from < to DO
    q := from; nl := FALSE;
    WHILE (q < to) & IsSpace(B.t[q]) DO
      IF (B.t[q] = 0AX) OR (B.t[q] = 0DX) THEN nl := TRUE END;
      INC(q)
    END;
    IF q > from THEN
      IF nl THEN A.AddInline(l, A.NewSimple(A.SoftBreak))
      ELSE A.AddInline(l, A.NewSimple(A.Space))
      END
    ELSE
      WHILE (q < to) & ~IsSpace(B.t[q]) DO INC(q) END;
      A.AddInline(l, A.NewStr(B.Rope(from, q)))
    END;
    from := q
  END;
  RETURN l.first
END BText;

(* The list a followed by the list b *)
PROCEDURE Concat(a, b: A.Inline): A.Inline;
  VAR x: A.Inline;
BEGIN
  IF a = NIL THEN RETURN b END;
  x := A.LastInline(a); x.next := b;
  RETURN a
END Concat;

(* Whether a letter starts at p *)
PROCEDURE LetterAt(p: LONGINT): BOOLEAN;
  VAR c: Utf8.Rune; q: LONGINT;
BEGIN
  IF p >= B.len THEN RETURN FALSE END;
  q := MI.RuneAt(p, c);
  RETURN (c < 80H) & B.IsLetter(B.t[p]) OR (c >= 80H) & Unicode.IsLetter(c)
END LetterAt;

(* orgCiteStyle: the style named by t[from .. to-1], or -1 *)
PROCEDURE CiteStyle(from, to: LONGINT): INTEGER;
BEGIN
  IF IsText(from, to, "t") OR IsText(from, to, "text") THEN RETURN TextStyle
  ELSIF IsText(from, to, "na") OR IsText(from, to, "noauthor") THEN
    RETURN NoAuthorStyle
  ELSIF IsText(from, to, "nil") THEN RETURN NilStyle
  ELSIF IsText(from, to, "a") OR IsText(from, to, "author")
      OR IsText(from, to, "n") OR IsText(from, to, "nocite")
      OR IsText(from, to, "ft") OR IsText(from, to, "note")
      OR IsText(from, to, "nb") OR IsText(from, to, "numeric") THEN
    RETURN OtherStyle
  END;
  RETURN -1
END CiteStyle;

(* orgCiteVariants at p: where they end, or -1 *)
PROCEDURE CiteVariants(p: LONGINT): LONGINT;
  PROCEDURE Full(p: LONGINT): BOOLEAN;
  BEGIN
    RETURN B.Looking(p, "bare") OR B.Looking(p, "caps") OR B.Looking(p, "full")
  END Full;
  PROCEDURE One(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch = "b") OR (ch = "c") OR (ch = "f")
  END One;
BEGIN
  IF Full(p) THEN
    INC(p, 4);
    WHILE (B.C(p) = "-") & Full(p + 1) DO INC(p, 5) END
  ELSIF (p < B.len) & One(B.t[p]) THEN
    WHILE (p < B.len) & One(B.t[p]) DO INC(p) END
  ELSE p := -1
  END;
  RETURN p
END CiteVariants;

(* spnl at p: spaces, and a new line and spaces if no blank line
   follows; where it ends, or -1 *)
PROCEDURE Spnl(p: LONGINT): LONGINT;
BEGIN
  p := B.SkipSpaces(p);
  IF (p < B.len) & (B.t[p] = 0AX) THEN
    INC(p);
    IF B.C(B.SkipSpaces(p)) = 0AX THEN RETURN -1 END;
    p := B.SkipSpaces(p)
  END;
  RETURN p
END Spnl;

(* rawAffix at p: characters but ^ ; [ ] and, in a prefix, @, and
   balanced brackets; where it ends *)
PROCEDURE RawAffix(p: LONGINT; prefix: BOOLEAN): LONGINT;
  VAR ch: CHAR; q: LONGINT;
BEGIN
  LOOP
    IF p >= B.len THEN EXIT END;
    ch := B.t[p];
    IF ch = "[" THEN
      q := RawAffix(p + 1, prefix);
      IF (q < B.len) & (B.t[q] = "]") THEN p := q + 1 ELSE EXIT END
    ELSIF (ch = "^") OR (ch = ";") OR (ch = "]") OR prefix & (ch = "@") THEN
      EXIT
    ELSE INC(p)
    END
  END;
  RETURN p
END RawAffix;

(* citePrefix (trimmed) and citeSuffix: t[from .. to-1] read as
   inlines *)
PROCEDURE Affix(from, to: LONGINT; trim: BOOLEAN): A.Inline;
  VAR b: B.Buf; f: B.Frame; cl: A.Inlines;
BEGIN
  B.InitBuf(b); B.Put(b, from, to); B.PutChar(b, 0X); DEC(b.len);
  Origin(OrgOffset, from, 0);
  Enter(f, b.t, b.len);
  A.InitInlines(cl);
  WHILE Inline(cl) DO END;
  Leave(f);
  IF trim THEN RETURN MI.Trim(cl) END;
  RETURN cl.first
END Affix;

(* Whether an orgCiteKeyChar starts at p *)
PROCEDURE CiteKeyChar(p: LONGINT): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  IF p >= B.len THEN RETURN FALSE END;
  ch := B.t[p];
  CASE ch OF
    ".", ":", "?", "!", "`", "'", "/", "*", "@", "+", "|", "(", ")", "{",
    "}", "<", ">", "&", "_", "^", "$", "#", "%", "~", "-": RETURN TRUE
  ELSE RETURN MI.AlnumAt(p)
  END
END CiteKeyChar;

(* citeItem at p: a prefix, @key and a suffix, in c; where it ends,
   or -1 *)
PROCEDURE CiteItem(p: LONGINT; VAR c: A.Citation): LONGINT;
  VAR q, k, e: LONGINT;
BEGIN
  q := RawAffix(p, TRUE);
  IF B.C(q) # "@" THEN RETURN -1 END;
  k := q + 1;
  WHILE CiteKeyChar(k) DO k := MI.RuneEnd(k) END;
  IF k = q + 1 THEN RETURN -1 END;
  e := RawAffix(k, FALSE);
  c := A.NewCitation(B.Rope(q + 1, k), A.NormalCitation, 0);
  c.prefix := Affix(p, q, TRUE);
  c.suffix := Affix(k, e, FALSE);
  RETURN e
END CiteItem;

(* orgCite: [cite/style/variants:items], into cs *)
PROCEDURE OrgCite(VAR cs: A.Citation): BOOLEAN;
  VAR q, r: LONGINT; sty: INTEGER; gp, gs, i: A.Inline; c, last: A.Citation;
BEGIN
  q := B.pos;
  IF ~B.Looking(q, "[cite") THEN RETURN FALSE END;
  INC(q, 5); sty := NilStyle;
  IF B.C(q) = "/" THEN
    r := q + 1;
    WHILE LetterAt(r) DO r := MI.RuneEnd(r) END;
    IF r > q + 1 THEN sty := CiteStyle(q + 1, r) ELSE sty := -1 END;
    IF sty >= 0 THEN q := r ELSE sty := NilStyle END
  END;
  IF B.C(q) = "/" THEN
    r := CiteVariants(q + 1);
    IF r >= 0 THEN q := r END
  END;
  IF (q >= B.len) OR (B.t[q] # ":") THEN RETURN FALSE END;
  q := Spnl(q + 1);
  IF q < 0 THEN RETURN FALSE END;
  gp := NIL; gs := NIL;
  r := RawAffix(q, TRUE);
  IF (r < B.len) & (B.t[r] = ";") THEN
    gp := Affix(q, r, TRUE); q := r + 1
  END;
  q := CiteItem(q, cs);
  IF q < 0 THEN RETURN FALSE END;
  last := cs;
  WHILE (q < B.len) & (B.t[q] = ";") DO
    r := CiteItem(B.SkipSpaces(q + 1), c);
    IF r < 0 THEN
      r := RawAffix(q + 1, FALSE);
      gs := Affix(q + 1, r, FALSE); q := r
    ELSE last.next := c; last := c; q := r
    END
  END;
  q := Spnl(q);
  IF (q < 0) OR (B.C(q) # "]") OR (q >= B.len) THEN RETURN FALSE END;
  B.pos := q + 1;
  last.suffix := Concat(last.suffix, gs);
  cs.prefix := Concat(gp, cs.prefix);
  IF sty = TextStyle THEN
    cs.mode := A.AuthorInText;
    i := cs.suffix;
    WHILE (i # NIL) & (i.kind = A.Space) DO i := i.next END;
    cs.suffix := i
  ELSIF sty = NoAuthorStyle THEN cs.mode := A.SuppressAuthor
  END;
  RETURN TRUE
END OrgCite;

(* orgRefCiteMode at p: where it ends, after its colon, or -1 *)
PROCEDURE RefCiteMode(p: LONGINT; VAR mode: INTEGER): LONGINT;
BEGIN
  IF B.Looking(p, "cite:") THEN mode := A.AuthorInText; RETURN p + 5
  ELSIF B.Looking(p, "citep:") THEN mode := A.NormalCitation; RETURN p + 6
  ELSIF B.Looking(p, "citep*:") THEN mode := A.NormalCitation; RETURN p + 7
  ELSIF B.Looking(p, "citet:") THEN mode := A.AuthorInText; RETURN p + 6
  ELSIF B.Looking(p, "citet*:") THEN mode := A.AuthorInText; RETURN p + 7
  ELSIF B.Looking(p, "citeyear:") THEN
    mode := A.SuppressAuthor; RETURN p + 9
  END;
  RETURN -1
END RefCiteMode;

(* Whether ch is one of orgRefCiteKey's special characters *)
PROCEDURE RefKeySpecial(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = "-") OR (ch = "_") OR (ch = ":") OR (ch = "\") OR (ch = ".")
    OR (ch = "/")
END RefKeySpecial;

(* Whether a character of an orgRefCiteKey starts at p *)
PROCEDURE RefKeyChar(p: LONGINT): BOOLEAN;
BEGIN
  RETURN (p < B.len) & (RefKeySpecial(B.t[p]) OR MI.AlnumAt(p))
END RefKeyChar;

(* orgRefCiteKey at p, a citation of the mode, in c; where it ends,
   or -1. The key ends before any special characters followed by a
   character not in keys. *)
PROCEDURE RefCiteKey(p: LONGINT; mode: INTEGER; VAR c: A.Citation): LONGINT;
  VAR from, r: LONGINT;
BEGIN
  IF B.C(p) = "&" THEN INC(p) END;
  from := p;
  LOOP
    r := p;
    WHILE (r < B.len) & RefKeySpecial(B.t[r]) DO INC(r) END;
    IF ~RefKeyChar(r) THEN EXIT END;
    p := MI.RuneEnd(p)
  END;
  IF p = from THEN RETURN -1 END;
  c := A.NewCitation(B.Rope(from, p), mode, 0);
  RETURN p
END RefCiteKey;

(* normalOrgRefCite: mode:key,key...; linkLikeOrgRefCite:
   [[mode:key][prefix::suffix]] *)
PROCEDURE RefCite(VAR cs: A.Citation): BOOLEAN;
  VAR q, r: LONGINT; mode: INTEGER; c, last: A.Citation; cl: A.Inlines;
    spc: BOOLEAN; suf: A.Inline;
BEGIN
  q := RefCiteMode(B.pos, mode);
  IF q >= 0 THEN
    q := RefCiteKey(q, mode, cs);
    IF q < 0 THEN RETURN FALSE END;
    last := cs;
    LOOP
      IF B.C(q) # "," THEN EXIT END;
      r := RefCiteKey(q + 1, mode, c);
      IF r < 0 THEN EXIT END;
      last.next := c; last := c; q := r
    END;
    B.pos := q;
    RETURN TRUE
  END;
  IF ~B.Looking(B.pos, "[[") THEN RETURN FALSE END;
  q := RefCiteMode(B.pos + 2, mode);
  IF q < 0 THEN RETURN FALSE END;
  q := RefCiteKey(q, mode, cs);
  IF (q < 0) OR ~B.Looking(q, "][") THEN RETURN FALSE END;
  B.pos := q + 2;
  A.InitInlines(cl);
  WHILE ~B.Looking(B.pos, "::") DO
    IF ~Inline(cl) THEN RETURN FALSE END
  END;
  INC(B.pos, 2);
  cs.prefix := MI.Trim(cl);
  spc := (B.C(B.pos) = " ") OR (B.C(B.pos) = 09X) & (B.pos < B.len);
  IF spc THEN INC(B.pos) END;
  A.InitInlines(cl);
  WHILE ~B.Looking(B.pos, "]]") DO
    IF ~Inline(cl) THEN RETURN FALSE END
  END;
  INC(B.pos, 2);
  suf := MI.Trim(cl);
  IF spc THEN suf := Concat(A.NewSimple(A.Space), suf) END;
  cs.suffix := suf;
  RETURN TRUE
END RefCite;

(* cite: an org-cite or org-ref citation, its text as written its
   content; only with the extension citations *)
PROCEDURE Cite(VAR l: A.Inlines): BOOLEAN;
  VAR p: LONGINT; s: State; cs: A.Citation;
BEGIN
  IF ~citations THEN RETURN FALSE END;
  p := B.pos; Save(s);
  IF ~OrgCite(cs) THEN
    Restore(s);
    IF ~RefCite(cs) THEN Restore(s); RETURN FALSE END
  END;
  A.Append(l, A.NewCite(cs, BText(p, B.pos)));
  RETURN TRUE
END Cite;

(* footnote: an inline note, [fn:name:text] or [fn::text], or a
   reference to a note, [fn:name] or [1]; nothing under f:nil *)
PROCEDURE Footnote(VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT; s: State; cl: A.Inlines; para: A.Block;
    note, t: A.Inline; ref: B.Buf;
BEGIN
  p := B.pos;
  IF B.Looking(p, "[fn:") THEN (* inlineNote *)
    q := p + 4;
    WHILE (q < B.len) & (MI.AlnumAt(q) OR (B.t[q] = "-") OR (B.t[q] = "_")) DO
      q := MI.RuneEnd(q)
    END;
    IF B.C(q) = ":" THEN
      Save(s);
      B.pos := q + 1;
      A.InitInlines(cl);
      WHILE (B.pos < B.len) & (B.t[B.pos] # "]") & Inline(cl) DO END;
      IF (B.C(B.pos) = "]") & (B.pos < B.len) & (cl.first # NIL) THEN
        INC(B.pos);
        para := A.NewInlinesBlock(A.Para, MI.Trim(cl));
        IF q > p + 4 THEN
          AddNote(Ropes.Cat(A.S("fn:"), B.Rope(p + 4, q)),
            A.DeepCopyBlocks(para))
        END;
        IF M.footnotes THEN A.Append(l, A.NewNote(para)) END;
        RETURN TRUE
      END;
      Restore(s)
    END
  END;
  q := NoteMarker(p); (* referencedNote *)
  IF q < 0 THEN RETURN FALSE END;
  B.pos := q;
  IF M.footnotes THEN
    B.InitBuf(ref); B.Put(ref, p + 1, q - 1);
    t := NIL; note := Pending(NoteRef, ref, t);
    A.Append(l, note)
  END;
  RETURN TRUE
END Footnote;

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

(* referencedNote, resolved: the note defined as ref, its contents
   resolved without notes, or the text [ref] *)
PROCEDURE NoteFor(w: Resolver; VAR ref: B.Buf): A.Inline;
  VAR n: Note; r: A.Rope; v: Resolver; b: A.Block;
BEGIN
  r := B.BufRope(ref); n := NIL;
  IF w.notes THEN
    n := notes;
    WHILE (n # NIL) & ~Ropes.Equal(n.ref, r) DO n := n.next END
  END;
  IF n = NIL THEN
    RETURN A.NewStr(Ropes.Cat(Ropes.Cat(A.S("["), r), A.S("]")))
  END;
  NEW(v); v.notes := FALSE;
  b := A.WalkBlocks(v, A.DeepCopyBlocks(n.blocks));
  RETURN A.NewNote(b)
END NoteFor;

PROCEDURE (w: Resolver) Inline*(i: A.Inline): A.Inline;
  VAR a: PendAttr;
BEGIN
  IF (i IS A.SpanInl) & (i(A.SpanInl).attr # NIL)
      & (i(A.SpanInl).attr IS PendAttr) THEN
    a := i(A.SpanInl).attr(PendAttr);
    IF a.how = NoteRef THEN RETURN NoteFor(w, a.target) END;
    RETURN Resolved(a, i(A.SpanInl).content)
  END;
  RETURN i
END Inline;

(* Resolves the links of the document d, read last, against its
   anchors and #+LINK formats, as pandoc's F monad does at the end *)
PROCEDURE Resolve*(d: A.Doc);
  VAR w: Resolver; old: BOOLEAN;
BEGIN
  old := A.mergeWalk; A.mergeWalk := TRUE; (* a note's [ref] joins the
    text around it *)
  NEW(w); w.notes := TRUE; A.WalkDoc(w, d);
  A.mergeWalk := old
END Resolve;

(* Resolves the blocks b, read from an included file, against the
   notes, anchors and #+LINK formats known now, as pandoc's runF does
   at an include; returns them *)
PROCEDURE ResolveBlocks*(b: A.Block): A.Block;
  VAR w: Resolver; old: BOOLEAN;
BEGIN
  old := A.mergeWalk; A.mergeWalk := TRUE;
  NEW(w); w.notes := TRUE; b := A.WalkBlocks(w, b);
  A.mergeWalk := old;
  RETURN b
END ResolveBlocks;

(* Math and LaTeX (Phase 27.4) *)

(* Whether ch is one of Org's characters not allowed at the inner
   border of $ math (mathForbiddenBorderChars, with the $) *)
PROCEDURE MathBorder(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = 09X) OR (ch = 0AX) OR (ch = 0DX) OR (ch = " ")
    OR (ch = ",") OR (ch = ";") OR (ch = ".") OR (ch = "$")
END MathBorder;

(* mathPostChars, or the end of the text, at p *)
PROCEDURE MathPost(p: LONGINT): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  IF p >= B.len THEN RETURN TRUE END;
  ch := B.C(p);
  RETURN (ch = 09X) OR (ch = 0AX) OR (ch = " ") OR (ch = 22X)
    OR (ch = "'") OR (ch = ")") OR (ch = ",") OR (ch = "-")
    OR (ch = ".") OR (ch = ":") OR (ch = ";") OR (ch = "?")
END MathPost;

(* mathEnd '$' at p: a character not at the border, a $ and a post
   character; the position of the $, or -1 *)
PROCEDURE MathEnd(p: LONGINT): LONGINT;
  VAR q: LONGINT; r: Utf8.Rune;
BEGIN
  IF (p >= B.len) OR MathBorder(B.C(p)) THEN RETURN -1 END;
  q := MI.RuneAt(p, r);
  IF (B.C(q) # "$") OR ~MathPost(q + 1) THEN RETURN -1 END;
  RETURN q
END MathEnd;

(* rawMathBetween open close: the text from B.pos+LEN(open) to the
   first close, as math of the kind given *)
PROCEDURE RawMath(open, close: ARRAY OF CHAR; kind: INTEGER;
    VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT;
BEGIN
  IF ~B.Looking(B.pos, open) THEN RETURN FALSE END;
  p := B.pos + 2; q := p; (* open and close are two characters *)
  WHILE (q < B.len) & ~B.Looking(q, close) DO INC(q) END;
  IF q >= B.len THEN RETURN FALSE END;
  A.Append(l, A.NewMath(kind, B.Rope(p, q)));
  B.pos := q + 2;
  RETURN TRUE
END RawMath;

(* math and displayMath at a $: math1CharBetween, mathTextBetween
   (at most two new lines inside), then $$...$$ *)
PROCEDURE DollarMath(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, start, e: LONGINT; lines: INTEGER; r: Utf8.Rune; ch: CHAR;
BEGIN
  p := B.pos;
  (* math1CharBetween *)
  IF (p + 1 < B.len) & ~MathBorder(B.C(p + 1)) THEN
    q := MI.RuneAt(p + 1, r);
    IF (B.C(q) = "$") & MathPost(q + 1) THEN
      A.Append(l, A.NewMath(A.InlineMath, B.Rope(p + 1, q)));
      B.pos := q + 1;
      RETURN TRUE
    END
  END;
  (* mathTextBetween *)
  IF ~MathBorder(B.C(p + 1)) THEN
    start := p + 1; q := start; lines := 0;
    LOOP
      e := MathEnd(q);
      IF e >= 0 THEN
        IF q = start THEN EXIT END; (* nothing before the final character *)
        A.Append(l, A.NewMath(A.InlineMath, B.Rope(start, e)));
        B.pos := e + 1;
        RETURN TRUE
      END;
      ch := B.C(q);
      IF (q >= B.len) OR (ch = "$") OR (ch = 0DX) THEN EXIT
      ELSIF ch = 0AX THEN
        IF lines = 2 THEN EXIT END;
        INC(lines); INC(q)
      ELSE q := MI.RuneAt(q, r)
      END
    END
  END;
  RETURN RawMath("$$", "$$", A.DisplayMath, l)
END DollarMath;

(* Sp: spaces and tabs at p, and a new line that does not end the
   paragraph with the spaces and tabs after it *)
PROCEDURE TeXSp(p: LONGINT): LONGINT;
BEGIN
  WHILE (B.C(p) = " ") OR (B.C(p) = 09X) DO INC(p) END;
  IF (B.C(p) = 0AX) & (p + 1 < B.len) & (B.BlankLine(p + 1) < 0) THEN
    INC(p);
    WHILE (B.C(p) = " ") OR (B.C(p) = 09X) DO INC(p) END
  END;
  RETURN p
END TeXSp;

(* The end of the TeX control word at p, a backslash *)
PROCEDURE TeXName(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  INC(p); ch := B.C(p);
  WHILE (p < B.len) & ((ch >= 80X) OR B.IsLetter(ch)) DO
    INC(p); ch := B.C(p)
  END;
  RETURN p
END TeXName;

(* Whether s[from .. to-1] names one of pandoc's inline (math)
   environments, LaTeX/Math.hs's inlineEnvironments *)
PROCEDURE MathEnvName(from, to: LONGINT): BOOLEAN;
  CONST Names = " displaymath math equation equation* gather gather* multline multline* eqnarray eqnarray* align align* alignat alignat* flalign flalign* dmath dmath* dgroup dgroup* darray darray* subequations ";
  VAR names: ARRAY 256 OF CHAR; i, j: LONGINT; n: LONGINT;
BEGIN
  names := Names; n := to - from;
  IF n <= 0 THEN RETURN FALSE END;
  i := 0;
  WHILE names[i] # 0X DO
    IF names[i] = " " THEN
      j := 0;
      WHILE (j < n) & (names[i + 1 + j] = B.C(from + j)) DO INC(j) END;
      IF (j = n) & (names[i + 1 + j] = " ") THEN RETURN TRUE END
    END;
    INC(i)
  END;
  RETURN FALSE
END MathEnvName;

(* {name} at p: the position after it, or -1; the name from n0 to n1 *)
PROCEDURE EnvName(p: LONGINT; VAR n0, n1: LONGINT): LONGINT;
BEGIN
  IF B.C(p) # "{" THEN RETURN -1 END;
  n0 := p + 1; n1 := n0;
  WHILE (n1 < B.len) & (B.C(n1) # "}") & (B.C(n1) # 0AX) DO INC(n1) END;
  IF B.C(n1) # "}" THEN RETURN -1 END;
  RETURN n1 + 1
END EnvName;

(* An inline math environment at p, \begin{name}...\end{name}, ended by
   the first \end{name} (mathEnv): the position after it, or -1 *)
PROCEDURE MathEnv(p: LONGINT): LONGINT;
  VAR q, n0, n1, m0, m1, e: LONGINT; ch: CHAR;

  PROCEDURE Same(): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    IF m1 - m0 # n1 - n0 THEN RETURN FALSE END;
    FOR i := 0 TO n1 - n0 - 1 DO
      IF B.C(m0 + i) # B.C(n0 + i) THEN RETURN FALSE END
    END;
    RETURN TRUE
  END Same;

BEGIN
  q := EnvName(TeXSp(p + 6), n0, n1);
  IF (q < 0) OR ~MathEnvName(n0, n1) THEN RETURN -1 END;
  LOOP
    IF q >= B.len THEN RETURN -1 END;
    ch := B.C(q);
    IF ch = "%" THEN (* a comment, to the end of the line *)
      WHILE (q < B.len) & (B.C(q) # 0AX) DO INC(q) END
    ELSIF ch = "\" THEN
      IF B.Looking(q, "\end") & (TeXName(q) = q + 4) THEN
        e := EnvName(TeXSp(q + 4), m0, m1);
        IF (e >= 0) & Same() THEN RETURN e END
      END;
      INC(q, 2)
    ELSE INC(q)
    END
  END
END MathEnv;

(* An Org entity: \name with any final braces dropped, from p to e,
   found in texmath's MathML table, PdEntities with its six
   differences; added to l *)
PROCEDURE Entity(p, e: LONGINT; VAR l: A.Inlines): BOOLEAN;
  VAR name: ARRAY 40 OF CHAR; i, n, c1, c2: LONGINT;
BEGIN
  n := e;
  WHILE (n > p + 1) & ((B.C(n - 1) = "{") OR (B.C(n - 1) = "}")) DO DEC(n) END;
  INC(p);
  IF (n <= p) OR (n - p >= LEN(name)) THEN RETURN FALSE END;
  FOR i := p TO n - 1 DO name[i - p] := B.C(i) END;
  name[n - p] := 0X;
  IF ~PdEntities.Lookup(name, c1, c2) THEN RETURN FALSE END;
  IF name = "epsilon" THEN c1 := 3F5H; c2 := 0
  ELSIF name = "varepsilon" THEN c1 := 3B5H; c2 := 0
  ELSIF name = "DotDot" THEN c1 := 20H; c2 := 20DCH
  ELSIF (name = "TripleDot") OR (name = "tdot") THEN c1 := 20H; c2 := 20DBH
  ELSIF name = "DownBreve" THEN c1 := 20H; c2 := 311H
  END;
  IF ~M.entities THEN A.Append(l, A.NewStr(B.Rope(p - 1, e)))
  ELSE
    MI.AddChar(l, c1);
    IF c2 # 0 THEN MI.AddChar(l, c2) END
  END;
  RETURN TRUE
END Entity;

(* inlineLaTeX: an Org entity, a LaTeX command or an inline math
   environment, as tex: and e: say. A command ends as PdMdInline's
   raw TeX does (decision 57): what pandoc gives through texmath is a
   RawInline here. *)
PROCEDURE InlineLaTeX(VAR l: A.Inlines): BOOLEAN;
  VAR p, e, f, n: LONGINT;
BEGIN
  p := B.pos;
  IF (B.C(p) # "\") OR (p + 1 >= B.len) THEN RETURN FALSE END;
  n := TeXName(p);
  IF (n = p + 4) & B.Looking(p, "\end")
      OR (n = p + 4) & B.Looking(p, "\and") THEN
    RETURN FALSE
  ELSIF (n = p + 6) & B.Looking(p, "\begin") THEN
    e := MathEnv(p);
    IF e < 0 THEN RETURN FALSE END;
    f := e;
    WHILE B.Looking(f, "{}") DO INC(f, 2) END; (* finalbraces *)
    IF B.C(n) = "{" THEN (* \begin{: parseAsInlineLaTeX *)
      IF M.latex = M.TexExport THEN
        A.Append(l, A.NewRawInline(A.S("latex"), B.Rope(p, e)))
      ELSIF M.latex = M.TexVerbatim THEN A.Append(l, BText(p, f))
      END
    ELSIF M.latex = M.TexExport THEN
      A.Append(l, A.NewRawInline(A.S("latex"), B.Rope(p, f)))
    ELSIF M.latex = M.TexVerbatim THEN A.Append(l, A.NewStr(B.Rope(p, f)))
    END;
    B.pos := f;
    RETURN TRUE
  END;
  e := MI.RawTeXEnd(p);
  IF e < 0 THEN RETURN FALSE END;
  WHILE (e > p) & ((B.C(e - 1) = " ") OR (B.C(e - 1) = 09X)
      OR (B.C(e - 1) = 0AX) OR (B.C(e - 1) = 0DX)) DO
    DEC(e)
  END;
  IF Entity(p, e, l) THEN
  ELSIF M.latex = M.TexExport THEN
    IF n <= p + 1 THEN n := p + 2 END;
    IF n > e THEN n := e END;
    Unknown("Raw LaTeX command", B.Rope(p, n), p);
    A.Append(l, A.NewRawInline(A.S("latex"), B.Rope(p, e)))
  ELSIF M.latex = M.TexVerbatim THEN A.Append(l, A.NewStr(B.Rope(p, e)))
  END;
  B.pos := e;
  RETURN TRUE
END InlineLaTeX;

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
    IF (ch = "c") & Cite(l) THEN
    ELSIF (ch < 80X) & B.IsLetter(ch) & PlainLink(l) THEN
    ELSIF (ch = "s") & InlineCode(l) THEN
    ELSE Str(l)
    END
  ELSIF ch = " " THEN (* whitespace *)
    WHILE B.IsSpace(B.C(p)) DO INC(p) END;
    B.pos := p; Newline;
    A.Append(l, A.NewSimple(A.Space))
  ELSIF (ch = "\") & (Linebreak(l)
      OR RawMath("\(", "\)", A.InlineMath, l)
      OR RawMath("\[", "\]", A.DisplayMath, l) OR InlineLaTeX(l)) THEN
  ELSIF (ch = "$") & DollarMath(l) THEN
  ELSIF (ch = "[") & (Cite(l) OR Footnote(l) OR ExplicitLink(l) OR SelfLink(l)) THEN
  ELSIF (ch = "<") & (AngleLink(l) OR Anchor(l)) THEN
  ELSIF ch = 0AX THEN RETURN Endline(l)
  ELSIF ch = 0DX THEN RETURN FALSE
  ELSIF (ch = "@") & ExportSnippet(l) THEN
  ELSIF (ch = "{") & MacroCall(l) THEN
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
  fancyLists := FALSE; citations := TRUE;
  (* -\t ('"{ and U+200B; -\t\n .,:!?;'")}[ and U+200B *)
  Chars(defPre, "- ('{", TRUE, FALSE);
  Chars(defPost, "- .,:!?;')}[", TRUE, TRUE);
  Reset
END PdOrgInline.
