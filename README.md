# SpiralWeb

SpiralWeb is a literate programming system (see [http://www.literateprogramming.com/index.html](http://www.literateprogramming.com/index.html)
for more information) that uses lightweight text
markup (Markdown, with Pandoc extensions being the only option at the
moment) as its default backend and provides simple, pain-free build
integration to make building real-life systems easy.

The source is, itself, written in SpiralWeb. A minimal version of the parser
is provided as a Python script. To build with a stock Python install, run the
following command to tangle sources:

    python bootstrap.py spiralweb.sw

This command will extract the sources into the `spiralweb` directory and a `setup.py`
file to the main source directory. To build an egg or install, use:

    python setup.py install

## Dependencies

SpiralWeb relies on PLY to handle its parsing.
