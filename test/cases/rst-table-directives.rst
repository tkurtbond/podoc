.. table:: Truth *table*
   :widths: 10 20

   =====  =====
   A      B
   =====  =====
   False  True
   True   False
   =====  =====

.. table:: Grid
   :widths: grid

   +-----+------+
   | a   | b    |
   +=====+======+
   | 1   | 2    |
   +-----+------+

.. table:: Auto
   :widths: auto

   +-----+------+
   | a   | b    |
   +=====+======+
   | 1   | 2    |
   +-----+------+

.. table::

   =====  =====
   x      y
   =====  =====

.. table:: Not one

   Just a para.

.. table:: Headless
   :widths: auto

   =====  =====
   x      y
   =====  =====

.. table:: Lead
   :widths: ,3 4,,

   =====  =====  ===
   A      B      C
   =====  =====  ===
   1      2      3
   =====  =====  ===

.. list-table:: Frozen *Delights*!
   :widths: 15 10 30
   :header-rows: 1

   * - Treat
     - Quantity
     - Description
   * - Albatross
     - 2.99
     - On a stick!
   * - Crunchy Frog
     - 1.49
     - If we took the bones out, it wouldn't be
       crunchy, now would it?

       Two paras.

.. list-table::

   * - a
     - b
   * - c

.. list-table:: Short
   :widths: auto
   :header-rows: 2

   * - a
     - b
     - c
   * - d
     - e
   * - f
     - g
     - h
     - i

.. list-table:: odd

   * - a
     - b
   * plain
   * - c
     - d

.. list-table:: W
   :widths: 0.2 0.3

   * - a
     - b
     - c

.. csv-table:: Frozen Delights!
   :header: "Treat", "Quantity", "Description"
   :widths: 15, 10, 30

   "Albatross", 2.99, "On a stick!"
   "Crunchy Frog", 1.49, "If we took the bones out, it wouldn't be
   crunchy, now would it?"
   "Gannet Ripple", 1.99, "On a ""stick""!"

.. csv-table:: Tabs
   :delim: tab
   :header-rows: 1

   a	 b	c
   *d*	e	  f

.. csv-table:: Esc
   :escape: \
   :quote: '
   :delim: ;
   :keepspace: true

   'a\'b'; c ;'d;e'
   ;x

.. csv-table:: Space
   :delim: space

   a b  c
   d e f

Title
=====

See `Title`_ and `Other`_.

Other
-----

.. _Title: http://x

.. csv-table:: F
   :file: rst-tables/data.csv
   :header-rows: 1
