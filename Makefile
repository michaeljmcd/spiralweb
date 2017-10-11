PYTHON_INTERPRETER = python3
TANGLE = $(PYTHON_INTERPRETER) -m spiralweb tangle
WEAVE = $(PYTHON_INTERPRETER) -m spiralweb weave

src: bootstrap spiralweb.sw
	$(TANGLE) spiralweb.sw

doc/spiralweb.md: spiralweb.sw
	$(WEAVE) spiralweb.sw

html: doc/spiralweb.html

dist: src html
	$(PYTHON_INTERPRETER) setup.py bdist_egg

doc/spiralweb.html: doc/spiralweb.md
	pandoc doc/spiralweb.md -o doc/spiralweb.html --smart --standalone --toc

bootstrap: 
	$(PYTHON_INTERPRETER) bootstrap.py spiralweb.sw

install: bootstrap dist
	$(PYTHON_INTERPRETER) setup.py install
