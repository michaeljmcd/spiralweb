@doc SpiralWeb [out=doc/spiralweb.md]
% SpiralWeb--A Literate Programming System
% Michael McDermott
% October 11, 2017

# SpiralWeb--A Literate Programming System #

SpiralWeb was born out of a certain discontent with existing literate
programming tools. Most notably, they are almost universally dependent on a
TeX or LaTeX toolchain. From a historical point of view, this is
understandable, as the birth of the two systems (TeX and Literate
Programming) were tied, even for their creator.

However, I do not really care for composing in TeX for the same reason I
do not care to compose in HTML (despite the fact that I could write HTML in
my sleep, largely thanks to an abundance of time doing web development):
the markup is simply too distracting, requiring far too much thought to be
put into markup and not enough into content.

Another big itch that SpiralWeb aims to scratch, is making the build
process simpler. With current tools (mostly, I am thinking of noweb here),
writing build scripts is annoying as it requires respecifying the entire
web structure within the build to make it work. As a direct result, updates
to program structures must be made in at least three places: the web
itself, the tangling portion of the build, and the weaving portion of the
build.

SpiralWeb, however, will integrate the functionality of the `cpif` script
from noweb.

## Usage ##

SpiralWeb aims to be an LP system that is easier to use for a production
system than most of the systems in existence. By default, SpiralWeb expects
a list of web files (we name them as `.sw` files, but any other extension
can be used as well).

We will define our target usage succinctly, in the form of the man page for
the executable `spiralweb`.

@code Man Page [out=doc/spiralweb.1.md,lang=markdown]
% SPIRALWEB(1) SpiralWeb User Manuals
% Michael McDermott
% October 11, 2017

# NAME

spiralweb - literate programming system

# SYNOPSIS

spiralweb command [*options*] [*web-file*]...

# DESCRIPTION

SpiralWeb is a literate programming system that uses lightweight text
markup (Markdown, with Pandoc extensions being the only option at the
moment) as its default backend and provides simple, pain-free build
integration to make building real-life systems easy.

When invoked, SpiralWeb performs both tangling (the process of extracting
source code from literate files) and weaving (the process of producing
documentation from literate files) simultaneously.

A literate file (or web, denoted by a .sw extension, by convention though
not by necessity) is made up of the following directives:

`@@doc (Name)? ([option=value,option2=value2...])?`

:   Denotes a document chunk. At the moment, the only option that is used
is the `out` parameter, which specifies a path (either absolutely or
relative to the literate file it appears in) for the woven output to be
written to.

`@@code (Name)? ([option=value,option2=value2...])?`

: Denotes the beginning of a code chunk. At present, the following options
are used:

. `out` which specifies a path (either absolutely or relative to the
literate file it appears in) for the tangled output to be written to.
. `lang` which specifies a language that the code is written in. This
attribute is not used except in the weaver, which uses it when emitting
markup, so that the code can be highlighted properly.

`@@<Name>`

: Within a code chunk, this indicates that another chunk will be inserted
at this point in the final source code. It is important to note that
SpiralWeb is indentation-sensitive, so any preceding spaces or tabs before
the reference will be used as the indentation for every line in the chunks
output--even if there is _also_ indentation in the chunk.

`@@@@`

: At any spot in a literate file, this directive results in a simple `@@`
symbol.  

# OPTIONS

At least one command must be specified, and the command can be one of the
following:

`tangle`
:  Extracts the compiler-readable source from each web provided at the
   command line.

`weave`
:  Creates backend-ready source for generating documentation.

`help`
:  Prints out a help message and exits.

If no files are specified at the command line, the web will be read from
stdin.

The following options apply to each of the commands listed above, except
help:

-c *CHUNK*, \--chunk=*CHUNK*
: Specifies one or more chunks to be tangled/woven

-f, \--force
: Ensures that any output will be written out, no matter what. By default,
    SpiralWeb first checks to see if the destination already exists and has
    identical contents, performing no write if this is so. With this
    option, the file must be written.
@=

## Parsing a Web ##

We will be using a recursive descent parser implemented with a library for
Clojure named Edessa^[edessaWebsite]. This means that we will use semantic
actions at the terminals to the grammar that will produce our internal
representation of a web. We will build this grammar up in two layers within
the grammar, one that deals in in the core tokens and another layer that
assembles those into chunks off of which the remaining operations will be
performed.

