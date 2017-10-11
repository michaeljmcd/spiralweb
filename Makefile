PYTHON_INTERPRETER = python3
TANGLE = $(PYTHON_INTERPRETER) spiralweb/main.py tangle
WEAVE = $(PYTHON_INTERPRETER) spiralweb/main.py weave

src: bootstrap spiralweb.sw
	$(TANGLE) spiralweb.sw

doc/spiralweb.md: spiralweb.sw
	$(WEAVE) spiralweb.sw

dist: src
	$(PYTHON_INTERPRETER) setup.py bdist_egg

html: doc/spiralweb.html

doc/spiralweb.html: doc/spiralweb.md
	pandoc doc/spiralweb.md -o doc/spiralweb.html --smart --standalone --toc

bootstrap: 
	$(PYTHON_INTERPRETER) bootstrap.py spiralweb.sw

install: bootstrap dist
	$(PYTHON_INTERPRETER) setup.py install
