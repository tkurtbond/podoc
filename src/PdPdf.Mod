MODULE PdPdf;
(* PdPdf: PDF output, as pandoc 3.10's makePDF (Text.Pandoc.PDF) makes
   it with pdfroff, groff or context.

   Prepare makes a temporary directory, copies the document's local
   images into it and points the images at the copies (fillMediaBag and
   extractMedia); for ConTeXt it also converts SVG images to PDF with
   rsvg-convert (convertImages). The writer then writes its source into
   the directory, at the path Source gives, and Make runs the engine on
   it: pdfroff and groff in the working directory, the source on their
   standard input and the PDF from their standard output; context in
   the temporary directory, on input.tex, which makes input.pdf. The
   PDF is copied to the output, and the directory is removed. *)

IMPORT Err, Ropes, A := PdAst, T := PdTemplate, L := PdLayout,
  C := PdContext, O := PdOptions, PdIO, R := PdRun;

TYPE
  Rope = Ropes.Rope;
  Path = R.Path;

  (* an image already handled: its url, and what it became (url NIL if
     it could not be read) *)
  Seen = POINTER TO SeenDesc;
  SeenDesc = RECORD
    src: Rope;
    url: Rope;
    next: Seen
  END;

  Walker = POINTER TO WalkerDesc;
  WalkerDesc = RECORD (A.WalkerDesc) END;

VAR
  tmp: Path; (* the temporary directory, "" if there is none *)
  tex: BOOLEAN; (* whether the engine is context *)
  seen: Seen;
  images: LONGINT; (* the number of the next image copied *)

(* Messages *)

(* Writes the bytes t[0 .. len-1] to standard error. *)
PROCEDURE ErrText(t: PdIO.Text; len: LONGINT);
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE i < len DO Err.Char(t[i]); INC(i) END;
  Err.Flush
END ErrText;

(* Removes the temporary directory and ends the program with the exit
   status code. *)
PROCEDURE Quit(code: INTEGER);
BEGIN
  IF tmp # "" THEN R.RemoveDir(tmp); tmp := "" END;
  PdIO.Exit(code)
END Quit;

(* Ends the program, as pandoc does when the engine prog is not
   there. *)
PROCEDURE NotFound(prog: ARRAY OF CHAR);
  VAR m: ARRAY 2 * R.PathLen + 100 OF CHAR;
BEGIN
  m := "'"; R.Append(m, prog);
  R.Append(m, "' not found. Please select a different --pdf-engine or install '");
  R.Append(m, prog); R.Append(m, "'");
  PdIO.Message(m);
  Quit(PdIO.PDFProgramNotFound)
END NotFound;

(* Ends the program with "Error producing PDF." and the bytes
   t[0 .. len-1], as pandoc does when the engine fails. *)
PROCEDURE Failed(t: PdIO.Text; len: LONGINT);
BEGIN
  PdIO.Message("Error producing PDF.");
  ErrText(t, len); Err.Ln; Err.Flush;
  Quit(PdIO.PDFError)
END Failed;

(* Images *)

