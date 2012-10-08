@doc SpiralWeb [out=doc/spiralweb.md]
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

@code Man Page [out=doc/spiralweb.1.md,lang=markdown]
% SPIRALWEB(1) SpiralWeb User Manuals
% Michael McDermott
% April 8, 2012

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

In order to parse a web, we will use
PLY^[plyWebsite] for both lexing and parsing. A hand-written parser was
briefly considered, but avoided as being too ponderous. Some experiments
were made with pyparsing, but its default policy of ignoring whitespace,
while ordinarily useful, proved annoying to work around. Some reading
was done on LEPL, but it seemed very similar to pyparsing. In the end,
going old-school worked out very, very well.

Yes, that statement was past tense. The bootstrapper had to be written
without literate goodness (or use something like noweb, which would
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

@code API Classes [out=spiralweb/api.py,lang=python]
import sys
import parser

@<SpiralWeb chunk class definitions>
@<SpiralWeb class definitions>
@=

The main class to represent a web is `SpiralWeb` and its state is
comparably small--just a list of chunks and the base directory from which
all operations are being performed (normally, this is the base path to the
literate file, regardless of the location from which the
application was invoked). Beyond this, we provide tangle and weave
operations to actually perform the two major functions of a literate
system.

@code SpiralWeb class definitions [lang=python]
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

@<Alternate SpiralWeb creation functions>
@=

In order to create more separation between the command-line presentation
layer and our main logic, we will define functions to parse input, given
the options we expect. In order to make this method generic, we will allow
the path parameter to be `None`. When this occurs, we assume that we need
to read `stdin` to get the input. In either event, we load the input into a
string, then parse it, returning the resultant `SpiralWeb` object.

@code Alternate SpiralWeb creation functions [lang=python]
def parseSwFile(path):
    handle = None

    if path == None:
        handle = sys.stdin
        path = 'stdin'
    else:
        handle = open(path, 'r')

    fileInput = handle.read()
    handle.close()

    chunkList = parser.parse_webs({path: fileInput})[path]

    return SpiralWeb(chunks=chunkList)
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
                outputs[chunk.name].options = dict(outputs[chunk.name].options.items() + chunk.options.items())
            else:
                outputs[chunk.name] = chunk

    terminalChunks = [x for x in self.chunks if x.hasOutputPath()]

    if chunks != None and len(chunks) > 0:
        for key in chunks:
            if outputs[key].hasOutputPath():
                outputs[key].writeOutput()
            else:
                print outputs[key].dumpLines()
    elif '*' in outputs.keys(): 
        content = outputs['*'].dumpLines()

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
        if isinstance(chunk, basestring):
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
                    print self.dispatchChunk(topLevelDocs[key])
    elif len(terminalChunks) > 0:
        for chunk in terminalChunks:
            self.writeOutChunk(chunk)
    else:
        for name, chunk in topLevelDocs.items():
            print self.dispatchChunk(chunk)

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

### Lexical Analysis ###

We will package both the lexer and the parser into a single file,
`parser.py` and export a single function to return a list of objects,
representing the list of all web files passed in.

@code Lexer/Parser [out=spiralweb/parser.py,lang=python]
import sys
import os
import ply.lex as lex
import ply.yacc as yacc
import api

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

@code Lexer Class [lang=python]
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

    def t_AT_DIRECTIVE(self, t):
        r'@@@@'
        t.value = '@@'
        return t

    def t_CHUNK_REFERENCE(self, t):
        r'[ \t]*@@<[^\]\n]+>[ \t]*'
        inputString = t.value.rstrip()
        refStart = inputString.find('@@<')

        t.value = {'indent' : inputString[0:refStart],
                   'ref' : inputString[refStart+2:len(inputString)-1]}
        return t

    def t_NEWLINE(self, t):
        r'\n+'
        t.lexer.lineno += len(t.value)
        return t

    def t_error(self, t):
        print "Illegal character '%s' on line %s" % (t.value[0], t.lineno)
        t.lexer.skip(1)

    @<Lexical Analysis Utility Methods>
@=

In order to ease the setup of our lexer, we will define the following
methods. 

`build` is a factory method of sorts. Most of the options are fairly self
explanatory. The most important ones are `debug` and `optimize`, whose
values may not be entirely obvious. 

PLY writes out `.out` files containing debugging information about the
grammar. In production, we do not wish this to occur and so turn off
"debugging".

Similarly, we disable optimization because this polutes the target
directory with Python files to represent a compiled lexer.

If we do not set these two options, the result is that the application
writes out junk files into the user's working directory.

@code Lexical Analysis Utility Methods [lang=python]
def build(self,**kwargs):
    self.lexer = lex.lex(module=self, optimize=False, debug=False, **kwargs)

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

@code Parser Class [lang=python]
# Parser definitions

class SpiralWebParser:
    starting = 'web'
    tokens = []

    def __init__(self):
        self.tokens = SpiralWebLexer.tokens
        self.build()

    def p_error(self, p):
        print ("Syntax error at token %(name)s at line %(line)i" % \
                {"line": p.lineno, "name": p.type })
        yacc.errok()

    def p_web(self, p):
        '''web : webtl web
               | empty'''
        if len(p) == 3:
            p[0] = [p[1]] + p[2]
        else:
            p[0] = []

    def p_webtl(self, p):
        '''webtl : codedefn
                 | docdefn
                 | doclines'''
        p[0] = p[1]

    def p_empty(self, p):
        'empty :'
        pass

    def p_doclines(self, p):
        '''doclines : TEXT
                    | NEWLINE
                    | AT_DIRECTIVE
                    | COMMA
                    | OPEN_PROPERTY_LIST
                    | CLOSE_PROPERTY_LIST
                    | EQUALS'''
        doc = api.SpiralWebChunk()
        doc.type = 'doc'
        doc.name = ''
        doc.options = {}
        doc.lines = [p[1]]
        p[0] = doc

    def p_docdefn(self, p):
        '''docdefn : DOC_DIRECTIVE TEXT optionalpropertylist NEWLINE doclines'''
        doc = api.SpiralWebChunk()
        doc.type = 'doc'
        doc.name = p[2].strip()
        doc.options = p[3]
        doc.lines = [p[5]]
        p[0] = doc

    def p_codedefn(self, p):
        '''codedefn : CODE_DIRECTIVE TEXT optionalpropertylist NEWLINE codelines CODE_END_DIRECTIVE
                    '''
        code = api.SpiralWebChunk()
        code.type = 'code'
        code.name = p[2].strip()
        code.options = p[3]
        code.lines = p[5]
        p[0] = code

    def p_codelines(self, p):
        '''codelines : codeline codelines
                     | empty'''
        if len(p) == 3:
           p[0] = [p[1]] + p[2]
        else:
           p[0] = []

    def p_codeline(self, p):
        '''codeline : TEXT 
                    | NEWLINE
                    | AT_DIRECTIVE
                    | OPEN_PROPERTY_LIST
                    | CLOSE_PROPERTY_LIST
                    | COMMA
                    | EQUALS
                    | chunkref'''
        doc = api.SpiralWebChunk()
        doc.type = 'doc'
        doc.name = ''
        doc.options = {}
        doc.lines = [p[1]]
        p[0] = doc

    def p_chunkref(self, p):
        '''chunkref : CHUNK_REFERENCE'''
        p[0] = api.SpiralWebRef(p[1]['ref'], p[1]['indent'])

    def p_optionalpropertylist(self, p):
        '''optionalpropertylist : propertylist 
                                | empty'''

        if p[1] == None:
           p[0] = {}
        else:
            p[0] = p[1]

    def p_propertylist(self, p):
        '''propertylist : OPEN_PROPERTY_LIST propertysequence CLOSE_PROPERTY_LIST'''
        p[0] = p[2]

    def p_propertysequence(self, p):
        '''propertysequence : empty 
                            | propertysequence1'''
        p[0] = p[1]

    def p_propertysequence1(self, p):
        '''propertysequence1 : property 
                             | propertysequence1 COMMA property'''
        if len(p) == 2:
           p[0] = p[1]
        else:
           p[0] = dict(p[1].items() + p[3].items())

    def p_property(self, p):
        '''property : TEXT EQUALS TEXT'''
        p[0] = {p[1] : p[3]}

    @<Parsing Factory Functions>

@<Parsing Interface Functions>
@=

Our factory functions for the parser closely mirror the ones set up for the
lexer and the definitions follow below. The options are less than clear,
but are set using the same rationale as the lexer. Refer to the commentary
in that section for more information.

@code Parsing Factory Functions [lang=python]
def build(self,**kwargs):
    self.lexer = SpiralWebLexer()
    self.lexer.build()

    self.parser = yacc.yacc(module=self, optimize=False, debug=False, **kwargs)

def parse(self, input):
    return self.parser.parse(input)
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

@code Parsing Interface Functions [lang=python]
def parse_webs(input_strings):
    output = {}
    parser = SpiralWebParser()

    for key, input in input_strings.iteritems():
        output[key] = parser.parse(input)

    return output
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

@code Main [out=spiralweb/main.py,lang=python]
import api
import parser
import argparse
import sys

def main():
    argparser = argparse.ArgumentParser(prog='spiralweb', description='Literate programming system')
    argparser.add_argument('--version', action='version', version='0.2')

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
                web = api.parseSwFile(path)

                if options.command == 'tangle':
                    web.tangle()
                elif options.command == 'weave':
                    web.weave()
            except BaseException, e:
                print "ERROR: " + str(e)

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
        version = '0.2',
        packages = ['spiralweb'],
        description = 'A lightweight-markup based literate programming system',    
        author = 'Michael McDermott',
        author_email = 'mmcdermott@@mad-computer-scientist.com',
        url = 'https://gitorious.org/spiralweb',
        keywords = ['literate programming', 'lp', 'markdown'],
        license = 'MIT',
        entry_points = {
            'console_scripts': [
                'spiralweb = spiralweb.main:main'
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

// vim: set tw=75 ai: 
