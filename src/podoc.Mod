MODULE podoc;
(* podoc: the parts of pandoc that the user's writing builds need, in
   Oberon-2. The command line is pandoc's: podoc [OPTIONS] [FILES].

   Phase 1: the inputs are joined as pandoc joins them and written out
   unchanged, the "source" format. *)

IMPORT ArgParser, PdIO, PdSource;

CONST
  Version = "0.1";
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
  output: ArgParser.String;
  to: ArgParser.String;
  tabStop: INTEGER;
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

(* Collects an input file; "-" is standard input. *)
PROCEDURE AddInput(startIdx: INTEGER; VAR arg: ARRAY OF CHAR): BOOLEAN;
  VAR f: File; n: LONGINT;
BEGIN
  NEW(f);
  n := 0; WHILE arg[n] # 0X DO INC(n) END;
  NEW(f.name, n + 1);
  COPY(arg, f.name^);
  f.next := NIL;
  IF files = NIL THEN files := f ELSE lastFile.next := f END;
  lastFile := f;
  RETURN TRUE
END AddInput;

PROCEDURE ParseCommandLine;
BEGIN
  parser := ArgParser.NewParser("podoc [OPTIONS] [FILES]", AddInput);
  parser.AddOption(ArgParser.MakeStringOption("o", "output",
    "Write to FILE rather than standard output.", SetOutput));
  parser.AddOption(ArgParser.MakeStringOption("t", "to",
    "The output format: source.", SetTo));
  parser.AddOption(ArgParser.MakeStringOption("w", "write",
    "The same as --to.", SetTo));
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

PROCEDURE Run;
  VAR text: PdIO.Text; len: LONGINT; f: File;
BEGIN
  IF to = "" THEN to := "source" END;
  IF to # "source" THEN
    PdIO.Message3("Unknown output format '", to, "'");
    PdIO.Exit(PdIO.UnknownWriter)
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
  IF len > 0 THEN PdIO.WriteChars(text^, 0, len) END;
  PdIO.CloseOutput
END Run;

BEGIN
  files := NIL; lastFile := NIL;
  output := ""; to := ""; tabStop := DefaultTabStop; done := FALSE;
  ParseCommandLine;
  IF done THEN PdIO.CloseOutput ELSE Run END
END podoc.
