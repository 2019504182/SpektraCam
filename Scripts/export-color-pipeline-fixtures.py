#!/usr/bin/env python3
"""New end-to-end fixtures from current pinned code; upstream snapshots stay untouched."""
import dataclasses,json,os,pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg');os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.runtime.params_builder import init_params,digest_params
from spektrafilm.runtime.process import simulate
from spektrafilm.profiles.io import load_profile
files=sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json'))
films=[load_profile(p.stem) for p in files if load_profile(p.stem).info.stage=='filming']
prints=[p.stem for p in files if load_profile(p.stem).info.stage=='printing']
rng=np.random.default_rng(20261031);image=rng.uniform(.005,1,(8,8,3));image[0,:6]=[[0,0,0],[.01]*3,[.184]*3,[1]*3,[1,0,0],[0,0,1]]
cases=[]
def setpath(obj,path,value):
 def update(current,parts):
  field=parts[0];match=re.fullmatch(r'(\w+)\[(\d+)\]',field)
  if len(parts)>1:new=update(getattr(current,field),parts[1:])
  elif match:
   field,index=match.groups();items=list(getattr(current,field));items[int(index)]=value;new=tuple(items)
  else:new=value
  if dataclasses.is_dataclass(current) and current.__dataclass_params__.frozen:return dataclasses.replace(current,**{field:new})
  setattr(current,field,new);return current
 return update(obj,path.split('.'))

def add(film,paper,scan=False,numbers=None,flags=None,choices=None):
 numbers=numbers or {};flags={'camera.auto_exposure':False,**(flags or {})};choices=choices or {}
 p=digest_params(init_params(film_profile=film,print_profile=paper))
 p.io.input_color_space='sRGB';p.io.input_cctf_decoding=False;p.io.output_color_space='sRGB';p.io.output_cctf_encoding=True;p.io.scan_film=scan
 p.debug.deactivate_spatial_effects=True;p.debug.deactivate_stochastic_effects=True
 for path,value in {**numbers,**flags,**choices}.items():setpath(p,path,value)
 p=digest_params(p,apply_stocks_specifics=False)
 output=simulate(image,p,digest_params_first=False)
 recipe=dict(filmID=film,printID=paper,scanFilm=scan,numbers=numbers,flags=flags,choices=choices)
 cases.append(dict(recipe=recipe,expected=output.reshape(-1,3).tolist()))
for film in films:add(film.info.stock,film.info.target_print or 'kodak_portra_endura',scan=film.is_positive)
for paper in prints:
 add('kodak_portra_400',paper,numbers={'camera.exposure_compensation_ev':1.25,'enlarger.y_filter_shift':12,'enlarger.m_filter_shift':-17,'enlarger.print_exposure':.75})
 add('fujifilm_pro_400h',paper,numbers={'camera.exposure_compensation_ev':-2,'enlarger.preflash_exposure':.015,'enlarger.preflash_y_filter_shift':5,'enlarger.preflash_m_filter_shift':-5},flags={'enlarger.print_exposure_compensation':False})
 add('kodak_vision3_500t',paper,numbers={'camera.exposure_compensation_ev':.5,'enlarger.y_filter_shift':-20,'enlarger.m_filter_shift':10},flags={'enlarger.normalize_print_exposure':False})
 add('kodak_portra_400',paper,numbers={'print_render.density_curves_morph.gamma_factor':1.2,'print_render.density_curves_morph.gamma_factor_blue':.9,'print_render.density_curves_morph.developer_exhaustion':.4},flags={'print_render.density_curves_morph.active':True,'camera.auto_exposure':True},choices={'camera.auto_exposure_method':'center_weighted'})
(ROOT/'Reference/Fixtures/color-pipeline.json').write_text(json.dumps(dict(revision='3bb2c2d2801ff68b92019cf1dbcbb133d60832bc',width=8,height=8,input=image.reshape(-1,3).tolist(),cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'end-to-end color-only cases, linear sRGB input / encoded sRGB output')
