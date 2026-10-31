#!/usr/bin/env python3
"""Spectral UV/IR cases from the actual pinned filming stage, not RGB filter approximations."""
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'))
os.environ.setdefault('NUMBA_NUM_THREADS','4');os.environ.setdefault('MPLBACKEND','Agg')
import numpy as np
from spektrafilm.profiles.io import load_profile
from spektrafilm.runtime.params_builder import init_params,digest_params
from spektrafilm.runtime.pipeline import SimulationPipeline
rng=np.random.default_rng(20261031);cases=[]
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 if load_profile(path.stem).info.stage!='filming':continue
 image=rng.uniform(0,1,(1,48,3));image[0,:8]=[[0]*3,[.184]*3,[1]*3,[1,0,0],[0,1,0],[0,0,1],[4,.1,.001],[-.01,.3,.8]]
 for uv,ir in [([1,410,8],[0,675,15]),([0,410,8],[1,675,15]),([.65,430,12],[.8,655,25])]:
  p=digest_params(init_params(film_profile=path.stem));p.camera.filter_uv=tuple(uv);p.camera.filter_ir=tuple(ir)
  stage=SimulationPipeline(p)._filming_stage
  expected=stage._rgb_to_film_raw(image,color_space='sRGB',apply_cctf_decoding=False)
  cases.append(dict(stock=path.stem,uv=uv,ir=ir,input=image.reshape(-1,3).tolist(),expected=expected.reshape(-1,3).tolist()))
(ROOT/'Reference/Fixtures/filtered-exposure.json').write_text(json.dumps(dict(cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'spectrally filtered Hanatos exposure cases')
