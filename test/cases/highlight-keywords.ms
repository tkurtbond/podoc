.LP
Pascal, with a file that adds and removes:
.IP
.nf
\f[CR]
\f[CB]procedure\f[CR] P; \f[CB]override\f[CR]; \f[CB]VIRTUAL\f[CR]; goto 1; \f[CB]begin\f[CR] \f[CB]end\f[CR]
\f[]
.fi
.LP
The same list in fpc, another name for the same language:
.IP
.nf
\f[CR]
\f[CB]OVERRIDE\f[CR] goto
\f[]
.fi
.LP
Oberon, with a file that replaces:
.IP
.nf
\f[CR]
\f[CB]MODULE\f[CR] M; \f[CB]PROCEDURE\f[CR] P; BEGIN \f[CB]END\f[CR] P; \f[CB]END\f[CR] M.
\f[]
.fi
.LP
Oberon-2 is the same language, so it is changed too:
.IP
.nf
\f[CR]
\f[CB]MODULE\f[CR] M; BEGIN \f[CB]END\f[CR] M.
\f[]
.fi
.LP
Oberon-07 is not:
.IP
.nf
\f[CR]
\f[CB]MODULE\f[CR] M; \f[CB]BEGIN\f[CR] \f[CB]END\f[CR] M.
\f[]
.fi
.LP
C, from the metadata, with \f[CR]widget\f[R] taken out again by a file:
.IP
.nf
\f[CR]
int widget; \f[CB]gadget\f[CR] x; \f[CB]long\f[CR] y;
\f[]
.fi
.LP
Ada, replaced by the metadata:
.IP
.nf
\f[CR]
\f[CB]procedure\f[CR] P is \f[CB]begin\f[CR] null; end P;
\f[]
.fi
.LP
sh without \f[CR]case\f[R]:
.IP
.nf
\f[CR]
case x in a) echo; \f[CB]esac\f[CR]
\f[CB]if\f[CR] true; \f[CB]then\f[CR] :; \f[CB]fi\f[CR]
\f[]
.fi
.LP
bash with \f[CR]select\f[R] and without \f[CR]time\f[R]:
.IP
.nf
\f[CR]
time ls
\f[CB]select\f[CR] x \f[CB]in\f[CR] a b; \f[CB]do\f[CR] :; \f[CB]done\f[CR]
\f[]
.fi
.LP
Inline:
\f[CR]\f[CB]begin\f[CR] \f[CB]override\f[CR] \f[CB]end\f[CR]\f[R].
