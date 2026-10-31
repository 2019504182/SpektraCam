#!/usr/bin/env python3
import dataclasses,json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.runtime.params_schema import DiffusionFilterParams
from spektrafilm.model import diffusion
rng=np.random.default_rng(20261031);cases=[];strengths=[]
for family in diffusion.DIFFUSION_FILTER_FAMILIES:
 for strength in [0,.03125,.125,.176776695,.25,.5,1,2,8]:
  strengths.append(dict(family=family,strength=strength,expected=diffusion._strength_to_scatter(strength,family)))
 for h,w in [(1,1),(5,7),(24,32),(31,63)]:
  image=rng.uniform(-.1,2,(h,w,3));image[0,0]=[20,2,.1];pitch=8.7
  for kwargs in [{},{'strength':1.25,'halo_warmth':-1.5,'spatial_scale':.3},
   {'core_intensity':.2,'halo_intensity':2.2,'bloom_intensity':.5,'halo_warmth':1.5,'halo_size':.7,'bloom_size':1.8},
   {'core_intensity':0,'halo_intensity':0,'bloom_intensity':0,'core_size':.25,'halo_size':2,'bloom_size':.1},
   {'active':False},{'strength':0},{'spatial_scale':0}]:
   p=DiffusionFilterParams(**{'active':True,'filter_family':family,**kwargs})
   overrides=diffusion._overrides_from_params(p)
   radius=int(np.ceil(max(8*diffusion._bloom_max_lambda_um(family,overrides)*p.spatial_scale/pitch,5)))
   radius=min(radius,max(min(h,w)//2-1,1))
   psf=diffusion.diffusion_filter_psf((2*radius+1,2*radius+1),family=family,spatial_scale=p.spatial_scale,pixel_size_um=pitch,halo_warmth=p.halo_warmth,overrides=overrides)
   output=diffusion.apply_diffusion_filter_um(image,p,pitch)
   cases.append(dict(width=w,height=h,pitch=pitch,radius=radius,parameters=dataclasses.asdict(p),input=image.reshape(-1,3).tolist(),kernel=psf.reshape(-1,3).tolist(),expected=output.reshape(-1,3).tolist()))
(ROOT/'Reference/Fixtures/diffusion-stages.json').write_text(json.dumps(dict(cases=cases,strengths=strengths),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'diffusion PSF/convolution cases and',len(strengths),'strength cases')
