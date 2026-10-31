#!/usr/bin/env python3
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.utils.fast_gaussian_filter import fast_gaussian_filter,fast_exponential_filter
rng=np.random.default_rng(20261031);cases=[]
for h,w in [(1,1),(5,7),(24,32),(31,63)]:
 image=rng.uniform(0,2,(h,w,3));image[0,0]=[10,1,.2]
 for sigma in [[0,0,0],[.2,.5,1],[2.99,3,3.01],[7.5,20,100]]:
  expected=fast_gaussian_filter(image,np.array(sigma))
  cases.append(dict(kind='gaussian',width=w,height=h,scale=sigma,input=image.reshape(-1,3).tolist(),expected=expected.reshape(-1,3).tolist()))
 for decay in [[.1,.3,1],[2,4,10]]:
  expected=fast_exponential_filter(image,np.array(decay))
  cases.append(dict(kind='exponential',width=w,height=h,scale=decay,input=image.reshape(-1,3).tolist(),expected=expected.reshape(-1,3).tolist()))
result=dict(revision='3bb2c2d2801ff68b92019cf1dbcbb133d60832bc',cases=cases)
(ROOT/'Reference/Fixtures/spatial-stages.json').write_text(json.dumps(result,allow_nan=False,separators=(',',':'))+'\n');print('Exported',len(cases),'spatial filter fixtures')
