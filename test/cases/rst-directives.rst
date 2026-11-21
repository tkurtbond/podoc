.. raw:: html

   <div>hi</div>

.. foo:: bar baz
   :name: myid
   :class: c1 c2
   :other: value

   Body *text*.

.. |u| unicode:: &#x263A; and x41 U+1F600 u12 \x2a é 0xZZ trademark

|u| here and |missing| and |img|.

.. |img| image:: a b.png
   :class: k1
   :align: left
   :target: http://x.org/a b


.. role:: kbd(literal)
.. role:: x(unknownparent)
.. role:: rh(raw)
   :format: latex

:kbd:`C-x` :x:`y` :rh:`\foo`

.. default-role:: kbd

`dflt`

.. |two| replace:: a

|two|

.. |multi| raw:: html

   <b>

|multi| inline

|multi|

.. Highlight:: python

::

   code

.. highlight::

::

   code2
