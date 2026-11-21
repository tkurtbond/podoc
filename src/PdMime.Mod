MODULE PdMime;
(* PdMime: the extensions pandoc 3.10 knows a MIME type for
   (Text.Pandoc.MIME.getMimeType), with the category of each type and
   the extension pandoc gives a file it names by hash.
   Written by tools/mkmime from data/mime-types.txt; do not edit. *)

CONST
  Unknown* = 0; Image* = 1; Video* = 2; Audio* = 3; Other* = 4;
  Count = 1166;
  WordLen = 14;

TYPE
  Word = ARRAY WordLen OF CHAR;

VAR
  exts: ARRAY Count OF Word;
  canons: ARRAY Count OF Word;
  cats: ARRAY Count OF CHAR;
  n: INTEGER;

(* Adds the entries in s, each "ext:c" or "ext:c:canonical" followed by
   a space *)
PROCEDURE Add(s: ARRAY OF CHAR);
  VAR i, j: INTEGER;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    j := 0;
    WHILE s[i] # ":" DO exts[n][j] := s[i]; INC(i); INC(j) END;
    exts[n][j] := 0X;
    cats[n] := s[i + 1]; INC(i, 2);
    IF s[i] = ":" THEN
      INC(i); j := 0;
      WHILE s[i] # " " DO canons[n][j] := s[i]; INC(i); INC(j) END;
      canons[n][j] := 0X
    ELSE COPY(exts[n], canons[n])
    END;
    INC(n); INC(i)
  END
END Add;

(* The index of the extension ext (without the dot, compared ignoring
   case), or -1 *)
PROCEDURE Find(VAR ext: ARRAY OF CHAR): INTEGER;
  VAR lo, hi, mid, i: INTEGER; e: Word;
