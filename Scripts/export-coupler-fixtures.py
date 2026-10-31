#!/usr/bin/env python3
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Reference/upstream/src'))
os.environ.setdefault('MPLBACKEND','Agg');os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.runtime.params_builder import init_params,digest_params
from spektrafilm.profiles.io import load_profile
from spektrafilm.model.couplers import compute_dir_couplers_matrix,apply_density_correction_dir_couplers
from spektrafilm.model.develop import develop_simple
rng=np.random.default_rng(20261031);cases=[]
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 if load_profile(path.stem).info.stage!='filming':continue
 p=digest_params(init_params(film_profile=path.stem))
 for amount in [0,.5,1]:
  p.film_render.dir_couplers.amount=amount;p.film_render.dir_couplers.diffusion_size_um=0
  curves=np.asarray(p.film.data.density_curves);curves=curves-np.nanmin(curves,axis=0)
  axis=np.asarray(p.film.data.log_exposure);inputs=rng.uniform(axis[0],axis[-1],(1,24,3));gamma=1.2
  density=develop_simple(inputs,axis,curves,gamma)
  result=apply_density_correction_dir_couplers(density,inputs,10,axis,curves,p.film_render.dir_couplers,p.film.info.type,gamma_factor=gamma)
  matrix=compute_dir_couplers_matrix(p.film_render.dir_couplers)*amount
  cases.append(dict(stock=path.stem,positive=p.film.is_positive,gamma=gamma,axis=axis.tolist(),curves=curves.tolist(),matrix=matrix.tolist(),input=inputs.reshape(-1,3).tolist(),expected=result.reshape(-1,3).tolist()))
out=ROOT/'Reference/Fixtures/coupler-stages.json';out.write_text(json.dumps(dict(revision='3bb2c2d2801ff68b92019cf1dbcbb133d60832bc',cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'stock/amount coupler fixtures')
