#!/usr/bin/env python3
import dataclasses,json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.runtime.params_schema import HalationParams
from spektrafilm.model.diffusion import apply_halation_um,boost_highlights
rng=np.random.default_rng(20261031);cases=[];boost=[]
for h,w in [(1,1),(12,16),(31,40)]:
 raw=rng.uniform(0,5,(h,w,3));raw[0,0]=[20,10,3]
 for pitch in [8.7,32.4]:
  for settings in [{},{'active':False},{'scatter_amount':0,'halation_renormalize':False},{'halation_amount':0,'scatter_spatial_scale':2},{'halation_bounce_decay':1,'halation_n_bounces':5}]:
   p=HalationParams(**settings);out=apply_halation_um(raw,p,pitch)
   cases.append(dict(width=w,height=h,pitch=pitch,parameters=dataclasses.asdict(p),input=raw.reshape(-1,3).tolist(),expected=out.reshape(-1,3).tolist()))
 for ev,rngValue,protect in [(0,.3,4),(1,.3,4),(5,.8,0),(2,0,10)]:
  out=boost_highlights(raw,boost_ev=ev,boost_range=rngValue,protect_ev=protect)
  boost.append(dict(width=w,height=h,ev=ev,range=rngValue,protect=protect,input=raw.reshape(-1,3).tolist(),expected=out.reshape(-1,3).tolist()))
(ROOT/'Reference/Fixtures/halation-stages.json').write_text(json.dumps(dict(cases=cases,boost=boost),allow_nan=False,separators=(',',':'))+'\n');print('Exported',len(cases),'halation and',len(boost),'highlight-boost cases')
