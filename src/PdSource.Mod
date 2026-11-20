MODULE PdSource;
(* PdSource: the input text, prepared and joined as pandoc does before
   its reader sees it (Text.Pandoc.App.Input and Text.Pandoc.Sources).

   Each input, a file or standard input, has a UTF-8 byte order mark at
   its start dropped and every CR removed; its tabs are expanded to
   spaces at every tabStop columns, counted in characters, not bytes,
   and a last line without a new line is given one (pandoc's
   tabFilter, which with --preserve-tabs, tabStop 0, does neither);
   and then a new line is appended. The inputs are joined in order. *)

IMPORT PdIO;

(* Appends the input src[0 .. slen-1], prepared as above with the tab
   stop tabStop (0 keeps tabs), to dst[0 .. dlen-1]; dlen becomes the
   new length. dst may be NIL. *)
PROCEDURE Add*(VAR dst: PdIO.Text; VAR dlen: LONGINT;
               VAR src: ARRAY OF CHAR; slen: LONGINT; tabStop: INTEGER);
  VAR i, tabs, col, n, start: LONGINT; ch: CHAR;
BEGIN
  start := dlen; i := 0;
  IF (slen >= 3) & (src[0] = 0EFX) & (src[1] = 0BBX) & (src[2] = 0BFX) THEN
    i := 3
  END;
  tabs := 0; n := i;
  WHILE n < slen DO
    IF src[n] = 09X THEN INC(tabs) END;
    INC(n)
  END;
  IF tabStop > 0 THEN n := tabStop ELSE n := 1 END;
  PdIO.Reserve(dst, dlen, dlen + slen + tabs * (n - 1) + 2);
  col := 0;
  WHILE i < slen DO
    ch := src[i];
    IF ch = 0DX THEN
      (* removed *)
    ELSIF (ch = 09X) & (tabStop > 0) THEN
      n := tabStop - col MOD tabStop;
      INC(col, n);
      WHILE n > 0 DO dst[dlen] := " "; INC(dlen); DEC(n) END
    ELSE
      dst[dlen] := ch; INC(dlen);
      IF ch = 0AX THEN col := 0
      ELSIF (ORD(ch) < 80H) OR (ORD(ch) >= 0C0H) THEN INC(col)
        (* a UTF-8 continuation byte, 80H..0BFH, adds no column *)
      END
    END;
    INC(i)
  END;
  IF (tabStop > 0) & (dlen > start) & (dst[dlen - 1] # 0AX) THEN
    dst[dlen] := 0AX; INC(dlen)
  END;
  dst[dlen] := 0AX; INC(dlen)
END Add;

(* Reads the input name ("-" is standard input) and appends it, prepared
   as above, to dst[0 .. dlen-1]. A file that cannot be read ends the
   program with a message. *)
PROCEDURE AddFile*(VAR dst: PdIO.Text; VAR dlen: LONGINT;
                   name: ARRAY OF CHAR; tabStop: INTEGER);
  VAR t: PdIO.Text; len: LONGINT;
BEGIN
  PdIO.ReadFile(name, t, len);
  IF t = NIL THEN PdIO.Reserve(t, 0, 1) END;
  Add(dst, dlen, t^, len, tabStop)
END AddFile;

END PdSource.