Our representation for tokens will be simple maps with `:type` and `:value`
keys on them, like the following for the `@doc` token:

    {:type :doc-directive :value "@doc"}

This will keep our representations fairly light and easy to work with.

### Tokens ###

We can identify a list of tokens based on our earlier description of the
SpiralWeb language.

The first set of tokens are the directives that begin and end chunks.

* `@doc` - begin a documentation chunk.
* `@code` - begin a code chunk.
* `@end` - to end a code block.

The existence of these three implies a fourth, a way to escape the at
symbol, which we designated as `@@`. Document and code chunks can have
property lists, which imply the need for the following tokens.

* `[`
* `]`
* `=`
* `,`

Finally, we have long strings of text and places where whitespace is
permitted. From this list 

@code Tokens
(def non-breaking-ws
  (parser (one-of [\space \tab])
          :name "Non-breaking whitespace"))
(def nl
  (parser (match \newline)
          :name "Newline"
          :using (fn [_] {:type :newline :value (str \newline)})))

(def t-text
  (parser
   (plus
    (parser (not-one-of [\@ \[ \] \= \, \newline])
            :name "Non-Reserved Characters"))
   :using (fn [x] {:type :text :value (apply str x)})
   :name "Text Token"))

(def code-end
  (parser (literal "@end")
          :using (fn [_] {:type :code-end :value "@end"})
          :name "Code End"))

(def doc-directive
  (parser (literal "@doc")
          :using (fn [_] {:type :doc-directive :value "@doc"})))

(def code-directive
  (parser (literal "@code")
          :using (fn [_] {:type :code-directive :value "@code"})))

(def at-directive
  (parser (literal "@@")
          :using (fn [_] {:type :at-directive :value "@@"})))

(def comma
  (parser (match \,)
          :using (fn [_] {:type :comma :value ","})))

(def t-equals
  (parser (match \=)
          :using (fn [_] {:type :equals :value "="})))

(def open-proplist
  (parser (match \[)
          :using (fn [_] {:type :open-proplist :value "["})))

(def close-proplist
  (parser (match \])
          :using (fn [_] {:type :close-proplist :value "]"})))
@=

### Grammar ###

A web is, at the end of the day, a web of chunks. This idea is easy to
represent. Most of these rules require predicates to match tokens. We will
define these first in order to simplify what follows.

@code Token Predicates
(defn- code-end? [t] (= (:type t) :code-end))
(defn- prop-token? [t] (= (:type t) :properties))
@=

Which leads us to the main rule for parsing a web.

@code Web Rule
(def web (star 
          (choice 
           code-definition 
           doc-definition 
           doclines)))
@=

The definition starts with the explicit chunk definitions and then uses
`doclines` as a fallback. Let's consider the code definition first.

