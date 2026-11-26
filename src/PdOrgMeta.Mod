MODULE PdOrgMeta;

(* The Org reader's export settings, as pandoc's
   Readers/Org/ExportSettings.hs reads them: pandoc's defaults, and
   #+OPTIONS read into them where it appears. Each setting takes
   effect with the construct it governs, in the module that reads
   that construct.

   The text read is PdMdBase's. *)

IMPORT PdIO, A := PdAst, B := PdMdBase;

CONST
  (* archived: ARCHIVE trees (arch:) *)
  ArchNone* = 0; ArchHeadline* = 1; ArchExport* = 2;
  (* subSup: subscripts and superscripts (^:) *)
  SubSupNone* = 0; SubSupBraced* = 1; SubSupAll* = 2;
  (* latex: LaTeX (tex:) *)
  TexIgnore* = 0; TexVerbatim* = 1; TexExport* = 2;

VAR
  archived*: INTEGER;
  (* drawers (d:): pandoc's Left names, all drawers but those in
     drawers, if drawersExcept; its Right names, only those, if not *)
  drawersExcept*: BOOLEAN;
  drawers*: A.StrList;
  emphasis*: BOOLEAN; (* *: *)
  headlineLevels*: LONGINT; (* H: *)
  preserveBreaks*: BOOLEAN; (* \n: *)
  smartQuotes*: BOOLEAN; (* ': *)
  specialStrings*: BOOLEAN; (* -: *)
  subSup*: INTEGER;
  withAuthor*, withCreator*, withEmail*: BOOLEAN; (* author:, creator:, email: *)
  entities*: BOOLEAN; (* e: *)
  footnotes*: BOOLEAN; (* f: *)
  latex*: INTEGER;
  planning*: BOOLEAN; (* p: *)
  tags*: BOOLEAN; (* tags: *)
  tables*: BOOLEAN; (* |: *)
  todo*: BOOLEAN; (* todo: *)

(* Sets pandoc's defaults (defaultExportSettings), with smart quotes on
   if smart or smartQuotes, and special strings if smart or special:
   optionsToParserState. *)
PROCEDURE Reset*(smart, quotes, special: BOOLEAN);
BEGIN
  archived := ArchHeadline;
  drawersExcept := TRUE; NEW(drawers); drawers.s := A.S("LOGBOOK"); drawers.next := NIL;
  emphasis := TRUE; headlineLevels := 3; preserveBreaks := FALSE;
  smartQuotes := smart OR quotes; specialStrings := smart OR special;
  subSup := SubSupAll;
  withAuthor := TRUE; withCreator := TRUE; withEmail := TRUE;
  entities := TRUE; footnotes := TRUE; latex := TexExport;
  planning := FALSE; tags := TRUE; tables := TRUE; todo := TRUE
END Reset;

(* Characters *)

(* Haskell's isSpace, for ASCII *)
PROCEDURE IsWhite(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch >= 09X) & (ch <= 0DX)
END IsWhite;

(* nonspaceChar *)
PROCEDURE NonSpace(p: LONGINT): BOOLEAN;
BEGIN
  RETURN (p < B.len) & ~IsWhite(B.t[p])
END NonSpace;

(* Whether key and a colon are at p: where the value starts, or -1. *)
PROCEDURE Key(p: LONGINT; key: ARRAY OF CHAR): LONGINT;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE key[i] # 0X DO
    IF B.C(p + i) # key[i] THEN RETURN -1 END;
    INC(i)
  END;
  IF B.C(p + i) # ":" THEN RETURN -1 END;
  RETURN p + i + 1
END Key;

(* Values *)

(* elispBoolean: one or more non-space characters, FALSE if nil, {} or
   () in any case. Where it ends, or -1. *)
PROCEDURE ElispBoolean(p: LONGINT; VAR val: BOOLEAN): LONGINT;
  VAR q, n: LONGINT; s: ARRAY 4 OF CHAR;
BEGIN
  IF ~NonSpace(p) THEN RETURN -1 END;
  q := p;
  WHILE NonSpace(q) DO INC(q) END;
  n := q - p; val := TRUE;
  IF (n = 2) OR (n = 3) THEN
    s[0] := B.Lower(B.t[p]); s[1] := B.Lower(B.t[p + 1]); s[2] := 0X;
    IF n = 3 THEN s[2] := B.Lower(B.t[p + 2]); s[3] := 0X END;
    val := ~((s = "nil") OR (s = "{}") OR (s = "()"))
  END;
  RETURN q
END ElispBoolean;

(* optionString s: s followed by a new line or a space. Where s ends,
   or -1. *)
PROCEDURE OptionString(p: LONGINT; s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT; ch: CHAR;
BEGIN
  IF ~B.Looking(p, s) THEN RETURN -1 END;
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  ch := B.C(p + n);
  IF (ch = 0AX) OR B.IsSpace(ch) THEN RETURN p + n END;
  RETURN -1
END OptionString;

(* Parsec's spaces: any white space, new lines too *)
PROCEDURE Spaces(p: LONGINT): LONGINT;
BEGIN
  WHILE (p < B.len) & IsWhite(B.t[p]) DO INC(p) END;
  RETURN p
END Spaces;

(* elispText: a double-quoted string of letters and digits, added to
   l. Where it ends, or -1. *)
PROCEDURE ElispText(p: LONGINT; VAR l, last: A.StrList): LONGINT;
  VAR q: LONGINT; s: A.StrList;
BEGIN
  IF B.C(p) # 22X THEN RETURN -1 END;
  q := p + 1;
  WHILE (q < B.len) & (B.t[q] # 22X) & (B.IsAlnum(B.t[q]) OR (B.t[q] >= 80X)) DO
    INC(q)
  END;
  IF B.C(q) # 22X THEN RETURN -1 END;
  NEW(s); s.s := B.Rope(p + 1, q); s.next := NIL;
  IF l = NIL THEN l := s ELSE last.next := s END;
  last := s;
  RETURN q + 1
END ElispText;

(* sepBy elispText spaces, then a closing parenthesis. Where it ends,
   or -1. *)
PROCEDURE TextList(p: LONGINT; VAR l: A.StrList): LONGINT;
  VAR q: LONGINT; last: A.StrList;
BEGIN
  l := NIL; last := NIL;
  q := ElispText(p, l, last);
  IF q >= 0 THEN
    p := q;
    LOOP
      q := Spaces(p);
      IF B.C(q) = 22X THEN
        q := ElispText(q, l, last);
        IF q < 0 THEN RETURN -1 END;
        p := q
      ELSIF q > p THEN
        RETURN -1 (* spaces consumed, and no text after them *)
      ELSE
        EXIT
      END
    END
  END;
  IF B.C(p) # ")" THEN RETURN -1 END;
  RETURN p + 1
END TextList;

(* The settings *)

(* booleanSetting *)
PROCEDURE Bool(p: LONGINT; key: ARRAY OF CHAR; VAR val: BOOLEAN): LONGINT;
  VAR q: LONGINT; v: BOOLEAN;
BEGIN
  q := Key(p, key);
  IF q >= 0 THEN q := ElispBoolean(q, v) END;
  IF q >= 0 THEN val := v END;
  RETURN q
END Bool;

(* ignoredSetting *)
PROCEDURE Ignored(p: LONGINT; key: ARRAY OF CHAR): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := Key(p, key);
  IF (q >= 0) & NonSpace(q) THEN
    WHILE NonSpace(q) DO INC(q) END;
    RETURN q
  END;
  RETURN -1
END Ignored;

(* subSupSetting "^" *)
PROCEDURE SubSupSetting(p: LONGINT): LONGINT;
  VAR q, r: LONGINT; v: BOOLEAN;
BEGIN
  q := Key(p, "^");
  IF q < 0 THEN RETURN -1 END;
  r := OptionString(q, "{}");
  IF r >= 0 THEN subSup := SubSupBraced; RETURN r END;
  r := ElispBoolean(q, v);
  IF r >= 0 THEN
    IF v THEN subSup := SubSupAll ELSE subSup := SubSupNone END
  END;
  RETURN r
END SubSupSetting;

(* archivedTreeSetting "arch" *)
PROCEDURE ArchSetting(p: LONGINT): LONGINT;
  VAR q, r: LONGINT; v: BOOLEAN;
BEGIN
  q := Key(p, "arch");
  IF q < 0 THEN RETURN -1 END;
  r := OptionString(q, "headline");
  IF r >= 0 THEN archived := ArchHeadline; RETURN r END;
  r := ElispBoolean(q, v);
  IF r >= 0 THEN
    IF v THEN archived := ArchExport ELSE archived := ArchNone END
  END;
  RETURN r
END ArchSetting;

(* complementableListSetting "d" *)
PROCEDURE DrawerSetting(p: LONGINT): LONGINT;
  VAR q, r: LONGINT; v: BOOLEAN; l: A.StrList;
BEGIN
  q := Key(p, "d");
  IF q < 0 THEN RETURN -1 END;
  IF B.Looking(q, "(not ") THEN
    r := TextList(q + 5, l);
    IF r >= 0 THEN drawersExcept := TRUE; drawers := l; RETURN r END
  END;
  IF B.C(q) = "(" THEN
    r := TextList(q + 1, l);
    IF r >= 0 THEN drawersExcept := FALSE; drawers := l; RETURN r END
  END;
  r := ElispBoolean(q, v);
  IF r >= 0 THEN drawersExcept := v; drawers := NIL END;
  RETURN r
END DrawerSetting;

(* integerSetting "H": digits, read as reads reads them *)
PROCEDURE IntSetting(p: LONGINT): LONGINT;
  VAR q: LONGINT; n: LONGINT;
BEGIN
  q := Key(p, "H");
  IF (q < 0) OR ~B.IsDigit(B.C(q)) THEN RETURN -1 END;
  n := 0;
  WHILE B.IsDigit(B.C(q)) DO
    IF n < 100000 THEN n := n * 10 + ORD(B.t[q]) - ORD("0") END;
    INC(q)
  END;
  headlineLevels := n;
  RETURN q
END IntSetting;

(* texSetting "tex" *)
PROCEDURE TexSetting(p: LONGINT): LONGINT;
  VAR q, r: LONGINT; v: BOOLEAN;
BEGIN
  q := Key(p, "tex");
  IF q < 0 THEN RETURN -1 END;
  r := OptionString(q, "verbatim");
  IF r >= 0 THEN latex := TexVerbatim; RETURN r END;
  r := ElispBoolean(q, v);
  IF r >= 0 THEN
    IF v THEN latex := TexExport ELSE latex := TexIgnore END
  END;
  RETURN r
END TexSetting;

(* ignoreAndWarn: anything up to a space or a new line, with pandoc's
   warning *)
PROCEDURE IgnoreAndWarn(p: LONGINT): LONGINT;
  VAR q: LONGINT; b: B.Buf; ch: CHAR;
BEGIN
  q := p;
  LOOP
    ch := B.C(q);
    IF (q >= B.len) OR (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX) THEN
      EXIT
    END;
    INC(q)
  END;
  IF q = p THEN RETURN -1 END;
  B.InitBuf(b);
  B.PutString(b, "Ignoring unknown Org export option: ");
  B.Put(b, p, q); B.PutChar(b, 0X);
  PdIO.Warn(b.t^);
  RETURN q
END IgnoreAndWarn;

(* exportSetting: one setting at p. Where it ends, or -1. *)
PROCEDURE Setting(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  q := SubSupSetting(p);
  IF q < 0 THEN q := Bool(p, "'", smartQuotes) END;
  IF q < 0 THEN q := Bool(p, "*", emphasis) END;
  IF q < 0 THEN q := Bool(p, "-", specialStrings) END;
  IF q < 0 THEN q := Ignored(p, ":") END;
  IF q < 0 THEN q := Ignored(p, "<") END;
  IF q < 0 THEN q := Bool(p, "\n", preserveBreaks) END;
  IF q < 0 THEN q := ArchSetting(p) END;
  IF q < 0 THEN q := Bool(p, "author", withAuthor) END;
  IF q < 0 THEN q := Ignored(p, "c") END;
  IF q < 0 THEN q := Bool(p, "creator", withCreator) END;
  IF q < 0 THEN q := DrawerSetting(p) END;
  IF q < 0 THEN q := Ignored(p, "date") END;
  IF q < 0 THEN q := Bool(p, "e", entities) END;
  IF q < 0 THEN q := Bool(p, "email", withEmail) END;
  IF q < 0 THEN q := Bool(p, "f", footnotes) END;
  IF q < 0 THEN q := IntSetting(p) END;
  IF q < 0 THEN q := Ignored(p, "inline") END;
  IF q < 0 THEN q := Ignored(p, "num") END;
  IF q < 0 THEN q := Bool(p, "p", planning) END;
  IF q < 0 THEN q := Ignored(p, "pri") END;
  IF q < 0 THEN q := Ignored(p, "prop") END;
  IF q < 0 THEN q := Ignored(p, "stat") END;
  IF q < 0 THEN q := Bool(p, "tags", tags) END;
  IF q < 0 THEN q := Ignored(p, "tasks") END;
  IF q < 0 THEN q := TexSetting(p) END;
  IF q < 0 THEN q := Ignored(p, "timestamp") END;
  IF q < 0 THEN q := Ignored(p, "title") END;
  IF q < 0 THEN q := Ignored(p, "toc") END;
  IF q < 0 THEN q := Bool(p, "todo", todo) END;
  IF q < 0 THEN q := Bool(p, "|", tables) END;
  IF q < 0 THEN q := IgnoreAndWarn(p) END;
  RETURN q
END Setting;

(* exportSettings: the settings of an #+OPTIONS line, from p, after
   its keyword, separated by spaces. Returns where they end: the line's
   new line, or past it where a list of drawers went on to the next
   line, as pandoc's does. *)
PROCEDURE Options*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  LOOP
    q := Setting(p);
    IF q < 0 THEN EXIT END;
    p := B.SkipSpaces(q)
  END;
  RETURN p
END Options;

BEGIN
  Reset(FALSE, FALSE, TRUE)
END PdOrgMeta.