(* Whether url has a scheme (http:, data:, file: and the like) *)
PROCEDURE HasScheme(VAR url: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT; ch: CHAR;
BEGIN
  ch := CAP(url[0]);
  IF (ch < "A") OR (ch > "Z") THEN RETURN FALSE END;
  i := 1;
  LOOP
    ch := CAP(url[i]);
    IF ch = ":" THEN RETURN i > 1 (* not a DOS drive letter *)
    ELSIF ~(((ch >= "A") & (ch <= "Z")) OR ((ch >= "0") & (ch <= "9"))
            OR (ch = "+") OR (ch = "-") OR (ch = ".")) THEN
      RETURN FALSE
    END;
    INC(i)
  END
END HasScheme;

(* Sets ext to the extension of the last part of the path p, with its
   ".", or "" *)
PROCEDURE Extension(VAR p: ARRAY OF CHAR; VAR ext: ARRAY OF CHAR);
  VAR i, dot, k: LONGINT;
BEGIN
  i := 0; dot := -1;
  WHILE (i < LEN(p)) & (p[i] # 0X) DO
    IF p[i] = "." THEN dot := i ELSIF p[i] = "/" THEN dot := -1 END;
    INC(i)
  END;
  k := 0;
  IF dot >= 0 THEN
    i := dot;
    WHILE (p[i] # 0X) & (k < LEN(ext) - 1) DO ext[k] := p[i]; INC(i); INC(k) END
  END;
  ext[k] := 0X
END Extension;

(* Whether the extension ext is s, ignoring case; s is lower case *)
PROCEDURE IsExt(VAR ext: ARRAY OF CHAR; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT; ch: CHAR;
BEGIN
  i := 0;
  LOOP
    ch := ext[i];
    IF (ch >= "A") & (ch <= "Z") THEN ch := CHR(ORD(ch) + 32) END;
    IF ch # s[i] THEN RETURN FALSE END;
    IF ch = 0X THEN RETURN TRUE END;
    INC(i)
  END
END IsExt;

(* Converts the SVG image at path to PDF, as pandoc's convertImage does
   with rsvg-convert; sets path to the PDF made, or warns and leaves it
   alone. *)
PROCEDURE ConvertSvg(VAR path: ARRAY OF CHAR);
  VAR out: Path; c: R.Command; m: ARRAY R.PathLen + 100 OF CHAR;
BEGIN
  COPY(tmp, out); R.Append(out, "/img"); R.AppendInt(out, images); INC(images);
  R.Append(out, ".pdf");
  m := "Could not convert image "; R.Append(m, path);
  IF ~R.Found("rsvg-convert") THEN
    R.Append(m, ": check that rsvg-convert is in path.");
    PdIO.Warn(m)
  ELSE
    c := R.New(); R.Add(c, "rsvg-convert");
    R.Add(c, "-f"); R.Add(c, "pdf"); R.Add(c, "-a");
    R.Add(c, "--dpi-x"); R.Add(c, "96"); R.Add(c, "--dpi-y"); R.Add(c, "96");
    R.Add(c, "-o"); R.Add(c, out); R.Add(c, path);
    R.AddText(c, " </dev/null >/dev/null");
    IF R.Run(c) = 0 THEN COPY(out, path)
    ELSE R.Append(m, ": conversion from SVG failed"); PdIO.Warn(m)
    END
  END
END ConvertSvg;

(* What the image src becomes: the path of its copy in the temporary
   directory, converted for ConTeXt if need be, or NIL if it cannot be
   read. *)
PROCEDURE Fetch(src: Rope): Rope;
  VAR s: Seen; url, path, ext: Path; r: Rope;
BEGIN
  s := seen;
  WHILE (s # NIL) & ~Ropes.Equal(s.src, src) DO s := s.next END;
  IF s # NIL THEN RETURN s.url END;
  Ropes.ToString(src, url);
  IF HasScheme(url) THEN
    r := src (* podoc does not fetch URLs; the engine may *)
  ELSIF ~PdIO.Exists(url) THEN
    r := NIL
  ELSE
    Extension(url, ext);
    COPY(tmp, path); R.Append(path, "/img"); R.AppendInt(path, images); INC(images);
    R.Append(path, ext);
    IF ~R.Copy(url, path) THEN r := NIL
    ELSE
      IF tex & IsExt(ext, ".svg") THEN ConvertSvg(path) END;
      r := Ropes.FromString(path)
    END
  END;
  NEW(s); s.src := src; s.url := r; s.next := seen; seen := s;
  RETURN r
END Fetch;

(* A Span of the image's description in place of the image l, which
   could not be read, as fillMediaBag's replacementSpan *)
PROCEDURE Replacement(l: A.LinkInl): A.Inline;
  VAR a: A.Attr; p: A.StrList; kv: A.KeyVal;
BEGIN
  IF l.attr = NIL THEN a := A.NewAttr(NIL) ELSE a := A.NewAttr(l.attr.id) END;
  A.AddClass(a, A.S("image")); A.AddClass(a, A.S("placeholder"));
  IF l.attr # NIL THEN
    p := l.attr.classes;
    WHILE p # NIL DO A.AddClass(a, p.s); p := p.next END
  END;
  A.AddKeyVal(a, A.S("original-image-src"), l.url);
  A.AddKeyVal(a, A.S("original-image-title"), l.title);
  IF l.attr # NIL THEN
    kv := l.attr.attrs;
    WHILE kv # NIL DO A.AddKeyVal(a, kv.key, kv.value); kv := kv.next END
  END;
  RETURN A.NewSpan(a, l.content)
END Replacement;

PROCEDURE (w: Walker) Inline*(i: A.Inline): A.Inline;
  VAR l: A.LinkInl; r: Rope; m, src: Path;
BEGIN
  IF i.kind = A.Image THEN
    l := i(A.LinkInl);
    r := Fetch(l.url);
    IF r = NIL THEN
      Ropes.ToString(l.url, src);
      m := "Could not fetch resource "; R.Append(m, src);
      R.Append(m, ": replacing image with description");
      PdIO.Warn(m);
      RETURN Replacement(l)
    END;
    l.url := r
  END;
  RETURN i
END Inline;

(* Making the PDF *)

(* Makes the temporary directory and handles the images of d for the
   engine: context when context is TRUE, else pdfroff or groff. *)
PROCEDURE Prepare*(d: A.Doc; context: BOOLEAN);
  VAR ok: BOOLEAN; w: Walker;
BEGIN
  tex := context; seen := NIL; images := 0;
  R.MakeTempDir(tmp, ok);
  IF ~ok THEN tmp := ""; PdIO.Fail("", "cannot make a temporary directory", PdIO.IOError) END;
  NEW(w);
  A.WalkMetaValue(w, d.meta);
  d.blocks := A.WalkBlocks(w, d.blocks)
END Prepare;

(* Sets name to the path the writer writes the engine's source to. *)
PROCEDURE Source*(VAR name: ARRAY OF CHAR);
BEGIN
  COPY(tmp, name);
  IF tex THEN R.Append(name, "/input.tex") ELSE R.Append(name, "/input.ms") END
END Source;

(* Whether the text t[0 .. len-1] contains s *)
PROCEDURE Contains(t: PdIO.Text; len: LONGINT; s: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: LONGINT;
BEGIN
  i := 0;
  WHILE i < len DO
    j := 0;
    WHILE (s[j] # 0X) & (i + j < len) & (t[i + j] = s[j]) DO INC(j) END;
    IF s[j] = 0X THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END Contains;

(* Adds the paper size arguments, from -V papersize, as pandoc does for
   pdfroff and groff *)
PROCEDURE AddPaper(c: R.Command);
  VAR v: T.Value; s: Path; a: ARRAY R.PathLen + 4 OF CHAR; n: LONGINT;
BEGIN
  v := T.Get(C.variables, "papersize");
  IF (v # NIL) & (v.kind = T.SimpleV) THEN
    Ropes.ToString(L.Render(v.doc, 0), s);
    n := 0; WHILE s[n] # 0X DO INC(n) END;
    a := "-P-p";
    IF (n > 0) & (s[n - 1] = "l") THEN
      s[n - 1] := 0X; R.Append(a, s); R.Add(c, a); R.Add(c, "-P-l")
    ELSE
      R.Append(a, s); R.Add(c, a)
    END
  END
END AddPaper;

(* Adds the --pdf-engine-opt arguments *)
PROCEDURE AddOpts(c: R.Command);
  VAR f: O.File;
BEGIN
  f := O.pdfEngineOpts;
  WHILE f # NIL DO R.Add(c, f.name^); f := f.next END
END AddOpts;

(* The last part of the path p *)
PROCEDURE BaseName(VAR p, base: ARRAY OF CHAR);
  VAR i, start, k: LONGINT;
BEGIN
  i := 0; start := 0;
  WHILE p[i] # 0X DO IF p[i] = "/" THEN start := i + 1 END; INC(i) END;
  k := 0;
  WHILE p[start] # 0X DO base[k] := p[start]; INC(k); INC(start) END;
  base[k] := 0X
END BaseName;

(* Writes the PDF in the file pdf to the output, -o or standard output,
   and removes the temporary directory. *)
PROCEDURE Deliver(VAR pdf: ARRAY OF CHAR);
  VAR t: PdIO.Text; len: LONGINT;
BEGIN
  PdIO.ReadFile(pdf, t, len);
  R.RemoveDir(tmp); tmp := "";
  PdIO.OpenOutput(O.output);
  IF len > 0 THEN PdIO.WriteChars(t^, 0, len) END;
  PdIO.CloseOutput
END Deliver;

(* Runs pdfroff or groff on the ms source *)
PROCEDURE Roff(VAR prog, base: ARRAY OF CHAR);
  VAR c: R.Command; src, pdf: Path; t: PdIO.Text; len: LONGINT;
BEGIN
  Source(src);
  COPY(tmp, pdf); R.Append(pdf, "/output.pdf");
  PdIO.ReadFile(src, t, len);
  c := R.New(); R.Add(c, prog);
  R.Add(c, "-ms");
  IF base = "pdfroff" THEN R.Add(c, "-mpdfmark"); R.Add(c, "-mspdf") ELSE R.Add(c, "-Tpdf") END;
  R.Add(c, "-e"); R.Add(c, "-t"); R.Add(c, "-k"); R.Add(c, "-KUTF-8");
  IF base = "pdfroff" THEN R.Add(c, "-i") END;
  IF Contains(t, len, ".PDFPIC") THEN R.Add(c, "-U") END;
  AddPaper(c); AddOpts(c);
  R.AddText(c, " <"); R.Add(c, src); R.AddText(c, " >"); R.Add(c, pdf);
  IF R.Run(c) # 0 THEN
    PdIO.ReadFile(pdf, t, len);
    Failed(t, len)
  END;
  Deliver(pdf)
END Roff;

(* Runs context on input.tex in the temporary directory *)
PROCEDURE ConTeXt(VAR prog: ARRAY OF CHAR);
  VAR c: R.Command; log, pdf: Path; t, m: PdIO.Text; len, i, j, k: LONGINT;
BEGIN
  COPY(tmp, log); R.Append(log, "/podoc-context.log");
  COPY(tmp, pdf); R.Append(pdf, "/input.pdf");
  c := R.New(); R.AddText(c, "cd"); R.Add(c, tmp); R.AddText(c, " && ");
  R.Add(c, prog); R.Add(c, "--batchmode"); AddOpts(c); R.Add(c, "input.tex");
  R.AddText(c, " </dev/null >"); R.Add(c, log);
  IF R.Run(c) # 0 THEN
    PdIO.ReadFile(log, t, len);
    (* the first line that starts with "tex error", or the whole log *)
    i := 0;
    WHILE (i < len) & ~((len - i >= 9) & (t[i] = "t") & (t[i+1] = "e") & (t[i+2] = "x")
        & (t[i+3] = " ") & (t[i+4] = "e") & (t[i+5] = "r") & (t[i+6] = "r")
        & (t[i+7] = "o") & (t[i+8] = "r")) DO
      WHILE (i < len) & (t[i] # 0AX) DO INC(i) END;
      IF i < len THEN INC(i) END
    END;
    IF i < len THEN
      j := i; WHILE (j < len) & (t[j] # 0AX) DO INC(j) END;
      NEW(m, j - i + 1);
      k := 0; WHILE i < j DO m[k] := t[i]; INC(k); INC(i) END;
      m[k] := 0AX;
      Failed(m, k + 1)
    END;
    Failed(t, len)
  END;
  IF ~PdIO.Exists(pdf) THEN Failed(NIL, 0) END;
  Deliver(pdf)
END ConTeXt;

(* Runs the engine, --pdf-engine, on the source written to Source, and
   writes the PDF to the output; an engine that fails ends the program
   with its message and PDFError. *)
PROCEDURE Make*;
  VAR prog, base: Path;
BEGIN
  COPY(O.pdfEngine, prog); BaseName(prog, base);
  IF ~R.Found(prog) THEN NotFound(prog) END;
  IF tex THEN ConTeXt(prog) ELSE Roff(prog, base) END
END Make;

(* Ends the program, as pandoc does, if PDF would be written to a
   terminal. *)
PROCEDURE CheckTerminal*;
BEGIN
  IF (O.output = "") & R.OutputIsTerminal() THEN
    PdIO.Message("Cannot write pdf output to terminal.");
    PdIO.Note("Specify an output file using the -o option, or use '-o -' to force output to stdout.", "", "");
    PdIO.Exit(PdIO.AppError)
  END
END CheckTerminal;

BEGIN
  tmp := ""; tex := FALSE; seen := NIL; images := 0
END PdPdf.
