MODULE PdImages;
(* PdImages: the document's local images, copied, named and converted
   for the output (decision 23, Phase 21).

   Extract does what pandoc 3.10's --extract-media=DIR does
   (Text.Pandoc.Class.IO.extractMedia, MediaBag.insertMedia): it copies
   each local image into DIR, under its own relative path or, if that
   cannot be kept, under the SHA-1 of its contents, and points the
   image at the copy. For ms it also converts the copies that groff
   cannot show to PDF, beside them, and points the images at the PDFs,
   for .PDFPIC. ForMs converts them without --extract-media, into the
   directory beside the ms file. Convert converts one image to PDF;
   PdPdf uses it for the images of a PDF made with groff or pdfroff,
   and with groff for PostScript images too (decision 26). *)

IMPORT Ropes, Strings, A := PdAst, PdIO, R := PdRun, PdMime, PdSha1;

CONST
  Missing = 0; Local = 1; (* Item.state *)

TYPE
  Rope = Ropes.Rope;
  Path = R.Path;

  (* a local image of the document, by its canonical path *)
  Item = POINTER TO ItemDesc;
  ItemDesc = RECORD
    key: Rope; (* the canonical path *)
    src: Rope; (* the path as first written *)
    state: INTEGER;
    convert: BOOLEAN; (* whether it is to be converted to PDF *)
    url: Rope; (* what the image becomes, or NIL if it stays *)
    next: Item
  END;

  (* a file name used in the output directory *)
  Name = POINTER TO NameDesc;
  NameDesc = RECORD
    s: Rope;
    next: Name
  END;

  Collector = POINTER TO CollectorDesc;
  CollectorDesc = RECORD (A.WalkerDesc) END;

  Rewriter = POINTER TO RewriterDesc;
  RewriterDesc = RECORD (A.WalkerDesc)
    replace: BOOLEAN (* whether a missing image becomes its description *)
  END;

VAR
  items, last: Item;
  names: Name;
  convertMs: BOOLEAN; (* whether Collect marks images to convert *)
  convertPs: BOOLEAN; (* whether it marks PostScript too (for mom) *)

(* Paths *)

(* Whether url has a scheme (http:, data:, file: and the like) *)
PROCEDURE HasScheme*(VAR url: ARRAY OF CHAR): BOOLEAN;
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
PROCEDURE Extension*(VAR p: ARRAY OF CHAR; VAR ext: ARRAY OF CHAR);
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
PROCEDURE IsExt*(VAR ext: ARRAY OF CHAR; s: ARRAY OF CHAR): BOOLEAN;
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

(* Whether the image at path is one groff cannot show and podoc
   converts to PDF: its extension's MIME type is an image's, ignoring
   case (SVG, PNG, JPEG and the like; not .pdf, .ps or .eps) *)
PROCEDURE Convertible*(VAR path: ARRAY OF CHAR): BOOLEAN;
  VAR ext: Path; i: LONGINT;
BEGIN
  Extension(path, ext);
  IF ext = "" THEN RETURN FALSE END;
  (* Category takes the extension without its dot *)
  i := 0; WHILE ext[i] # 0X DO ext[i] := ext[i + 1]; INC(i) END;
  RETURN PdMime.Category(ext) = PdMime.Image
END Convertible;

(* Whether the image at path is PostScript, which the ms writer shows
   with .PSPIC: its extension is .eps or .ps, matched exactly, as
   pandoc's ms writer matches it. groff -Tpdf (gropdf) ignores .PSPIC,
   so for PDF made with groff these are converted (decision 26). *)
PROCEDURE PostScript*(VAR path: ARRAY OF CHAR): BOOLEAN;
  VAR ext: Path;
BEGIN
  Extension(path, ext);
  RETURN (ext = ".eps") OR (ext = ".ps")
END PostScript;