BEGIN
  i := 0;
  WHILE (i < LEN(ext)) & (ext[i] # 0X) DO
    IF i = WordLen - 1 THEN RETURN -1 END;
    IF (ext[i] >= "A") & (ext[i] <= "Z") THEN e[i] := CHR(ORD(ext[i]) + 32)
    ELSE e[i] := ext[i]
    END;
    INC(i)
  END;
  e[i] := 0X;
  lo := 0; hi := Count - 1;
  WHILE lo <= hi DO
    mid := (lo + hi) DIV 2;
    IF exts[mid] = e THEN RETURN mid
    ELSIF exts[mid] < e THEN lo := mid + 1
    ELSE hi := mid - 1
    END
  END;
  RETURN -1
END Find;

(* The category of the MIME type of the extension ext (without the
   dot, compared ignoring case): Image, Video, Audio, Other, or Unknown
   if there is no MIME type for it *)
PROCEDURE Category*(ext: ARRAY OF CHAR): INTEGER;
  VAR k: INTEGER;
BEGIN
  k := Find(ext);
  IF k < 0 THEN RETURN Unknown END;
  CASE cats[k] OF
    "i": RETURN Image
  | "v": RETURN Video
  | "a": RETURN Audio
  ELSE RETURN Other
  END
END Category;

(* Sets canon to the extension, without the dot, pandoc gives a file
   with the extension ext that it names by the hash of its contents:
   that of ext's MIME type (Text.Pandoc.MIME.extensionFromMimeType),
   or "so", application/octet-stream's, if ext has none *)
PROCEDURE Canonical*(ext: ARRAY OF CHAR; VAR canon: ARRAY OF CHAR);
  VAR k: INTEGER;
BEGIN
  k := Find(ext);
  IF k < 0 THEN COPY("so", canon) ELSE COPY(canons[k], canon) END
END Canonical;

BEGIN
  n := 0;
  Add("%:o:sik 123:o 323:o 3dml:o 3ds:i 3g2:v 3gp:v:3gpp 3gpp:v 7z:o ");
  Add("aab:o:x32 aac:a aam:o aas:o abw:o ac:o acc:o ace:o acu:o ");
  Add("acutc:o:atc adp:a aep:o afm:o:pfm afp:o:listafp ahead:o ai:o:ps ");
  Add("aif:a:aiff aifc:a:aiff aiff:a air:o ait:o alc:o ami:o apk:o ");
  Add("apng:i appcache:o:manifest application:o apr:o arc:o art:i ");
  Add("asc:o:txt asf:v:asx asm:o:s asn:o aso:o:val asx:v atc:o atom:o ");
  Add("atomcat:o atomsrv:o atomsvc:o atx:o au:a:snd avi:v avif:i aw:o ");
  Add("azf:o azs:o azw:o b:o bak:o:sik bat:o:dll bcpio:o bdf:o bdm:o ");
  Add("bed:o bh2:o bib:o bin:o:so blb:o:blorb blorb:o bmi:o bmp:i ");
  Add("boo:o book:o:frm box:o boz:o bpk:o:so bsd:o btif:i bz:o:bz2 ");
  Add("bz2:o c:o c++:o:cxx c11amc:o c11amz:o c3d:o c4d:o:c4u c4f:o:c4u ");
  Add("c4g:o:c4u c4p:o:c4u c4u:o cab:o cabal:o cac:o:cache cache:o ");
  Add("caf:a cap:o:pcap car:o cascii:o:ctab cat:o cb7:o:cbz cba:o:cbz ");
  Add("cbin:o:ctab cbr:o:cbz cbt:o:cbz cbz:o cc:o:cxx cco:o cct:o:w3d ");
  Add("ccxml:o cdbcmsg:o cdf:o cdkey:o cdmia:o cdmic:o cdmid:o cdmio:o ");
  Add("cdmiq:o cdr:i cdt:i cdx:o cdxml:o cdy:o cef:o:cxf cer:o cfs:o ");
  Add("cgm:i chat:o chm:o chrt:o cif:o cii:o cil:o cla:o class:o ");
  Add("clkk:o clkp:o clkt:o clkw:o clkx:o clp:o cls:o:tex cmc:o cmdf:o ");
  Add("cml:o cmp:o cmx:i cod:o com:o:dll conf:o:txt cpa:o cpio:o ");
  Add("cpp:o:cxx cpt:i crd:o crl:o crt:o:pem cryptonote:o csf:o csh:o ");
  Add("csm:o csml:o:csm csp:o css:o:less cst:o:w3d csv:o ctab:o ctx:o ");
  Add("cu:o cub:o curl:o cww:o cxf:o cxt:o:w3d cxx:o d:o dae:o daf:o ");
  Add("dart:o dat:o:zmt dataless:o:seed davmount:o dbk:o dcr:o:w3d ");
  Add("dcurl:o dd2:o ddd:o deb:o:udeb def:o:txt deploy:o:so der:o:pem ");
  Add("dfac:o dgc:o dic:o:hh dif:v:dv diff:o:patch dir:o:w3d dis:o ");
  Add("dist:o:so distz:o:so djv:i:djvu djvu:i dl:v dll:o dmg:o ");
  Add("dmp:o:pcap dms:o dna:o doc:o:dot docm:o docx:o dot:o dotm:o ");
  Add("dotx:o dp:o dpg:o dra:a dsc:o dssc:o dtb:o dtd:o dts:a dtshd:a ");
  Add("dump:o:so dv:v dvb:v dvi:o dwf:o dwg:i dx:o:jdx dxf:i dxp:o ");
  Add("dxr:o:w3d ear:o:war ecelp4800:a ecelp7470:a ecelp9600:a ecma:o ");
  Add("edm:o edx:o efif:o ei6:o elc:o:so emb:o:embl embl:o emf:i ");
  Add("eml:o:mime emma:o emz:o:wmz ent:o:prt eol:a eot:o eps:o epub:o ");
  Add("es3:o:et3 esa:o esf:o et3:o etx:o eva:o evy:o exe:o exi:o ext:o ");
  Add("ez:o ez2:o ez3:o f:o:for f4v:v f77:o:for f90:o:for fb:o:frm ");
  Add("fbdoc:o:frm fbs:i fcdt:o fch:o:fchk fchk:o fcs:o fdf:o ");
  Add("fe_launch:o fg5:o fgd:o:w3d fh:i:fhc fh4:i:fhc fh5:i:fhc ");
  Add("fh7:i:fhc fhc:i fig:o flac:a fli:v flo:o flv:v flw:o flx:o ");
  Add("fly:o fm:o:maker fnc:o for:o fpx:i frame:o:maker frm:o fs:o:txt ");
  Add("fsc:o fst:i ftc:o fti:o fvt:v fxp:o:fxpl fxpl:o fzs:o g2w:o ");
  Add("g3:i g3w:o gac:o gal:o gam:o:inp gamin:o:inp gau:o:gjf gbr:o ");
  Add("gca:o gcd:o gcf:o gcg:o gdl:o gen:o geo:o gex:o:gre gf:o ggb:o ");
  Add("ggt:o ghf:o gif:i gim:o gjc:o:gjf gjf:o gl:v glsl:o:txt gml:o ");
  Add("gmx:o gnumeric:o gph:o gpt:o gpx:o gqf:o:gqs gqs:o gram:o ");
  Add("gramps:o gre:o grv:o grxml:o gsf:o gsm:a gtar:o:taz gtm:o gtw:o ");
  Add("gv:o gxf:o gxt:o gz:o h:o h++:o:hxx h261:v h263:v h264:v hal:o ");
  Add("hbci:o hdf:o hh:o:hxx hin:o hlp:o hpgl:o hpid:o hpp:o:hxx hps:o ");
  Add("hqx:o hs:o hta:o htc:o htke:o htm:o:shtml html:o:shtml hvd:o ");
  Add("hvp:o hvs:o hxx:o i2g:o ica:o icc:o:icm ice:o icm:o ico:i ");
  Add("ics:o:icz icz:o ief:i ifb:o:icz ifm:o iges:o:igs igl:o igm:o ");
  Add("igs:o igx:o iif:o iii:o img:o:so imp:o ims:o in:o:txt ");
  Add("ink:o:inkml inkml:o inp:o ins:o:isp install:o iota:o ipfix:o ");
  Add("ipk:o irm:o irp:o iso:o isp:o ist:o:istr istr:o itp:o ivp:o ");
  Add("ivu:o jad:o jam:o jar:o:war jardiff:o java:o jdx:o jfif:i:jpg ");
  Add("jisp:o jlt:o jmz:o jng:i jnlp:o joda:o jpe:i:jpg jpeg:i:jpg ");
  Add("jpg:i jpgm:v:jpm jpgv:v jpm:v js:o:mjs json:o jsonml:o jxl:i ");
  Add("kar:a:rmi karbon:o key:o kfo:o kia:o kil:o kin:o kml:o kmz:o ");
  Add("kne:o:knp knp:o kon:o kpr:o:kpt kpt:o kpxx:o ksp:o ktr:o:ktz ");
  Add("ktx:i ktz:o kwd:o:kwt kwt:o lasxml:o latex:o lbd:o lbe:o les:o ");
  Add("less:o lha:o:lzh lhs:o link66:o list:o:txt list3820:o:listafp ");
  Add("listafp:o lnk:o log:o:txt lostxml:o lrf:o:so lrm:o lsf:v:lsx ");
  Add("lsx:v ltf:o ltx:o:tex lvp:a lwp:o lyx:o lzh:o lzx:o m13:o:mvb ");
  Add("m14:o:mvb m1v:v:mpeg m21:o:mp21 m2a:a:mpega m2v:v:mpeg ");
  Add("m3a:a:mpega m3u:o:m3u8 m3u8:o m4a:a:mp4a m4u:v:mxu m4v:v ");
  Add("ma:o:nb mads:o mag:o maker:o man:o manifest:o mar:o:so ");
  Add("markdown:o:md mathml:o mb:o:nb mbk:o mbox:o mc1:o mcd:o mcif:o ");
  Add("mcm:o mcurl:o md:o mdb:o mdi:i me:o mesh:o:silo meta4:o ");
  Add("metalink:o mets:o mfm:o mft:o mgp:o mgz:o mid:a:rmi midi:a:rmi ");
  Add("mie:o mif:o mime:o mj2:v:mjp2 mjp2:v mjs:o mk3d:v:mkv mka:a ");
  Add("mks:v:mkv mkv:v mlp:o mm:o mmd:o:mmod mmf:o mml:o mmod:o mmr:i ");
  Add("mng:v mny:o mobi:o:prc moc:o mods:o mol:o mol2:o moo:o ");
  Add("mop:o:zmt mopcrt:o:zmt mov:v movie:v mp2:a:mpega mp21:o ");
  Add("mp2a:a:mpega mp3:a:mpega mp4:v:mpg4 mp4a:a mp4s:o mp4v:v:mpg4 ");
  Add("mpc:o:zmt mpe:v:mpeg mpeg:v mpega:a mpg:v:mpeg mpg4:v ");
  Add("mpga:a:mpega mpkg:o mpm:o mpn:o mpp:o:mpt mpt:o mpy:o mqy:o ");
  Add("mrc:o mrcx:o ms:o mscml:o mseed:o mseq:o msf:o msh:o:silo msi:o ");
  Add("msl:o msm:o:so msp:o:so msty:o mts:o mus:o musicxml:o mvb:o ");
  Add("mwf:o mxf:o mxl:o mxml:o:xvml mxs:o mxu:v n-gage:o n3:o nb:o ");
  Add("nbp:o nc:o ncx:o nfo:o ngdat:o nitf:o:ntf nlu:o nml:o nnd:o ");
  Add("nns:o nnw:o npx:i nsc:o nsf:o ntf:o nwc:o nzb:o o:o oa2:o oa3:o ");
  Add("oas:o obd:o obj:o oda:o odb:o odc:o odf:o odft:o odg:o odi:o ");
  Add("odm:o odp:o ods:o odt:o oga:a:spx ogg:a:spx ogv:v ogx:o:ogg ");
  Add("old:o:sik omdoc:o onepkg:o:onetoc2 onetmp:o:onetoc2 ");
  Add("onetoc:o:onetoc2 onetoc2:o opf:o opml:o oprc:o:pqa opus:a org:o ");
  Add("osf:o osfpvg:o otc:o otf:o otg:o oth:o oti:o otp:o ots:o ott:o ");
  Add("oxps:o oxt:o oza:o p:o:pas p10:o p12:o:pfx p7b:o:spc p7c:o:p7m ");
  Add("p7m:o p7r:o p7s:o p8:o pac:o pas:o pat:i patch:o paw:o pbd:o ");
  Add("pbm:i pcap:o pcf:o pcl:o pclxl:o pct:i:pic pcurl:o pcx:i pdb:o ");
  Add("pdf:o pem:o pfa:o:pfm pfb:o:pfm pfm:o pfr:o pfx:o pgm:i pgn:o ");
  Add("pgp:o php:o:phtml php3:o php3p:o php4:o phps:o pht:o:phtml ");
  Add("phtml:o pic:i pk:o pkg:o:so pki:o pkipath:o pl:o:pm plb:o plc:o ");
  Add("plf:o pls:a pm:o pml:o png:i pnm:i portpkg:o pot:o:txt potm:o ");
  Add("potx:o ppam:o ppd:o ppm:i pps:o:ppt ppsm:o ppsx:o ppt:o pptm:o ");
  Add("pptx:o pqa:o prc:o pre:o prf:o prt:o ps:o psb:o psd:i psf:o ");
  Add("pskcxml:o ptid:o pub:o pvb:o pwn:o py:o pya:a pyc:o:pyo pyo:o ");
  Add("pyv:v qam:o qbo:o qfx:o qps:o qt:v:mov qtl:o qwd:o:qxt ");
  Add("qwt:o:qxt qxb:o:qxt qxd:o:qxt qxl:o:qxt qxt:o ra:a:rm ram:a:rm ");
  Add("rar:o ras:i rcprofile:o rd:o rdf:o rdz:o rep:o res:o rgb:i ");
  Add("rhtml:o rif:o rip:a ris:o rl:o rlc:i rld:o rm:a rmi:a rmp:a ");
  Add("rms:o rmvb:o rnc:o roa:o roff:o:tr ros:o rp9:o rpm:o rpss:o ");
  Add("rpst:o rq:o rs:o rsd:o rss:o rtf:o rtx:o run:o rxn:o s:o s3m:a ");
  Add("saf:o sbml:o sc:o scd:o scm:o scq:o scs:o sct:o:wsc scurl:o ");
  Add("sd:o sd2:a sda:o sdc:o sdd:o sdf:o sdkd:o:sdkm sdkm:o sdp:o ");
  Add("sds:o sdw:o:vor sea:o see:o seed:o sema:o semd:o semf:o ser:o ");
  Add("setpay:o setreg:o sfd-hdstx:o sfs:o sfv:o sgf:o sgi:i sgl:o ");
  Add("sgm:o:sgml sgml:o sh:o shar:o shf:o shtml:o sid:a sig:o sik:o ");
  Add("sil:a silo:o sis:o:sisx sisx:o sit:o sitx:o skd:o:skt skm:o:skt ");
  Add("skp:o:skt skt:o sldm:o sldx:o slt:o sm:o smf:o:sdf smi:o:smil ");
  Add("smil:o smv:v smzip:o snd:a snf:o so:o spc:o spf:o spl:o spot:o ");
  Add("spp:o spq:o spx:a sql:o src:o srt:o sru:o srx:o ssdl:o sse:o ");
  Add("ssf:o ssml:o st:o stc:o std:o stf:o sti:o stk:o stl:o str:o ");
  Add("stw:o sty:o:tex sub:o sus:o:susp susp:o sv4cpio:o sv4crc:o ");
  Add("svc:o svd:o svg:i svgz:i:svg sw:o swa:o:w3d swf:o:swfl swfl:o ");
  Add("swi:o sxc:o sxd:o sxg:o sxi:o sxm:o sxw:o t:o:tr t3:o taglet:o ");
  Add("tao:o tar:o tar.bz2:o:tbz tar.gz:o:tgz taz:o tbz:o tcap:o ");
  Add("tcl:o:tk teacher:o tei:o:teicorpus teicorpus:o tex:o ");
  Add("texi:o:texinfo texinfo:o text:o:txt tfi:o tfm:o tga:i tgf:o ");
  Add("tgz:o thmx:o tif:i:tiff tiff:i tk:o tm:o:ts tmo:o torrent:o ");
  Add("tpl:o tpt:o tr:o tra:o trm:o ts:o tsd:o tsp:o tsv:o ttc:o:ttf ");
  Add("ttf:o ttl:o twd:o:twds twds:o txd:o txf:o txt:o u32:o:x32 ");
  Add("udeb:o ufd:o:ufdl ufdl:o ulx:o umj:o unityweb:o uoml:o ");
  Add("uri:o:urls uris:o:urls urls:o ustar:o utz:o uu:o uva:a:uvva ");
  Add("uvd:o:uvvf uvf:o:uvvf uvg:i:uvvi uvh:v:uvvh uvi:i:uvvi ");
  Add("uvm:v:uvvm uvp:v:uvvp uvs:v:uvvs uvt:o:uvvt uvu:v:uvvu ");
  Add("uvv:v:uvvv uvva:a uvvd:o:uvvf uvvf:o uvvg:i:uvvi uvvh:v uvvi:i ");
  Add("uvvm:v uvvp:v uvvs:v uvvt:o uvvu:v uvvv:v uvvx:o:uvx uvvz:o:uvz ");
  Add("uvx:o uvz:o val:o vcard:o vcd:o vcf:o vcg:o vcs:o vcx:o vis:o ");
  Add("viv:v vmd:o vms:o vob:v vor:o vox:o:x32 vrm:o vrml:o:wrl ");
  Add("vs:o:txt vsd:o:vsw vsf:o vss:o:vsw vst:o:vsw vsw:o vtt:o vtu:o ");
  Add("vxml:o w3d:o wad:o war:o wasm:o wav:a wax:a wbmp:i wbs:o ");
  Add("wbxml:o wcm:o:wps wdb:o:wps wdp:i weba:a webm:v webp:i wg:o ");
  Add("wgt:o wk:o wks:o:wps wm:v wma:a wmd:o wmf:i wml:o wmlc:o wmls:o ");
  Add("wmlsc:o wmv:v wmx:v wmz:o woff:o woff2:o wp5:o wpd:o wpl:o ");
  Add("wps:o wqd:o wri:o wrl:o wsc:o wsdl:o wspolicy:o wtb:o wvx:v ");
  Add("wz:o x32:o x3d:o:x3dz x3db:o:x3dbz x3dbz:o x3dv:o:x3dvz x3dvz:o ");
  Add("x3dz:o xaml:o xap:o xar:o xbap:o xbd:o xbm:i xcf:i xdf:o xdm:o ");
  Add("xdp:o xdssc:o xdw:o xenc:o xer:o xfdf:o xfdl:o xht:o:xhtml ");
  Add("xhtml:o xhvml:o:xvml xif:i xla:o:xlb xlam:o xlb:o xlc:o:xlb ");
  Add("xlf:o xlm:o:xlb xls:o:xlb xlsb:o xlsm:o xlsx:o xlt:o:xlb xltm:o ");
  Add("xltx:o xlw:o:xlb xm:a xml:o xo:o xop:o xpi:o xpl:o xpm:i xpr:o ");
  Add("xps:o xpw:o:xpx xpx:o xsl:o:xml xslt:o xsm:o xspf:o xtel:o ");
  Add("xul:o xvm:o:xvml xvml:o xwd:i xyz:o xz:o yang:o yin:o z1:o:z8 ");
  Add("z2:o:z8 z3:o:z8 z4:o:z8 z5:o:z8 z6:o:z8 z7:o:z8 z8:o zaz:o ");
  Add("zip:o zir:o:zirz zirz:o zmm:o zmt:o ");
END PdMime.
