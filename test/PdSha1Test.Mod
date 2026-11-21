MODULE PdSha1Test;
(* Tests of PdSha1, against the digests of sha1sum and FIPS 180-4's
   examples *)

IMPORT Out, S := PdSha1;

VAR failures: INTEGER; buf: ARRAY 1000001 OF CHAR;

PROCEDURE Report(ok: BOOLEAN; name: ARRAY OF CHAR);
BEGIN
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(name); Out.Ln
END Report;

(* The digest of the first len bytes of s is want *)
PROCEDURE T(name: ARRAY OF CHAR; s: ARRAY OF CHAR; len: LONGINT; want: ARRAY OF CHAR);
  VAR hex: ARRAY 41 OF CHAR;
BEGIN
  S.Hex(s, len, hex);
  IF hex # want THEN Out.String("  got "); Out.String(hex); Out.Ln END;
  Report(hex = want, name)
END T;

PROCEDURE Million;
  VAR i: LONGINT; hex: ARRAY 41 OF CHAR;
BEGIN
  FOR i := 0 TO 999999 DO buf[i] := "a" END;
  S.Hex(buf, 1000000, hex);
  Report(hex = "34aa973cd4c4daa4f61eeb2bdbad27316534016f", "a million a")
END Million;

PROCEDURE Bytes;
  VAR i: LONGINT; hex: ARRAY 41 OF CHAR;
BEGIN
  FOR i := 0 TO 255 DO buf[i] := CHR(i) END;
  S.Hex(buf, 256, hex);
  Report(hex = "4916d6bdb7f78e6803698cab32d1586ea457dfc8", "bytes 0 to 255")
END Bytes;

BEGIN
  failures := 0;
  T("empty", "", 0, "da39a3ee5e6b4b0d3255bfef95601890afd80709");
  T("abc", "abc", 3, "a9993e364706816aba3e25717850c26c9cd0d89d");
  T("two blocks", "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56,
    "84983e441c3bd26ebaae4aa1f95129e5e54670f1");
  T("55 bytes", "0123456789012345678901234567890123456789012345678901234", 55,
    "9f3a4ce7f66b1b74c34da2c5d732c39f81e0f8df");
  T("64 bytes", "0123456789012345678901234567890123456789012345678901234567890123", 64,
    "cf0800f7644ace3cb4c3fa33388d3ba0ea3c8b6e");
  Million;
  Bytes;
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdSha1Test.
