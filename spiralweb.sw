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
    Defined by the regular expression `[^@@\[\]=,\n]+`.

#### Analyzing the Input Stream ####

The entrypoint into the lexical analysis will be a structure that contains all
of the state of the lexer and the operations will operate on it. At this point,
the only state will be the buffered IO reader that wraps the input stream.

@code Lexer Type Definitions
type Lexer struct {
    inputStream *bufio.Reader
}

func NewLexer(inputStream io.Reader) *Lexer {
    return &Lexer{inputStream: bufio.NewReader(inputStream)}
}
@=

We will implement a `Scan` function against this structure that will be
responsible for returning the next token, `INVALID` if an error is reached or
`EOF` if the end of input is reached. It behooves us, then, to validate these
semantics with some test code. We will start with some simple happy path
examples and then proceed to some nastier cases.

@code Semantic Analysis Tests [out=lexer_test.go,lang=go]
package main

import "testing"
import "strings"

func TestSimpleTokens(t *testing.T) {
    input := `,
[
]
=`
    expectedTokens := []Lexeme {
        Lexeme{lexemeType: COMMA, value: ","},
        Lexeme{lexemeType: NEWLINE, value: "\n"},
        Lexeme{lexemeType: OPEN_PROPERTY_LIST, value: "["},
        Lexeme{lexemeType: NEWLINE, value: "\n"},
        Lexeme{lexemeType: CLOSE_PROPERTY_LIST, value: "]"},
        Lexeme{lexemeType: NEWLINE, value: "\n"},
        Lexeme{lexemeType: EQUALS, value: "="},
        Lexeme{lexemeType: EOF, value: ""},
    }

    lexer := NewLexer(strings.NewReader(input))
    i := 0

    var token Lexeme
    for {
        token = lexer.Scan()

        if token != expectedTokens[i] {
            t.Errorf("Unexpected token found. Expected: %+v, got %+v", expectedTokens[i], token)
            break
        }

        if token.lexemeType == ILLEGAL {
            t.Errorf("Illegal input detected. %+v", token)
            break
        }

        if token.lexemeType == EOF || token.lexemeType == ILLEGAL {
            break
        }

        i++
    }
}
@=

The previous test demonstrates converting the single-rune values into lexemes.
The next test is to demonstrate that runs of text are properly recognized.

@code Semantic Analysis Tests
func TestTextRuns(t *testing.T) {
    input := `testing 1 2 3`
    lexer := NewLexer(strings.NewReader(input))

    var token Lexeme
    token = lexer.Scan()

    if token.lexemeType != TEXT || token.value != "testing 1 2 3" {
        t.Errorf("Unexpected token %+v", token)
    }

    AssertEOFTokenNext(lexer, t)
}
@=

Next we will validate that tokens of common directives are recognized.

@code Semantic Analysis Tests
func TestDirectiveTokens(t *testing.T) {
    var samples = map[string]Lexeme {
        "@@@@": Lexeme{lexemeType: AT_DIRECTIVE, value: "@@@@"},
        "@@doc": Lexeme{lexemeType: DOC_DIRECTIVE, value: "@@doc"},
        "@@code": Lexeme{lexemeType: CODE_DIRECTIVE, value: "@@code"},
        "@@=": Lexeme{lexemeType: CODE_END_DIRECTIVE, value: "@@="},
        "@@<example reference for a chunk>": Lexeme{lexemeType: CHUNK_REFERENCE, value: "example reference for a chunk"},
        "@@;": Lexeme{lexemeType: ILLEGAL, value: ""},
        "@@dostoyevsky": Lexeme{lexemeType: ILLEGAL, value: "@@dostoyevsky"},
        "@@<an unterminated id": Lexeme{lexemeType: ILLEGAL, value: "@@<an unterminated id"},
    }

    for input, expectedOutput := range samples {
        lexer := NewLexer(strings.NewReader(input))

        var token Lexeme
        token = lexer.Scan()

        if token.lexemeType != expectedOutput.lexemeType || token.value != expectedOutput.value  {
            t.Errorf("Unexpected token %+v", token)
        }

        if token.lexemeType != ILLEGAL { // We don't care what comes after an illegal token.
            AssertEOFTokenNext(lexer, t)
        }
    }
}
@=

