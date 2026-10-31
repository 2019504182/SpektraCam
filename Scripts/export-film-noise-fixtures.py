#!/usr/bin/env python3
"""Whole-graph flat-field statistics; native random samples intentionally differ from NumPy."""
import dataclasses,json,os,pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Reference/upstream/src'))
os.environ.setdefault('NUMBA_NUM_THREADS','4');os.environ.setdefault('MPLBACKEND','Agg')
import numpy as np
from spektrafilm.runtime.params_builder import init_params,digest_params
from spektrafilm.runtime.process import simulate

def setpath(obj,path,value):
 field,separator,tail=path.partition('.');match=re.fullmatch(r'(\w+)\[(\d+)\]',field)
 if separator:new=setpath(getattr(obj,field),tail,value)
 elif match:
  field,index=match.groups();items=list(getattr(obj,field));items[int(index)]=value;new=tuple(items)
 else:new=value
 if dataclasses.is_dataclass(obj) and obj.__dataclass_params__.frozen:return dataclasses.replace(obj,**{field:new})
 setattr(obj,field,new);return obj

width,height=192,128
image=np.full((height,width,3),.184)
cases=[]
for film in ['kodak_portra_400','kodak_gold_200','kodak_vision3_500t','fujifilm_provia_100f']:
 for mode in ['layers','simple','microstructure']:
  numbers={'camera.film_format_mm':width*8.7/1000,'film_render.grain.particle_area_um2':.8}
  flags={'camera.auto_exposure':False,'print_render.glare.active':False}
  if mode=='simple':flags['film_render.grain.sublayers_active']=False;numbers['film_render.grain.n_sub_layers']=5
  if mode=='microstructure':numbers.update({'film_render.grain.micro_structure[0]':8,'film_render.grain.micro_structure[1]':1500})
  scan=film=='fujifilm_provia_100f'
  p=digest_params(init_params(film_profile=film,print_profile='kodak_portra_endura'))
  p.io.input_color_space='sRGB';p.io.input_cctf_decoding=False;p.io.output_color_space='sRGB';p.io.output_cctf_encoding=True;p.io.scan_film=scan
  for key,value in {**numbers,**flags}.items():setpath(p,key,value)
  p=digest_params(p,apply_stocks_specifics=False)
  out=simulate(image,p,digest_params_first=False)
  assert np.isfinite(out).all()
  flat=out.reshape(-1,3);mean=flat.mean(0);variance=flat.var(0)
  centered=out-mean
  lag=(centered[:,:-1]*centered[:,1:]).mean((0,1))/variance
  corr=np.corrcoef(flat,rowvar=False)
  cases.append(dict(name=film+'/'+mode,recipe=dict(filmID=film,printID='kodak_portra_endura',scanFilm=scan,numbers=numbers,flags=flags),mean=mean.tolist(),variance=variance.tolist(),lag=lag.tolist(),correlation=corr.tolist()))
path=ROOT/'Reference/Fixtures/film-noise.json'
path.write_text(json.dumps(dict(width=width,height=height,input=.184,cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'whole-film statistical cases')
