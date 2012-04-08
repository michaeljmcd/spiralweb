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

t_AT_DIRECTIVE = r'@@'
t_TEXT = '[^@\[\]=,\n]+'
t_COMMA = r','
t_DOC_DIRECTIVE = r'@doc'
t_CODE_DIRECTIVE = r'@code'
t_CODE_END_DIRECTIVE = r'@='
t_OPEN_PROPERTY_LIST = r'\['
t_CLOSE_PROPERTY_LIST = r']'
t_EQUALS = r'='

def t_CHUNK_REFERENCE(t):
    r'[ \t]*@<[^\]]+>[ \t]*'
    inputString = t.value.rstrip()
    refStart = inputString.find('@<')

    t.value = {'indent' : inputString[0:refStart],
               'ref' : inputString[refStart+2:len(inputString)-1]}
    return t

def t_NEWLINE(t):
    r'\n+'
    t.lexer.lineno += len(t.value)
    return t

# Parser definitions

class SpiralWebDoc():
    text = ''
    name = ''
    options = {}

class SpiralWebCode():
    lines = []
    options = {}
    name = ''

class SpiralWebRef():
    name = ''
    indentLevel = 0

    def __init__(self, name, indentLevel=''):
        self.name = name
        self.indentLevel = indentLevel

starting = 'web'

def p_web(p):
    '''web : codedefn
           | docdefn
           | doclines'''
    return p[0]

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
    return p[0]

def p_docdefn(p):
    '''docdefn : DOC_DIRECTIVE TEXT optionalpropertylist NEWLINE doclines'''
    code = SpiralWebDoc()
    code.name = p[1]
    code.options = p[2]
    code.lines = p[4]
    return code

def p_codedefn(p):
    '''codedefn : CODE_DIRECTIVE TEXT optionalpropertylist NEWLINE codelines CODE_END_DIRECTIVE
                '''
    code = SpiralWebCode()
    code.name = p[1]
    code.options = p[2]
    code.lines = p[4]
    return code

def p_codelines(p):
    '''codelines : TEXT 
                 | NEWLINE
                 | AT_DIRECTIVE
                 | OPEN_PROPERTY_LIST
                 | CLOSE_PROPERTY_LIST
                 | COMMA
                 | EQUALS
                 | chunkref'''
    return p[0]

def p_chunkref(p):
    '''chunkref : CHUNK_REFERENCE'''
    return SpiralWebRef(p[0]['ref'], p[0]['ref'])

def p_optionalpropertylist(p):
    '''optionalpropertylist : propertylist 
                            | empty'''
    return p[0]

def p_propertylist(p):
    '''propertylist : OPEN_PROPERTY_LIST propertysequence CLOSE_PROPERTY_LIST'''
    return p[1]

def p_propertysequence(p):
    '''propertysequence : empty 
                        | propertysequence1'''
    return p[0]

def p_propertysequence1(p):
    '''propertysequence1 : property 
                         | propertysequence1 COMMA property'''
    if len(p) == 1:
       return p[0]
    else:
       return [p[0], p[1]]

def p_property(p):
    '''property : TEXT EQUALS TEXT'''
    return (p[0], p[1])

if __name__ == '__main__':
    lexer = lex.lex()
    yacc = yacc.yacc()
    fileInput = ''

    with open(sys.argv[1]) as fileHandle:
        fileInput = fileHandle.read() 

    print yacc.parse(fileInput)
    #lexer.input(fileInput)

    #for tok in lexer:
    #    print tok