(* Whether ch separates the parts of a path *)
PROCEDURE Sep(ch: CHAR): BOOLEAN;
BEGIN RETURN (ch = "/") OR (ch = "\")
END Sep;

(* Sets s to the path p as pandoc canonicalizes it (filepath's
   normalise, "\" made "/"): repeated "/" and "." parts dropped *)
PROCEDURE Normalise(VAR p, s: ARRAY OF CHAR);
  VAR i, k, start: LONGINT; trail: BOOLEAN;
BEGIN
  i := 0; k := 0; trail := FALSE;
  IF Sep(p[0]) THEN s[0] := "/"; k := 1 END;
  WHILE p[i] # 0X DO
    IF Sep(p[i]) THEN INC(i); trail := TRUE
    ELSE
      start := i;
      WHILE (p[i] # 0X) & ~Sep(p[i]) DO INC(i) END;
      IF (i - start = 1) & (p[start] = ".") THEN trail := TRUE
      ELSE
        IF (k > 0) & (s[k - 1] # "/") THEN s[k] := "/"; INC(k) END;
        WHILE start < i DO s[k] := p[start]; INC(k); INC(start) END;
        trail := FALSE
      END
    END
  END;
  IF trail & (k > 0) & (s[k - 1] # "/") THEN s[k] := "/"; INC(k) END;
  IF k = 0 THEN s[0] := "."; k := 1 END;
  s[k] := 0X
END Normalise;

(* Whether s contains t *)
PROCEDURE Contains(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: LONGINT;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    j := 0;
    WHILE (t[j] # 0X) & (s[i + j] = t[j]) DO INC(j) END;
    IF t[j] = 0X THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END Contains;

(* Sets p to the directory dir and the name, joined as pandoc's
   Posix.</> joins them *)
PROCEDURE Join(VAR dir, name, p: ARRAY OF CHAR);
  VAR n: LONGINT;
BEGIN
  COPY(dir, p);
  n := 0; WHILE p[n] # 0X DO INC(n) END;
  IF (n > 0) & (p[n - 1] # "/") THEN R.Append(p, "/") END;
  R.Append(p, name)
END Join;

(* Sets dir to the directory part of the path p, "" if it has none *)
PROCEDURE DirName(VAR p, dir: ARRAY OF CHAR);
  VAR i, slash: LONGINT;
BEGIN
  i := 0; slash := -1;
  WHILE p[i] # 0X DO IF p[i] = "/" THEN slash := i END; INC(i) END;
  IF slash = 0 THEN COPY("/", dir)
  ELSE
    i := 0; WHILE i < slash DO dir[i] := p[i]; INC(i) END;
    IF slash < 0 THEN dir[0] := 0X ELSE dir[slash] := 0X END
  END
END DirName;

(* Makes the directory dir and those above it; returns whether it
   could. *)
PROCEDURE MakeDirs(VAR dir: ARRAY OF CHAR): BOOLEAN;
  VAR c: R.Command;
BEGIN
  IF dir = "" THEN RETURN TRUE END;
  c := R.New(); R.AddText(c, "mkdir -p"); R.Add(c, dir); R.AddText(c, " 2>/dev/null");
  RETURN R.Run(c) = 0
END MakeDirs;

(* Sets name to the name pandoc gives the image at path when it cannot
   keep the path: the SHA-1 of its contents and the extension of its
   MIME type (insertMedia's hashpath) *)
PROCEDURE HashName(VAR path, name: ARRAY OF CHAR);
  VAR t: PdIO.Text; len, i: LONGINT; empty: ARRAY 1 OF CHAR;
    p, ext, canon: Path;
BEGIN
  PdIO.ReadFile(path, t, len);
  IF len = 0 THEN PdSha1.Hex(empty, 0, name) ELSE PdSha1.Hex(t^, len, name) END;
  COPY(path, p); Extension(p, ext);
  IF ext = ".gz" THEN
    i := 0; WHILE p[i] # 0X DO INC(i) END;
    p[i - 3] := 0X; Extension(p, ext)
  END;
  IF ext = "" THEN PdMime.Canonical("", canon)
  ELSE
    i := 0; WHILE ext[i + 1] # 0X DO ext[i] := ext[i + 1]; INC(i) END;
    ext[i] := 0X;
    PdMime.Canonical(ext, canon)
  END;
  R.Append(name, "."); R.Append(name, canon)
END HashName;

(* Converting *)

(* Whether the command c succeeds, its output and errors discarded *)
PROCEDURE Quiet(c: R.Command): BOOLEAN;
BEGIN
  R.AddText(c, " </dev/null >/dev/null 2>&1");
  RETURN R.Run(c) = 0
END Quiet;

(* Converts the bitmap src to the PDF out with ImageMagick: prog is
   "magick" or ImageMagick 6's "convert", ident its identify command.
   An image with no resolution of its own is given 96 dpi. *)
PROCEDURE Magick(VAR src, out: ARRAY OF CHAR; prog, ident: ARRAY OF CHAR): BOOLEAN;
  VAR c: R.Command;
BEGIN
  c := R.New(); R.AddText(c, "if "); R.AddText(c, ident);
  R.AddText(c, " -format '%U\n'"); R.Add(c, src);
  R.AddText(c, " 2>/dev/null | head -n 1 | grep -qx Undefined; then ");
  R.Add(c, prog); R.AddText(c, " -units PixelsPerInch -density 96");
  R.Add(c, src); R.Add(c, out);
  R.AddText(c, "; else "); R.Add(c, prog); R.Add(c, src); R.Add(c, out);
  R.AddText(c, "; fi");
  RETURN Quiet(c)
END Magick;

(* Converts the image src to the PDF out: SVG with rsvg-convert, as
   pandoc's convertImage does, but for groff (groff TRUE) as PDF 1.4,
   which gropdf can read, if rsvg-convert can write it; PostScript
   (.eps and .ps) with Ghostscript, as PDF 1.4 cropped to the bounding
   box (decision 26); any other image with the first of img2pdf and
   magick (or ImageMagick 6's convert) that is found and succeeds.
   (GraphicsMagick's PDFs have an object gropdf refuses, so gm is not
   used.) Returns whether it converted the image; if not, warns. *)
PROCEDURE Convert*(VAR src, out: ARRAY OF CHAR; groff: BOOLEAN): BOOLEAN;
  VAR ext: Path; m: ARRAY R.PathLen + 100 OF CHAR; tried: BOOLEAN;

  PROCEDURE Rsvg(format: ARRAY OF CHAR): BOOLEAN;
    VAR c: R.Command;
  BEGIN
    c := R.New(); R.Add(c, "rsvg-convert");
    R.Add(c, "-f"); R.Add(c, format); R.Add(c, "-a");
    R.Add(c, "--dpi-x"); R.Add(c, "96"); R.Add(c, "--dpi-y"); R.Add(c, "96");
    R.Add(c, "-o"); R.Add(c, out); R.Add(c, src);
    RETURN Quiet(c)
  END Rsvg;

  PROCEDURE Img2pdf(): BOOLEAN;
    VAR c: R.Command;
  BEGIN
    c := R.New(); R.Add(c, "img2pdf"); R.Add(c, "-o"); R.Add(c, out); R.Add(c, src);
    RETURN Quiet(c)
  END Img2pdf;

  PROCEDURE Gs(): BOOLEAN;
    VAR c: R.Command; o: ARRAY R.PathLen + 16 OF CHAR;
  BEGIN
    c := R.New(); R.Add(c, "gs");
    R.Add(c, "-q"); R.Add(c, "-dSAFER"); R.Add(c, "-dBATCH"); R.Add(c, "-dNOPAUSE");
    R.Add(c, "-sDEVICE=pdfwrite"); R.Add(c, "-dEPSCrop");
    R.Add(c, "-dCompatibilityLevel=1.4");
    o := "-sOutputFile="; R.Append(o, out); R.Add(c, o);
    R.Add(c, src);
    RETURN Quiet(c)
  END Gs;

BEGIN
  m := "Could not convert image "; R.Append(m, src);
  IF PostScript(src) THEN
    IF ~R.Found("gs") THEN
      R.Append(m, ": check that gs is in path.");
      PdIO.Warn(m); RETURN FALSE
    END;
    IF Gs() THEN RETURN TRUE END;
    R.Append(m, ": conversion from PostScript failed"); PdIO.Warn(m);
    RETURN FALSE
  END;
  Extension(src, ext);
  IF IsExt(ext, ".svg") THEN
    IF ~R.Found("rsvg-convert") THEN
      R.Append(m, ": check that rsvg-convert is in path.");
      PdIO.Warn(m); RETURN FALSE
    END;
    IF groff & Rsvg("pdf1.4") OR Rsvg("pdf") THEN RETURN TRUE END;
    R.Append(m, ": conversion from SVG failed"); PdIO.Warn(m);
    RETURN FALSE
  END;
  tried := FALSE;
  IF R.Found("img2pdf") THEN
    tried := TRUE;
    IF Img2pdf() THEN RETURN TRUE END
  END;
  IF R.Found("magick") THEN
    tried := TRUE;
    IF Magick(src, out, "magick", "magick identify") THEN RETURN TRUE END
  ELSIF R.Found("convert") & R.Found("identify") THEN
    tried := TRUE;
    IF Magick(src, out, "convert", "identify") THEN RETURN TRUE END
  END;
  IF tried THEN R.Append(m, ": conversion to PDF failed")
  ELSE R.Append(m, ": check that img2pdf or magick is in path.")
  END;
  PdIO.Warn(m);
  RETURN FALSE
END Convert;

(* Sets w and h to the size in points of the first page of the PDF at
   path, as pdfinfo reports it ("Page size: 595.28 x 841.89 pts");
   returns FALSE, with no warning, if pdfinfo is not found or cannot
   read it. For mom's .PDF_IMAGE, which needs a size (decision 27). *)
PROCEDURE PageSize*(VAR path: ARRAY OF CHAR; VAR w, h: LONGREAL): BOOLEAN;
  VAR dir, out: Path; ok: BOOLEAN; c: R.Command; t: PdIO.Text; len, i: LONGINT;

  (* The number at t[i], skipping spaces before it, in x *)
  PROCEDURE Number(VAR x: LONGREAL): BOOLEAN;
    VAR s: ARRAY 32 OF CHAR; k: LONGINT;
  BEGIN
    WHILE (i < len) & (t[i] = " ") DO INC(i) END;
    k := 0;
    WHILE (i < len) & (k < LEN(s) - 1) & ((t[i] >= "0") & (t[i] <= "9") OR (t[i] = ".")) DO
      s[k] := t[i]; INC(k); INC(i)
    END;
    s[k] := 0X;
    IF k = 0 THEN RETURN FALSE END;
    Strings.StrToLongReal(s, x);
    RETURN x > 0
  END Number;

BEGIN
  IF ~R.Found("pdfinfo") THEN RETURN FALSE END;
  R.MakeTempDir(dir, ok);
  IF ~ok THEN RETURN FALSE END;
  COPY(dir, out); R.Append(out, "/size");
  c := R.New(); R.AddText(c, "pdfinfo"); R.Add(c, path);
  R.AddText(c, " 2>/dev/null </dev/null | grep '^Page size:' >"); R.Add(c, out);
  ok := R.Run(c) = 0;
  IF ok THEN PdIO.ReadFile(out, t, len) END;
  R.RemoveDir(dir);
  IF ~ok OR (len <= 10) THEN RETURN FALSE END;
  i := 10; (* after "Page size:" *)
  IF ~Number(w) THEN RETURN FALSE END;
  WHILE (i < len) & (t[i] = " ") DO INC(i) END;
  IF (i >= len) OR (t[i] # "x") THEN RETURN FALSE END;
  INC(i);
  RETURN Number(h)
END PageSize;

(* Makes the next ForMs and Extract convert PostScript (.eps and .ps)
   to PDF too, as mom's .PDF_IMAGE shows only PDF (on TRUE) *)
PROCEDURE ConvertPostScript*(on: BOOLEAN);
BEGIN
  convertPs := on
END ConvertPostScript;

(* The document's images *)

(* A Span of the image's description in place of the image l, which
   could not be read, as fillMediaBag's replacementSpan *)
PROCEDURE Replacement*(l: A.LinkInl): A.Inline;
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

(* Warns that the image src could not be read, as pandoc does *)
PROCEDURE WarnMissing*(src: Rope);
  VAR m, s: Path;
BEGIN
  Ropes.ToString(src, s);
  m := "Could not fetch resource "; R.Append(m, s);
  R.Append(m, ": replacing image with description");
  PdIO.Warn(m)
END WarnMissing;

(* The item for the local image url, NIL if url is not local; a new
   item is added if add is TRUE *)
PROCEDURE Find(url: Rope; add: BOOLEAN): Item;
  VAR s, n: Path; key: Rope; it: Item;
BEGIN
  IF Ropes.Length(url) >= R.PathLen THEN RETURN NIL END;
  Ropes.ToString(url, s);
  IF (s = "") OR HasScheme(s) THEN RETURN NIL END;
  Normalise(s, n); key := Ropes.FromString(n);
  it := items;
  WHILE (it # NIL) & ~Ropes.Equal(it.key, key) DO it := it.next END;
  IF (it = NIL) & add THEN
    NEW(it); it.key := key; it.src := url; it.url := NIL; it.next := NIL;
    IF PdIO.Exists(s) THEN it.state := Local ELSE it.state := Missing END;
    it.convert := convertMs & (it.state = Local) & (Convertible(n) OR convertPs & PostScript(n));
    IF last = NIL THEN items := it ELSE last.next := it END;
    last := it
  END;
  RETURN it
END Find;

PROCEDURE (w: Collector) Inline*(i: A.Inline): A.Inline;
  VAR it: Item;
BEGIN
  IF i.kind = A.Image THEN it := Find(i(A.LinkInl).url, TRUE) END;
  RETURN i
END Inline;

PROCEDURE (w: Rewriter) Inline*(i: A.Inline): A.Inline;
  VAR it: Item; l: A.LinkInl;
BEGIN
  IF i.kind = A.Image THEN
    l := i(A.LinkInl);
    it := Find(l.url, FALSE);
    IF it # NIL THEN
      IF (it.state = Missing) & w.replace THEN
        WarnMissing(l.url); RETURN Replacement(l)
      ELSIF it.url # NIL THEN l.url := it.url
      END
    END
  END;
  RETURN i
END Inline;

(* Collects the local images of d *)
PROCEDURE Collect(d: A.Doc; ms: BOOLEAN);
  VAR w: Collector;
BEGIN
  items := NIL; last := NIL; names := NIL; convertMs := ms;
  NEW(w);
  A.WalkMetaValue(w, d.meta);
  d.blocks := A.WalkBlocks(w, d.blocks)
END Collect;

(* Points the images of d at what Collect's items became; a missing one
   becomes its description if replace is TRUE *)
PROCEDURE Rewrite(d: A.Doc; replace: BOOLEAN);
  VAR w: Rewriter;
BEGIN
  NEW(w); w.replace := replace;
  A.WalkMetaValue(w, d.meta);
  d.blocks := A.WalkBlocks(w, d.blocks)
END Rewrite;

(* Whether the name s is used *)
PROCEDURE Used(VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR n: Name; r: Rope;
BEGIN
  r := Ropes.FromString(s); n := names;
  WHILE (n # NIL) & ~Ropes.Equal(n.s, r) DO n := n.next END;
  RETURN n # NIL
END Used;

(* Records the name s as used *)
PROCEDURE Use(VAR s: ARRAY OF CHAR);
  VAR n: Name;
BEGIN
  NEW(n); n.s := Ropes.FromString(s); n.next := names; names := n
END Use;

(* Sets pdf to the name, unused, of the PDF made from the image named
   name: name with ".pdf" for its extension, and "-2", "-3" and so on
   added before it if that is used *)
PROCEDURE PdfName(VAR name, pdf: ARRAY OF CHAR);
  VAR base: Path; ext: Path; i, k, n: LONGINT;
BEGIN
  COPY(name, base); Extension(base, ext);
  i := 0; WHILE base[i] # 0X DO INC(i) END;
  k := 0; WHILE ext[k] # 0X DO INC(k) END;
  base[i - k] := 0X;
  COPY(base, pdf); R.Append(pdf, ".pdf");
  n := 2;
  WHILE Used(pdf) DO
    COPY(base, pdf); R.Append(pdf, "-"); R.AppendInt(pdf, n); R.Append(pdf, ".pdf");
    INC(n)
  END;
  Use(pdf)
END PdfName;

(* Converts the image file to a PDF in dir, named from name; sets the
   item's url to the PDF's path, joined to urlDir, if it could *)
PROCEDURE ConvertItem(it: Item; VAR file, dir, name, urlDir: ARRAY OF CHAR);
  VAR pdf, out, url: Path;
BEGIN
  PdfName(name, pdf);
  Join(dir, pdf, out);
  IF Convert(file, out, TRUE) THEN
    Join(urlDir, pdf, url); it.url := Ropes.FromString(url)
  END
END ConvertItem;

(* Copies the local images of d into the directory dir, as pandoc's
   --extract-media=DIR does, and points the images at the copies; an
   image that cannot be read becomes its description, with a warning.
   For ms (ms TRUE) the copies groff cannot show are converted to PDF
   beside them, and the images pointed at the PDFs. *)
PROCEDURE Extract*(d: A.Doc; VAR dir: ARRAY OF CHAR; ms: BOOLEAN);
  VAR it: Item; src, key, name, file, sub, url: Path;
    m: ARRAY R.PathLen + 100 OF CHAR;
BEGIN
  Collect(d, ms);
  it := items;
  WHILE it # NIL DO
    IF it.state = Local THEN
      Ropes.ToString(it.src, src); Ropes.ToString(it.key, key);
      IF (key[0] # "/") & ~Contains(key, "..") & ~Contains(key, "%") THEN
        COPY(key, name)
      ELSE HashName(src, name)
      END;
      Use(name);
      Join(dir, name, file); DirName(file, sub);
      IF ~MakeDirs(sub) OR ~R.Copy(src, file) THEN
        m := "Could not extract image "; R.Append(m, src); R.Append(m, " to ");
        R.Append(m, file);
        PdIO.Fail("", m, PdIO.IOError)
      END;
      Join(dir, name, url); it.url := Ropes.FromString(url);
      it.src := Ropes.FromString(name) (* for ConvertItem below *)
    END;
    it := it.next
  END;
  it := items;
  WHILE it # NIL DO
    IF it.convert THEN
      Ropes.ToString(it.src, name); Join(dir, name, file);
      ConvertItem(it, file, dir, name, dir)
    END;
    it := it.next
  END;
  Rewrite(d, TRUE)
END Extract;

(* Converts the local images of d that groff cannot show to PDF, for ms
   written to the file output, into the directory beside it named for
   it, out-media for out.ms, and points the images at the PDFs, by
   paths relative to the output's directory (groff finds .PDFPIC files
   from the directory it runs in). With no output file, standard
   output, it converts none and warns if there were any. *)
PROCEDURE ForMs*(d: A.Doc; VAR output: ARRAY OF CHAR);
  VAR it: Item; any: BOOLEAN; outDir, base, media, dir, src, name: Path;
    i, k: LONGINT;
BEGIN
  Collect(d, TRUE);
  any := FALSE; it := items;
  WHILE it # NIL DO any := any OR it.convert; it := it.next END;
  IF ~any THEN RETURN END;
  IF (output = "") OR (output = "-") THEN
    IF convertPs THEN
      PdIO.Warn("Images not converted to PDF for mom written to standard output: use -o FILE or --extract-media=DIR")
    ELSE
      PdIO.Warn("Images not converted to PDF for ms written to standard output: use -o FILE or --extract-media=DIR")
    END;
    RETURN
  END;
  DirName(output, outDir);
  (* media: the output's name without its extension, and "-media" *)
  i := 0; k := 0;
  WHILE output[i] # 0X DO IF output[i] = "/" THEN k := i + 1 END; INC(i) END;
  i := 0; WHILE output[k] # 0X DO base[i] := output[k]; INC(i); INC(k) END;
  base[i] := 0X;
  Extension(base, src);
  k := 0; WHILE src[k] # 0X DO INC(k) END;
  IF (k > 0) & (k < i) THEN base[i - k] := 0X END;
  COPY(base, media); R.Append(media, "-media");
  Join(outDir, media, dir);
  IF (outDir = "") THEN COPY(media, dir) END;
  IF ~MakeDirs(dir) THEN
    PdIO.Fail(dir, "cannot be made", PdIO.IOError)
  END;
  it := items;
  WHILE it # NIL DO
    IF it.convert THEN
      Ropes.ToString(it.src, src); Ropes.ToString(it.key, name);
      (* the last part of the path *)
      i := 0; k := 0;
      WHILE name[i] # 0X DO IF name[i] = "/" THEN k := i + 1 END; INC(i) END;
      i := 0; WHILE name[k] # 0X DO name[i] := name[k]; INC(i); INC(k) END;
      name[i] := 0X;
      ConvertItem(it, src, dir, name, media)
    END;
    it := it.next
  END;
  Rewrite(d, FALSE)
END ForMs;

BEGIN
  items := NIL; last := NIL; names := NIL; convertMs := FALSE; convertPs := FALSE
END PdImages.
