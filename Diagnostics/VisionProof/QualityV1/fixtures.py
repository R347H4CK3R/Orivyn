#!/usr/bin/env python3
"""Frozen synthetic inputs. Pure integer RGB drawing; no inference, OCR or fonts."""
import hashlib, json, pathlib, struct, zlib
SIDE = 384
WHITE = (255, 255, 255)
BLUE = (0, 80, 220)
ORANGE = (240, 120, 0)
# Locally authored 5x7 block glyphs, rendered at integer 7x scale (35x49px).
GLYPHS = {
 'M':['10001','11011','10101','10101','10001','10001','10001'],
 'A':['01110','10001','10001','11111','10001','10001','10001'],
 'P':['11110','10001','10001','11110','10000','10000','10000'],
 'L':['10000','10000','10000','10000','10000','10000','11111'],
 'E':['11111','10000','10000','11110','10000','10000','11111'],
 'C':['01111','10000','10000','10000','10000','10000','01111'],
 'D':['11110','10001','10001','10001','10001','10001','11110'],
 'R':['11110','10001','10001','11110','10100','10010','10001'],
 '4':['00010','00110','01010','10010','11111','00010','00010'],
 '7':['11111','00001','00010','00100','01000','01000','01000'],
 '8':['01110','10001','10001','01110','10001','10001','01110'],
 '2':['01110','10001','00001','00010','00100','01000','11111'],
 ' ':['00000']*7,
}
SPATIAL = 'Where is the blue circle relative to the orange square? Answer with one word: left, right, above, or below.'
COUNT = 'How many circles are visible? Return only the number.'
TEXT = 'Transcribe all text in the image. Return only the text.'
# Every circle has radius32; every square is64x64. Integer centers and generous
# whitespace prevent touching/occlusion. Counts include only fully visible circles.
CASES = [
 ('case01','spatial',SPATIAL,['left'], [('circle',96,192),('square',288,192)]),
 ('case02','spatial',SPATIAL,['right'], [('circle',288,192),('square',96,192)]),
 ('case03','spatial',SPATIAL,['above'], [('circle',192,96),('square',192,288)]),
 ('case04','spatial',SPATIAL,['below'], [('circle',192,288),('square',192,96)]),
 ('case05','count',COUNT,['0','zero','none','no circles','0 circles','zero circles'], [('square',96,96),('square',288,96),('square',192,288)]),
 ('case06','count',COUNT,['1','one','1 circle','one circle'], [('circle',192,96),('square',96,288),('square',288,288)]),
 ('case07','count',COUNT,['2','two','2 circles','two circles'], [('circle',96,96),('circle',288,96),('square',192,288)]),
 ('case08','count',COUNT,['4','four','4 circles','four circles'], [('circle',96,96),('circle',288,96),('circle',96,288),('circle',288,288),('square',192,192)]),
 ('case09','text',TEXT,['maple 47'], 'MAPLE 47'),
 ('case10','text',TEXT,['cedar 82'], 'CEDAR 82'),
]
def render(case):
    pixels = bytearray(WHITE * (SIDE * SIDE))
    def dot(x,y,color):
        assert 0 <= x < SIDE and 0 <= y < SIDE
        i=(y*SIDE+x)*3; pixels[i:i+3]=bytes(color)
    drawing=case[4]
    if isinstance(drawing,str):
        scale=7; width=(len(drawing)*6-1)*scale
        x0=(SIDE-width)//2; y0=(SIDE-7*scale)//2
        for n,c in enumerate(drawing):
            for y,row in enumerate(GLYPHS[c]):
                for x,bit in enumerate(row):
                    if bit=='1':
                        for dy in range(scale):
                            for dx in range(scale): dot(x0+n*6*scale+x*scale+dx,y0+y*scale+dy,(0,0,0))
    else:
        for shape,cx,cy in drawing:
            for y in range(cy-32,cy+32):
                for x in range(cx-32,cx+32):
                    if shape=='square' or (2*x+1-2*cx)**2+(2*y+1-2*cy)**2<=64**2:
                        dot(x,y,ORANGE if shape=='square' else BLUE)
    return bytes(pixels)
def png(rgb):
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    scan=b''.join(b'\0'+rgb[y*SIDE*3:(y+1)*SIDE*3] for y in range(SIDE))
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',SIDE,SIDE,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b'')
def sha(data): return hashlib.sha256(data).hexdigest()
def manifest():
    return {'version':1,'status':'frozen before any model evaluation','width':SIDE,'height':SIDE,
      'rgbFormat':'top-to-bottom row-major packed RGB8, sRGB values, opaque white background',
      'modelInput':'Only pixels plus the case question; never IDs, expected values, geometry or metadata.',
      'cases':[{'id':c[0],'category':c[1],'question':c[2],'acceptedNormalizedAnswers':c[3],
                'referenceDrawing':c[4],'pngSHA256':sha(png(render(c))),'rgbSHA256':sha(render(c))} for c in CASES]}
if __name__=='__main__':
    root=pathlib.Path(__file__).resolve().parent
    out=root/'fixtures';out.mkdir(exist_ok=True)
    for c in CASES: (out/(c[0]+'.png')).write_bytes(png(render(c)))
    (root/'FROZEN_CASES.json').write_text(json.dumps(manifest(),indent=2)+'\n')
