.LP
Pascal, Object Pascal and Ada:
.IP
.nf
\f[CR]
\f[CI]{$mode objfpc}\f[CR]
\f[CB]type\f[CR] TA = \f[CB]class\f[CR] (TObject) \f[CB]procedure\f[CR] P; \f[CB]end\f[CR];
\f[CB]begin\f[CR] s := \(aqit\(aq\(aqs\(aq; &type := 1 \f[CB]end\f[CR]. \f[CI]// done\f[CR]
\f[]
.fi
.IP
.nf
\f[CR]
C : Character := Character\(aq(\(aqa\(aq);
\f[CB]for\f[CR] I \f[CB]in\f[CR] A\(aqRange \f[CB]loop\f[CR] \f[CB]null\f[CR]; \f[CB]end\f[CR] \f[CB]loop\f[CR]; \f[CI]-- each\f[CR]
\f[]
.fi
.LP
C++, with a raw string, and \f[CR]\f[CB]try\f[CR] { f(); }\f[R]:
.IP
.nf
\f[CR]
#include <new>
\f[CB]auto\f[CR] s = R\(dqx(a \(dqquoted\(dq
  try)x\(dq; \f[CB]try\f[CR] { \f[CB]throw\f[CR] 1; } \f[CB]catch\f[CR] (...) {}
\f[]
.fi
