MODULE PdMime;
(* PdMime: the extensions pandoc 3.10 knows a MIME type for
   (Text.Pandoc.MIME.getMimeType), with the category of each type.
   Written by tools/mkmime from data/mime-types.txt; do not edit. *)

CONST
  Unknown* = 0; Image* = 1; Video* = 2; Audio* = 3; Other* = 4;
  Count = 1166;
  WordLen = 14;

TYPE
  Word = ARRAY WordLen OF CHAR;

VAR
  exts: ARRAY Count OF Word;
  cats: ARRAY Count OF CHAR;
  n: INTEGER;

(* Adds the entries in s, each "ext:c" followed by a space *)
PROCEDURE Add(s: ARRAY OF CHAR);
  VAR i, j: INTEGER;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    j := 0;
    WHILE s[i] # ":" DO exts[n][j] := s[i]; INC(i); INC(j) END;
    exts[n][j] := 0X;
    cats[n] := s[i + 1]; INC(n); INC(i, 3)
  END
END Add;

(* The category of the MIME type of the extension ext (without the
   dot, compared ignoring case): Image, Video, Audio, Other, or Unknown
   if there is no MIME type for it *)
PROCEDURE Category*(ext: ARRAY OF CHAR): INTEGER;
  VAR lo, hi, mid, i: INTEGER; e: Word;
