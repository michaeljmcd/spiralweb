import sys
from pyparsing import Token, Literal, Or, Word, Optional, LineStart, LineEnd, SkipTo, StringEnd, ZeroOrMore, NotAny, OneOrMore, Regex, MatchFirst, alphas, StringStart, Group, Suppress, ParserElement

ParserElement.setDefaultWhitespaceChars('\t')

textLine = LineStart() + Or(NotAny("@"), "@@") + SkipTo(LineEnd()) + LineEnd()
codeRef = LineStart() + ZeroOrMore(" ") + Literal("@<") + SkipTo(">") + LineEnd()
docLine = textLine
codeLine = textLine | codeRef
chunkDef = LineStart() + Literal("@code") + OneOrMore(" ").suppress() + \
           OneOrMore(alphas + " ").setResultsName('chunkName') + \
           LineEnd() + \
           Group(ZeroOrMore(codeLine)).setResultsName('chunkLines') + \
           LineStart() + Suppress("@=") + LineEnd() + \
           LineEnd()
instruction = chunkDef 
chunk = Group(ZeroOrMore(instruction | docLine)).setResultsName('lines')

if __name__ == '__main__':
    print chunk.parseFile(sys.argv[1], parseAll=True)
