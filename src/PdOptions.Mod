MODULE PdOptions;
(* PdOptions: podoc's command line, in pandoc's forms (with ArgParser:
   --opt=val, --opt val, -ovalue, -o value, clustered short options),
   and the formats it implies, as pandoc 3.10 works them out
   (Text.Pandoc.App, Text.Pandoc.App.OutputSettings and
   Text.Pandoc.Format):

   - The input format is -f's; without -f, the format of the first
     input whose extension names one, else markdown (with a warning
     unless the input is standard input). podoc reads only markdown.
   - The output format is -t's; without -t, the format -o's extension
     names, else html (with a warning when -o names a file).
   - Output is PDF when -o ends in .pdf or -t is pdf. The writer and
     the engine then come from -t and --pdf-engine as pandoc's
     pdfWriterAndProg finds them, and the output is standalone.

   Filters (--lua-filter, -F/--filter) are kept in command-line order,
   for the built-in filters that replace them. *)

IMPORT ArgParser, PdIO, A := PdAst, C := PdContext;

CONST
  (* filter kinds *)
  LuaFilter* = 0; (* --lua-filter *)
  JsonFilter* = 1; (* -F, --filter *)

  DefaultTabStop = 4;
  Version = "0.1";

TYPE
  Name* = POINTER TO ARRAY OF CHAR;
  File* = POINTER TO FileDesc;
  FileDesc* = RECORD
    name*: Name;
    next*: File
  END;

  Filter* = POINTER TO FilterDesc;
  FilterDesc* = RECORD
    kind*: INTEGER; (* LuaFilter or JsonFilter *)
    name*: Name; (* as given *)
    next*: Filter
  END;

  String* = ArgParser.String;

VAR
  files*: File; (* the inputs; NIL for standard input *)
  metaFiles*: File; (* --metadata-file *)
  cmdMeta*: A.MetaMapV; (* -M *)
  output*: String; (* -o; "" for standard output *)
  from*: String; (* -f; "" until Resolve *)
  gridTables*: BOOLEAN; (* the grid_tables extension: TRUE unless -f
    markdown-grid_tables *)
  to*: String; (* -t; the writer after Resolve, without extensions *)
  gutenberg*: BOOLEAN; (* after Resolve: -t plain+gutenberg *)
  pdf*: BOOLEAN; (* after Resolve: the output is PDF *)
  pdfEngine*: String; (* --pdf-engine, or after Resolve the engine for PDF *)
  pdfEngineOpts*: File; (* --pdf-engine-opt *)
  extractMedia*: String; (* --extract-media; "" if not given *)
  filters*: Filter; (* --lua-filter, -F *)
  (* the writer as a Lua filter's FORMAT names it, after Resolve: to,
     but html5 when -t html5 named it so *)
  filterFormat*: String;
  tabStop*: INTEGER; (* --tab-stop; 0 for -p *)
  standalone*: BOOLEAN; (* -s *)
  template*: String; (* --template; "" for the default *)
  before*, after*, header*: File; (* -B, -A, -H *)
  wrap*: String; (* --wrap: auto, none or preserve *)
  columns*: LONGINT; (* --columns: the line length, 72 by default *)
  idPrefix*: String; (* --id-prefix *)
  numberSections*: BOOLEAN; (* -N *)
  toc*: BOOLEAN; (* --toc *)
  tocDepth*: INTEGER; (* --toc-depth *)
  done*: BOOLEAN; (* --help or --version was given: nothing else is done *)

  parser: ArgParser.Parser;
  lastFile, lastMetaFile, lastBefore, lastAfter, lastHeader, lastOpt: File;
  lastFilter: Filter;

(* Names and formats *)

