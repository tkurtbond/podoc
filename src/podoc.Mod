MODULE podoc;
(* podoc: the parts of pandoc that the user's writing builds need, in
   Oberon-2. The command line is pandoc's: podoc [OPTIONS] [FILES].

   The inputs are joined as pandoc joins them. The "source" format
   writes them out unchanged; "json" reads them as pandoc markdown and
   writes the document as pandoc's JSON.

   The document's metadata is that of the metadata files, then of the
   document, then of -M, the later replacing the earlier, key by
   key.

   The template's variables are those of -V, then those podoc sets, as
   pandoc does: sourcefile, outputfile, pandoc-version, include-before
   (-B), include-after (-A), header-includes (-H) and curdir. *)

IMPORT Platform, ArgParser, PdIO, PdSource, A := PdAst, PdMarkdown, PdJson,
  T := PdTemplate, C := PdContext, PdHtml, PdMs, PdConTeXt, PdMdWriter;

CONST
  Version = "0.1";
  PandocVersion = "3.10"; (* the pandoc podoc follows *)
  DefaultTabStop = 4;

TYPE
  Name = POINTER TO ARRAY OF CHAR;
  File = POINTER TO FileDesc;
  FileDesc = RECORD
    name: Name;
    next: File
  END;

VAR
  parser: ArgParser.Parser;
  files, lastFile: File;
  metaFiles, lastMetaFile: File; (* --metadata-file *)
  cmdMeta: A.MetaMapV; (* -M *)
  output: ArgParser.String;
  to: ArgParser.String;
  tabStop: INTEGER;
  standalone: BOOLEAN; (* -s *)
  template: ArgParser.String; (* --template; "" for the default *)
  before, lastBefore, after, lastAfter, header, lastHeader: File; (* -B, -A, -H *)
  wrap: ArgParser.String; (* --wrap: auto, none or preserve *)
  idPrefix: ArgParser.String; (* --id-prefix *)
  numberSections: BOOLEAN; (* -N *)
  toc: BOOLEAN; (* --toc *)
  tocDepth: INTEGER; (* --toc-depth *)
  done: BOOLEAN; (* --help or --version was given: nothing else is done *)

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

PROCEDURE SetOutput(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, output);
  RETURN TRUE
END SetOutput;

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

(* A file named arg *)
PROCEDURE NewFile(VAR arg: ARRAY OF CHAR): File;
  VAR f: File; n: LONGINT;
BEGIN
  NEW(f);
  n := 0; WHILE arg[n] # 0X DO INC(n) END;
  NEW(f.name, n + 1);
  COPY(arg, f.name^);
  f.next := NIL;
  RETURN f
END NewFile;

