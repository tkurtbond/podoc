MODULE PdIO;
(* PdIO: podoc's input and output, and its messages.

   Input is read whole into a flat array of bytes (a Text). Output goes
   to standard output or to one file, through a buffer, as strings,
   characters and Ropes. A message is written to standard error as
   "podoc: ..."; Fail writes one and ends the program with one of
   pandoc's exit codes, so that a build sees the same status from
   podoc as from pandoc. *)

IMPORT SYSTEM, Platform, Err, Out, Ropes;

CONST
  (* pandoc's exit codes, from Text.Pandoc.Error *)
  IOError* = 1;
  AppError* = 4;
  TemplateError* = 5;
  OptionError* = 6;
  UnknownReader* = 21;
  UnknownWriter* = 22;
  ParseError* = 64;
  CouldNotFindDataFile* = 97;
  CouldNotFindMetadataFile* = 98;
  ResourceNotFound* = 99;

  BufSize = 8192;
  ReadChunk = 65536;

TYPE
  (* A text read whole: its bytes are t[0 .. len-1], len kept apart. *)
  Text* = POINTER TO ARRAY OF CHAR;

VAR
  out: Platform.FileHandle;
  outIsFile: BOOLEAN;
  outName: ARRAY 4096 OF CHAR;
  buf: ARRAY BufSize OF CHAR;
  bufLen: LONGINT;

(* Messages *)

(* Writes "podoc: " to standard error, to start a message. *)
PROCEDURE Start;
BEGIN
  Out.Flush;
  Err.String("podoc: ")
END Start;

(* Writes "podoc: msg" and a new line to standard error. *)
PROCEDURE Message*(msg: ARRAY OF CHAR);
BEGIN
  Start; Err.String(msg); Err.Ln; Err.Flush
END Message;

(* Writes "podoc: abc", the strings a, b and c, and a new line to
   standard error. *)
PROCEDURE Message3*(a, b, c: ARRAY OF CHAR);
BEGIN
  Start; Err.String(a); Err.String(b); Err.String(c); Err.Ln; Err.Flush
END Message3;

(* Writes "podoc: [WARNING] msg" and a new line to standard error. *)
PROCEDURE Warn*(msg: ARRAY OF CHAR);
BEGIN
  Start; Err.String("[WARNING] "); Err.String(msg); Err.Ln; Err.Flush
END Warn;

(* Ends the program with the exit status code, after writing what is
   buffered for standard output. *)
PROCEDURE Exit*(code: INTEGER);
BEGIN
  Out.Flush; Err.Flush;
  Platform.Exit(code)
END Exit;

(* Writes "podoc: name: msg" to standard error and ends the program with
   the exit status code; name is left out when it is empty. *)
PROCEDURE Fail*(name, msg: ARRAY OF CHAR; code: INTEGER);
BEGIN
  Start;
  IF name # "" THEN Err.String(name); Err.String(": ") END;
  Err.String(msg); Err.Ln;
  Exit(code)
END Fail;

(* Input *)

(* Makes t hold at least need bytes, keeping its first len; t may be
   NIL. *)
PROCEDURE Reserve*(VAR t: Text; len, need: LONGINT);
  VAR n: Text; size, i: LONGINT;
BEGIN
  IF t = NIL THEN size := ReadChunk ELSE size := LEN(t^) END;
  WHILE size < need DO size := size * 2 END;
  IF (t = NIL) OR (size > LEN(t^)) THEN
    NEW(n, size);
    i := 0; WHILE i < len DO n[i] := t[i]; INC(i) END;
    t := n
  END
END Reserve;

(* Reads all of h into t; len is how many bytes. *)
PROCEDURE ReadHandle(h: Platform.FileHandle; VAR t: Text; VAR len: LONGINT): Platform.ErrorCode;
  VAR n: LONGINT; e: Platform.ErrorCode;
BEGIN
  t := NIL; len := 0;
  LOOP
    IF (t = NIL) OR (LEN(t^) - len < ReadChunk) THEN Reserve(t, len, len + ReadChunk) END;
    e := Platform.Read(h, SYSTEM.ADR(t[len]), LEN(t^) - len, n);
    IF e # 0 THEN
      IF ~Platform.Interrupted(e) THEN RETURN e END
    ELSIF n = 0 THEN
      EXIT
    ELSE
      INC(len, n)
    END
  END;
  RETURN 0
END ReadHandle;

(* Whether the file name exists (it may still be unreadable). *)
PROCEDURE Exists*(name: ARRAY OF CHAR): BOOLEAN;
  VAR h: Platform.FileHandle; e: Platform.ErrorCode;
    n: ARRAY 4096 OF CHAR;
BEGIN
  COPY(name, n);
  e := Platform.OldRO(n, h);
  IF e # 0 THEN RETURN ~Platform.Absent(e) END;
  e := Platform.Close(h);
  RETURN TRUE
END Exists;

(* Reads the file name, or standard input when name is "-", whole into
   t; len is its length in bytes. A file that cannot be read ends the
   program with a message and IOError. *)
PROCEDURE ReadFile*(name: ARRAY OF CHAR; VAR t: Text; VAR len: LONGINT);
  VAR h: Platform.FileHandle; e, e2: Platform.ErrorCode;
    n: ARRAY 4096 OF CHAR;
BEGIN
  IF name = "-" THEN
    e := ReadHandle(Platform.StdIn, t, len);
    IF e # 0 THEN Fail("standard input", "cannot be read", IOError) END
  ELSE
    COPY(name, n);
    e := Platform.OldRO(n, h);
    IF e # 0 THEN
      IF Platform.Absent(e) THEN Fail(name, "does not exist", IOError)
      ELSE Fail(name, "cannot be opened", IOError)
      END
    END;
    e := ReadHandle(h, t, len);
    e2 := Platform.Close(h);
    IF e # 0 THEN Fail(name, "cannot be read", IOError) END
  END
END ReadFile;

(* Output *)

(* Ends the program because the output cannot be written. *)
PROCEDURE WriteFailed;
BEGIN
  bufLen := 0;
  IF outIsFile THEN Fail(outName, "cannot be written", IOError)
  ELSE Fail("standard output", "cannot be written", IOError)
  END
END WriteFailed;

(* Sends what is buffered to the output. *)
PROCEDURE FlushBuf;
BEGIN
  IF bufLen > 0 THEN
    IF Platform.Write(out, SYSTEM.ADR(buf[0]), bufLen) # 0 THEN WriteFailed END;
    bufLen := 0
  END
END FlushBuf;

(* Makes the file name the output, or standard output when name is "" or
   "-". The file is created, or emptied if it is there. *)
PROCEDURE OpenOutput*(name: ARRAY OF CHAR);
  VAR e: Platform.ErrorCode;
BEGIN
  FlushBuf;
  IF (name = "") OR (name = "-") THEN
    out := Platform.StdOut; outIsFile := FALSE; outName := ""
  ELSE
    COPY(name, outName);
    e := Platform.New(outName, out);
    IF e # 0 THEN Fail(name, "cannot be created", IOError) END;
    outIsFile := TRUE
  END
END OpenOutput;

(* Writes the bytes t[start .. start+len-1]. *)
PROCEDURE WriteChars*(VAR t: ARRAY OF CHAR; start, len: LONGINT);
BEGIN
  IF len >= BufSize THEN
    FlushBuf;
    IF Platform.Write(out, SYSTEM.ADR(t[start]), len) # 0 THEN WriteFailed END
  ELSE
    IF bufLen + len > BufSize THEN FlushBuf END;
    WHILE len > 0 DO buf[bufLen] := t[start]; INC(bufLen); INC(start); DEC(len) END
  END
END WriteChars;

(* Writes the character ch. *)
PROCEDURE WriteChar*(ch: CHAR);
BEGIN
  IF bufLen = BufSize THEN FlushBuf END;
  buf[bufLen] := ch; INC(bufLen)
END WriteChar;

(* Writes the string s, up to its 0X. *)
PROCEDURE WriteString*(s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO WriteChar(s[i]); INC(i) END
END WriteString;

(* Writes a new line. *)
PROCEDURE WriteLn*;
BEGIN
  WriteChar(0AX)
END WriteLn;

(* A chunk is all LEN(chunk) characters of a leaf, with no 0X after. *)
PROCEDURE VisitChunk(VAR chunk: ARRAY OF CHAR): BOOLEAN;
BEGIN
  WriteChars(chunk, 0, LEN(chunk));
  RETURN TRUE
END VisitChunk;

(* Writes the rope r. *)
PROCEDURE WriteRope*(r: Ropes.Rope);
BEGIN
  Ropes.IterateChunks(r, VisitChunk)
END WriteRope;

(* Writes what is buffered and closes the output if it is a file. *)
PROCEDURE CloseOutput*;
BEGIN
  FlushBuf;
  IF outIsFile THEN
    IF Platform.Close(out) # 0 THEN WriteFailed END;
    outIsFile := FALSE
  END;
  out := Platform.StdOut
END CloseOutput;

BEGIN
  out := Platform.StdOut; outIsFile := FALSE; outName := ""; bufLen := 0
END PdIO.