(* Appends s to the end of d, as far as d holds it *)
PROCEDURE Append(s: ARRAY OF CHAR; VAR d: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  i := 0; WHILE (i < LEN(d)) & (d[i] # 0X) DO INC(i) END;
  j := 0;
  WHILE (j < LEN(s)) & (s[j] # 0X) & (i < LEN(d) - 1) DO
    d[i] := s[j]; INC(i); INC(j)
  END;
  IF i < LEN(d) THEN d[i] := 0X END
END Append;

(* The length of s *)
PROCEDURE Len(VAR s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  RETURN n
END Len;

(* The start of the last component of path *)
PROCEDURE FileStart(VAR path: ARRAY OF CHAR): LONGINT;
  VAR i, s: LONGINT;
BEGIN
  s := 0; i := 0;
  WHILE (i < LEN(path)) & (path[i] # 0X) DO
    IF path[i] = "/" THEN s := i + 1 END;
    INC(i)
  END;
  RETURN s
END FileStart;

(* ext := path's extension, lower case, with its dot, as filepath's
   takeExtension finds it; "" if there is none *)
PROCEDURE Extension*(path: ARRAY OF CHAR; VAR ext: ARRAY OF CHAR);
  VAR i, d, n, j: LONGINT;
BEGIN
  n := Len(path); d := -1;
  i := FileStart(path);
  WHILE i < n DO
    IF path[i] = "." THEN d := i END;
    INC(i)
  END;
  j := 0;
  IF d >= 0 THEN
    i := d;
    WHILE (i < n) & (j < LEN(ext) - 1) DO
      IF (path[i] >= "A") & (path[i] <= "Z") THEN
        ext[j] := CHR(ORD(path[i]) - ORD("A") + ORD("a"))
      ELSE ext[j] := path[i]
      END;
      INC(i); INC(j)
    END
  END;
  ext[j] := 0X
END Extension;

(* base := path's last component without its extension (takeBaseName) *)
PROCEDURE BaseName*(path: ARRAY OF CHAR; VAR base: ARRAY OF CHAR);
  VAR i, s, e, j: LONGINT;
BEGIN
  s := FileStart(path); e := Len(path);
  i := s;
  WHILE i < Len(path) DO
    IF path[i] = "." THEN e := i END;
    INC(i)
  END;
  j := 0;
  WHILE (s < e) & (j < LEN(base) - 1) DO base[j] := path[s]; INC(s); INC(j) END;
  base[j] := 0X
END BaseName;

(* name := path's last component (takeFileName) *)
PROCEDURE FileName*(path: ARRAY OF CHAR; VAR name: ARRAY OF CHAR);
  VAR s, j: LONGINT;
BEGIN
  s := FileStart(path); j := 0;
  WHILE (s < LEN(path)) & (path[s] # 0X) & (j < LEN(name) - 1) DO
    name[j] := path[s]; INC(s); INC(j)
  END;
  name[j] := 0X
END FileName;

(* fmt := the format path's extension names, as pandoc's
   formatFromFilePath; "" if it names none *)
PROCEDURE FormatFromPath*(path: ARRAY OF CHAR; VAR fmt: ARRAY OF CHAR);
  VAR e: ARRAY 32 OF CHAR;
BEGIN
  Extension(path, e);
  IF (e = ".adoc") OR (e = ".asciidoc") THEN COPY("asciidoc", fmt)
  ELSIF e = ".bib" THEN COPY("biblatex", fmt)
  ELSIF (e = ".context") OR (e = ".ctx") THEN COPY("context", fmt)
  ELSIF e = ".csv" THEN COPY("csv", fmt)
  ELSIF e = ".db" THEN COPY("docbook", fmt)
  ELSIF e = ".dj" THEN COPY("djot", fmt)
  ELSIF e = ".djvu" THEN COPY("djvu", fmt)
  ELSIF e = ".doc" THEN COPY("doc", fmt)
  ELSIF e = ".docx" THEN COPY("docx", fmt)
  ELSIF e = ".dokuwiki" THEN COPY("dokuwiki", fmt)
  ELSIF e = ".epub" THEN COPY("epub", fmt)
  ELSIF e = ".fb2" THEN COPY("fb2", fmt)
  ELSIF (e = ".htm") OR (e = ".html") OR (e = ".xhtml") THEN COPY("html", fmt)
  ELSIF e = ".icml" THEN COPY("icml", fmt)
  ELSIF e = ".ipynb" THEN COPY("ipynb", fmt)
  ELSIF e = ".json" THEN COPY("json", fmt)
  ELSIF (e = ".latex") OR (e = ".ltx") OR (e = ".tex") THEN COPY("latex", fmt)
  ELSIF (e = ".lhs") OR (e = ".markdown") OR (e = ".md") OR (e = ".mdown")
     OR (e = ".mdwn") OR (e = ".mkd") OR (e = ".mkdn") OR (e = ".text")
     OR (e = ".txt") THEN COPY("markdown", fmt)
  ELSIF e = ".markua" THEN COPY("markua", fmt)
  ELSIF (e = ".ms") OR (e = ".roff") THEN COPY("ms", fmt)
  ELSIF e = ".muse" THEN COPY("muse", fmt)
  ELSIF e = ".native" THEN COPY("native", fmt)
  ELSIF e = ".ods" THEN COPY("ods", fmt)
  ELSIF e = ".odp" THEN COPY("odp", fmt)
  ELSIF e = ".odf" THEN COPY("odf", fmt)
  ELSIF e = ".odt" THEN COPY("odt", fmt)
  ELSIF e = ".opml" THEN COPY("opml", fmt)
  ELSIF e = ".org" THEN COPY("org", fmt)
  ELSIF e = ".pdf" THEN COPY("pdf", fmt)
  ELSIF (e = ".pl") OR (e = ".pm") OR (e = ".pod") THEN COPY("pod", fmt)
  ELSIF e = ".pptx" THEN COPY("pptx", fmt)
  ELSIF e = ".ris" THEN COPY("ris", fmt)
  ELSIF e = ".rst" THEN COPY("rst", fmt)
  ELSIF e = ".rtf" THEN COPY("rtf", fmt)
  ELSIF e = ".s5" THEN COPY("s5", fmt)
  ELSIF e = ".t2t" THEN COPY("t2t", fmt)
  ELSIF e = ".tei" THEN COPY("tei", fmt)
  ELSIF (e = ".texi") OR (e = ".texinfo") THEN COPY("texinfo", fmt)
  ELSIF e = ".textile" THEN COPY("textile", fmt)
  ELSIF e = ".tsv" THEN COPY("tsv", fmt)
  ELSIF e = ".typ" THEN COPY("typst", fmt)
  ELSIF e = ".wiki" THEN COPY("mediawiki", fmt)
  ELSIF e = ".xls" THEN COPY("xls", fmt)
  ELSIF e = ".xlsx" THEN COPY("xlsx", fmt)
  ELSIF e = ".xml" THEN COPY("xml", fmt)
  ELSIF e = ".zip" THEN COPY("zip", fmt)
  ELSIF (e[0] = ".") & (e[1] >= "1") & (e[1] <= "9") & (e[2] = 0X) THEN
    COPY("man", fmt)
  ELSE fmt[0] := 0X
  END
END FormatFromPath;

(* Whether pandoc pairs the writer w with the PDF engine e (pandoc's
   engines list, in its order; podoc makes PDF only with groff,
   pdfroff and context) *)
PROCEDURE Pairs(w, e: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN (w = "ms") & ((e = "groff") OR (e = "pdfroff"))
    OR (w = "context") & (e = "context")
END Pairs;

(* Works out the writer and engine for PDF output from writer, -t ("" if
   none or "pdf"), and engine, --pdf-engine ("" if none), as pandoc's
   pdfWriterAndProg: sets w and e and returns TRUE, or sets err to
   pandoc's message and returns FALSE. Without either, pandoc uses latex
   and pdflatex, which podoc does not have. *)
PROCEDURE PdfWriterAndEngine*(writer, engine: ARRAY OF CHAR;
  VAR w, e, err: ARRAY OF CHAR): BOOLEAN;
  VAR base: String; ok: BOOLEAN;
BEGIN
  ok := TRUE; err[0] := 0X;
  BaseName(engine, base);
  IF (writer = "") & (engine = "") THEN
    COPY("latex", w); COPY("pdflatex", e)
  ELSIF engine = "" THEN
    COPY(writer, w);
    IF writer = "ms" THEN COPY("groff", e)
    ELSIF writer = "context" THEN COPY("context", e)
    ELSIF (writer = "html") OR (writer = "html5") THEN COPY("weasyprint", e)
    ELSIF (writer = "latex") OR (writer = "beamer") THEN COPY("pdflatex", e)
    ELSIF writer = "typst" THEN COPY("typst", e)
    ELSE
      ok := FALSE;
      COPY("cannot produce pdf output from ", err);
      Append(writer, err)
    END
  ELSIF writer = "" THEN
    COPY(engine, e);
    IF (base = "groff") OR (base = "pdfroff") THEN COPY("ms", w)
    ELSIF base = "context" THEN COPY("context", w)
    ELSE
      ok := FALSE;
      COPY("pdf-engine ", err); Append(base, err);
      Append(" not known", err)
    END
  ELSIF Pairs(writer, base) THEN
    COPY(writer, w); COPY(engine, e)
  ELSE
    ok := FALSE;
    COPY("pdf-engine ", err); Append(engine, err);
    Append(" is not compatible with output format ", err);
    Append(writer, err)
  END;
  RETURN ok
END PdfWriterAndEngine;

(* The command line *)

PROCEDURE Help(): BOOLEAN;
BEGIN
  parser.Usage;
  done := TRUE;
  RETURN FALSE
END Help;

PROCEDURE ShowVersion(): BOOLEAN;
BEGIN
  PdIO.WriteString("podoc "); PdIO.WriteString(Version); PdIO.WriteLn;
  PdIO.WriteString("A subset of pandoc in Oberon-2, built with poc."); PdIO.WriteLn;
  done := TRUE;
  RETURN FALSE
END ShowVersion;

(* A file named arg *)
PROCEDURE NewName(VAR arg: ARRAY OF CHAR): Name;
  VAR n: Name;
BEGIN
  NEW(n, Len(arg) + 1);
  COPY(arg, n^);
  RETURN n
END NewName;

(* Adds a file named arg to the list first .. last *)
PROCEDURE AddTo(VAR first, last: File; VAR arg: ARRAY OF CHAR);
  VAR f: File;
BEGIN
  NEW(f); f.name := NewName(arg); f.next := NIL;
  IF first = NIL THEN first := f ELSE last.next := f END;
  last := f
END AddTo;

PROCEDURE SetOutput(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, output);
  RETURN TRUE
END SetOutput;

PROCEDURE SetFrom(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, from);
  RETURN TRUE
END SetFrom;

PROCEDURE SetTo(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, to);
  RETURN TRUE
END SetTo;

PROCEDURE SetTabStop(n: LONGINT): BOOLEAN;
BEGIN
  tabStop := SHORT(n);
  RETURN TRUE
END SetTabStop;

PROCEDURE PreserveTabs(): BOOLEAN;
BEGIN
  tabStop := 0;
  RETURN TRUE
END PreserveTabs;

(* Collects an input file; "-" is standard input. *)
PROCEDURE AddInput(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddTo(files, lastFile, arg);
  RETURN TRUE
END AddInput;

PROCEDURE AddMetaFile(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddTo(metaFiles, lastMetaFile, arg);
  RETURN TRUE
END AddMetaFile;

PROCEDURE AddBefore(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddTo(before, lastBefore, arg);
  RETURN TRUE
END AddBefore;

PROCEDURE AddAfter(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddTo(after, lastAfter, arg);
  RETURN TRUE
END AddAfter;

PROCEDURE AddHeader(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddTo(header, lastHeader, arg);
  RETURN TRUE
END AddHeader;

PROCEDURE SetStandalone(): BOOLEAN;
BEGIN
  standalone := TRUE;
  RETURN TRUE
END SetStandalone;

(* --template: implies -s *)
PROCEDURE SetTemplate(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, template); standalone := TRUE;
  RETURN TRUE
END SetTemplate;

(* -V KEY[=VALUE] *)
PROCEDURE AddVariable(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  C.SetVariable(arg);
  RETURN TRUE
END AddVariable;

(* -M KEY[=VALUE], or KEY[:VALUE]: sets KEY to VALUE, true by default,
   as pandoc's readMetaValue reads it: true and false, in lower, title
   or upper case, are booleans, the rest strings. A key given again
   becomes a list of its values. *)
PROCEDURE AddMeta(VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR i, j: LONGINT; key, val: String; v, old: A.MetaValue;
    l: A.MetaListV;
BEGIN
  i := 0;
  WHILE (arg[i] # 0X) & (arg[i] # ":") & (arg[i] # "=") DO
    key[i] := arg[i]; INC(i)
  END;
  key[i] := 0X;
  IF arg[i] = 0X THEN val := "true"
  ELSE
    INC(i); j := 0;
    WHILE arg[i] # 0X DO val[j] := arg[i]; INC(i); INC(j) END;
    val[j] := 0X
  END;
  IF (val = "true") OR (val = "True") OR (val = "TRUE") THEN
    v := A.NewMetaBool(TRUE)
  ELSIF (val = "false") OR (val = "False") OR (val = "FALSE") THEN
    v := A.NewMetaBool(FALSE)
  ELSE
    v := A.NewMetaString(A.S(val))
  END;
  old := A.GetMeta(cmdMeta, key);
  IF old = NIL THEN A.SetMeta(cmdMeta, A.S(key), v)
  ELSIF old IS A.MetaListV THEN A.AddMetaItem(old(A.MetaListV), v)
  ELSE
    l := A.NewMetaList(); A.AddMetaItem(l, old); A.AddMetaItem(l, v);
    A.SetMeta(cmdMeta, A.S(key), l)
  END;
  RETURN TRUE
END AddMeta;

(* --wrap: auto, none or preserve *)
PROCEDURE SetWrap(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  IF (arg # "auto") & (arg # "none") & (arg # "preserve") THEN
    PdIO.Message("--wrap must be auto, none, or preserve");
    PdIO.Exit(PdIO.OptionError)
  END;
  COPY(arg, wrap);
  RETURN TRUE
END SetWrap;

(* --columns: a number greater than 0, perhaps between spaces, as
   pandoc's safeStrRead reads it *)
PROCEDURE SetColumns(VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR i, n: LONGINT; ok: BOOLEAN;
BEGIN
  i := 0; n := 0; ok := FALSE;
  WHILE (i < LEN(arg)) & ((arg[i] = " ") OR (arg[i] = 9X) OR (arg[i] = 0AX)) DO INC(i) END;
  WHILE (i < LEN(arg)) & (arg[i] >= "0") & (arg[i] <= "9") & (n <= 99999999) DO
    n := n * 10 + ORD(arg[i]) - ORD("0"); ok := TRUE; INC(i)
  END;
  WHILE (i < LEN(arg)) & ((arg[i] = " ") OR (arg[i] = 9X) OR (arg[i] = 0AX)) DO INC(i) END;
  IF ~ok OR (n = 0) OR (i < LEN(arg)) & (arg[i] # 0X) THEN
    PdIO.Message("Argument of --columns must be a number greater than 0");
    PdIO.Exit(PdIO.OptionError)
  END;
  columns := n;
  RETURN TRUE
END SetColumns;

PROCEDURE SetIdPrefix(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, idPrefix);
  RETURN TRUE
END SetIdPrefix;

PROCEDURE SetExtractMedia(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, extractMedia);
  RETURN TRUE
END SetExtractMedia;

PROCEDURE SetNumberSections(): BOOLEAN;
BEGIN
  numberSections := TRUE;
  RETURN TRUE
END SetNumberSections;

(* --css: adds a URL to the variable css *)
PROCEDURE AddCss(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  C.AddListString("css", arg);
  RETURN TRUE
END AddCss;

(* --pdf-engine: groff, pdfroff or context, by base name; pandoc's
   other engines make PDF from writers podoc does not have *)
PROCEDURE SetPdfEngine(VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR b: String;
BEGIN
  BaseName(arg, b);
  IF (b # "groff") & (b # "pdfroff") & (b # "context") THEN
    PdIO.Message("Argument of --pdf-engine must be one of");
    PdIO.Message("	groff"); PdIO.Message("	pdfroff"); PdIO.Message("	context");
    PdIO.Exit(PdIO.OptionError)
  END;
  COPY(arg, pdfEngine);
  RETURN TRUE
END SetPdfEngine;

PROCEDURE AddPdfEngineOpt(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddTo(pdfEngineOpts, lastOpt, arg);
  RETURN TRUE
END AddPdfEngineOpt;

PROCEDURE AddFilter(kind: INTEGER; VAR arg: ARRAY OF CHAR);
  VAR f: Filter;
BEGIN
  NEW(f); f.kind := kind; f.name := NewName(arg); f.next := NIL;
  IF filters = NIL THEN filters := f ELSE lastFilter.next := f END;
  lastFilter := f
END AddFilter;

PROCEDURE AddLuaFilter(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddFilter(LuaFilter, arg);
  RETURN TRUE
END AddLuaFilter;

PROCEDURE AddJsonFilter(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  AddFilter(JsonFilter, arg);
  RETURN TRUE
END AddJsonFilter;

PROCEDURE SetToc(): BOOLEAN;
BEGIN
  toc := TRUE;
  RETURN TRUE
END SetToc;

PROCEDURE SetTocDepth(n: LONGINT): BOOLEAN;
BEGIN
  tocDepth := SHORT(n);
  RETURN TRUE
END SetTocDepth;

(* Parses the command line into the variables above. --help and
   --version set done. *)
PROCEDURE Parse*;
BEGIN
  parser := ArgParser.NewParser("podoc [OPTIONS] [FILES]", AddInput);
  parser.AddOption(ArgParser.MakeStringOption("f", "from",
    "The input format: markdown.", SetFrom));
  parser.AddOption(ArgParser.MakeStringOption("r", "read",
    "The same as --from.", SetFrom));
  parser.AddOption(ArgParser.MakeStringOption("t", "to",
    "The output format: html, html5, ms, context, markdown, json or pdf.", SetTo));
  parser.AddOption(ArgParser.MakeStringOption("w", "write",
    "The same as --to.", SetTo));
  parser.AddOption(ArgParser.MakeStringOption("o", "output",
    "Write to FILE rather than standard output; its extension can name the format.", SetOutput));
  parser.AddOption(ArgParser.MakeStringOption("M", "metadata",
    "Set the metadata field KEY to VALUE (KEY[=VALUE]).", AddMeta));
  parser.AddOption(ArgParser.MakeStringOption(0X, "metadata-file",
    "Read metadata from the YAML file FILE.", AddMetaFile));
  parser.AddOption(ArgParser.MakeOption("s", "standalone",
    "Write a whole document, with the template.", SetStandalone));
  parser.AddOption(ArgParser.MakeStringOption(0X, "template",
    "Use the template FILE (implies -s).", SetTemplate));
  parser.AddOption(ArgParser.MakeStringOption("V", "variable",
    "Set the template variable KEY to VALUE (KEY[=VALUE]).", AddVariable));
  parser.AddOption(ArgParser.MakeStringOption("H", "include-in-header",
    "Put the contents of FILE in the header (header-includes).", AddHeader));
  parser.AddOption(ArgParser.MakeStringOption("B", "include-before-body",
    "Put the contents of FILE at the start of the body.", AddBefore));
  parser.AddOption(ArgParser.MakeStringOption("A", "include-after-body",
    "Put the contents of FILE at the end of the body.", AddAfter));
  parser.AddOption(ArgParser.MakeOption("N", "number-sections",
    "Number the sections' headings.", SetNumberSections));
  parser.AddOption(ArgParser.MakeOption(0X, "toc",
    "Write a table of contents (with -s).", SetToc));
  parser.AddOption(ArgParser.MakeOption(0X, "table-of-contents",
    "The same as --toc.", SetToc));
  parser.AddOption(ArgParser.MakeIntOption(0X, "toc-depth",
    "Put headings of levels 1 to N in the table of contents (3).", SetTocDepth, 1, 6));
  parser.AddOption(ArgParser.MakeStringOption("c", "css",
    "Link to the style sheet URL (HTML, with -s).", AddCss));
  parser.AddOption(ArgParser.MakeStringOption(0X, "id-prefix",
    "Put STRING before every identifier (HTML).", SetIdPrefix));
  parser.AddOption(ArgParser.MakeStringOption(0X, "extract-media",
    "Copy local images into DIR and refer to the copies.", SetExtractMedia));
  parser.AddOption(ArgParser.MakeStringOption(0X, "pdf-engine",
    "Make PDF with PROGRAM: pdfroff or groff (ms), or context.", SetPdfEngine));
  parser.AddOption(ArgParser.MakeStringOption(0X, "pdf-engine-opt",
    "Pass STRING to the PDF engine.", AddPdfEngineOpt));
  parser.AddOption(ArgParser.MakeStringOption("L", "lua-filter",
    "Run the built-in filter that replaces the Lua filter FILE.", AddLuaFilter));
  parser.AddOption(ArgParser.MakeStringOption("F", "filter",
    "Run the built-in filter that replaces the filter PROGRAM.", AddJsonFilter));
  parser.AddOption(ArgParser.MakeStringOption(0X, "wrap",
    "How to wrap lines: auto, none or preserve.", SetWrap));
  parser.AddOption(ArgParser.MakeStringOption(0X, "columns",
    "Wrap lines at N columns (72).", SetColumns));
  parser.AddOption(ArgParser.MakeIntOption(0X, "tab-stop",
    "Expand tabs to every N columns (4).", SetTabStop, 1, 1000));
  parser.AddOption(ArgParser.MakeOption("p", "preserve-tabs",
    "Keep tabs as they are.", PreserveTabs));
  parser.AddOption(ArgParser.MakeOption("v", "version",
    "Show podoc's version.", ShowVersion));
  parser.AddOption(ArgParser.MakeOption("h", "help",
    "Show this help.", Help));
  parser.ParseArguments(1)
END Parse;

(* Warns as pandoc's CouldNotDeduceFormat: exts is the extensions, with
   " or " between them *)
PROCEDURE CouldNotDeduce(exts, fmt: ARRAY OF CHAR);
  VAR m: ARRAY 4096 OF CHAR;
BEGIN
  COPY("[WARNING] Could not deduce format from file extension ", m);
  Append(exts, m);
  PdIO.Message(m);
  COPY("  Defaulting to ", m); Append(fmt, m);
  PdIO.Message(m)
END CouldNotDeduce;

(* The extensions in spec from i on, as pandoc's parseFlavoredFormat
   and applyExtensionsDiff take them: each +ext enables ext and each
   -ext disables it, and an extension enabled anywhere is on, whatever
   disables it. a and b are the extensions the format takes ("" for
   none); on is a's state, its default on entry. Returns FALSE, with
   bad the extension, at the first that is neither a nor b. *)
PROCEDURE Extensions(spec: ARRAY OF CHAR; i: LONGINT; a, b: ARRAY OF CHAR;
                     VAR on: BOOLEAN; VAR bad: ARRAY OF CHAR): BOOLEAN;
  VAR j: LONGINT; ext: String; plus, enabled, disabled: BOOLEAN;
BEGIN
  enabled := FALSE; disabled := FALSE;
  WHILE spec[i] # 0X DO
    plus := spec[i] = "+"; INC(i); j := 0;
    WHILE (spec[i] # 0X) & (spec[i] # "+") & (spec[i] # "-") DO
      ext[j] := spec[i]; INC(i); INC(j)
    END;
    ext[j] := 0X;
    IF (a # "") & (ext = a) THEN
      IF plus THEN enabled := TRUE ELSE disabled := TRUE END
    ELSIF (b = "") OR (ext # b) THEN COPY(ext, bad); RETURN FALSE
    END
  END;
  on := enabled OR on & ~disabled;
  RETURN TRUE
END Extensions;

(* name := spec up to its first + or -; returns where that is *)
PROCEDURE FormatName(spec: ARRAY OF CHAR; VAR name: ARRAY OF CHAR): LONGINT;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (spec[i] # 0X) & (spec[i] # "+") & (spec[i] # "-") DO
    name[i] := spec[i]; INC(i)
  END;
  name[i] := 0X;
  RETURN i
END FormatName;

(* Ends podoc if the reader is not markdown: 21 for another format, 23
   for an extension of markdown that podoc does not take. grid_tables
   sets gridTables; gutenberg, which pandoc's reader ignores, is
   taken and ignored. *)
PROCEDURE CheckReader;
  VAR i: LONGINT; name, ext: String;
BEGIN
  i := FormatName(from, name);
  IF name # "markdown" THEN
    PdIO.Message3("Unknown input format '", name, "'");
    PdIO.Exit(PdIO.UnknownReader)
  END;
  IF ~Extensions(from, i, "grid_tables", "gutenberg", gridTables, ext) THEN
    PdIO.Message3("The extension '", ext, "' is not supported by podoc.");
    PdIO.Exit(PdIO.UnsupportedExtension)
  END
END CheckReader;

(* Ends podoc with 23 if toExts, the writer's extensions, has one that
   podoc does not take: gutenberg for plain, which sets gutenberg, and
   for markdown, where pandoc ignores it. For another writer gutenberg
   gets pandoc's message. *)
PROCEDURE CheckWriter(VAR name, toExts: ARRAY OF CHAR);
  VAR ext: String; m: ARRAY 4096 OF CHAR; ok: BOOLEAN;
BEGIN
  gutenberg := FALSE;
  IF (to = "plain") OR (to = "markdown") THEN
    ok := Extensions(toExts, 0, "gutenberg", "", gutenberg, ext);
    IF to = "markdown" THEN gutenberg := FALSE END
  ELSE ok := Extensions(toExts, 0, "", "", gutenberg, ext)
  END;
  IF ~ok THEN
    IF ext = "gutenberg" THEN
      COPY("The extension 'gutenberg' is not supported for ", m);
      Append(name, m); Append(".", m); PdIO.Message(m);
      COPY("Use --list-extensions=", m); Append(name, m);
      Append(" to list supported extensions.", m); PdIO.Message(m)
    ELSE
      PdIO.Message3("The extension '", ext, "' is not supported by podoc.")
    END;
    PdIO.Exit(PdIO.UnsupportedExtension)
  END
END CheckWriter;

(* Checks the filters, by their file names: podoc runs built-in code
   in place of the user's filters (pandoc-include, given with --filter;
   subs.lua, strip-comments.lua, general.lua, toc-columns.lua and
   combine-docs.lua, given with --lua-filter), ignores
   pandoc-mermaid-selenium-filter with a warning (decision 4), and ends
   with pandoc's message and status for a failed filter, 83, at any
   other, or at one of these given with the other option. The filters
   left in filters are those podoc runs. *)
PROCEDURE CheckFilters;
  VAR f, next: Filter; n: String; m: ARRAY 4096 OF CHAR;
BEGIN
  f := filters; filters := NIL; lastFilter := NIL;
  WHILE f # NIL DO
    next := f.next; f.next := NIL;
    FileName(f.name^, n);
    IF n = "pandoc-mermaid-selenium-filter" THEN
      COPY("[WARNING] podoc ignores the filter ", m); Append(f.name^, m);
      PdIO.Message(m)
    ELSIF (n = "pandoc-include") & (f.kind = JsonFilter)
       OR ((n = "subs.lua") OR (n = "strip-comments.lua")
           OR (n = "general.lua") OR (n = "toc-columns.lua")
           OR (n = "combine-docs.lua")) & (f.kind = LuaFilter) THEN
      IF filters = NIL THEN filters := f ELSE lastFilter.next := f END;
      lastFilter := f
    ELSIF n = "pandoc-include" THEN (* given to --lua-filter *)
      COPY("Error running filter '", m); Append(f.name^, m); Append("':", m);
      PdIO.Message(m);
      PdIO.Fail("cannot open pandoc-include", "No such file or directory", PdIO.FilterError)
    ELSIF (n = "subs.lua") OR (n = "strip-comments.lua")
       OR (n = "general.lua") OR (n = "toc-columns.lua")
       OR (n = "combine-docs.lua") THEN (* given to --filter *)
      COPY("Error running filter '", m); Append(f.name^, m); Append("':", m);
      PdIO.Message(m);
      COPY("Could not find executable ", m); Append(f.name^, m);
      PdIO.Message(m);
      PdIO.Exit(PdIO.FilterError)
    ELSE
      COPY("Error running filter '", m); Append(f.name^, m); Append("':", m);
      PdIO.Message(m);
      PdIO.Message("podoc has no built-in filter in its place");
      PdIO.Exit(PdIO.FilterError)
    END;
    f := next
  END
END CheckFilters;

(* Works out the input and output formats from the options and the
   files' names, as pandoc does, and ends podoc with pandoc's message
   and status if they are not ones podoc has: from becomes "markdown";
   to becomes the writer (html, ms, context, markdown, plain, json or podoc's
   source) and pdf whether its output is made into PDF, with pdfEngine
   the engine. *)
PROCEDURE Resolve*;
  VAR f: File; fmt, exts, w, e, toExts: String; err: ARRAY 4096 OF CHAR;
    i, j: LONGINT;
BEGIN
  IF from = "" THEN
    f := files; exts := "";
    WHILE (f # NIL) & (from = "") DO
      FormatFromPath(f.name^, from);
      IF f # files THEN Append(" or ", exts) END;
      Extension(f.name^, fmt); Append(fmt, exts);
      f := f.next
    END;
    IF from = "" THEN
      IF (files # NIL) & ((files.name^ # "-") OR (files.next # NIL)) THEN
        CouldNotDeduce(exts, "markdown")
      END;
      from := "markdown"
    END
  END;
  CheckReader;
  (* -t's extensions apart; checked once the writer is known *)
  i := FormatName(to, fmt); j := 0;
  WHILE to[i] # 0X DO toExts[j] := to[i]; INC(i); INC(j) END;
  toExts[j] := 0X; COPY(fmt, to);
  Extension(output, fmt);
  pdf := (fmt = ".pdf") OR (to = "pdf");
  IF pdf THEN
    IF to = "pdf" THEN to := "" END;
    IF ~PdfWriterAndEngine(to, pdfEngine, w, e, err) THEN
      PdIO.Message(err); PdIO.Exit(PdIO.AppError)
    END;
    BaseName(e, fmt);
    IF (fmt # "groff") & (fmt # "pdfroff") & (fmt # "context") THEN
      COPY("podoc makes PDF only with -t ms (groff, pdfroff) or -t context (context), not with ", err);
      Append(e, err);
      PdIO.Message(err); PdIO.Exit(PdIO.AppError)
    END;
    COPY(w, to); COPY(e, pdfEngine);
    standalone := TRUE
  ELSIF to = "" THEN
    IF (output = "") OR (output = "-") THEN to := "html"
    ELSE
      FormatFromPath(output, to);
      IF to = "" THEN CouldNotDeduce(fmt, "html"); to := "html" END
    END
  END;
  COPY(to, filterFormat);
  IF to = "html5" THEN to := "html" END;
  IF (to # "source") & (to # "json") & (to # "html") & (to # "ms")
     & (to # "context") & (to # "markdown") & (to # "plain") THEN
    PdIO.Message3("Unknown output format '", to, "'");
    PdIO.Exit(PdIO.UnknownWriter)
  END;
  CheckWriter(filterFormat, toExts);
  CheckFilters
END Resolve;

BEGIN
  files := NIL; lastFile := NIL; metaFiles := NIL; lastMetaFile := NIL;
  cmdMeta := A.NewMetaMap();
  output := ""; from := ""; gridTables := TRUE; to := ""; gutenberg := FALSE; pdf := FALSE;
  pdfEngine := ""; extractMedia := "";
  pdfEngineOpts := NIL; lastOpt := NIL; filters := NIL; lastFilter := NIL;
  tabStop := DefaultTabStop; done := FALSE;
  standalone := FALSE; template := "";
  wrap := "auto"; columns := 72; idPrefix := ""; numberSections := FALSE; toc := FALSE; tocDepth := 3;
  before := NIL; lastBefore := NIL; after := NIL; lastAfter := NIL;
  header := NIL; lastHeader := NIL
END PdOptions.
