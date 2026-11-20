MODULE PdWords;
(* PdWords: the URI schemes autolinks recognise and the abbreviations
   after which a space is non-breaking, as pandoc 3.10 has them.
   Written by tools/mkwords; do not edit. *)

IMPORT PdIO;

CONST
  Schemes = 268;
  Abbreviations = 80;
  WordLen = 31;

TYPE
  Word = ARRAY WordLen OF CHAR;

VAR
  schemes: ARRAY Schemes OF Word;
  abbrevs: ARRAY Abbreviations OF Word;
  ns, na: INTEGER;

(* Adds the words in s, each followed by a space, to the schemes if
   scheme, else to the abbreviations *)
PROCEDURE Add(scheme: BOOLEAN; s: ARRAY OF CHAR);
  VAR i, j: INTEGER; w: Word;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    j := 0;
    WHILE s[i] # " " DO w[j] := s[i]; INC(i); INC(j) END;
    w[j] := 0X; INC(i);
    IF scheme THEN schemes[ns] := w; INC(ns)
    ELSE abbrevs[na] := w; INC(na)
    END
  END
END Add;

PROCEDURE Lower(ch: CHAR): CHAR;
BEGIN
  IF (ch >= "A") & (ch <= "Z") THEN ch := CHR(ORD(ch) + 32) END;
  RETURN ch
END Lower;

(* The length of the longest URI scheme, ignoring ASCII case, that t
   has at p; 0 if there is none *)
PROCEDURE Scheme*(t: PdIO.Text; p: LONGINT): LONGINT;
  VAR i, j, best: LONGINT;
BEGIN
  best := 0;
  FOR i := 0 TO Schemes - 1 DO
    j := 0;
    WHILE (schemes[i][j] # 0X) & (Lower(t[p + j]) = schemes[i][j]) DO
      INC(j)
    END;
    IF (schemes[i][j] = 0X) & (j > best) THEN best := j END
  END;
  RETURN best
END Scheme;

(* Whether t[from .. to-1] is one of the abbreviations *)
PROCEDURE IsAbbreviation*(t: PdIO.Text; from, to: LONGINT): BOOLEAN;
  VAR i, j: LONGINT;
BEGIN
  IF to - from < WordLen THEN
    FOR i := 0 TO Abbreviations - 1 DO
      j := 0;
      WHILE (from + j < to) & (abbrevs[i][j] = t[from + j]) DO INC(j) END;
      IF (from + j = to) & (abbrevs[i][j] = 0X) THEN RETURN TRUE END
    END
  END;
  RETURN FALSE
END IsAbbreviation;

BEGIN
  ns := 0; na := 0;
  Add(TRUE, "aaa aaas about acap acct acr adiumxtra afp afs aim appdata apt ");
  Add(TRUE, "attachment aw barion beshare bitcoin blob bolo browserext ");
  Add(TRUE, "callto cap chrome chrome-extension cid coap coaps ");
  Add(TRUE, "com-eventbrite-attendee content crid cvs data dav dict dis ");
  Add(TRUE, "dlna-playcontainer dlna-playsingle dns dntp dtn dvb ed2k ");
  Add(TRUE, "example facetime fax feed feedready file filesystem finger fish ");
  Add(TRUE, "ftp geo gg git gizmoproject go gopher graph gtalk h323 ham hcp ");
  Add(TRUE, "http https hxxp hxxps hydrazone iax icap icon im imap info ");
  Add(TRUE, "iotdisco ipn ipp ipps irc irc6 ircs iris iris.beep iris.lwz ");
  Add(TRUE, "iris.xpc iris.xpcs isostore itms jabber jar jms keyparc lastfm ");
  Add(TRUE, "ldap ldaps lvlt magnet mailserver mailto maps market message ");
  Add(TRUE, "mid mms modem mongodb moz ms-access ms-browser-extension ");
  Add(TRUE, "ms-drive-to ms-enrollment ms-excel ms-gamebarservices ");
  Add(TRUE, "ms-getoffice ms-help ms-infopath ms-media-stream-id ");
  Add(TRUE, "ms-officeapp ms-project ms-powerpoint ms-publisher ");
  Add(TRUE, "ms-search-repair ms-secondary-screen-controller ");
  Add(TRUE, "ms-secondary-screen-setup ms-settings ms-settings-airplanemode ");
  Add(TRUE, "ms-settings-bluetooth ms-settings-camera ms-settings-cellular ");
  Add(TRUE, "ms-settings-cloudstorage ms-settings-connectabledevices ");
  Add(TRUE, "ms-settings-displays-topology ms-settings-emailandaccounts ");
  Add(TRUE, "ms-settings-language ms-settings-location ms-settings-lock ");
  Add(TRUE, "ms-settings-nfctransactions ms-settings-notifications ");
  Add(TRUE, "ms-settings-power ms-settings-privacy ms-settings-proximity ");
  Add(TRUE, "ms-settings-screenrotation ms-settings-wifi ");
  Add(TRUE, "ms-settings-workplace ms-spd ms-sttoverlay ms-transit-to ");
  Add(TRUE, "ms-virtualtouchpad ms-visio ms-walk-to ms-whiteboard ");
  Add(TRUE, "ms-whiteboard-cmd ms-word msnim msrp msrps mtqp mumble mupdate ");
  Add(TRUE, "mvn news nfs ni nih nntp notes ocf oid onenote onenote-cmd ");
  Add(TRUE, "opaquelocktoken pack palm paparazzi pkcs11 platform pop pres ");
  Add(TRUE, "prospero proxy pwid psyc qb query redis rediss reload res ");
  Add(TRUE, "resource rmi rsync rtmfp rtmp rtsp rtsps rtspu secondlife ");
  Add(TRUE, "service session sftp sgn shttp sieve sip sips skype smb sms ");
  Add(TRUE, "smtp snews snmp soap.beep soap.beeps soldat spotify ssh steam ");
  Add(TRUE, "stun stuns submit svn tag teamspeak tel teliaeid telnet tftp ");
  Add(TRUE, "things thismessage tip tn3270 tool turn turns tv udp unreal urn ");
  Add(TRUE, "ut2004 v-event vemmi ventrilo videotex vnc view-source wais ");
  Add(TRUE, "webcal wpid ws wss wtai wyciwyg xcon xcon-userid xfire ");
  Add(TRUE, "xmlrpc.beep xmlrpc.beeps xmpp xri ymsgr z39.50 z39.50r z39.50s ");
  Add(TRUE, "doi gemini isbn javascript pmid ");
  Add(FALSE, "aet. aetat. al. Apr. Aug. bk. Bros. c. Capt. cf. ch. chap. chs. ");
  Add(FALSE, "Co. col. Corp. cp. d. Dec. Dr. e.g. ed. eds. esp. f. fasc. Feb. ");
  Add(FALSE, "ff. fig. fl. fol. fols. Fr. Gen. Gov. Hon. i.e. ill. Inc. incl. ");
  Add(FALSE, "Jan. Jr. Jul. Jun. Ltd. M.A. M.D. Mar. Mr. Mrs. Ms. n. n.b. nn. ");
  Add(FALSE, "No. Nov. Oct. p. Ph.D. pp. Pres. Prof. pt. q.v. Rep. Rev. s.v. ");
  Add(FALSE, "s.vv. saec. sec. Sen. Sep. Sept. Sgt. Sr. St. univ. viz. vol. ");
  Add(FALSE, "vs. ");
END PdWords.
