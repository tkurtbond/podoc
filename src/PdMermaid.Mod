MODULE PdMermaid;
(* PdMermaid: draws the document's mermaid code blocks with pomermaid
   (Phase 25, decisions 48 to 51), in place of
   pandoc-mermaid-selenium-filter. It runs as that filter would, given
   with --filter by that name or as pomermaid.

   pomermaid is a program of its own (~/Repos/Oberon/pomermaid), found
   in PATH and run once on each CodeBlock with the class mermaid:

   ms, mom   -t pic, as a raw block of the writer's format, measured in
             the document's font and size: the variables, or else the
             metadata, fontfamily and pointsize, as the templates use
             them (T and 10 for ms, T and 12.5 for mom, by default)
   context   -t mp, as a raw context block
   others    -t svg, written to mermaid-images/SHA1.svg, where SHA1 is
             the SHA-1 of the block's text, as the Python filter names
             its PNGs, unless that file is there already; the block
             becomes a paragraph of that image, as with the filter

   Each diagram's settings (decision 52) come from, first to last:

   - the block's attributes size, subgraphs and font;
   - mermaid.diagrams.ID in the metadata, a map, where ID is the
     block's identifier, with the fields size, subgraphs, width and
     font;
   - the variables mermaid-size, mermaid-subgraphs, mermaid-width and
     mermaid-font, or else those metadata fields;
   - the fields of the metadata map mermaid;
   - for ms and mom, the font and size above.

   size, in points, is pomermaid's --size; for context, the drawing is
   also set in that body font (\switchtobodyfont), which makes it
   smaller or larger. subgraphs, stack or side, is --subgraphs; width,
   a length with i, c or p, is --width; font, a groff font, is --font,
   for ms and mom only. The block's width is not pomermaid's: in HTML
   it is the image's, as with the filter. An SVG drawn with settings
   is named by the SHA-1 of its text and its settings.

   What pomermaid writes to standard error is passed on as warnings. A
   block pomermaid cannot draw stays a code block, with a warning; so
   does every block when pomermaid is not found. The writer's source
   for a PDF runs groff with -p when it holds a pic drawing (PdPdf). *)

IMPORT SYSTEM, Platform, Ropes, PdIO, R := PdRun, PdSha1, A := PdAst, T := PdTemplate,
  L := PdLayout, C := PdContext, PdShared;

CONST
  Pic = 0; Mp = 1; Svg = 2; (* what pomermaid draws *)
  Program = "pomermaid";
  ImageDir = "mermaid-images";