@code Code Chunk Rule
(def code-definition
  (parser (then 
           code-directive 
           t-text 
           (optional property-list) 
           nl 
           (plus codeline)
           code-end)
          :using
          (fn [x]
            (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
                  props (flatten (map :value (filter prop-token? all-tokens)))]
              {:type :code
               :options props
               :name (-> n :value trim)
               :lines (filter #(not (or (prop-token? %) (code-end? %))) lines)}))))
@=

Both code and documentation chunks allow properties to be associated with
the chunk. This is to support output and formatting options. A property
list is just a series of name-value pairs surrounded by brackets.

@code Property List Rule
(def property
  (parser (then
           t-text 
           t-equals
           t-text)
          :using
          (fn [x]
            (let [scrubbed (filter (comp not nil?) x)]
              {:type :property
              :value {:name (-> scrubbed first :value trim)
              :value (-> scrubbed (nth 2) :value trim)}}))))

(def property-sequence (choice 
                        (then comma property)
                        property))

(def property-list
  (parser (then open-proplist
           (star property-sequence)
           close-proplist
           (star non-breaking-ws))
          :using
          (fn [x]
            {:type :properties :value
             (filter (fn [y] (and (not (nil? y))
                                  (= :property (:type y)))) x)})))

@=

The core content of a code chunk is obviously a series of lines of code.

@code Code Line Rule
(def codeline
  (parser
   (choice t-text
           nl
           at-directive
           comma
           t-equals
           open-proplist
           close-proplist
           chunkref)
   :name "Codeline"))
@=

Most of these options are simply unescaped bits of text. The one chunk that
stands out is chunk references. These are the heart of a web, the linking
between different code chunks.

@code Chunk Reference Rule
(def chunkref
  (parser
   (then
    (star non-breaking-ws)
    (match \@) (match \<)
    (plus (not-one-of [\> \newline]))
    (match \>)
    (star non-breaking-ws))
   :using
   (fn [x]
     (let [ref-text (apply str x)
           trimmed-ref-text (trim ref-text)]
       {:type :chunk-reference
        :name (subs trimmed-ref-text 2 (- (count trimmed-ref-text) 1))
        :indent-level (index-of ref-text "@<")}))
   :name "Chunk Reference"))
@=

Rolling all the way back up to the top, we have ignored document lines.
This is largely because document lines are easy so we define it here.

@code Document Line Rule
(def docline
  (parser
   (choice t-text
           nl
           at-directive
           comma
           t-equals
           open-proplist
           close-proplist)
   :name "Docline"))

(def doclines (plus docline))
@=

Now, Clojure's loading encourages a bottom-up listing of functionality
so we will restate our parsing rules accordingly.

@code Parsing Rules
@<Document Line Rule>
@<Chunk Reference Rule>
@<Property List Rule>
@<Code Line Rule>
@<Code Chunk Rule>
@<Web Rule>
@=

### Conclusion ###

In order to make all this code useful, we need to assemble it into a module
to be used in our codebase.

@code [out=src/spiralweb/parser.clj]
(ns spiralweb.parser
  (:require [clojure.string :refer [starts-with? trim index-of]]
            [taoensso.timbre :as t :refer [debug error]]
            [edessa.parser :refer :all]))

@<Tokens>
@<Token Predicates>
@<Parsing Rules>
@=

## Tangling ##

Next, we turn our attention to the `tangle` method, as it is the one needed
to get to the point where we can weave. Tangling occurrs in two phases.
First, we expand all of our code chunks. Multiple specifications of the
same chunk are concatenated together and chunk references are expanded
until only strings need to be written out.

In the second phase, we are interested in outputting our results. The main
focus of SpiralWeb is build situations where we need to write each of our
webs out to a source tree. However, it only makes sense to ensure that
SpiralWeb works with either methodology. Our output strategy will be:

I.  If the parameter `chunks` includes a list, we output each chunk in that
    list, and no others.
II.  If no list has been passed in, but a chunk named `*` exists, we output
     that chunk (the `*` chunk is considered the "root chunk" in this case).
III.  If neither of the previous conditions matches and there are one or
      more chunks with an `out` parameter, we output all of them.
IV.  If none of the above match, we raise an exception indicating the
     problem.

Understanding that "output", in this context means to write a chunk's lines
out to the location specified by the `out` option, if it exists, and to
write them to `stdout`, if it does not.

@code Tangle Method [lang=python]
def tangle(self,chunks=None):
    outputs = {}

    for chunk in self.chunks:
        if chunk.type == 'code':
            if chunk.name in outputs.keys():
                outputs[chunk.name].lines += chunk.lines
                outputs[chunk.name].options = dict(list(outputs[chunk.name].options.items()) + list(chunk.options.items()))
            else:
                outputs[chunk.name] = chunk

    terminalChunks = [x for x in self.chunks if x.hasOutputPath()]

    if chunks != None and len(chunks) > 0:
        for key in chunks:
            if outputs[key].hasOutputPath():
                outputs[key].writeOutput()
            else:
                print(outputs[key].dumpLines())
    elif '*' in outputs.keys(): 
        content = outputs['*'].dumpLines()

        if outputs['*'].hasOutputPath():
            outputs['*'].writeOutput()
        else:
            print(content)
    elif len(terminalChunks) > 0:
        for chunk in terminalChunks:
            chunk.writeOutput()
    else:
        raise BaseException('No chunks specified, no chunks with out attributes, and no root chunk defined')
        
    return outputs
@=

## Weaving ##

Once we have tangling, we can turn our attention to weaving documentation.
Tangling is the simpler operation of the two, since it merely extracts and
outputs text. Weaving, on the other hand, requires some knowledge of the
final destination format.

Examples of this, include the setting of code chunks which in all but the
most plain of backends will require a little work to typeset. Our basic
method will be expand chunks (the same way we do when tangling) and hand
them off to the backend class to do the real work.

As we go forward, we want backends to be pluggable without modifying the
main source for SpiralWeb. The vision is to implement a full plugin system.
But, for the time being, we will write a hard-coded backed with a class
structure meant to facilitate the automatic loading of derivors in the
future.

@code Weave Method [lang=python]
def weave(self, chunks=None):
    backend = PandocMarkdownBackend()

    outputs = self.resolveDocumentation()
    backend.output(outputs, chunks)
@=

Next we need to define what it means to resolve the documentation chunks.
Because we have a `@@doc` directive, we enable a single physical web to
output multiple woven documentation files. 

We can expect that we will receive an arbitrary sequence of chunks. We want
to combine all of the chunks separated by any `@@doc` directives under a
single heading. The beginning of the file can be thought of as an implicit
`@@doc` directive.

To make it clear, we would expect the following file:

    This is an example script.

    @@code test.sh
    #!/bin/sh

    echo test
    @@=

    More examples.

    @@doc Example
    
    More test.

    @@code test2.sh
    #!/bin/sh

    echo test2
    @@=

To parse in the following chunk list:

1. `doc` ("This is an example script. \\n")
2. `code` \[test.sh] ("#!/bin/sh\n   echo test")
3. `doc` ("More examples")
4. `doc` \[Example] ("More test.") 
5. `code` \[test2.sh] ("#!/bin/sh\\n  echo test2")

The end result should combine chunks 1-3 under a single documentation
chunk and chunks 4-5 under another, so that if chunks are passed to the
output sequence, we can dump those out alone.

Our method will process the chunk list until we get this result, we then
return it as a dictionary to the caller.

@code Weave Method [lang=python]
def resolveDocumentation(self):
    documentation_chunks = {}
    last_doc = None

    for chunk in self.chunks:
        if (chunk.type == 'doc' and chunk.name != last_doc \
            and chunk.name != ''):
            last_doc = chunk.name
        elif last_doc == None:
            if chunk.type == 'doc':
                last_doc = chunk.name
            else:
                doc = SpiralWebChunk()
                doc.type = 'doc'
                doc.name = '*'
                last_doc = '*'

                documentation_chunks[doc.name] = doc
        
        if last_doc in documentation_chunks:
            documentation_chunks[last_doc].lines.append(chunk)
        else:
            documentation_chunks[last_doc] = chunk

    return documentation_chunks
@=

All backends must derive from a base class which defines the high-level
output operations along with reasonable defaults. The main starting point
for any backend is `dispatchChunk` which accepts a chunk and then decides
which of the main method stubs to call. It is expected that the default
implementation in `SpiralWebBackend` will suffice. Nonetheless, it can be
altered by other implementors should they so desire it.

We will look at the `type` attribute of the chunk and call the appropriate
method out of this list: `formatDoc`, `formatCode`, and `formatRef`. The
base backend will define each of these methods to simply return the text
from the chunk as it is passed in. This is clearly not very useful, but it
gives a good fallback.

@code SpiralWeb class definitions [lang=python]
class SpiralWebBackend():
    def dispatchChunk(self, chunk):
        if isinstance(chunk, str):
            return chunk
        elif chunk.type == 'doc':
            return self.formatDoc(chunk)
        elif chunk.type == 'code':
            return self.formatCode(chunk)
        elif chunk.type == 'ref':
            return self.formatRef(chunk)
        else:
                raise BaseException('Unrecognized chunk type (something must have gone pretty badly wrong).')

    def formatDoc(self, chunk):
        return chunk.dumpLines()

    def formatCode(self, chunk):
        return chunk.dumpLines()

    def formatRef(self, chunk):
        return chunk.dumpLines()

    @<SpiralWebBackend Output Methods>
@=

Once we have handled our basic formatting, we need to actually output the
user's request. Again, this method is not likely to have any reason to
change in inheriting classes, but we define it here for ease and just in
case. Our basic logic closely follows that of the `tangle` method above.

I. If a non-empty list of chunks has been provided to export, we will
output all documentation chunks of the same name. Please not that there
can be documentation and code chunks of the same name without error.
II. If there is one or more terminal (i.e. a `@@doc` directive with an
`out` parmeter) write it out.
III. If none of the above apply, concatenate all output and write it to
`stdout`.

@code SpiralWebBackend Output Methods [lang=python]
def output(self, topLevelDocs, chunksToOutput):
    terminalChunks = [x for w, x in topLevelDocs.items() \
                      if x.type == 'doc' and x.hasOutputPath()]

    if chunksToOutput != None and len(chunksToOutput) > 0:
        for key in topLevelDocs:
            if topLevelDocs[key].type == 'doc':
                if topLevelDocs[key].hasOutputPath():
                    self.writeOutChunk(topLevelDocs[key])
                else:
                    print(self.dispatchChunk(topLevelDocs[key]))
    elif len(terminalChunks) > 0:
        for chunk in terminalChunks:
            self.writeOutChunk(chunk)
    else:
        for name, chunk in topLevelDocs.items():
            print(self.dispatchChunk(chunk))

def writeOutChunk(self, chunk):
    if not 'out' in chunk.options:
        raise BaseException('When writing out a chunk with writeOutChunk an output parameter is expected')
    else:
        with open(chunk.options['out'], 'w') as outFile:
            outFile.write(self.dispatchChunk(chunk))
@=

With our superclass acting as a superstructure, we define the Pandoc
backend. Documentation lines will be passed through verbatim as we need to
do no extra processing on them. Code lines, on the other hand, will require
a little more work. We will format them for Markdown as delimited code
blocks.

@code SpiralWeb class definitions [lang=python]
class PandocMarkdownBackend(SpiralWebBackend):
    def formatDoc(self, chunk):
        lines = [self.dispatchChunk(x) for x in chunk.lines] 
        return ''.join(lines)

    def formatCode(self, chunk):
        leader = "~~~~~~~~~~~~~~~~~"
        options = ''

        if chunk.options.get('lang') != None:
            options = '{.%(language)s .numberLines}' % \
                {'language': chunk.options.get('lang')}

        lines = [self.dispatchChunk(x) for x in chunk.lines]

        return "%(leader)s%(options)s\n%(code)s%(trailer)s\n" % \
            {"leader": leader, "code": ''.join(lines),
             "trailer": leader, "options": options}

    def formatRef(self, chunk):
        return "<%(name)s>" % {"name": chunk.name}
@=

#### Web Components ####

It turns out, ironically, that there are only two kinds of chunks that
actually matter: text-producing chunks (either document or code) and chunk
references.

We define both with a `dumpLines` method that will perform all resolutions
and produce final output for the given chunk. 

@code SpiralWeb chunk class definitions [lang=python]
class SpiralWebChunk():
    lines = []
    options = {}
    name = ''
    type = ''
    parent = None

    def getChunk(self, name):
        for chunk in self.lines:
            if not isinstance(chunk, str):
                if chunk.name == name:
                    return chunk
                elif chunk.getChunk(name) != None:
                    return chunk.getChunk(name)
        return None

    def setParent(self, parent):
        self.parent = parent

        for line in self.lines:
            if not isinstance(line, str):
                line.setParent(parent)

    def dumpLines(self, indentLevel=''):
        output = ''

        for line in self.lines:
            if isinstance(line, str):
                output += line

                if line.find("\n") != -1:
                    output += indentLevel
            else:
                output += line.dumpLines(indentLevel)

        return output

    def hasOutputPath(self):
        return 'out' in self.options.keys()

    def writeOutput(self):
        if self.hasOutputPath():
            content = self.dumpLines()
            path = self.options['out']

            with open(path, 'w') as fileHandle:
                fileHandle.write(content)
        else:
            raise BaseException('No output path specified')

    def __add__(self, exp):
        if isinstance(exp, str):
            for line in self.lines:
                exp += line
            return exp
        else:
            merged = SpiralWebChunk()
            merged.lines = self.lines + exp.lines
            merged.name = self.name
            merged.type = self.type
            merged.parent = self.parent
            merged.options = self.options

            return merged

class SpiralWebRef():
    name = ''
    indentLevel = 0
    parent = None
    type = 'ref'

    def __init__(self, name, indentLevel=''):
        self.name = name
        self.indentLevel = indentLevel

    def __add__(self, exp):
        return exp + self.parent.getChunk(name).dumpLines(indentLevel=self.indentLevel)

    def getChunk(self, name):
        if name == self.name:
            return self
        else:
            return None

    def setParent(self, parent):
        self.parent = parent

    def dumpLines(self, indentLevel=''):
        refChunk = self.parent.getChunk(self.name)

        if refChunk != None:
            return indentLevel + self.indentLevel + refChunk.dumpLines(indentLevel=indentLevel+self.indentLevel)
        else:
            raise BaseException('No chunk named %s found' % self.name)

@=

## The Command Line Application ##

In the previous sections, we defined the command-line syntax for the
invocation of `spiralweb`. Here we take that specification and combine it
with the APIs we defined previously to put it all together and create a
usable command line application.

To perform command line argument parsing, we will use the `argparse`
library that ships with Python[^argparse]. Once the command line arguments
have been parsed, we will create one or more `SpiralWeb` objects (one for
each file) and act on them as indicated by our arguments.

The goal is for SpiralWeb to have a sort of CLI DSL, as is the case with
many good command line utilities, like `git` or `svn`. Towards that end, we
will use the subparser ability of `argparse` to build parsers to handle
each of our commands. We can then act upon what is presented us.

@code Main [out=spiralweb/__main__.py,lang=python]
from spiralweb.api import parseSwFile
import parser
import argparse
import sys

def main():
    argparser = argparse.ArgumentParser(prog='spiralweb', description='Literate programming system')
    argparser.add_argument('--version', action='version', version='0.3')

    subparsers = argparser.add_subparsers(dest='command')

    tangle_parser = subparsers.add_parser('tangle', help='Extract source files from SpiralWeb literate webs')
    tangle_parser.add_argument('files', nargs=argparse.REMAINDER)

    weave_parser = subparsers.add_parser('weave', help='Generate documentation source files from SpiralWeb literate webs')
    weave_parser.add_argument('files', nargs=argparse.REMAINDER)

    help = subparsers.add_parser('help', help='Print help')

    options = argparser.parse_args()

    if options.command == 'help':
        argparser.print_help()
    else:
        if len(options.files) == 0:
            options.files.append(None)

        for path in options.files:
            try:
                web = parseSwFile(path)

                if options.command == 'tangle':
                    web.tangle()
                elif options.command == 'weave':
                    web.weave()
            except BaseException as e:
                print("ERROR: " + str(e))

if __name__ == '__main__':
    main()
@=

## Packaging ##

In order to ease installation, we will use setuptools. Because PLY
generates code, we have no dependencies outside of the base Python install.

@code setuptools file [out=setup.py,lang=python]
from setuptools import setup, find_packages

setup(
        name = 'spiralweb',
        version = '0.3',
        packages = ['spiralweb'],
        description = 'A lightweight-markup based literate programming system',    
        author = 'Michael McDermott',
        author_email = 'mmcdermott@@mad-computer-scientist.com',
        url = 'https://github.com/michaeljmcd/spiralweb',
        keywords = ['literate programming', 'lp', 'markdown'],
        license = 'MIT',
        install_requires = ['ply'],
        entry_points = {
            'console_scripts': [
                'spiralweb = spiralweb.__main__:main'
            ]},
        long_description = """\
SpiralWeb is a literate programming system that uses lightweight text
markup (Markdown, with Pandoc extensions being the only option at the
moment) as its default backend and provides simple, pain-free build
integration to make building real-life systems easy.
"""
)
@=

## Conclusion ##

As we wrap up, our main conclusions are to look forward to the sorts of
advancements we would like to see in the next version:

* Indexing--unlike noweb and funnelweb, we did not include indexing. The
  plan would be to add an `@@index` directive to the grammar that allows
  for web-wide and chunk-specific indexing.
* Allow external webs to be included in a web.

## References ##

[^argparse]: <http://docs.python.org/library/argparse.html#module-argparse>
[^plyWebsite]: (PLY Website)[http://www.dabeaz.com/ply/]
[^edessaWebsite]: (Edessa on Github)[https://github.com/michaeljmcd/edessa]

// vim: set tw=75 ai: 
