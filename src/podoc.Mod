MODULE podoc;
(* podoc: the parts of pandoc that the user's writing builds need, in
   Oberon-2. The command line is pandoc's: podoc [OPTIONS] [FILES];
   PdOptions reads it and works out the formats.

   The inputs are joined as pandoc joins them. The "source" format
   writes them out unchanged; the others read them as pandoc markdown.

   The document's metadata is that of the metadata files, then of the
   document, then of -M, the later replacing the earlier, key by
   key.

   The template's variables are those of -V, then those podoc sets, as
   pandoc does: sourcefile, outputfile, pandoc-version, pdf-engine,
   include-before (-B), include-after (-A), header-includes (-H) and
   curdir.

   The filters run in order on the document read: pandoc-include is
   PdInclude, the user's Lua filters are PdFilters. *)

IMPORT Platform, PdIO, PdSource, A := PdAst, PdMarkdown, PdJson,
  T := PdTemplate, C := PdContext, PdHtml, PdMs, PdConTeXt, PdMdWriter,
  PdInclude, PdFilters, O := PdOptions;

CONST
  PandocVersion = "3.10"; (* the pandoc podoc follows *)

(* Running *)

(* Sets the keys of the map from in the map to *)
PROCEDURE MergeMeta(to, from: A.MetaMapV);
  VAR e: A.MetaEntry;
BEGIN
  e := from.entries;
  WHILE e # NIL DO A.SetMeta(to, e.key, e.value); e := e.next END
END MergeMeta;

(* Runs the filters on the document d *)
PROCEDURE RunFilters(d: A.Doc);
  VAR f: O.Filter; n: O.String; i: O.File;
BEGIN
  f := O.filters;
  WHILE f # NIL DO
    O.FileName(f.name^, n);
    IF n = "pandoc-include" THEN
      i := O.files;
      WHILE i # NIL DO PdInclude.AddInput(i.name^); i := i.next END;
      PdInclude.Expand(d, f.name^)
    ELSIF n = "subs.lua" THEN PdFilters.Subs(d, f.name^)
    ELSIF n = "strip-comments.lua" THEN PdFilters.StripComments(d)
    ELSIF n = "general.lua" THEN PdFilters.General(d, O.filterFormat)
    ELSIF n = "toc-columns.lua" THEN PdFilters.TocColumns(d)
    ELSIF n = "combine-docs.lua" THEN PdFilters.CombineDocs(d, f.name^)
    END;
    f := f.next
  END
END RunFilters;

(* The document in text[0 .. len-1], with the metadata of the metadata
   files and -M *)
PROCEDURE ReadDoc(text: PdIO.Text; len: LONGINT): A.Doc;
  VAR m: A.MetaMapV; f: O.File; d: A.Doc;
BEGIN
  m := A.NewMetaMap();
  f := O.metaFiles;
  WHILE f # NIL DO
    MergeMeta(m, PdMarkdown.ReadMetaFile(f.name^, O.tabStop));
    f := f.next
  END;
  d := PdMarkdown.Read(text, len, O.tabStop);
  MergeMeta(m, d.meta); MergeMeta(m, O.cmdMeta);
  d.meta := m;
  RunFilters(d);
  RETURN d
END ReadDoc;

(* Adds the contents of the files to the list variable key *)
PROCEDURE AddFiles(key: ARRAY OF CHAR; f: O.File);
BEGIN
  WHILE f # NIL DO C.AddFileContents(key, f.name^); f := f.next END
END AddFiles;

(* The variables podoc sets, after -V, as pandoc's outputSettings sets
   them *)
PROCEDURE SetVariables;
  VAR f: O.File;
BEGIN
  IF O.files = NIL THEN C.AddListString("sourcefile", "-")
  ELSE
    f := O.files;
    WHILE f # NIL DO C.AddListString("sourcefile", f.name^); f := f.next END
  END;
  IF O.output = "" THEN C.SetVariableIfAbsent("outputfile", "-")
  ELSE C.SetVariableIfAbsent("outputfile", O.output)
  END;
  C.SetVariableIfAbsent("pandoc-version", PandocVersion);
  IF O.pdfEngine # "" THEN C.SetVariableIfAbsent("pdf-engine", O.pdfEngine) END;
  AddFiles("include-before", O.before);
  AddFiles("include-after", O.after);
  AddFiles("header-includes", O.header);
  C.SetVariableIfAbsent("curdir", Platform.CWD)
END SetVariables;

PROCEDURE Run;
  VAR text: PdIO.Text; len: LONGINT; f: O.File; tmpl: T.Template;
    to: O.String;
BEGIN
  O.Resolve;
  COPY(O.to, to);
  IF O.pdf THEN
    (* Phase 14 runs the engine *)
    PdIO.Message("podoc cannot make PDF yet");
    PdIO.Exit(PdIO.PDFError)
  END;
  f := O.metaFiles;
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
  IF O.standalone & (O.template # "") THEN C.Get(O.template, to, tmpl)
  ELSIF O.standalone & (to = "html") THEN C.GetDefault("html5", tmpl)
  ELSIF O.standalone & (to = "ms") THEN C.GetDefault("ms", tmpl)
  ELSIF O.standalone & (to = "context") THEN C.GetDefault("context", tmpl)
  ELSIF O.standalone & (to = "markdown") THEN C.GetDefault("markdown", tmpl)
  END;
  text := NIL; len := 0;
  IF O.files = NIL THEN
    PdSource.AddFile(text, len, "-", O.tabStop)
  ELSE
    f := O.files;
    WHILE f # NIL DO
      PdSource.AddFile(text, len, f.name^, O.tabStop);
      f := f.next
    END
  END;
  PdIO.OpenOutput(O.output);
  IF to = "json" THEN
    IF O.standalone THEN PdJson.WriteDocNoNl(ReadDoc(text, len))
    ELSE PdJson.WriteDoc(ReadDoc(text, len))
    END
  ELSIF to = "html" THEN
    IF O.files = NIL THEN
      PdHtml.SetOptions(O.idPrefix, O.numberSections, O.wrap = "preserve", O.toc, O.tocDepth, "-")
    ELSE
      PdHtml.SetOptions(O.idPrefix, O.numberSections, O.wrap = "preserve", O.toc, O.tocDepth, O.files.name^)
    END;
    PdHtml.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF to = "ms" THEN
    PdMs.SetOptions(O.numberSections, O.wrap = "preserve", O.toc, O.tocDepth);
    PdMs.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF to = "context" THEN
    PdConTeXt.SetOptions(O.numberSections, O.wrap = "preserve", O.toc, O.tocDepth);
    PdConTeXt.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF to = "markdown" THEN
    PdHtml.SetOptions(O.idPrefix, O.numberSections, FALSE, FALSE, O.tocDepth, "-");
    PdMdWriter.SetOptions(O.wrap = "preserve", O.toc, O.tocDepth, O.numberSections, O.idPrefix);
    PdMdWriter.WriteDoc(ReadDoc(text, len), tmpl)
  ELSIF len > 0 THEN
    PdIO.WriteChars(text^, 0, len)
  END;
  PdIO.CloseOutput
END Run;

BEGIN
  O.Parse;
  IF O.done THEN PdIO.CloseOutput ELSE Run END
END podoc.
