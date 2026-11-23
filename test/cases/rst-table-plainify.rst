A simple table whose body has a list: the body cells stay Para,
the header cells are Plain.

=====  =====
a      b
=====  =====
c      - d
e      f
=====  =====

A simple table without one: all Plain.

=====  =====
a      b
=====  =====
c      d
=====  =====

A CSV table with a list in its header: every cell stays Para.

.. csv-table::
   :header: x, "- y"

   "a", "b"

A CSV table with a list in its body.

.. csv-table::

   "a", "- b"
   c, d

A CSV table without one: all Plain.

.. csv-table::

   "a", "b"
   c, d
