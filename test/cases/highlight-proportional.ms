.SH 1
Head \f[CB]\f[CB]IF\f[CB] x \f[CBI](* c *)\f[CB] \f[CB]END\f[CB]\f[B]
.LP
Inline
\f[CR]\f[CB]IF\f[CR] x \f[CB]THEN\f[CR] \f[CI](* c *)\f[CR] \f[CB]END\f[CR]\f[R],
\f[CR]\f[CB]int\f[CR] x; \f[CI]// c {}\f[CR]\f[R], \f[CR]IF x\f[R] and
\f[CR]plain\f[R].
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
\f[B]MODULE\f[R] M; \f[I](* a {comment}\f[R]
\h'|2u*\n[PdCodeCol]u'\f[I]over two lines *)\f[R]
\h'|2u*\n[PdCodeCol]u'\f[B]VAR\f[R] s: \f[B]ARRAY\f[R] 8 \f[B]OF\f[R] CHAR; \f[I](* it\(aqs -- 50% *)\f[R]
\f[B]BEGIN\f[R] s := \(dq(* a\(rsb *)\(dq; t := \(aqEND\(aq
\f[B]END\f[R] M.
.fi
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
\&.dot at start
\f[B]static\f[R] \f[B]int\f[R] f(\f[B]void\f[R]) { \f[B]return\f[R] \(aq\(rs\(aq\(aq; } \f[I]// x--y \(ga\(gaz\(aq\(aq\f[R]
.fi
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
\f[B]FROM\f[R] InOut \f[B]IMPORT\f[R] WriteString; \f[I](* end END *)\f[R]
.fi
.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
no language # $ { } -- x
.fi
.IP
.nf
\f[CR]
MODULE Plain;
\f[]
.fi
