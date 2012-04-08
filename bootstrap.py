import sys
import codecs

class SpiralWeb():
    chunks = []

class SpiralWebChunk():
    properties = { }

class SpiralWebDocChunk(SpiralWebChunk):
    lines = []

class SpiralWebCodeChunk(SpiralWebChunk):
    lines = []

class SpiralWebChunkReference(SpiralWebChunk):
    chunkName = ''

class SpiralWebParser():
    _indent = []
    _inputFile = None
    _buffer = None
    lineNumber = 1

    def parseFile(self, path):
        _inputFile = codecs.open(path, encoding='utf-8')

        for line in inputFile:
            if line[0] == '@' and line[1] != '@':
                self._parseDirective()
            else:
                self._parseText()

    def _advanceOneLine(self):
        self._buffer = self._inputFile.readline()
        self._indent = []
        self.lineNumber = self.lineNumber + 1

    def _parseDirective():

    def _parseText():
        print 'text'

if __name__ == '__main__':
    parser = SpiralWebParser()
    print parser.parseFile(sys.argv[1])