BEGIN
  i := 0;
  WHILE (i < LEN(ext)) & (ext[i] # 0X) DO
    IF i = WordLen - 1 THEN RETURN Unknown END;
    IF (ext[i] >= "A") & (ext[i] <= "Z") THEN e[i] := CHR(ORD(ext[i]) + 32)
    ELSE e[i] := ext[i]
    END;
    INC(i)
  END;
  e[i] := 0X;
  lo := 0; hi := Count - 1;
  WHILE lo <= hi DO
    mid := (lo + hi) DIV 2;
    IF exts[mid] = e THEN
      CASE cats[mid] OF
        "i": RETURN Image
      | "v": RETURN Video
      | "a": RETURN Audio
      ELSE RETURN Other
      END
    ELSIF exts[mid] < e THEN lo := mid + 1
    ELSE hi := mid - 1
    END
  END;
  RETURN Unknown
END Category;

BEGIN
  n := 0;
  Add("%:o 123:o 323:o 3dml:o 3ds:i 3g2:v 3gp:v 3gpp:v 7z:o aab:o ");
  Add("aac:a aam:o aas:o abw:o ac:o acc:o ace:o acu:o acutc:o adp:a ");
  Add("aep:o afm:o afp:o ahead:o ai:o aif:a aifc:a aiff:a air:o ait:o ");
  Add("alc:o ami:o apk:o apng:i appcache:o application:o apr:o arc:o ");
  Add("art:i asc:o asf:v asm:o asn:o aso:o asx:v atc:o atom:o ");
  Add("atomcat:o atomsrv:o atomsvc:o atx:o au:a avi:v avif:i aw:o ");
  Add("azf:o azs:o azw:o b:o bak:o bat:o bcpio:o bdf:o bdm:o bed:o ");
  Add("bh2:o bib:o bin:o blb:o blorb:o bmi:o bmp:i boo:o book:o box:o ");
  Add("boz:o bpk:o bsd:o btif:i bz:o bz2:o c:o c++:o c11amc:o c11amz:o ");
  Add("c3d:o c4d:o c4f:o c4g:o c4p:o c4u:o cab:o cabal:o cac:o cache:o ");
  Add("caf:a cap:o car:o cascii:o cat:o cb7:o cba:o cbin:o cbr:o cbt:o ");
  Add("cbz:o cc:o cco:o cct:o ccxml:o cdbcmsg:o cdf:o cdkey:o cdmia:o ");
  Add("cdmic:o cdmid:o cdmio:o cdmiq:o cdr:i cdt:i cdx:o cdxml:o cdy:o ");
  Add("cef:o cer:o cfs:o cgm:i chat:o chm:o chrt:o cif:o cii:o cil:o ");
  Add("cla:o class:o clkk:o clkp:o clkt:o clkw:o clkx:o clp:o cls:o ");
  Add("cmc:o cmdf:o cml:o cmp:o cmx:i cod:o com:o conf:o cpa:o cpio:o ");
  Add("cpp:o cpt:i crd:o crl:o crt:o cryptonote:o csf:o csh:o csm:o ");
  Add("csml:o csp:o css:o cst:o csv:o ctab:o ctx:o cu:o cub:o curl:o ");
  Add("cww:o cxf:o cxt:o cxx:o d:o dae:o daf:o dart:o dat:o dataless:o ");
  Add("davmount:o dbk:o dcr:o dcurl:o dd2:o ddd:o deb:o def:o deploy:o ");
  Add("der:o dfac:o dgc:o dic:o dif:v diff:o dir:o dis:o dist:o ");
  Add("distz:o djv:i djvu:i dl:v dll:o dmg:o dmp:o dms:o dna:o doc:o ");
  Add("docm:o docx:o dot:o dotm:o dotx:o dp:o dpg:o dra:a dsc:o dssc:o ");
  Add("dtb:o dtd:o dts:a dtshd:a dump:o dv:v dvb:v dvi:o dwf:o dwg:i ");
  Add("dx:o dxf:i dxp:o dxr:o ear:o ecelp4800:a ecelp7470:a ");
  Add("ecelp9600:a ecma:o edm:o edx:o efif:o ei6:o elc:o emb:o embl:o ");
  Add("emf:i eml:o emma:o emz:o ent:o eol:a eot:o eps:o epub:o es3:o ");
  Add("esa:o esf:o et3:o etx:o eva:o evy:o exe:o exi:o ext:o ez:o ");
  Add("ez2:o ez3:o f:o f4v:v f77:o f90:o fb:o fbdoc:o fbs:i fcdt:o ");
  Add("fch:o fchk:o fcs:o fdf:o fe_launch:o fg5:o fgd:o fh:i fh4:i ");
  Add("fh5:i fh7:i fhc:i fig:o flac:a fli:v flo:o flv:v flw:o flx:o ");
  Add("fly:o fm:o fnc:o for:o fpx:i frame:o frm:o fs:o fsc:o fst:i ");
  Add("ftc:o fti:o fvt:v fxp:o fxpl:o fzs:o g2w:o g3:i g3w:o gac:o ");
  Add("gal:o gam:o gamin:o gau:o gbr:o gca:o gcd:o gcf:o gcg:o gdl:o ");
  Add("gen:o geo:o gex:o gf:o ggb:o ggt:o ghf:o gif:i gim:o gjc:o ");
  Add("gjf:o gl:v glsl:o gml:o gmx:o gnumeric:o gph:o gpt:o gpx:o ");
  Add("gqf:o gqs:o gram:o gramps:o gre:o grv:o grxml:o gsf:o gsm:a ");
  Add("gtar:o gtm:o gtw:o gv:o gxf:o gxt:o gz:o h:o h++:o h261:v ");
  Add("h263:v h264:v hal:o hbci:o hdf:o hh:o hin:o hlp:o hpgl:o hpid:o ");
  Add("hpp:o hps:o hqx:o hs:o hta:o htc:o htke:o htm:o html:o hvd:o ");
  Add("hvp:o hvs:o hxx:o i2g:o ica:o icc:o ice:o icm:o ico:i ics:o ");
  Add("icz:o ief:i ifb:o ifm:o iges:o igl:o igm:o igs:o igx:o iif:o ");
  Add("iii:o img:o imp:o ims:o in:o ink:o inkml:o inp:o ins:o ");
  Add("install:o iota:o ipfix:o ipk:o irm:o irp:o iso:o isp:o ist:o ");
  Add("istr:o itp:o ivp:o ivu:o jad:o jam:o jar:o jardiff:o java:o ");
  Add("jdx:o jfif:i jisp:o jlt:o jmz:o jng:i jnlp:o joda:o jpe:i ");
  Add("jpeg:i jpg:i jpgm:v jpgv:v jpm:v js:o json:o jsonml:o jxl:i ");
  Add("kar:a karbon:o key:o kfo:o kia:o kil:o kin:o kml:o kmz:o kne:o ");
  Add("knp:o kon:o kpr:o kpt:o kpxx:o ksp:o ktr:o ktx:i ktz:o kwd:o ");
  Add("kwt:o lasxml:o latex:o lbd:o lbe:o les:o less:o lha:o lhs:o ");
  Add("link66:o list:o list3820:o listafp:o lnk:o log:o lostxml:o ");
  Add("lrf:o lrm:o lsf:v lsx:v ltf:o ltx:o lvp:a lwp:o lyx:o lzh:o ");
  Add("lzx:o m13:o m14:o m1v:v m21:o m2a:a m2v:v m3a:a m3u:o m3u8:o ");
  Add("m4a:a m4u:v m4v:v ma:o mads:o mag:o maker:o man:o manifest:o ");
  Add("mar:o markdown:o mathml:o mb:o mbk:o mbox:o mc1:o mcd:o mcif:o ");
  Add("mcm:o mcurl:o md:o mdb:o mdi:i me:o mesh:o meta4:o metalink:o ");
  Add("mets:o mfm:o mft:o mgp:o mgz:o mid:a midi:a mie:o mif:o mime:o ");
  Add("mj2:v mjp2:v mjs:o mk3d:v mka:a mks:v mkv:v mlp:o mm:o mmd:o ");
  Add("mmf:o mml:o mmod:o mmr:i mng:v mny:o mobi:o moc:o mods:o mol:o ");
  Add("mol2:o moo:o mop:o mopcrt:o mov:v movie:v mp2:a mp21:o mp2a:a ");
  Add("mp3:a mp4:v mp4a:a mp4s:o mp4v:v mpc:o mpe:v mpeg:v mpega:a ");
  Add("mpg:v mpg4:v mpga:a mpkg:o mpm:o mpn:o mpp:o mpt:o mpy:o mqy:o ");
  Add("mrc:o mrcx:o ms:o mscml:o mseed:o mseq:o msf:o msh:o msi:o ");
  Add("msl:o msm:o msp:o msty:o mts:o mus:o musicxml:o mvb:o mwf:o ");
  Add("mxf:o mxl:o mxml:o mxs:o mxu:v n-gage:o n3:o nb:o nbp:o nc:o ");
  Add("ncx:o nfo:o ngdat:o nitf:o nlu:o nml:o nnd:o nns:o nnw:o npx:i ");
  Add("nsc:o nsf:o ntf:o nwc:o nzb:o o:o oa2:o oa3:o oas:o obd:o obj:o ");
  Add("oda:o odb:o odc:o odf:o odft:o odg:o odi:o odm:o odp:o ods:o ");
  Add("odt:o oga:a ogg:a ogv:v ogx:o old:o omdoc:o onepkg:o onetmp:o ");
  Add("onetoc:o onetoc2:o opf:o opml:o oprc:o opus:a org:o osf:o ");
  Add("osfpvg:o otc:o otf:o otg:o oth:o oti:o otp:o ots:o ott:o oxps:o ");
  Add("oxt:o oza:o p:o p10:o p12:o p7b:o p7c:o p7m:o p7r:o p7s:o p8:o ");
  Add("pac:o pas:o pat:i patch:o paw:o pbd:o pbm:i pcap:o pcf:o pcl:o ");
  Add("pclxl:o pct:i pcurl:o pcx:i pdb:o pdf:o pem:o pfa:o pfb:o pfm:o ");
  Add("pfr:o pfx:o pgm:i pgn:o pgp:o php:o php3:o php3p:o php4:o ");
  Add("phps:o pht:o phtml:o pic:i pk:o pkg:o pki:o pkipath:o pl:o ");
  Add("plb:o plc:o plf:o pls:a pm:o pml:o png:i pnm:i portpkg:o pot:o ");
  Add("potm:o potx:o ppam:o ppd:o ppm:i pps:o ppsm:o ppsx:o ppt:o ");
  Add("pptm:o pptx:o pqa:o prc:o pre:o prf:o prt:o ps:o psb:o psd:i ");
  Add("psf:o pskcxml:o ptid:o pub:o pvb:o pwn:o py:o pya:a pyc:o pyo:o ");
  Add("pyv:v qam:o qbo:o qfx:o qps:o qt:v qtl:o qwd:o qwt:o qxb:o ");
  Add("qxd:o qxl:o qxt:o ra:a ram:a rar:o ras:i rcprofile:o rd:o rdf:o ");
  Add("rdz:o rep:o res:o rgb:i rhtml:o rif:o rip:a ris:o rl:o rlc:i ");
  Add("rld:o rm:a rmi:a rmp:a rms:o rmvb:o rnc:o roa:o roff:o ros:o ");
  Add("rp9:o rpm:o rpss:o rpst:o rq:o rs:o rsd:o rss:o rtf:o rtx:o ");
  Add("run:o rxn:o s:o s3m:a saf:o sbml:o sc:o scd:o scm:o scq:o scs:o ");
  Add("sct:o scurl:o sd:o sd2:a sda:o sdc:o sdd:o sdf:o sdkd:o sdkm:o ");
  Add("sdp:o sds:o sdw:o sea:o see:o seed:o sema:o semd:o semf:o ser:o ");
  Add("setpay:o setreg:o sfd-hdstx:o sfs:o sfv:o sgf:o sgi:i sgl:o ");
  Add("sgm:o sgml:o sh:o shar:o shf:o shtml:o sid:a sig:o sik:o sil:a ");
  Add("silo:o sis:o sisx:o sit:o sitx:o skd:o skm:o skp:o skt:o sldm:o ");
  Add("sldx:o slt:o sm:o smf:o smi:o smil:o smv:v smzip:o snd:a snf:o ");
  Add("so:o spc:o spf:o spl:o spot:o spp:o spq:o spx:a sql:o src:o ");
  Add("srt:o sru:o srx:o ssdl:o sse:o ssf:o ssml:o st:o stc:o std:o ");
  Add("stf:o sti:o stk:o stl:o str:o stw:o sty:o sub:o sus:o susp:o ");
  Add("sv4cpio:o sv4crc:o svc:o svd:o svg:i svgz:i sw:o swa:o swf:o ");
  Add("swfl:o swi:o sxc:o sxd:o sxg:o sxi:o sxm:o sxw:o t:o t3:o ");
  Add("taglet:o tao:o tar:o tar.bz2:o tar.gz:o taz:o tbz:o tcap:o ");
  Add("tcl:o teacher:o tei:o teicorpus:o tex:o texi:o texinfo:o text:o ");
  Add("tfi:o tfm:o tga:i tgf:o tgz:o thmx:o tif:i tiff:i tk:o tm:o ");
  Add("tmo:o torrent:o tpl:o tpt:o tr:o tra:o trm:o ts:o tsd:o tsp:o ");
  Add("tsv:o ttc:o ttf:o ttl:o twd:o twds:o txd:o txf:o txt:o u32:o ");
  Add("udeb:o ufd:o ufdl:o ulx:o umj:o unityweb:o uoml:o uri:o uris:o ");
  Add("urls:o ustar:o utz:o uu:o uva:a uvd:o uvf:o uvg:i uvh:v uvi:i ");
  Add("uvm:v uvp:v uvs:v uvt:o uvu:v uvv:v uvva:a uvvd:o uvvf:o uvvg:i ");
  Add("uvvh:v uvvi:i uvvm:v uvvp:v uvvs:v uvvt:o uvvu:v uvvv:v uvvx:o ");
  Add("uvvz:o uvx:o uvz:o val:o vcard:o vcd:o vcf:o vcg:o vcs:o vcx:o ");
  Add("vis:o viv:v vmd:o vms:o vob:v vor:o vox:o vrm:o vrml:o vs:o ");
  Add("vsd:o vsf:o vss:o vst:o vsw:o vtt:o vtu:o vxml:o w3d:o wad:o ");
  Add("war:o wasm:o wav:a wax:a wbmp:i wbs:o wbxml:o wcm:o wdb:o wdp:i ");
  Add("weba:a webm:v webp:i wg:o wgt:o wk:o wks:o wm:v wma:a wmd:o ");
  Add("wmf:i wml:o wmlc:o wmls:o wmlsc:o wmv:v wmx:v wmz:o woff:o ");
  Add("woff2:o wp5:o wpd:o wpl:o wps:o wqd:o wri:o wrl:o wsc:o wsdl:o ");
  Add("wspolicy:o wtb:o wvx:v wz:o x32:o x3d:o x3db:o x3dbz:o x3dv:o ");
  Add("x3dvz:o x3dz:o xaml:o xap:o xar:o xbap:o xbd:o xbm:i xcf:i ");
  Add("xdf:o xdm:o xdp:o xdssc:o xdw:o xenc:o xer:o xfdf:o xfdl:o ");
  Add("xht:o xhtml:o xhvml:o xif:i xla:o xlam:o xlb:o xlc:o xlf:o ");
  Add("xlm:o xls:o xlsb:o xlsm:o xlsx:o xlt:o xltm:o xltx:o xlw:o xm:a ");
  Add("xml:o xo:o xop:o xpi:o xpl:o xpm:i xpr:o xps:o xpw:o xpx:o ");
  Add("xsl:o xslt:o xsm:o xspf:o xtel:o xul:o xvm:o xvml:o xwd:i xyz:o ");
  Add("xz:o yang:o yin:o z1:o z2:o z3:o z4:o z5:o z6:o z7:o z8:o zaz:o ");
  Add("zip:o zir:o zirz:o zmm:o zmt:o ");
END PdMime.
