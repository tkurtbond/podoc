Before |s|.

.. include:: rst-include/part.rst

After |s|.

.. include:: rst-include/part.rst
   :start-line: 2
   :end-line: 3

.. include:: rst-include/code.txt
   :literal:

.. include:: rst-include/code.txt
   :code: python
   :name: cc
   :class: k1 k2
   :number-lines: 10

.. include:: rst-include/part.rst
   :start-after: three
   :end-before: |s|

.. include:: rst-include/sub/s.rst

.. include:: missing.rst

Done.
