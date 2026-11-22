Pascal, Object Pascal and Ada:

```objfpc
{$mode objfpc}
type TA = class (TObject) procedure P; end;
begin s := 'it''s'; &type := 1 end. // done
```

```ada
C : Character := Character'('a');
for I in A'Range loop null; end loop; -- each
```

C++, with a raw string, and `try { f(); }`{.cpp}:

```cpp
#include <new>
auto s = R"x(a "quoted"
  try)x"; try { throw 1; } catch (...) {}
```
