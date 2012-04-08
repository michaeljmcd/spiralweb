@doc SpiralWeb [out=spiralweb.md]
SpiralWeb--A Literate Programming System
========================================

@code Lexer/Parser [out=parser.py]
import sys
import ply.lex as lex
import ply.yacc as yacc

# Lexing definitions

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

t_AT_DIRECTIVE = r'@@@@'
t_TEXT = '[^@@\[\]=,\n]+'
t_COMMA = r','
t_DOC_DIRECTIVE = r'@@doc'
t_CODE_DIRECTIVE = r'@@code'
t_CODE_END_DIRECTIVE = r'@@='
t_OPEN_PROPERTY_LIST = r'\['
t_CLOSE_PROPERTY_LIST = r']'
t_EQUALS = r'='

def t_CHUNK_REFERENCE(t):
    r'[ \t]*@@<[^\]]+>[ \t]*'
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

# Parser definitions

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
                output += indentLevel + line
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
            raise 'No output path specified'

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
        return self.parent.getChunk(self.name).dumpLines(indentLevel=indentLevel+self.indentLevel)

class SpiralWeb():
    chunks = []

    def __init__(self, chunks):
        self.chunks = chunks

        for chunk in self.chunks:
            chunk.setParent(self)

    def getChunk(self, name):
        for chunk in self.chunks:
            if chunk.name == name:
                return chunk

        return None

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
        else:
            raise 'No chunks specified, no chunks with out attributes, and no root chunk defined'
            
        return outputs

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

if __name__ == '__main__':
    lexer = lex.lex()
    parser = yacc.yacc()
    fileInput = ''

    with open(sys.argv[1]) as fileHandle:
        fileInput = fileHandle.read() 

    parsed = parser.parse(fileInput)
    web = SpiralWeb(parsed)
    web.tangle([sys.argv[2]])
@=
