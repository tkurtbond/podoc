.LP
The metadata\(cqs style, \f[CR]\f[CB]BEGIN\f[CR] \f[CB]END\f[CR]\f[R]:
.IP
.nf
\f[B]BEGIN\f[R] x := 1 \f[B]END\f[R]
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
