@doc SpiralWeb [out=spiralweb.md]
% SpiralWeb--A Literate Programming System
% Michael McDermott
% April 08, 2012

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

@code Man Page [out=spiralweb.1.md]
% SPIRALWEB(1) SpiralWeb User Manuals
% Michael McDermott
% April 8, 2012

# NAME

spiralweb - literate programming system

# SYNOPSIS

spiralweb [*options*] [*web-file*]...

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

: At any spot in a literate file, this directive

# OPTIONS

-c *CHUNK*, \--chunk=*CHUNK*
: Specifies one or more chunks to be tangled/woven

-t, \--tangle
: Performs a tangle operation _only_.

-w, \--weave
: Performs a weave operation _only_.

-f, \--force
: Ensures that any output will be written out, no matter what. By default,
    SpiralWeb first checks to see if the destination already exists and has
    identical contents, performing no write if this is so. With this
    option, the file must be written.
@=

## Parsing a Web ##

In order to parse a web, we will use
PLY^[[http://www.dabeaz.com/ply/](PLY Website)] for both lexing and
parsing. A hand-written parser was briefly considered, but avoided as being
too ponderous. Some experiments were made with pyparsing, but its default
policy of ignoring whitespace, while ordinarily useful, proved annoying to
work around. Some reading was done on LEPL, but it seemed very similar to
pyparsing. In the end, going old-school worked out very, very well.

Yes, that statement was past tense. The bootstrapper had to be written
without literate goodness (well, or use something like noweb, which would
add yet another layer to the build process--one that was just not
necessary).

### Representation of a Web ###

Before parsing a web, we will examine our representation for one. The
classes derived here will be how we represent the file in memory and will
also provide the methods that provide the real operations (i.e. tangling
and weaving) that we wish to perform on a web.

We define a web as a list of chunks upon which we can perform operations,
and will place all of these classes in a module entitled `api` for use by
other sections. Of note is the fact that, when we get around to making
SpiralWeb fully extensible, `api` will be the public-facing aspect of the
source.

@code API Classes [out=api.py]
@<SpiralWeb chunk class definitions>
@<SpiralWeb class definition>
@=

The main class to represent a web is `SpiralWeb` and its state is
comparably small--just a list of chunks and the base directory from which
all operations are being performed (normally, this is the base path to the
literate file, regardless of the location from which the
application was invoked). Beyond this, we provide tangle and weave
operations to actually perform the two major functions of a literate
system.

@code SpiralWeb class definition
class SpiralWeb():
    chunks = []
    baseDir = ''

    def __init__(self, chunks=[], baseDir=''):
        self.chunks = chunks
        self.baseDir = baseDir

        for chunk in self.chunks:
            chunk.setParent(self)

    def getChunk(self, name):
        for chunk in self.chunks:
            if chunk.name == name:
                return chunk

        return None

    @<Tangle Method>
    @<Weave Method>
@=

#### Tangling ####

Next, we turn our attention to the `tangle` method, as it is the one needed
to get to the point where we can weave. Tangling occurrs in two phases.
First, we expand all of our code chunks. Multiple specifications of the
same chunk are concatenated together and chunk references are expanded
until only strings need to be written out.

In the second phase, we are interested in outputting our results. The main
focus of SpiralWeb is build situations where we need to write each of our
webs out to a source tree. However, it only makes sense to ensure that
SpiralWeb works with either methodology. Our output strategy will be:

I. If the parameter `chunks` includes a list, we output each chunk in that
list, and no others.
II. If no list has been passed in, but a chunk named `*` exists, we output
that chunk (the `*` chunk is considered the "root chunk" in this case).
III. If neither of the previous conditions matches and there are one or
more chunks with an `out` parameter, we output all of them.
IV. If none of the above match, we raise an exception indicating the
problem.

Understanding that "output", in this context means to write a chunk's lines
out to the location specified by the `out` option, if it exists, and to
write them to `stdout`, if it does not.

@code Tangle Method
def tangle(self,chunks=None):
    outputs = {}

    for chunk in self.chunks:
        if chunk.type == 'code':
            if chunk.name in outputs.keys():
                outputs[chunk.name].lines += chunk.lines
                outputs[chunk.name].options = dict(outputs[chunk.name].options.items() + chunk.options.items())
            else:
                outputs[chunk.name] = chunk

    if chunks != None and len(chunks) > 0:
        for key in chunks:
            if outputs[key].hasOutputPath():
                outputs[key].writeOutput()
            else:
                print outputs[key].dumpLines()
    elif '*' in outputs.keys(): 
        content = outputs[key].dumpLines()

        if outputs['*'].hasOutputPath():
            outputs['*'].writeOutput()
        else:
            print content
    elif len(terminalChunks) > 0:
        for chunk in terminalChunks:
            chunk.writeOutput()
    else:
        raise BaseException('No chunks specified, no chunks with out attributes, and no root chunk defined')
        
    return outputs
@=

#### Weaving ####

Once we have tangling, we can turn our attention to weaving documentation.
Tangling is the simpler operation of the two, since it merely extracts and
outputs text. Weaving, on the other hand, requires some knowledge of the
final destination format.

Examples of this, include the setting of code chunks which in all but the
most plain of backends will require a little work to typeset.

@code Weave Method
def weave(self, chunks=None):
    outputs = {}

    for chunk in self.chunks:
        if chunk.name in outputs.keys():
            outputs[chunk.name].lines += chunk.lines
            outputs[chunk.name].options = dict(outputs[chunk.name].options.items() + chunk.options.items())
        else:
            outputs[chunk.name] = chunk

    for key in chunks:
        if outputs[key].hasOutputPath():
            outputs[key].writeOutput()
        else:
            print outputs[key].dumpLines()
@=

It turns out, ironically, that there are only two kinds of chunks that
actually matter: text-producing chunks (either document or code) and chunk
references.

We define both with a `dumpLines` method that will perform all resolutions
and produce final output for the given chunk. 

@code SpiralWeb chunk class definitions
class SpiralWebChunk():
    lines = []
    options = {}
    name = ''
    type = ''
    parent = None

    def getChunk(self, name):
        for chunk in self.lines:
            if not isinstance(chunk, basestring):
                if chunk.name == name:
                    return chunk
                elif chunk.getChunk(name) != None:
                    return chunk.getChunk(name)
        return None

    def setParent(self, parent):
        self.parent = parent

        for line in self.lines:
            if not isinstance(line, basestring):
                line.setParent(parent)

    def dumpLines(self, indentLevel=''):
        output = ''

        for line in self.lines:
            if isinstance(line, basestring):
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
        if isinstance(exp, basestring):
            for line in self.lines:
                exp += line
            return exp

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
            return refChunk.dumpLines(indentLevel=indentLevel+self.indentLevel)
        else:
            raise BaseException('No chunk named %s found' % self.name)

@=

### Lexical Analysis ###

We will package both the lexer and the parser into a single file,
`parser.py` and export a single function to return a list of objects,
representing the list of all web files passed in.

@code Lexer/Parser [out=parser.py]
import sys
import ply.lex as lex
import ply.yacc as yacc
from api import SpiralWebChunk, SpiralWebRef, SpiralWeb

@<Lexer Class>
@<Parser Class>
@=

As parsing is a sequential, two-step model (first lexing, then parsing), it
makes sense to break down the lexer first. Our token list is short and
actually fairly simple. We have two directives (`@@doc` and `@@code`) that
form our first two tokens. Then, there is the escaped at symbol (`@@@@`).

The portion of our target language that creates the most tokens is the
property list that can accompany any `@@doc` or `@@code` directive. As we
saw above, a property list as the form `[key=value?(,key=value)*]`.
Therefore, we can easily add the tokens `[`, `=`, `,` and `]` to our list.

Since whitespace is important, for either code or documentation chunks, we
need to add a newline token to the list.

Finally, within a code directive, we need the ability to reference a chunk
defined elsewhere, defined above as `@@<Chunk name>`. Before moving to the
code, we list out our tokens in EBNF:

    document directive = "@@doc" 
    code directive = "@@code"
    code end directive = "@@="
    open property list = "["
    close property list = "]"
    comma = ","
    equals = "="
    at = "@@@@"
    chunk reference = whitepace* "@@<" text ">"
    newline = "\n"
    text = "[^@@\[\]=,\n]+"

The only real points worthy of mention is the chunk reference whitespace
must be retained on its way to the parser in order to preserve
indentation.

@code Lexer Class
# Lexing definitions

class SpiralWebLexer:
    tokens = ('DOC_DIRECTIVE', 
              'OPEN_PROPERTY_LIST',
              'CLOSE_PROPERTY_LIST',
              'EQUALS',
              'COMMA',
              'CHUNK_REFERENCE',
              'CODE_DIRECTIVE',
              'CODE_END_DIRECTIVE',
              'NEWLINE',
              'AT_DIRECTIVE',
              'TEXT')

    t_TEXT = '[^@@\[\]=,\n]+'
    t_COMMA = r','
    t_DOC_DIRECTIVE = r'@@doc'
    t_CODE_DIRECTIVE = r'@@code'
    t_CODE_END_DIRECTIVE = r'@@='
    t_OPEN_PROPERTY_LIST = r'\['
    t_CLOSE_PROPERTY_LIST = r']'
    t_EQUALS = r'='

    def t_AT_DIRECTIVE(t):
        r'@@'
        t.value = '@@'
        return t

    def t_CHUNK_REFERENCE(t):
        r'[ \t]*@@<[^\]\n]+>[ \t]*'
        inputString = t.value.rstrip()
        refStart = inputString.find('@@<')

        t.value = {'indent' : inputString[0:refStart],
                   'ref' : inputString[refStart+2:len(inputString)-1]}
        return t

    def t_NEWLINE(t):
        r'\n+'
        t.lexer.lineno += len(t.value)
        return t

    def t_error(t):
        print "Illegal character '%s' on line %s" % (t.value[0], t.lineno)
        t.lexer.skip(1)

    def build(self,**kwargs):
        self.lexer = lex.lex(module=self, **kwargs)

    def lex(self, input):
        token_list = []

        self.build()
        self.lexer.input(input)

        while True:
            token = self.lexer.token()

            if not token: break
            token_list
@=

### Parsing ###

The parser will require a little more work, but not much. The grammar is
specified in its entirety below, but first we lay out the fundamental
groundwork.

We are really just building off of the groundwork provided by the lexer. In
it essence, this grammar is simple. Perhaps too simple (I honestly believe
that the simplicity of the grammar is what made the selection of
higher-level parser builders inefficient--they are all designed to make
hard grammars simple. Along the way, they make valid assumptions, usually
about whitespace, that seriously interfere with a truly simple grammar).

The grammar needs to parse out the basic directives that we outlined in the
manual page above. We will define the grammar in EBNF form, before
proceeding to the code:

    web = webline | empty
    webline = code definition | doc definition | doc line
    doc_line = text | newline | at directive | comma | open property list |
        close property list | equals 
    docdefn : doc_directive TEXT optionalpropertylist NEWLINE doclines

@code Parser Class
# Parser definitions

class SpiralWebParser:
    starting = 'web'

    def p_web(p):
        '''web : webtl web
               | empty'''
        if len(p) == 3:
            p[0] = [p[1]] + p[2]
        else:
            p[0] = []

    def p_webtl(p):
        '''webtl : codedefn
                 | docdefn
                 | doclines'''
        p[0] = p[1]

    def p_empty(p):
        'empty :'
        pass

    def p_doclines(p):
        '''doclines : TEXT
                    | NEWLINE
                    | AT_DIRECTIVE
                    | COMMA
                    | OPEN_PROPERTY_LIST
                    | CLOSE_PROPERTY_LIST
                    | EQUALS'''
        doc = SpiralWebChunk()
        doc.type = 'doc'
        doc.name = ''
        doc.options = {}
        doc.lines = [p[1]]
        p[0] = doc

    def p_docdefn(p):
        '''docdefn : DOC_DIRECTIVE TEXT optionalpropertylist NEWLINE doclines'''
        doc = SpiralWebChunk()
        doc.type = 'doc'
        doc.name = p[2].strip()
        doc.options = p[3]
        doc.lines = [p[5]]
        p[0] = doc

    def p_codedefn(p):
        '''codedefn : CODE_DIRECTIVE TEXT optionalpropertylist NEWLINE codelines CODE_END_DIRECTIVE
                    '''
        code = SpiralWebChunk()
        code.type = 'code'
        code.name = p[2].strip()
        code.options = p[3]
        code.lines = p[5]
        p[0] = code

    def p_codelines(p):
        '''codelines : codeline codelines
                     | empty'''
        if len(p) == 3:
           p[0] = [p[1]] + p[2]
        else:
           p[0] = []

    def p_codeline(p):
        '''codeline : TEXT 
                    | NEWLINE
                    | AT_DIRECTIVE
                    | OPEN_PROPERTY_LIST
                    | CLOSE_PROPERTY_LIST
                    | COMMA
                    | EQUALS
                    | chunkref'''
        doc = SpiralWebChunk()
        doc.type = 'doc'
        doc.name = ''
        doc.options = {}
        doc.lines = [p[1]]
        p[0] = doc

    def p_chunkref(p):
        '''chunkref : CHUNK_REFERENCE'''
        p[0] = SpiralWebRef(p[1]['ref'], p[1]['indent'])

    def p_optionalpropertylist(p):
        '''optionalpropertylist : propertylist 
                                | empty'''

        if p[1] == None:
           p[0] = {}
        else:
            p[0] = p[1]

    def p_propertylist(p):
        '''propertylist : OPEN_PROPERTY_LIST propertysequence CLOSE_PROPERTY_LIST'''
        p[0] = p[2]

    def p_propertysequence(p):
        '''propertysequence : empty 
                            | propertysequence1'''
        p[0] = p[1]

    def p_propertysequence1(p):
        '''propertysequence1 : property 
                             | propertysequence1 COMMA property'''
        if len(p) == 2:
           p[0] = p[1]
        else:
           p[0] = dict(p[1].items() + p[3].items())

    def p_property(p):
        '''property : TEXT EQUALS TEXT'''
        p[0] = {p[1] : p[3]}

    def build(self,**kwargs):
        self.lexer = SpiralWebLexer()
        self.lexer.build()

        self.parser = yacc.yacc(module=self, **kwargs)

    def parse(self, input):
        self.build()
        return self.parser.parse(fileInput)

@<Parsing Interface Functions>
@=

As we do not wish to leak implementation details to the interface, we will
define a simple function to parse the input. In order to farther distance
the parsing of a file from the basic input, we will define the function
(dubbed `parse_webs`) to accept a hashtable with a key (usually the path to
the web, but it could just be an arbitrary identifier) corresponding to a
single string with the input. It then turns around and returns a hashtable
with the same key, but instead of the string, a `SpiralWeb` object.

We will implement the actions (i.e. whether to tangle, weave, or both)
entirely to the application, which can call each web's interface at
leisure.

@code Parsing Interface Functions
def parse_webs(input_strings):
    output = {}
    parser = SpiralWebParser()

    for key, input in input_strings:
        output[key] = parser.parse(input)

    return output
@=

## The Command Line Application ##

In the previous sections, we defined the command-line syntax for the
invocation of `spiralweb`. Here we take that specification and combine it
with the APIs we defined previously to put it all together and create a
usable command line application.

To perform command line argument parsing, we will use the `argparse`
library that ships with Python

http://docs.python.org/library/argparse.html#module-argparse

@code Main [out=main.py]
import api
import parser
import argparse
import sys

if __name__ == '__main__':
    argparser = argparse.ArgumentParser(description='Literate programming system')
    argparser.add_argument('-c, --chunk', 
                           action='append',
                           help='Specify a chunk to operate on.')
    argparser.add_argument('-t, --tangle',
                           action='store_true',
                           help='Extract source code from web files.')
    argparser.add_argument('-w, --weave',
                           action='store_true',
                           help='Generate documentation from web files.')
    argparser.add_argument('-f, --force',
                           help='Force output to be written.')

    options = argparser.parse_args()
    print options
@=

// vim: set tw=75 ai: 
