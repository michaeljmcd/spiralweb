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

The language of SpiralWeb was specified in the previous section, which also
included the end-user documentation. With that in mind, we will now turn our
attention to the process of parsing a web, from which we will be able to readily
implement the operations in which we are interested.

### Lexical Analysis ###

In order to parse a web, we will be handrolling a lexer and parser, using the
ideas put forth by Rob Pike and further discussed by Ben Johnson
^[handwrittenparsers]. 

#### Tokens ####

The goal of any lexical analysis is to produce a stream of tokens. We define
this fairly simply as a type with a corresponding bit of text. 

@code Lexeme Struct Definition
type Lexeme struct {
    lexemeType LexemeType
    value string
}
@=

The type is just an integer value that indicates the type of the token. The
tokens that we will recognize are listed below.

@code Lexer Type Definitions
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

@<Lexeme Struct Definition>
@=

Most of these should be fairly self explanatory. Nonetheless, we will list out
the regular expressions that define each of these. Note that our implementation
does not actually use regular expressions to perform lexical analysis, they are
simply a handy shorthand to describe what makes a valid instance of each value.

`ILLEGAL` 

:   A sentinel value to be returned whenever an invalid token is found. For,
    example, let us say that we hit an unescaped `@@cdoe`. This is not a valid
    directive and will trigger an error.

`EOF`

:   A sentinel value indicating the end of an input stream.

`DOC_DIRECTIVE`

:   An opening to a directive used to mark the beginning of documentation. The
    only valid value is `@doc`.

`CODE_DIRECTIVE`

:   A directive indicating the beginning of a code section. Only accepted by
    `@code`.

`CODE_END_DIRECTIVE`

:   The end delimeter for a code block. Should be comprised of `@=`.

`OPEN_PROPERTY_LIST`

:   The opening of a list of properties. These are used in code blocks to allow
    hints to be passed to the tangling and weaving engines. An example might be
    `[lang=go]`. The value is `[`.

`CLOSE_PROPERTY_LIST`

:   Defined by `]`, this is the ending of a list of properties as described in
    the previous definition.

`EQUALS`

:   The equals sign, used in property lists as above. Defined as `=`.

`COMMA`

:   The comma symbol, defined as `,`. Used in property lists as above.

`AT_DIRECTIVE`

:   Because `@@` is used as a part of many directives in SpiralWeb, the at
    directive (specified as `@@@@`) is simply a way to escape the at symbol.

`CHUNK_REFERENCE`

:   The directive used inside code chunks to indicate that another chunk should
    be inserted at a given location in the output. It is defined as `@@<TEXT...>`.

`NEWLINE`

:   It is what it says on the tin. Either `\r` or `\r\n`.

`TEXT`

:   A catch-all for other text. Used in both documentation and code portions.

#### Analyzing the Input Stream ####

@code Lexer Type Definitions
type Lexer struct {
    inputStream *bufio.Reader
}

func NewLexer(inputStream *io.Reader) *Lexer {
    return &Lexer{inputStream: bufio.NewReader(*inputStream)}
}
@=

@code Scanning Implementation
func (lexer *Lexer) Scan() (lexeme Lexeme) {
    nextCharacter := lexer.read()

    if nextCharacter == eof {
        return Lexeme{lexemeType: EOF, value: ""}
    }

    if nextCharacter == ',' {
        return Lexeme{lexemeType: COMMA, value: string(nextCharacter)}
    }

    if nextCharacter == '[' {
        return Lexeme{lexemeType: OPEN_PROPERTY_LIST, value: string(nextCharacter)}
    }

    if nextCharacter == ']' {
        return Lexeme{lexemeType: CLOSE_PROPERTY_LIST, value: string(nextCharacter)}
    }

    return Lexeme{lexemeType: EOF, value: ""} //TODO: fixme
}

@<IO Helpers>
@=

@code IO Helpers
var eof = rune(0)

func (lexer *Lexer) read() rune {
    char, _, error := lexer.inputStream.ReadRune()

    if error != nil {
        return eof
    }

    return char
}
@=

#### The Top-Level File ####

@code SpiralWeb Lexer [out=lexer.go,lang=go]
package main

import (
    "io"
    "bufio"
)

@<Lexer Type Definitions>
@<Scanning Implementation>
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
    "github.com/urfave/cli" 
    "os"
    "log"
)

func main() {
    @<Logging Setup>

    app := cli.NewApp()
    app.Name = "spiralweb"
    app.Usage = "Literate programming in a language agnostic fashion with lightweight markup languages."

    @<Flag Definitions>

    app.Run(os.Args)
}
@=

### Tangling Subcommand ###

We will begin by defining the `tangle` subcommand and then look at our
implementation of it.

@code Flag Definitions [lang=go]
app.Commands = []cli.Command {
    {
        Name: "tangle",
        Usage: "Extract source code from a spiral web.",
        Flags: []cli.Flag {
            cli.BoolTFlag {
                Name: "force, f",
                Usage: "Forces output to be written, even if there are no changes.",
            },
            cli.StringFlag {
                Name: "chunk, c",
                Usage: "Specifies chunk to tangle.",
            },
        },
        Action: func(context *cli.Context) error {
            log.Println("You wanna tangle?")

            if context.Bool("force") {
                log.Println("Forcing output.")
            }

            return nil
        },
    },
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
[^handwrittenparsers]: <https://blog.gopheracademy.com/advent-2014/parsers-lexers/>

// vim: set tw=80 ai: 
