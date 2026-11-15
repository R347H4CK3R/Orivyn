"""Freeze new geometry before either baseline or candidate inference."""
import json, shutil
from pathlib import Path
base=Path(__file__).resolve().parents[1]/'VisionProof'
target=base/'BorderHoldout'
target.mkdir()
for name in ('fixtures.py','run.py','score.py'):
 shutil.copy2(base/'QualityV1'/name,target/name)
extra = """
# Independent geometry/count holdouts authored before evaluation.
CASES=[
 ('hold01','spatial',SPATIAL,['left'],[('circle',120,160),('square',264,160)]),
 ('hold02','spatial',SPATIAL,['right'],[('circle',264,224),('square',120,224)]),
 ('hold03','spatial',SPATIAL,['above'],[('circle',224,120),('square',224,264)]),
 ('hold04','spatial',SPATIAL,['below'],[('circle',160,264),('square',160,120)]),
 ('hold05','count',COUNT,['0','zero','none','no circles','0 circles','zero circles'],[('square',160,160)]),
 ('hold06','count',COUNT,['1','one','1 circle','one circle'],[('circle',250,250)]),
 ('hold07','count',COUNT,['2','two','2 circles','two circles'],[('circle',120,192),('circle',264,192)]),
 ('hold08','count',COUNT,['3','three','3 circles','three circles'],[('circle',96,120),('circle',192,264),('circle',288,120),('square',192,120)]),
 ('hold09','count',COUNT,['5','five','5 circles','five circles'],[('circle',96,96),('circle',288,96),('circle',192,192),('circle',96,288),('circle',288,288)]),
 ('hold10','count',COUNT,['6','six','6 circles','six circles'],[('circle',96,96),('circle',192,96),('circle',288,96),('circle',96,288),('circle',192,288),('circle',288,288)]),
]
"""
extra += """
# Absolute positions retain original image-center semantics.
ABSX='Is the circle in the left or right half of the image? Return only left or right.'
ABSY='Is the circle in the top or bottom half of the image? Return only top or bottom.'
CASES += [
 ('absolute-left','absolute',ABSX,['left'],[('circle',96,192)]),
 ('absolute-right','absolute',ABSX,['right'],[('circle',288,192)]),
 ('absolute-top','absolute',ABSY,['top'],[('circle',192,96)]),
 ('absolute-bottom','absolute',ABSY,['bottom'],[('circle',192,288)]),
]
# Natural photographs from the separately pinned llama source, not user data.
import os
from PIL import Image
ASSETS=pathlib.Path(os.environ['ORIVYN_LLAMA_FIXTURES'])
NATURAL={
 'landscape':('1.jpg','ddbdb9cdb5f109c567d2aafd076288cd57187e7a97d94898c72591dbfe28235c'),
 'flower':('beautiful-flowers-lotus.webp','a5f728fbce7c5b2ed8ef32303942f97a00e4cadb791ec65eadcfbe59ebe9625f'),
}
for name,(file,digest) in NATURAL.items():
 assert sha((ASSETS/file).read_bytes())==digest
 for boxed in (False,True):
  question='What is between the mountains? Return one word.' if name=='landscape' else 'What is the main object in the image? Return one word.'
  expected=['water','river','lake','fjord'] if name=='landscape' else ['flower','lotus','lily']
  CASES.append(('natural-'+name+('-boxed' if boxed else '-full'),'natural',question,expected,(name,boxed)))
original_render=render
def render(case):
 if case[1]!='natural':return original_render(case)
 name,boxed=case[4]
 im=Image.open(ASSETS/NATURAL[name][0]).convert('RGB')
 if boxed:
  im.thumbnail((256,256),Image.Resampling.LANCZOS)
  canvas=Image.new('RGB',(384,384),'white')
  canvas.paste(im,((384-im.width)//2,(384-im.height)//2))
 else:canvas=im.resize((384,384),Image.Resampling.LANCZOS)
 return canvas.tobytes()
"""
with (target/'fixtures.py').open('a') as f:f.write(extra)
import sys
sys.path.insert(0,str(target))
import fixtures
(target/'FROZEN_CASES.json').write_text(json.dumps(fixtures.manifest(),indent=2)+'\n')
