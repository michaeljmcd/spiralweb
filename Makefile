src: spiralweb.sw
	spiralweb tangle spiralweb.sw && python spiralweb/main.py tangle tests.sw && mv *tab.py spiralweb/

doc/spiralweb.md: spiralweb.sw
	spiralweb weave spiralweb.sw

dist: src
	python setup.py bdist_egg

html: doc/spiralweb.html

doc/spiralweb.html: doc/spiralweb.md
	pandoc doc/spiralweb.md -o doc/spiralweb.html --smart --standalone