(* Collects an input file; "-" is standard input. *)
PROCEDURE AddInput(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR f: File;
BEGIN
  f := NewFile(arg);
  IF files = NIL THEN files := f ELSE lastFile.next := f END;
  lastFile := f;
  RETURN TRUE
END AddInput;

(* --metadata-file: collects a metadata file *)
PROCEDURE AddMetaFile(VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR f: File;
BEGIN
  f := NewFile(arg);
  IF metaFiles = NIL THEN metaFiles := f ELSE lastMetaFile.next := f END;
  lastMetaFile := f;
  RETURN TRUE
END AddMetaFile;

(* Adds a file named arg to the list first .. last *)
PROCEDURE AddTo(VAR first, last: File; VAR arg: ARRAY OF CHAR);
  VAR f: File;
BEGIN
  f := NewFile(arg);
  IF first = NIL THEN first := f ELSE last.next := f END;
  last := f
END AddTo;

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
  VAR i, j: LONGINT; key, val: ArgParser.String; v, old: A.MetaValue;
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
    PdIO.Message3("Unknown option for wrap: '", arg, "'");
    PdIO.Exit(2)
  END;
  COPY(arg, wrap);
  RETURN TRUE
END SetWrap;

PROCEDURE SetIdPrefix(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  COPY(arg, idPrefix);
  RETURN TRUE
END SetIdPrefix;

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

(* --pdf-engine: sets the variable pdf-engine *)
PROCEDURE SetPdfEngine(VAR arg: ARRAY OF CHAR): BOOLEAN;
BEGIN
  C.SetVariableIfAbsent("pdf-engine", arg);
  RETURN TRUE
END SetPdfEngine;

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

PROCEDURE ParseCommandLine;
BEGIN
  parser := ArgParser.NewParser("podoc [OPTIONS] [FILES]", AddInput);
  parser.AddOption(ArgParser.MakeStringOption("o", "output",
    "Write to FILE rather than standard output.", SetOutput));
  parser.AddOption(ArgParser.MakeStringOption("t", "to",
    "The output format: html, html5, json or source.", SetTo));
  parser.AddOption(ArgParser.MakeStringOption("w", "write",
    "The same as --to.", SetTo));
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
  parser.AddOption(ArgParser.MakeStringOption(0X, "pdf-engine",
    "Use PROGRAM to make PDF (pdfroff, groff); ms writes PDF marks for it.", SetPdfEngine));
  parser.AddOption(ArgParser.MakeStringOption(0X, "wrap",
    "How to wrap lines: auto, none or preserve (podoc does not wrap).", SetWrap));
  parser.AddOption(ArgParser.MakeIntOption(0X, "tab-stop",
    "Expand tabs to every N columns (4).", SetTabStop, 1, 1000));
  parser.AddOption(ArgParser.MakeOption("p", "preserve-tabs",
    "Keep tabs as they are.", PreserveTabs));
  parser.AddOption(ArgParser.MakeOption("v", "version",
    "Show podoc's version.", ShowVersion));
  parser.AddOption(ArgParser.MakeOption("h", "help",
    "Show this help.", Help));
  parser.ParseArguments(1)
END ParseCommandLine;

(* Running *)

(* Sets the keys of the map from in the map to *)
PROCEDURE MergeMeta(to, from: A.MetaMapV);
  VAR e: A.MetaEntry;
BEGIN
  e := from.entries;
  WHILE e # NIL DO A.SetMeta(to, e.key, e.value); e := e.next END
END MergeMeta;

(* The document in text[0 .. len-1], with the metadata of the metadata
   files and -M *)
PROCEDURE ReadDoc(text: PdIO.Text; len: LONGINT): A.Doc;
  VAR m: A.MetaMapV; f: File; d: A.Doc;
BEGIN
  m := A.NewMetaMap();
  f := metaFiles;
  WHILE f # NIL DO
    MergeMeta(m, PdMarkdown.ReadMetaFile(f.name^, tabStop));
    f := f.next
  END;
  d := PdMarkdown.Read(text, len, tabStop);
  MergeMeta(m, d.meta); MergeMeta(m, cmdMeta);
  d.meta := m;
  RETURN d
END ReadDoc;

(* Adds the contents of the files to the list variable key *)
PROCEDURE AddFiles(key: ARRAY OF CHAR; f: File);
BEGIN
  WHILE f # NIL DO C.AddFileContents(key, f.name^); f := f.next END
END AddFiles;

(* The variables podoc sets, after -V, as pandoc's outputSettings sets
   them *)
PROCEDURE SetVariables;
  VAR f: File;
BEGIN
  IF files = NIL THEN C.AddListString("sourcefile", "-")
  ELSE
    f := files;
    WHILE f # NIL DO C.AddListString("sourcefile", f.name^); f := f.next END
  END;
  IF output = "" THEN C.SetVariableIfAbsent("outputfile", "-")
  ELSE C.SetVariableIfAbsent("outputfile", output)
  END;
  C.SetVariableIfAbsent("pandoc-version", PandocVersion);
  AddFiles("include-before", before);
  AddFiles("include-after", after);
  AddFiles("header-includes", header);
  C.SetVariableIfAbsent("curdir", Platform.CWD)
END SetVariables;

PROCEDURE Run;
  VAR text: PdIO.Text; len: LONGINT; f: File; tmpl: T.Template;
BEGIN
  IF to = "" THEN to := "source" END;
  IF to = "html5" THEN to := "html" END;
  IF (to # "source") & (to # "json") & (to # "html") & (to # "ms")
     & (to # "context") & (to # "markdown") THEN
    PdIO.Message3("Unknown output format '", to, "'");
    PdIO.Exit(PdIO.UnknownWriter)
  END;
  f := metaFiles;
  WHILE f # NIL DO
    IF ~PdIO.Exists(f.name^) THEN
      PdIO.Message3("Could not find metadata file '", f.name^, "'");
      PdIO.Exit(PdIO.CouldNotFindMetadataFile)
    END;
    f := f.next
  END;
  SetVariables;
  (* json has no default template, and writes none *)
  tmpl := NIL;
  IF standalone & (template # "") THEN C.Get(template, to, tmpl)
  ELSIF standalone & (to = "html") THEN C.GetDefault("html5", tmpl)
  ELSIF standalone & (to = "ms") THEN C.GetDefault("ms", tmpl)
  ELSIF standalone & (to = "context") THEN C.GetDefault("context", tmpl)
  ELSIF standalone & (to = "markdown") THEN C.GetDefault("markdown", tmpl)
  END;
  text := NIL; len := 0;
  IF files = NIL THEN
    PdSource.AddFile(text, len, "-", tabStop)
  ELSE
    f := files;
    WHILE f # NIL DO
      PdSource.AddFile(text, len, f.name^, tabStop);
      f := f.next
    END
  END;
  PdIO.OpenOutput(output);
  IF to = "json" THEN
    IF standalone THEN PdJson.WriteDocNoNl(ReadDoc(text, len))
    ELSE PdJson.WriteDoc(ReadDoc(text, len))
    END
  ELSIF to = "html" THEN
    IF files = NIL THEN
      PdHtml.SetOptions(idPrefix, numberSections, wrap = "preserve", toc, tocDepth, "-")
    ELSE
      PdHtml.SetOptions(idPrefix, numberSections, wrap = "preserve", toc, tocDepth, files.name^)
    END;
    PdHtml.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF to = "ms" THEN
    PdMs.SetOptions(numberSections, wrap = "preserve", toc, tocDepth);
    PdMs.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF to = "context" THEN
    PdConTeXt.SetOptions(numberSections, wrap = "preserve", toc, tocDepth);
    PdConTeXt.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF to = "markdown" THEN
    PdHtml.SetOptions(idPrefix, numberSections, FALSE, FALSE, tocDepth, "-");
    PdMdWriter.SetOptions(wrap = "preserve", toc, tocDepth, numberSections, idPrefix);
    PdMdWriter.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF len > 0 THEN
    PdIO.WriteChars(text^, 0, len)
  END;
  PdIO.CloseOutput
END Run;

BEGIN
  files := NIL; lastFile := NIL; metaFiles := NIL; lastMetaFile := NIL;
  cmdMeta := A.NewMetaMap();
  output := ""; to := ""; tabStop := DefaultTabStop; done := FALSE;
  standalone := FALSE; template := "";
  wrap := "auto"; idPrefix := ""; numberSections := FALSE; toc := FALSE; tocDepth := 3;
  before := NIL; lastBefore := NIL; after := NIL; lastAfter := NIL;
  header := NIL; lastHeader := NIL;
  ParseCommandLine;
  IF done THEN PdIO.CloseOutput ELSE Run END
END podoc.
