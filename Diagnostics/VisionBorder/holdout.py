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
with (target/'fixtures.py').open('a') as f:f.write(extra)
import sys
sys.path.insert(0,str(target))
import fixtures
(target/'FROZEN_CASES.json').write_text(json.dumps(fixtures.manifest(),indent=2)+'\n')
