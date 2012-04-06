import sys
from pyparsing import Token, Literal, alphas, Word, Optional, LineStart, LineEnd, SkipTo

propertyName = Word("abcdefghijklmnopqrstuvwxyz./0123456789") 
name = propertyName
attrList = propertyName + Literal("=").suppress() + propertyName
codeChunkDef = LineStart() + Literal("<<").suppress() + name.setResultsName("name") \
    + Optional(attrList).setResultsName("options") + Literal(">>=").suppress() \
    + LineEnd() + SkipTo(LineStart() + "@" + LineEnd())

chunk = codeChunkDef

if __name__ == '__main__':
    with open(sys.argv[1]) as f:
        currentInput = f.read()
        print chunk.parseString(currentInput)
