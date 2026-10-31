#!/usr/bin/env python3
import json,math,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg');os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.runtime.params_builder import init_params,digest_params
from spektrafilm.runtime.pipeline import SimulationPipeline
from spektrafilm.model.illuminants import standard_illuminant
from spektrafilm.profiles.io import load_profile
rng=np.random.default_rng(20261031);profiles={};cases=[]
prints=[p.stem for p in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')) if load_profile(p.stem).info.stage=='printing']
for film in ['kodak_portra_400','fujifilm_pro_400h','kodak_vision3_500t']:
 for paper in prints:
  for variant in range(4):
   p=init_params(film_profile=film,print_profile=paper)
   p.scanner.white_correction=False;p.scanner.black_correction=False
   if variant==1:
    p.camera.exposure_compensation_ev=1.25;p.enlarger.y_filter_shift=12;p.enlarger.m_filter_shift=-17;p.enlarger.print_exposure=.75
   elif variant==2:
    p.camera.exposure_compensation_ev=-2;p.enlarger.print_exposure_compensation=False
   elif variant==3:
    p.enlarger.normalize_print_exposure=False;p.enlarger.print_exposure_compensation=False
    p.enlarger.y_filter_shift=-20;p.enlarger.m_filter_shift=10;p.enlarger.preflash_exposure=.015;p.enlarger.preflash_y_filter_shift=5;p.enlarger.preflash_m_filter_shift=-5
   p=digest_params(p);sim=SimulationPipeline(p);stage=sim._printing_stage
   for profile in [p.film,p.print]:
    if profile.info.stock not in profiles:
     profiles[profile.info.stock]=dict(channels=np.asarray(profile.data.channel_density).tolist(),base=np.asarray(profile.data.base_density).tolist(),sensitivity=np.nan_to_num(10**profile.data.log_sensitivity).tolist())
   inputs=rng.uniform(-.02,2,(1,12,3));expected=stage.expose(inputs)
   mid=sim._enlarger_service.density_spectral_midgray.reshape(-1);comp=sim._enlarger_service.density_spectral_midgray_comp
   cases.append(dict(film=film,paper=paper,midgray=mid.tolist(),midgrayComp=None if comp is None else comp.reshape(-1).tolist(),neutral=[p.enlarger.c_filter_neutral,p.enlarger.m_filter_neutral,p.enlarger.y_filter_neutral],shift=[0,p.enlarger.m_filter_shift,p.enlarger.y_filter_shift],preflashShift=[0,p.enlarger.preflash_m_filter_shift,p.enlarger.preflash_y_filter_shift],preflashExposure=p.enlarger.preflash_exposure,printExposure=p.enlarger.print_exposure,compensate=p.enlarger.print_exposure_compensation,normalize=p.enlarger.normalize_print_exposure,input=inputs.reshape(-1,3).tolist(),expected=expected.reshape(-1,3).tolist()))
def safe(v):
 if isinstance(v,float) and not math.isfinite(v):return 'NaN' if math.isnan(v) else ('Infinity' if v>0 else '-Infinity')
 if isinstance(v,list):return [safe(x) for x in v]
 if isinstance(v,dict):return {k:safe(x) for k,x in v.items()}
 return v
result=dict(profiles=profiles,illuminant=standard_illuminant('TH-KG3').tolist(),wavelengths=np.arange(380,781,5).tolist(),cases=cases)
(ROOT/'Reference/Fixtures/print-exposure-stages.json').write_text(json.dumps(safe(result),allow_nan=False,separators=(',',':'))+'\n');print('Exported print-exposure fixtures:',len(cases),'cases')
