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

In order to parse a web, we will be handrolling a lexer and parser, using the
ideas put forth by Rob Pike.

@code SpiralWeb Lexer [out=lexer.go,lang=go]
package main

import (
    "bufio"
)

type LexemeType int

const (
    ILLEGAL LexemeType = iota
    EOF

    DOC_DIRECTIVE
    OPEN_PROPERTY_LIST
    CLOSE_PROPERTY_LIST
    EQUALS
    COMMA
    CHUNK_REFERENCE
    CODE_DIRECTIVE
    CODE_END_DIRECTIVE
    NEWLINE
    AT_DIRECTIVE
    TEXT
)

type Lexeme struct {
    lexemeType LexemeType
    value string
}

type Lexer struct {
    inputStream *bufio.Reader
    output chan Lexeme
}

func NewLexer(inputStream *bufio.Reader) *Lexer {
    return &Lexer{inputStream: inputStream}
}
@=

## The Command Line Application ##

In the previous sections, we defined the command-line syntax for the
invocation of `spiralweb`. Here we take that specification and combine it
with the APIs we defined previously to put it all together and create a
usable command line application.

We will use Golang's `flag` package ^[flagpackage] to parse out the command line
parameters. The general usage of this package is to first define the flags, then
run the parser, as we see here.

@code CLI [out=spiralweb.go,lang=go]
package main

import (
    "flag"
    "fmt"
    "os"
    "log"
)

func main() {
    @<Logging Setup>
    @<Flag Definitions>
    @<CLI Parsing>
    @<Tangle Command Execution>
}
@=

### Tangling Subcommand ###

We will begin by defining the `tangle` subcommand and then look at our
implementation of it.

@code Flag Definitions [lang=go]
tangleCommand := flag.NewFlagSet("tangle", flag.ExitOnError)
tangleCommand.String("chunk", "", "Specifies one or more chunks to be tangled.")
tangleCommand.Bool("force", false, "Forces output to be written out.")
@=

@code Tangle Command Execution [lang=go]
if tangleCommand.Parsed() {
    log.Println("You wanna tangle?")
}
@=

Now that we have defined our flags and their consequences we turn to parsing.
In an ideal world, we would define our subcommands and let the library sort out
the rest. We do not live in an ideal world. The `flag` package allows multiple
independent flag sets to be defined but does not, at this writing, automatically
determine which one to run ^[subcommand-detection].

Therefore, now that we have defined the command sets, we me must detect which to
use and then let the library handle it.

@code CLI Parsing [lang=go]
if len(os.Args) < 2 {
    fmt.Println("You need help.")
    return
}

switch os.Args[1] {
    case "tangle":
        tangleCommand.Parse(os.Args[2:])
}
@=

### Logging Configuration ###

We focused on the actual interface in the previous sections. There is one slight
bit of book-keeping that we need to address, which is configuring logging.
Logging was used in the previous sections but bears a bit of setup.

@code Logging Setup
log := log.New(os.Stderr, "", log.LstdFlags | log.Lshortfile)
@=

## References

[^flagpackage]: <https://golang.org/pkg/flag/>
[^subcommand-detection]: <https://stackoverflow.com/questions/24504024/defining-independent-flagsets-in-golang>

// vim: set tw=75 ai: 
