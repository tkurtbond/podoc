MODULE PdOptionsTest;
(* Tests of PdOptions: file names, the format a name implies, and the
   writer and engine for PDF output, as pandoc 3.10 works them out. *)

IMPORT Out, O := PdOptions;

VAR
  failures: INTEGER;

PROCEDURE Report(ok: BOOLEAN; name: ARRAY OF CHAR);
BEGIN
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(name); Out.Ln
END Report;

PROCEDURE Append(s: ARRAY OF CHAR; VAR d: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE d[i] # 0X DO INC(i) END;
  j := 0; WHILE s[j] # 0X DO d[i] := s[j]; INC(i); INC(j) END;
  d[i] := 0X
END Append;

(* Checks that path implies the format want ("" for none) *)
PROCEDURE Format(path, want: ARRAY OF CHAR);
  VAR f: ARRAY 32 OF CHAR; name: ARRAY 128 OF CHAR;
BEGIN
  O.FormatFromPath(path, f);
  name := "format of "; Append(path, name);
  Report(f = want, name)
END Format;

(* Checks the extension, base name and file name of path *)
PROCEDURE Names(path, ext, base, file: ARRAY OF CHAR);
  VAR e, b, f: ARRAY 64 OF CHAR; name: ARRAY 128 OF CHAR;
BEGIN
  O.Extension(path, e); O.BaseName(path, b); O.FileName(path, f);
  name := "names of "; Append(path, name);
  Report((e = ext) & (b = base) & (f = file), name)
END Names;

(* Checks the writer and engine for PDF from writer and engine: want
   the writer and engine, or the error if wantW is "!" *)
PROCEDURE Pdf(writer, engine, wantW, wantE: ARRAY OF CHAR);
  VAR w, e, err: ARRAY 256 OF CHAR; ok: BOOLEAN; name: ARRAY 128 OF CHAR;
BEGIN
  ok := O.PdfWriterAndEngine(writer, engine, w, e, err);
  name := "pdf from writer '"; Append(writer, name);
  Append("' and engine '", name); Append(engine, name); Append("'", name);
  IF wantW = "!" THEN Report(~ok & (err = wantE), name)
  ELSE Report(ok & (w = wantW) & (e = wantE), name)
  END
END Pdf;

BEGIN
  failures := 0;
  Names("a.md", ".md", "a", "a.md");
  Names("dir.x/b.TeX", ".tex", "b", "b.TeX");
  Names("/usr/bin/pdfroff", "", "pdfroff", "pdfroff");
  Names("/dev/null", "", "null", "null");
  Names("a.b.c", ".c", "a.b", "a.b.c");
  Format("a.md", "markdown");
  Format("a.TXT", "markdown");
  Format("a.markdown", "markdown");
  Format("a.html", "html");
  Format("a.htm", "html");
  Format("a.ms", "ms");
  Format("a.roff", "ms");
  Format("a.ctx", "context");
  Format("a.context", "context");
  Format("a.tex", "latex");
  Format("a.json", "json");
  Format("a.PDF", "pdf");
  Format("a.1", "man");
  Format("a.10", "");
  Format("a.zz", "");
  Format("noext", "");
  Format("dir.md/noext", "");
  Pdf("", "", "latex", "pdflatex");
  Pdf("ms", "", "ms", "groff");
  Pdf("context", "", "context", "context");
  Pdf("html", "", "html", "weasyprint");
  Pdf("", "pdfroff", "ms", "pdfroff");
  Pdf("", "/usr/bin/groff", "ms", "/usr/bin/groff");
  Pdf("", "context", "context", "context");
  Pdf("ms", "pdfroff", "ms", "pdfroff");
  Pdf("context", "/opt/ctx/context", "context", "/opt/ctx/context");
  Pdf("json", "", "!", "cannot produce pdf output from json");
  Pdf("html", "context", "!", "pdf-engine context is not compatible with output format html");
  Pdf("ms", "context", "!", "pdf-engine context is not compatible with output format ms");
  Pdf("", "xyz", "!", "pdf-engine xyz not known");
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdOptionsTest.
