.LP
The metadata\(cqs style, \f[CR]BEGIN END\f[R]:
.IP
.nf
\f[CR]
BEGIN x := 1 END
\f[]
.fi
.LP
A block\(cqs class wins:
.IP
.nf
\f[CR]
\f[CB]BEGIN\f[CR] x := 2 \f[CB]END\f[CR]
\f[]
.fi
.IP
.nf
\f[CR]
int x = 3;
\f[]
.fi
.LP
\f[CR]\f[CB]int\f[CR] x\f[R] and \f[CR]int y\f[R].