Finally, we define a helper function used to validate that the next token is the
EOF token. This is due to the fact that many of the above tests need to end on
this note.

@code Semantic Analysis Tests
func AssertEOFTokenNext(lexer *Lexer, t *testing.T) {
    token := lexer.Scan()

    if token.lexemeType != EOF || token.value != "" {
        t.Errorf("Unexpected token %+v", token)
    }
}
@=

The scanning method is fairly straightforward. Many of our token are single
characters, so we can represent detect them with simple conditional checks that
return the token that we would expect. There are two main cases besides this,
which we will discuss below, namely parsing out raw text for the output (as is
the majority of both documentation and code chunks) and tokenizing the various
control sequences.

The method below demonstrates the basic token detection, with the other cases to
follow.

@code Scanning Implementation
func (lexer *Lexer) Scan() (lexeme Lexeme) {
    nextCharacter := lexer.Read()

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

    if nextCharacter == '=' {
        return Lexeme{lexemeType: EQUALS, value: string(nextCharacter)}
    }

    if nextCharacter == '\n' {
        return Lexeme{lexemeType: NEWLINE, value: string(nextCharacter)}
    }

    @<Lex Directives>
    @<Consume Text>
}

@<IO Helpers>
@=

The first of the cases we were examining is detecting one of the control
sequences that begins with the `@@` symbol. Here we find that there are several
possiblities for what the full token could be. It could be `DOC_DIRECTIVE`,
`CODE_DIRECTIVE`, `CODE_END_DIRECTIVE`, `AT_DIRECTIVE` or `CHUNK_REFERENCE`.

The way that we will accomplish this is to peek at the next character and
attempt to read in the token indicated by the next character. Fortunately, the
current token set only requires a single character of lookahead to determine
what the valid potential values are. Therefore, we will peek and delegate to a
corresponding IO helper in order to read the token, if the input matches, or an
error if it does not.

@code Lex Directives
if nextCharacter == '@@' {
    lookaheadCharacter := lexer.Peek()

    switch {
        case lookaheadCharacter == '@@':
            lexer.Read()
            return Lexeme{lexemeType: AT_DIRECTIVE, value: "@@@@"}
        case lookaheadCharacter == '=':
            lexer.Read()
            return Lexeme{lexemeType: CODE_END_DIRECTIVE, value: "@@="}
        case lookaheadCharacter == 'd':
            return AttemptDocDirectiveRead(lexer)
        case lookaheadCharacter == 'c':
            return AttemptCodeDirectiveRead(lexer)
        case lookaheadCharacter == '<':
            return AttemptChunkReferenceRead(lexer)
    }

    return Lexeme{lexemeType: ILLEGAL, value: ""}
}
@=

We will define each of these `Attempt*` helpers in turn. We will begin with the
function to attempt to read a `DOC_DIRECTIVE`. A doc directive is terminated by
a Unicode space, so we will read until we find a space character when we peek
ahead. If the resulting string is not `@@doc`, we will return an error.

@code IO Helpers
func AttemptDocDirectiveRead(lexer *Lexer) Lexeme {
    stringValue := lexer.ReadUntilWhitespace()

    if stringValue == "doc" {
        return Lexeme{lexemeType: DOC_DIRECTIVE, value: "@@doc"}
    }

    return Lexeme{lexemeType: ILLEGAL, value: "@@" + stringValue}
}
@=

This code is simplified by the `ReadUntilWhitespace` function on the lexer,
which, as implied, will keep reading until whitespace is reached.

