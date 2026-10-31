#!/usr/bin/env python3
"""Export mathematical stage fixtures from the pinned, unmodified Python runtime."""
import hashlib,json,math,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Reference/upstream/src'))
os.environ.setdefault('MPLBACKEND','Agg');os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.profiles.io import load_profile
from spektrafilm.model.develop import develop_simple,compute_density_spectral
from spektrafilm.utils.conversions import density_to_light
from spektrafilm.model.illuminants import standard_illuminant
from spektrafilm.config import STANDARD_OBSERVER_CMFS
from spektrafilm.utils.fast_interp import fast_interp
rng=np.random.default_rng(20261030)
cases=[]
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 p=load_profile(path.stem)
 for gamma in [.7,1,1.4]:
  axis=np.asarray(p.data.log_exposure);curves=np.asarray(p.data.density_curves)
  inputs=rng.uniform(axis[0]/gamma-1,axis[-1]/gamma+1,(1,24,3))
  inputs[0,0,:]=axis[0]/gamma;inputs[0,1,:]=axis[-1]/gamma
  output=develop_simple(inputs,axis,curves,gamma)
  cases.append(dict(id=f'{path.stem}-{gamma}',axis=axis.tolist(),curves=curves.tolist(),gamma=gamma,
                    input=inputs.reshape(-1,3).tolist(),expected=output.reshape(-1,3).tolist()))
# Repeated-axis exact-match behavior is distinct from endpoint clamping.
x=np.array([0.,1.,1.,2.]);y=np.array([[0.,0.,0.],[1.,2.,3.],[4.,5.,6.],[7.,8.,9.]])
a=np.array([[[-1.,0.,1.],[1.000001,1.5,3.]]])
cases.append(dict(id='repeated-axis',axis=x.tolist(),curves=y.tolist(),gamma=1.,input=a.reshape(-1,3).tolist(),expected=fast_interp(a,x,y).reshape(-1,3).tolist()))
p=load_profile('kodak_portra_400');density=rng.uniform(-.1,3,(1,12,3));channels=np.asarray(p.data.channel_density);base=np.asarray(p.data.base_density);illum=standard_illuminant(p.info.viewing_illuminant)
spectrum=compute_density_spectral(channels,density,base);light=density_to_light(spectrum,illum)
cmfs=np.asarray(STANDARD_OBSERVER_CMFS[:]);normalization=np.sum(illum*cmfs[:,1]);xyz=light@cmfs/normalization
spectral=dict(channels=channels.tolist(),base=base.tolist(),illuminant=illum.tolist(),cmfs=cmfs.tolist(),density=density.reshape(-1,3).tolist(),spectrum=spectrum.reshape(12,-1).tolist(),light=light.reshape(12,-1).tolist(),xyz=xyz.reshape(12,3).tolist())
result=dict(revision='3bb2c2d2801ff68b92019cf1dbcbb133d60832bc',seed=20261030,curveCases=cases,spectralCase=spectral)
out=ROOT/'Reference/Fixtures';out.mkdir(exist_ok=True)
def safe(value):
 if isinstance(value,float) and not math.isfinite(value):return 'NaN' if math.isnan(value) else ('Infinity' if value>0 else '-Infinity')
 if isinstance(value,list):return [safe(v) for v in value]
 if isinstance(value,dict):return {k:safe(v) for k,v in value.items()}
 return value
payload=(json.dumps(safe(result),allow_nan=False,separators=(',',':'))+'\n').encode();(out/'core-stages.json').write_bytes(payload)
(out/'core-stages.sha256').write_text(hashlib.sha256(payload).hexdigest()+'  core-stages.json\n')
print(f'Exported {len(cases)} density-curve cases and spectral/XYZ fixtures ({len(payload)} bytes)')
