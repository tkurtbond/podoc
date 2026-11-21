MODULE PdSha1;
(* PdSha1: the SHA-1 digest (FIPS 180-4) of bytes, as hexadecimal.
   pandoc names an extracted image whose path it cannot keep by the
   SHA-1 of its contents (Text.Pandoc.MediaBag.insertMedia). Words are
   SYSTEM.INT32 under both size models; their sums wrap around, and
   their bits are handled as SETs. *)

IMPORT SYSTEM;

TYPE
  Word = SYSTEM.INT32;

VAR
  h: ARRAY 5 OF Word;
  w: ARRAY 80 OF Word;

PROCEDURE Xor(a, b: Word): Word;
BEGIN RETURN SYSTEM.VAL(Word, SYSTEM.VAL(SET, a) / SYSTEM.VAL(SET, b))
END Xor;

PROCEDURE And(a, b: Word): Word;
BEGIN RETURN SYSTEM.VAL(Word, SYSTEM.VAL(SET, a) * SYSTEM.VAL(SET, b))
END And;

PROCEDURE Or(a, b: Word): Word;
BEGIN RETURN SYSTEM.VAL(Word, SYSTEM.VAL(SET, a) + SYSTEM.VAL(SET, b))
END Or;

PROCEDURE Not(a: Word): Word;
BEGIN RETURN SYSTEM.VAL(Word, -SYSTEM.VAL(SET, a))
END Not;

(* a rotated left by n bits *)
PROCEDURE Rol(a: Word; n: INTEGER): Word;
BEGIN RETURN SYSTEM.ROT(a, n)
END Rol;

(* The byte ch as a word *)
PROCEDURE Byte(ch: CHAR): Word;
  VAR v: Word;
BEGIN v := ORD(ch); RETURN v
END Byte;

(* Processes the 64-byte block b[0 .. 63] *)
PROCEDURE Block(VAR b: ARRAY OF CHAR);
  VAR i: INTEGER; a, bb, c, d, e, f, k, t: Word;
BEGIN
  FOR i := 0 TO 15 DO
    w[i] := Or(Or(SYSTEM.LSH(Byte(b[4 * i]), 24), SYSTEM.LSH(Byte(b[4 * i + 1]), 16)),
               Or(SYSTEM.LSH(Byte(b[4 * i + 2]), 8), Byte(b[4 * i + 3])))
  END;
  FOR i := 16 TO 79 DO
    w[i] := Rol(Xor(Xor(w[i - 3], w[i - 8]), Xor(w[i - 14], w[i - 16])), 1)
  END;
  a := h[0]; bb := h[1]; c := h[2]; d := h[3]; e := h[4];
  FOR i := 0 TO 79 DO
    IF i < 20 THEN f := Or(And(bb, c), And(Not(bb), d)); k := 5A827999H
    ELSIF i < 40 THEN f := Xor(Xor(bb, c), d); k := 6ED9EBA1H
    ELSIF i < 60 THEN f := Or(Or(And(bb, c), And(bb, d)), And(c, d)); k := SYSTEM.VAL(Word, 8F1BBCDCH)
    ELSE f := Xor(Xor(bb, c), d); k := SYSTEM.VAL(Word, 0CA62C1D6H)
    END;
    t := Rol(a, 5) + f + e + k + w[i];
    e := d; d := c; c := Rol(bb, 30); bb := a; a := t
  END;
  h[0] := h[0] + a; h[1] := h[1] + bb; h[2] := h[2] + c; h[3] := h[3] + d; h[4] := h[4] + e
END Block;

(* The low four bits of x *)
PROCEDURE Digit(x: Word): INTEGER;
BEGIN RETURN SHORT(x MOD 16)
END Digit;

(* Sets hex to the SHA-1 of the bytes t[0 .. len-1], as 40 lower-case
   hexadecimal digits; hex must hold 41 characters. *)
PROCEDURE Hex*(VAR t: ARRAY OF CHAR; len: LONGINT; VAR hex: ARRAY OF CHAR);
  VAR b: ARRAY 64 OF CHAR; i, n: LONGINT; j, k, d: INTEGER; bits: HUGEINT; x: Word;
BEGIN
  h[0] := 67452301H; h[1] := SYSTEM.VAL(Word, 0EFCDAB89H);
  h[2] := SYSTEM.VAL(Word, 98BADCFEH); h[3] := 10325476H;
  h[4] := SYSTEM.VAL(Word, 0C3D2E1F0H);
  i := 0;
  WHILE len - i >= 64 DO
    FOR j := 0 TO 63 DO b[j] := t[i + j] END;
    Block(b); INC(i, 64)
  END;
  n := len - i;
  j := 0; WHILE j < n DO b[j] := t[i + j]; INC(j) END;
  b[n] := 80X; INC(n);
  IF n > 56 THEN
    WHILE n < 64 DO b[n] := 0X; INC(n) END;
    Block(b); n := 0
  END;
  WHILE n < 56 DO b[n] := 0X; INC(n) END;
  bits := len; bits := bits * 8;
  FOR j := 63 TO 56 BY -1 DO b[j] := CHR(bits MOD 256); bits := bits DIV 256 END;
  Block(b);
  n := 0;
  FOR k := 0 TO 4 DO
    x := h[k];
    FOR j := 7 TO 0 BY -1 DO
      d := Digit(SYSTEM.LSH(x, -4 * j));
      IF d < 10 THEN hex[n] := CHR(ORD("0") + d) ELSE hex[n] := CHR(ORD("a") + d - 10) END;
      INC(n)
    END
  END;
  hex[n] := 0X
END Hex;

END PdSha1.
