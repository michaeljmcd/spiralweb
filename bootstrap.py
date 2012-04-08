import sys
import ply.lex as lex

tokens = ('DOC_DIRECTIVE', 
          'OPEN_PROPERTY_LIST',
          'CLOSE_PROPERTY_LIST',
          'EQUALS',
          'COMMA',
          'CHUNK_REFERENCE',
          'CODE_DIRECTIVE',
          'CODE_END_DIRECTIVE',
          'AT_DIRECTIVE',
          'TEXT')

t_AT_DIRECTIVE = r'@@'
t_TEXT = '[^@\[\]=,]+'
t_COMMA = r','
t_DOC_DIRECTIVE = r'@doc'
t_CODE_DIRECTIVE = r'@code'
t_CODE_END_DIRECTIVE = r'@='
t_CHUNK_REFERENCE = r'[ \t]*@<[^\]]+>[ \t]*'
t_OPEN_PROPERTY_LIST = r'\['
t_CLOSE_PROPERTY_LIST = r']'
t_EQUALS = r'='

def t_newline(t):
    r'\n+'
    t.lexer.lineno += len(t.value)

if __name__ == '__main__':
    lexer = lex.lex()
    fileInput = ''

    with open(sys.argv[1]) as fileHandle:
        fileInput = fileHandle.read() 

    lexer.input(fileInput)

    for tok in lexer:
        print tok
