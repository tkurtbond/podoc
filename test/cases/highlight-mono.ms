.SH 1
Head \f[CB]\f[CB]IF\f[CB] x \f[CBI](* c *)\f[CB] \f[CB]END\f[CB]\f[B]
.LP
Inline
\f[CR]\f[CB]IF\f[CR] x \f[CB]THEN\f[CR] \f[CI](* c *)\f[CR] \f[CB]END\f[CR]\f[R],
\f[CR]\f[CB]int\f[CR] x; \f[CI]// c {}\f[CR]\f[R], \f[CR]IF x\f[R] and
\f[CR]plain\f[R].
.IP
.nf
\f[CR]
\f[CB]MODULE\f[CR] M; \f[CI](* a {comment}
  over two lines *)\f[CR]
  \f[CB]VAR\f[CR] s: \f[CB]ARRAY\f[CR] 8 \f[CB]OF\f[CR] CHAR; \f[CI](* it\(aqs -- 50% *)\f[CR]
\f[CB]BEGIN\f[CR] s := \(dq(* a\(rsb *)\(dq; t := \(aqEND\(aq
\f[CB]END\f[CR] M.
\f[]
.fi
.IP
.nf
\f[CR]
\&.dot at start
\f[CB]static\f[CR] \f[CB]int\f[CR] f(\f[CB]void\f[CR]) { \f[CB]return\f[CR] \(aq\(rs\(aq\(aq; } \f[CI]// x--y \(ga\(gaz\(aq\(aq\f[CR]
\f[]
.fi
.IP
.nf
\f[CR]
\f[CB]FROM\f[CR] InOut \f[CB]IMPORT\f[CR] WriteString; \f[CI](* end END *)\f[CR]
\f[]
.fi
.IP
.nf
\f[CR]
no language # $ { } -- x
\f[]
.fi
.IP
.nf
\f[CR]
MODULE Plain;
\f[]
.fi