TYPE
  Rope = Ropes.Rope;
  Name = ARRAY 64 OF CHAR;

  Settings = RECORD (* a diagram's, "" for none *)
    font, size, subgraphs, width: Name
  END;

  Walker = POINTER TO WalkerDesc;
  WalkerDesc = RECORD (A.WalkerDesc)
    form: INTEGER; (* Pic, Mp or Svg *)
    raw: Name; (* the raw blocks' format, for Pic and Mp *)
    doc: A.Doc;
    font, size: Name; (* the document's --font and --size, for Pic; or
      "" for pomermaid's own *)
    checked, found: BOOLEAN; (* whether pomermaid was looked for, and
      found *)
    dir: R.Path (* the temporary directory, "" until it is made *)
  END;

(* Settings *)

(* Sets s to the variable key (-V) if it is text, or else to the
   metadata field key as plain text; to "" if there is neither. *)
PROCEDURE Setting(d: A.Doc; key: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
  VAR v: T.Value; m: A.MetaValue; r: Rope;
BEGIN
  r := NIL;
  v := T.Get(C.variables, key);
  IF (v # NIL) & (v.kind = T.SimpleV) THEN r := L.Render(v.doc, 0)
  ELSE
    m := A.GetMeta(d.meta, key);
    IF m # NIL THEN
      WITH
        m: A.MetaStringV DO r := m.s
      | m: A.MetaInlinesV DO r := PdShared.Stringify(m.inlines)
      ELSE
      END
    END
  END;
  r := Ropes.Trim(r);
  IF r = NIL THEN s[0] := 0X ELSE Ropes.ToString(r, s) END
END Setting;

(* Whether s is a groff family name, letters and digits only *)
PROCEDURE IsFamily(VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (s[i] >= "0") & (s[i] <= "9") OR (CAP(s[i]) >= "A") & (CAP(s[i]) <= "Z") DO INC(i) END;
  RETURN (i > 0) & (s[i] = 0X)
END IsFamily;

(* Takes a unit "p" (groff's points) or "pt" off the end of s, and
   returns whether s is then a number of points, as pomermaid's --size
   takes it: digits, with a decimal part or none. *)
PROCEDURE Points(VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: INTEGER;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  IF (i >= 2) & (s[i - 2] = "p") & (s[i - 1] = "t") THEN DEC(i, 2); s[i] := 0X
  ELSIF (i >= 1) & (s[i - 1] = "p") THEN DEC(i); s[i] := 0X
  END;
  j := 0; WHILE (s[j] >= "0") & (s[j] <= "9") DO INC(j) END;
  IF j = 0 THEN RETURN FALSE END;
  IF s[j] = "." THEN
    INC(j); i := j;
    WHILE (s[j] >= "0") & (s[j] <= "9") DO INC(j) END;
    IF j = i THEN RETURN FALSE END
  END;
  RETURN s[j] = 0X
END Points;

(* Whether s is a length pomermaid's --width takes: digits, with a
   decimal part or none, and a unit i, c or p or none *)
PROCEDURE IsLength(VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: INTEGER;
BEGIN
  j := 0; WHILE (s[j] >= "0") & (s[j] <= "9") DO INC(j) END;
  IF j = 0 THEN RETURN FALSE END;
  IF s[j] = "." THEN
    INC(j); i := j;
    WHILE (s[j] >= "0") & (s[j] <= "9") DO INC(j) END;
    IF j = i THEN RETURN FALSE END
  END;
  IF (s[j] = "i") OR (s[j] = "c") OR (s[j] = "p") THEN INC(j) END;
  RETURN s[j] = 0X
END IsLength;

(* Sets s to m as plain text, if it is a string or inlines, and returns
   TRUE; or returns FALSE. *)
PROCEDURE MetaText(m: A.MetaValue; VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR r: Rope;
BEGIN
  r := NIL;
  IF m # NIL THEN
    WITH
      m: A.MetaStringV DO r := m.s
    | m: A.MetaInlinesV DO r := PdShared.Stringify(m.inlines)
    ELSE RETURN FALSE
    END
  ELSE RETURN FALSE
  END;
  r := Ropes.Trim(r);
  IF r = NIL THEN s[0] := 0X ELSE Ropes.ToString(r, s) END;
  RETURN TRUE
END MetaText;

(* The field key of m, if m is a map; or NIL *)
PROCEDURE Field(m: A.MetaValue; key: ARRAY OF CHAR): A.MetaValue;
BEGIN
  IF (m # NIL) & (m IS A.MetaMapV) THEN RETURN A.GetMeta(m(A.MetaMapV), key) END;
  RETURN NIL
END Field;

(* Sets s to b's setting key (size, subgraphs, width or font), as the
   module's comment says, from the first of its places from level on
   (0, the block's attributes, to 3, the map mermaid) that has it, and
   sets level to the next place; or s to "" *)
PROCEDURE Lookup(w: Walker; b: A.CodeBlk; key: ARRAY OF CHAR; VAR level: INTEGER;
    VAR s: ARRAY OF CHAR);
  VAR r: Rope; found: BOOLEAN; mermaid: A.MetaValue; id: Name; v: ARRAY 32 OF CHAR;
BEGIN
  s[0] := 0X;
  mermaid := A.GetMeta(w.doc.meta, "mermaid");
  WHILE level < 4 DO
    INC(level);
    CASE level - 1 OF
      0:
        IF key # "width" THEN
          r := A.GetKeyVal(b.attr, key, found);
          IF found THEN
            r := Ropes.Trim(r);
            IF r # NIL THEN Ropes.ToString(r, s) END;
            IF s # "" THEN RETURN END
          END
        END
    | 1:
        IF (b.attr # NIL) & ~Ropes.IsEmpty(b.attr.id)
            & (Ropes.Length(b.attr.id) < LEN(id)) THEN
          Ropes.ToString(b.attr.id, id);
          IF MetaText(Field(Field(Field(mermaid, "diagrams"), id), key), s)
              & (s # "") THEN RETURN END
        END
    | 2:
        v := "mermaid-"; R.Append(v, key);
        Setting(w.doc, v, s);
        IF s # "" THEN RETURN END
    | 3:
        IF MetaText(Field(mermaid, key), s) & (s # "") THEN RETURN END
    END
  END;
  s[0] := 0X
END Lookup;

(* Warns that podoc ignores the mermaid setting key, s, which is not
   what what says *)
PROCEDURE Ignore(key, s, what: ARRAY OF CHAR);
  VAR m: ARRAY 300 OF CHAR;
BEGIN
  m := "podoc ignores mermaid "; R.Append(m, key); R.Append(m, " '");
  R.Append(m, s); R.Append(m, "': it is not "); R.Append(m, what);
  PdIO.Warn(m)
END Ignore;

(* Whether s is a good value for the setting key *)
PROCEDURE Good(key: ARRAY OF CHAR; VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR t: Name;
BEGIN
  IF key = "size" THEN COPY(s, t); RETURN Points(t)
  ELSIF key = "subgraphs" THEN RETURN (s = "stack") OR (s = "side")
  ELSIF key = "width" THEN RETURN IsLength(s)
  ELSE RETURN IsFamily(s)
  END
END Good;

(* Sets s to b's setting key, the first good one; warns of each one
   that is not, and takes the next *)
PROCEDURE Get(w: Walker; b: A.CodeBlk; key: ARRAY OF CHAR; VAR s: ARRAY OF CHAR);
  VAR level: INTEGER;
BEGIN
  level := 0;
  LOOP
    Lookup(w, b, key, level, s);
    IF (s = "") OR Good(key, s) THEN EXIT END;
    IF key = "size" THEN Ignore(key, s, "a number of points")
    ELSIF key = "subgraphs" THEN Ignore(key, s, "stack or side")
    ELSIF key = "width" THEN Ignore(key, s, "a length (a number, with i, c or p)")
    ELSE Ignore(key, s, "a groff font")
    END
  END;
  IF key = "size" THEN IF Points(s) THEN END END (* the unit off *)
END Get;

(* Sets o to b's settings, checked, for w's form *)
PROCEDURE GetSettings(w: Walker; b: A.CodeBlk; VAR o: Settings);
BEGIN
  Get(w, b, "size", o.size);
  IF (o.size = "") & (w.form = Pic) THEN o.size := w.size END;
  Get(w, b, "subgraphs", o.subgraphs);
  Get(w, b, "width", o.width);
  o.font := "";
  IF w.form = Pic THEN
    Get(w, b, "font", o.font);
    IF o.font = "" THEN o.font := w.font END
  END
END GetSettings;

(* Sets s to the settings o as pomermaid's options, "" for none *)
PROCEDURE Options(VAR o: Settings; VAR s: ARRAY OF CHAR);
BEGIN
  s[0] := 0X;
  IF o.font # "" THEN R.Append(s, " --font "); R.Append(s, o.font) END;
  IF o.size # "" THEN R.Append(s, " --size "); R.Append(s, o.size) END;
  IF o.subgraphs # "" THEN R.Append(s, " --subgraphs "); R.Append(s, o.subgraphs) END;
  IF o.width # "" THEN R.Append(s, " --width "); R.Append(s, o.width) END
END Options;

(* Sets w's font and size from d's fontfamily and pointsize, for pic in
   the writer to (ms or mom), with a warning for one podoc cannot
   use. *)
PROCEDURE Fonts(w: Walker; d: A.Doc; to: ARRAY OF CHAR);
  VAR s: Name; m: ARRAY 200 OF CHAR;
BEGIN
  Setting(d, "fontfamily", s);
  IF s = "" THEN w.font := "TR"
  ELSIF IsFamily(s) THEN COPY(s, w.font); R.Append(w.font, "R")
  ELSE
    w.font := "TR";
    m := "podoc draws mermaid diagrams in TR: fontfamily '"; R.Append(m, s);
    R.Append(m, "' is not a groff family"); PdIO.Warn(m)
  END;
  Setting(d, "pointsize", s);
  IF to = "mom" THEN w.size := "12.5" ELSE w.size := "10" END;
  IF s = "" THEN
  ELSIF Points(s) THEN COPY(s, w.size)
  ELSE
    m := "podoc draws mermaid diagrams at "; R.Append(m, w.size);
    R.Append(m, " points: pointsize '"); Setting(d, "pointsize", s); R.Append(m, s);
    R.Append(m, "' is not a number of points"); PdIO.Warn(m)
  END
END Fonts;

(* Running pomermaid *)

(* Passes on the lines of the file err as warnings *)
PROCEDURE PassOn(VAR err: ARRAY OF CHAR);
  VAR t: PdIO.Text; len, i, j: LONGINT; line: ARRAY 1024 OF CHAR;
BEGIN
  IF ~PdIO.Exists(err) THEN RETURN END;
  PdIO.ReadFile(err, t, len);
  i := 0;
  WHILE i < len DO
    j := 0;
    WHILE (i < len) & (t[i] # 0AX) DO
      IF j < LEN(line) - 1 THEN line[j] := t[i]; INC(j) END;
      INC(i)
    END;
    line[j] := 0X; INC(i);
    IF j > 0 THEN PdIO.Warn(line) END
  END
END PassOn;

(* Whether pomermaid can be run, looking for it the first time; warns
   once if it cannot *)
PROCEDURE Found(w: Walker): BOOLEAN;
BEGIN
  IF ~w.checked THEN
    w.checked := TRUE; w.found := R.Found(Program);
    IF ~w.found THEN
      PdIO.Warn("Could not convert mermaid diagrams: check that pomermaid is in path.")
    END
  END;
  RETURN w.found
END Found;

(* Writes r and a new line to the file name; returns whether it could.
   (Not through PdIO, whose output may be podoc's own by now.) *)
PROCEDURE WriteFile(VAR name: ARRAY OF CHAR; r: Rope): BOOLEAN;
  VAR h: Platform.FileHandle; t: PdIO.Text; len: LONGINT; e, e2: Platform.ErrorCode;
BEGIN
  len := Ropes.Length(r);
  NEW(t, len + 1); Ropes.Blit(r, 0, t^, 0, len); t[len] := 0AX;
  IF Platform.New(name, h) # 0 THEN RETURN FALSE END;
  e := Platform.Write(h, SYSTEM.ADR(t[0]), len + 1);
  e2 := Platform.Close(h);
  RETURN (e = 0) & (e2 = 0)
END WriteFile;

(* Adds the shell's operator op, then the path p in quotes, to c *)
PROCEDURE AddRedirect(c: R.Command; op, p: ARRAY OF CHAR);
BEGIN
  R.AddText(c, op); R.Add(c, p)
END AddRedirect;

(* Runs pomermaid on the text of b into the file out of w's temporary
   directory, which it makes the first time; returns whether it drew
   it. *)
PROCEDURE Run(w: Walker; b: A.CodeBlk; VAR o: Settings; VAR out: ARRAY OF CHAR): BOOLEAN;
  VAR c: R.Command; in, err: R.Path; ok: BOOLEAN; st: INTEGER;
    m: ARRAY 200 OF CHAR;
BEGIN
  IF w.dir = "" THEN
    R.MakeTempDir(w.dir, ok);
    IF ~ok THEN
      w.dir := "";
      PdIO.Warn("Could not convert mermaid diagram: no temporary directory");
      RETURN FALSE
    END
  END;
  COPY(w.dir, in); R.Append(in, "/diagram.mmd");
  COPY(w.dir, err); R.Append(err, "/errors");
  COPY(w.dir, out); R.Append(out, "/diagram.out");
  IF ~WriteFile(in, b.text) THEN
    PdIO.Warn("Could not convert mermaid diagram: cannot write it for pomermaid");
    RETURN FALSE
  END;
  c := R.New(); R.Add(c, Program);
  R.Add(c, "-t");
  CASE w.form OF
    Pic: R.Add(c, "pic")
  | Mp: R.Add(c, "mp")
  | Svg: R.Add(c, "svg")
  END;
  IF o.font # "" THEN R.Add(c, "--font"); R.Add(c, o.font) END;
  IF o.size # "" THEN R.Add(c, "--size"); R.Add(c, o.size) END;
  IF o.subgraphs # "" THEN R.Add(c, "--subgraphs"); R.Add(c, o.subgraphs) END;
  IF o.width # "" THEN R.Add(c, "--width"); R.Add(c, o.width) END;
  R.Add(c, "-o"); R.Add(c, out);
  AddRedirect(c, " <", in); AddRedirect(c, " 2>", err);
  st := R.Run(c);
  PassOn(err);
  IF st # 0 THEN
    m := "Could not convert mermaid diagram: pomermaid ended with status ";
    R.AppendInt(m, st); R.Append(m, "; it stays a code block");
    PdIO.Warn(m)
  END;
  RETURN st = 0
END Run;

(* The blocks *)

(* The raw block of w's format holding the file out, without its last
   new line; for Mp with a size, set in that body font *)
PROCEDURE RawBlock(w: Walker; VAR o: Settings; VAR out: ARRAY OF CHAR): A.Block;
  VAR t: PdIO.Text; len: LONGINT; r: Rope; s: ARRAY 100 OF CHAR;
BEGIN
  PdIO.ReadFile(out, t, len);
  IF (len > 0) & (t[len - 1] = 0AX) THEN DEC(len) END;
  r := Ropes.FromSubchars(t^, 0, len);
  IF (w.form = Mp) & (o.size # "") THEN
    s := "\start\switchtobodyfont["; R.Append(s, o.size); R.Append(s, "pt]");
    r := Ropes.Cat(Ropes.AppendChar(A.S(s), 0AX), r);
    r := Ropes.Cat(Ropes.AppendChar(r, 0AX), A.S("\par\stop"))
  END;
  RETURN A.NewRawBlock(A.S(w.raw), r)
END RawBlock;

(* The paragraph of the image at path, with b's identifier and pairs, as
   the Python filter makes it, but for podoc's own: size, subgraphs and
   font *)
PROCEDURE ImagePara(b: A.CodeBlk; VAR path: ARRAY OF CHAR): A.Block;
  VAR attr: A.Attr; p: A.KeyVal;
BEGIN
  attr := A.NewAttr(b.attr.id); p := b.attr.attrs;
  WHILE p # NIL DO
    IF ~Ropes.EqualString(p.key, "size") & ~Ropes.EqualString(p.key, "subgraphs")
        & ~Ropes.EqualString(p.key, "font") THEN
      A.AddKeyVal(attr, p.key, p.value)
    END;
    p := p.next
  END;
  RETURN A.NewInlinesBlock(A.Para,
    A.NewLink(A.Image, attr, NIL, A.S(path), A.S("")))
END ImagePara;

(* b drawn as SVG, in mermaid-images, or b if it cannot be *)
PROCEDURE SvgBlock(w: Walker; b: A.CodeBlk; VAR o: Settings): A.Block;
  VAR t: PdIO.Text; len: LONGINT; hex: ARRAY 41 OF CHAR; r: Rope;
    path, out: R.Path; c: R.Command; m: ARRAY R.PathLen + 100 OF CHAR;
    opts: ARRAY 300 OF CHAR;
BEGIN
  r := b.text; Options(o, opts);
  IF opts # "" THEN (* the settings are part of the name *)
    r := Ropes.Cat(Ropes.AppendChar(r, 0AX), A.S(opts))
  END;
  len := Ropes.Length(r);
  NEW(t, len + 1); Ropes.Blit(r, 0, t^, 0, len); t[len] := 0X;
  PdSha1.Hex(t^, len, hex);
  COPY(ImageDir, path); R.Append(path, "/"); R.Append(path, hex); R.Append(path, ".svg");
  IF PdIO.Exists(path) THEN RETURN ImagePara(b, path) END;
  IF ~Found(w) OR ~Run(w, b, o, out) THEN RETURN b END;
  c := R.New(); R.AddText(c, "mkdir -p"); R.Add(c, ImageDir);
  AddRedirect(c, " 2>", "/dev/null");
  IF (R.Run(c) # 0) OR ~R.Copy(out, path) THEN
    m := "Could not convert mermaid diagram: cannot write "; R.Append(m, path);
    PdIO.Warn(m);
    RETURN b
  END;
  RETURN ImagePara(b, path)
END SvgBlock;

PROCEDURE (w: Walker) Block*(b: A.Block): A.Block;
  VAR out: R.Path; o: Settings;
BEGIN
  IF (b.kind = A.CodeBlock) & A.HasClass(b(A.CodeBlk).attr, "mermaid") THEN
    GetSettings(w, b(A.CodeBlk), o);
    IF w.form = Svg THEN RETURN SvgBlock(w, b(A.CodeBlk), o)
    ELSIF Found(w) & Run(w, b(A.CodeBlk), o, out) THEN RETURN RawBlock(w, o, out)
    END
  END;
  RETURN b
END Block;

(* Draws the mermaid code blocks of d with pomermaid, for the writer to
   (ms, mom, context, html, markdown and so on). *)
PROCEDURE Draw*(d: A.Doc; to: ARRAY OF CHAR);
  VAR w: Walker;
BEGIN
  NEW(w); w.doc := d; w.checked := FALSE; w.found := FALSE; w.dir := "";
  w.font := ""; w.size := ""; COPY(to, w.raw);
  IF (to = "ms") OR (to = "mom") THEN w.form := Pic; Fonts(w, d, to)
  ELSIF to = "context" THEN w.form := Mp
  ELSE w.form := Svg
  END;
  A.WalkDoc(w, d);
  IF w.dir # "" THEN R.RemoveDir(w.dir) END
END Draw;

END PdMermaid.
