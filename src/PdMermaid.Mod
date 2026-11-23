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

  Walker = POINTER TO WalkerDesc;
  WalkerDesc = RECORD (A.WalkerDesc)
    form: INTEGER; (* Pic, Mp or Svg *)
    raw: Name; (* the raw blocks' format, for Pic and Mp *)
    font, size: Name; (* --font and --size, or "" for pomermaid's own *)
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
PROCEDURE Run(w: Walker; b: A.CodeBlk; VAR out: ARRAY OF CHAR): BOOLEAN;
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
  IF w.font # "" THEN R.Add(c, "--font"); R.Add(c, w.font) END;
  IF w.size # "" THEN R.Add(c, "--size"); R.Add(c, w.size) END;
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
   new line *)
PROCEDURE RawBlock(w: Walker; VAR out: ARRAY OF CHAR): A.Block;
  VAR t: PdIO.Text; len: LONGINT;
BEGIN
  PdIO.ReadFile(out, t, len);
  IF (len > 0) & (t[len - 1] = 0AX) THEN DEC(len) END;
  RETURN A.NewRawBlock(A.S(w.raw), Ropes.FromSubchars(t^, 0, len))
END RawBlock;

(* The paragraph of the image at path, with b's identifier and pairs, as
   the Python filter makes it *)
PROCEDURE ImagePara(b: A.CodeBlk; VAR path: ARRAY OF CHAR): A.Block;
  VAR attr: A.Attr;
BEGIN
  attr := A.NewAttr(b.attr.id); attr.attrs := b.attr.attrs;
  RETURN A.NewInlinesBlock(A.Para,
    A.NewLink(A.Image, attr, NIL, A.S(path), A.S("")))
END ImagePara;

(* b drawn as SVG, in mermaid-images, or b if it cannot be *)
PROCEDURE SvgBlock(w: Walker; b: A.CodeBlk): A.Block;
  VAR t: PdIO.Text; len: LONGINT; hex: ARRAY 41 OF CHAR;
    path, out: R.Path; c: R.Command; m: ARRAY R.PathLen + 100 OF CHAR;
BEGIN
  len := Ropes.Length(b.text);
  NEW(t, len + 1); Ropes.Blit(b.text, 0, t^, 0, len); t[len] := 0X;
  PdSha1.Hex(t^, len, hex);
  COPY(ImageDir, path); R.Append(path, "/"); R.Append(path, hex); R.Append(path, ".svg");
  IF PdIO.Exists(path) THEN RETURN ImagePara(b, path) END;
  IF ~Found(w) OR ~Run(w, b, out) THEN RETURN b END;
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
  VAR out: R.Path;
BEGIN
  IF (b.kind = A.CodeBlock) & A.HasClass(b(A.CodeBlk).attr, "mermaid") THEN
    IF w.form = Svg THEN RETURN SvgBlock(w, b(A.CodeBlk))
    ELSIF Found(w) & Run(w, b(A.CodeBlk), out) THEN RETURN RawBlock(w, out)
    END
  END;
  RETURN b
END Block;

(* Draws the mermaid code blocks of d with pomermaid, for the writer to
   (ms, mom, context, html, markdown and so on). *)
PROCEDURE Draw*(d: A.Doc; to: ARRAY OF CHAR);
  VAR w: Walker;
BEGIN
  NEW(w); w.checked := FALSE; w.found := FALSE; w.dir := "";
  w.font := ""; w.size := ""; COPY(to, w.raw);
  IF (to = "ms") OR (to = "mom") THEN w.form := Pic; Fonts(w, d, to)
  ELSIF to = "context" THEN w.form := Mp
  ELSE w.form := Svg
  END;
  A.WalkDoc(w, d);
  IF w.dir # "" THEN R.RemoveDir(w.dir) END
END Draw;

END PdMermaid.