@code IO Helpers
func (lexer *Lexer) ReadUntilWhitespace() string {
    var valueBuilder strings.Builder
    var nextCharacter rune

    for {
        lookaheadCharacter := lexer.Peek()
        if unicode.IsSpace(lookaheadCharacter) || lookaheadCharacter == eof {
            break
        }

        nextCharacter = lexer.Read()
        valueBuilder.WriteRune(nextCharacter)
    }

    return valueBuilder.String()
}
@=

`CODE_DIRECTIVE` behaves similarly, reading until a space is reached and
validating that the correct directive is found at the end.

@code IO Helpers
func AttemptCodeDirectiveRead(lexer *Lexer) Lexeme {
    stringValue := lexer.ReadUntilWhitespace()

    if stringValue == "code" {
        return Lexeme{lexemeType: CODE_DIRECTIVE, value: "@@code"}
    }

    return Lexeme{lexemeType: ILLEGAL, value: "@@" + stringValue}
}
@=

Parsing out a code reference is similar, but we do not parse to whitespace as
the name within a chunk reference may contain whitespace. Therefore, we will
have to write our own reader.

@code IO Helpers
func AttemptChunkReferenceRead(lexer *Lexer) Lexeme {
    var b strings.Builder
    var nc rune

    b.WriteRune('@@')

    for {
        lc := lexer.Peek()

        if lc == '\r' || lc == '\f' || lc == '\n' || lc == eof {
            break
        }

        nc = lexer.Read()
        b.WriteRune(nc)

        if nc == '>' {
            break
        }
    }

    var s = b.String()

    if s[0:2] != "@@<" || s[len(s) - 1] != '>' {
        return Lexeme{lexemeType: ILLEGAL, value: s}
    }

    return Lexeme{lexemeType: CHUNK_REFERENCE, value: s[2:len(s)-1]}
}
@=

With the control statements handled, we turn our attention to consuming runs of
text that will be included in output, be it code or documentation. The code we
have written before serves us in good stead because by looking at it we realize
that we our directives begin with a relatively small number of characters and
all we need to do is consume text until we reach one.

We will use the `strings.Builder` ^[stringsbuilder] struct to dynamically build
up the string as we read input to minimize memory copying.

@code Consume Text
var valueBuilder strings.Builder
valueBuilder.WriteRune(nextCharacter)

for {
    lookaheadCharacter := lexer.Peek()
    if isControlSequenceStartingCharacter(lookaheadCharacter) || lookaheadCharacter == eof {
        break
    }

    nextCharacter = lexer.Read()
    valueBuilder.WriteRune(nextCharacter)
}

return Lexeme{lexemeType: TEXT, value: valueBuilder.String()}
@=

All that remains is to define `isControlSequenceStartingCharacter`, the
predicate for determining when we should stop consuming input. Based on the
definition of the `TEXT` lexeme above, we can readily define this without
resorting to a regular expression.

@code IO Helpers
func isControlSequenceStartingCharacter(c rune) (bool) {
    return c == '@@' || c == '[' || c == ']' || c == '-' || c == ',' || c == '\n'
}
@=

Throughout the above code, we have made use of a few wrapper functions that make
IO a little nicer as we are going through. We define these functions below. The
big reason for these definitions is to allow all of the lexing to be done with
Go runes instead of raw bytes.

@code IO Helpers
var eof = rune(0)

func (lexer *Lexer) Read() rune {
    char, _, error := lexer.inputStream.ReadRune()

    if error != nil {
        return eof
    }

    return char
}

func (lexer *Lexer) Peek() rune {
    rune, _, err := lexer.inputStream.ReadRune()

    if err != nil {
        return eof
    }

    lexer.inputStream.UnreadRune()
    return rune
}
@=

#### The Top-Level File ####

All of the lexical analysis will be wrapped up in a single source file, which we
sketch out here.

@code SpiralWeb Lexer [out=lexer.go,lang=go]
package main

import (
    "io"
    "bufio"
    "strings"
    "unicode"
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
[^stringsbuilder]: <https://golang.org/pkg/strings/#Builder>

// vim: set tw=80 ai: 
