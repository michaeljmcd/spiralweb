PYTHON_INTERPRETER = python3

src: spiralweb.sw
	spiralweb tangle spiralweb.sw && python spiralweb/main.py tangle tests.sw

doc/spiralweb.md: spiralweb.sw
	spiralweb weave spiralweb.sw

dist: src
	$(PYTHON_INTERPRETER) setup.py bdist_egg

html: doc/spiralweb.html

doc/spiralweb.html: doc/spiralweb.md
	pandoc doc/spiralweb.md -o doc/spiralweb.html --smart --standalone --toc

bootstrap: 
	$(PYTHON_INTERPRETER) bootstrap.py spiralweb.sw
