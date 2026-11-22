.IP
.nf
.if !r PdCodeCol .nr PdCodeCol 0.5m
.if !r PdCodeGap .nr PdCodeGap 1m
.nr PdG1 6*\n[PdCodeCol]
.nr PdG1 \n[PdG1]>?(\w'\&x :='u+\n[PdCodeGap]u)
.nr PdG2 9*\n[PdCodeCol]
.nr PdG2 \n[PdG2]>?(\w'\&x :=\h'|\n[PdG1]u'1'u+\n[PdCodeGap]u)
x :=\h'|\n[PdG1]u'1\h'|\n[PdG2]u'\f[I](* one *)\f[R]
.fi
