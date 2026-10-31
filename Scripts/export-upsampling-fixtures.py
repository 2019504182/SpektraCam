#!/usr/bin/env python3
"""Capture the exact stock-specific Hanatos tables used by the upstream runtime."""
import hashlib,json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'))
os.environ.setdefault('MPLBACKEND','Agg');os.environ.setdefault('NUMBA_NUM_THREADS','4')
import colour,numpy as np
from spektrafilm.profiles.io import load_profile
from spektrafilm.runtime.params_builder import init_params,digest_params
from spektrafilm.runtime.pipeline import SimulationPipeline
from spektrafilm.utils.spectral_upsampling import _illuminant_to_xy
rng=np.random.default_rng(20261031);cases=[];binary=bytearray()
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 if load_profile(path.stem).info.stage!='filming':continue
 p=digest_params(init_params(film_profile=path.stem));sim=SimulationPipeline(p);stage=sim._filming_stage
 sensitivity=np.nan_to_num(10**p.film.data.log_sensitivity)
 table=stage._lut_service.get_filming_tc_lut(sensitivity)
 inputs=rng.uniform(0,1,(1,48,3));inputs[0,:8]=[[0,0,0],[.184]*3,[1]*3,[1,0,0],[0,1,0],[0,0,1],[4,.1,.001],[-.01,.3,.8]]
 output=stage._rgb_to_film_raw(inputs,color_space='sRGB',apply_cctf_decoding=False)
 matrix=colour.RGB_to_XYZ(np.eye(3),colourspace='sRGB',apply_cctf_decoding=False,
                         illuminant=_illuminant_to_xy(p.film.info.reference_illuminant),chromatic_adaptation_transform='CAT16')
 offset=len(binary);payload=np.asarray(table,dtype='<f8').tobytes();binary+=payload
 cases.append(dict(stock=path.stem,size=table.shape[0],byteOffset=offset,byteLength=len(payload),matrix=matrix.tolist(),input=inputs.reshape(-1,3).tolist(),expected=output.reshape(-1,3).tolist()))
out=ROOT/'Reference/Fixtures';(out/'hanatos-tables.f64').write_bytes(binary)
(out/'upsampling-stages.json').write_text(json.dumps(dict(revision='3bb2c2d2801ff68b92019cf1dbcbb133d60832bc',tablesSHA256=hashlib.sha256(binary).hexdigest(),cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'stock tables:',len(binary),'bytes')
