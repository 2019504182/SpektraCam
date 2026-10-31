#!/usr/bin/env python3
"""Spatial pipeline fixtures from pinned runtime; stochastic stages are explicitly off."""
import dataclasses,json,os,pathlib,re,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'))
os.environ.setdefault('NUMBA_NUM_THREADS','4');os.environ.setdefault('MPLBACKEND','Agg')
import numpy as np
from spektrafilm.runtime.params_builder import init_params,digest_params
from spektrafilm.runtime.process import simulate
from spektrafilm.profiles.io import load_profile
rng=np.random.default_rng(20261031);image=rng.uniform(.005,1,(12,16,3));image[3,4]=[20,2,.1];image[0,:3]=[[0,0,0],[.184]*3,[1]*3]
def setpath(obj,path,value):
 field,separator,tail=path.partition('.')
 match=re.fullmatch(r'(\w+)\[(\d+)\]',field)
 if separator:new=setpath(getattr(obj,field),tail,value)
 elif match:
  field,index=match.groups();items=list(getattr(obj,field));items[int(index)]=value;new=tuple(items)
 else:new=value
 if dataclasses.is_dataclass(obj) and obj.__dataclass_params__.frozen:return dataclasses.replace(obj,**{field:new})
 setattr(obj,field,new);return obj
cases=[]
def add(film,paper,scan,numbers=None,flags=None,choices=None):
 # Synthetic 0.128 mm frame makes this small fixture exercise 8 µm pitch, not a UI preset.
 numbers={'camera.film_format_mm':.128,**(numbers or {})}
 flags={'camera.auto_exposure':False,'film_render.grain.active':False,'print_render.glare.active':False,**(flags or {})}
 p=digest_params(init_params(film_profile=film,print_profile=paper))
 p.io.input_color_space='sRGB';p.io.input_cctf_decoding=False;p.io.output_color_space='sRGB';p.io.output_cctf_encoding=True;p.io.scan_film=scan
 p.debug.deactivate_stochastic_effects=True
 choices=choices or {}
 for key,value in {**numbers,**flags,**choices}.items():setpath(p,key,value)
 p=digest_params(p,apply_stocks_specifics=False)
 output=simulate(image,p,digest_params_first=False)
 assert np.all(np.isfinite(output))
 cases.append(dict(recipe=dict(filmID=film,printID=paper,scanFilm=scan,numbers=numbers,flags=flags,choices=choices),expected=output.reshape(-1,3).tolist()))
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 film=load_profile(path.stem)
 if film.info.stage=='filming':add(film.info.stock,film.info.target_print or 'kodak_portra_endura',film.is_positive)
for stock in ['kodak_portra_400','kodak_gold_200','kodak_vision3_500t','fujifilm_velvia_100']:
 add(stock,'kodak_2383',stock=='fujifilm_velvia_100',numbers={
  'camera.lens_blur_um':32,'film_render.halation.boost_ev':2,'film_render.halation.protect_ev':0,
  'film_render.halation.boost_range':.8,'film_render.halation.halation_spatial_scale':4,
  'film_render.dir_couplers.diffusion_size_um':48,'scanner.lens_blur':.4,'scanner.unsharp_mask[0]':2,
  'scanner.unsharp_mask[1]':1.2,'camera.exposure_compensation_ev':1.25,'enlarger.y_filter_shift':9})
for stage in ['camera','enlarger']:
 for family in ['glimmerglass','black_pro_mist','pro_mist','cinebloom']:
  prefix=stage+'.diffusion_filter'
  add('kodak_portra_400','kodak_portra_endura',False,
   numbers={prefix+'.strength':.7,prefix+'.halo_warmth':-.4,prefix+'.halo_intensity':1.7},
   flags={prefix+'.active':True},choices={prefix+'.filter_family':family})
add('kodak_vision3_500t','kodak_2383',False,
 flags={'camera.diffusion_filter.active':True,'enlarger.diffusion_filter.active':True},
 choices={'camera.diffusion_filter.filter_family':'black_pro_mist','enlarger.diffusion_filter.filter_family':'cinebloom'})
add('fujifilm_velvia_100','kodak_portra_endura',True,flags={'enlarger.diffusion_filter.active':True})
papers=[load_profile(p.stem) for p in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json'))]
for paper in [p.info.stock for p in papers if p.info.stage=='printing']:
 for black,white in [(True,False),(False,True),(True,True)]:
  add('kodak_portra_400',paper,False,flags={'scanner.black_correction':black,'scanner.white_correction':white})
for film in ['fujifilm_provia_100f','fujifilm_velvia_100','kodak_ektachrome_100','kodak_kodachrome_64']:
 for black,white in [(True,False),(False,True),(True,True)]:
  add(film,'kodak_portra_endura',True,flags={'scanner.black_correction':black,'scanner.white_correction':white})
add('kodak_portra_400','kodak_portra_endura',True,flags={'scanner.black_correction':True,'scanner.white_correction':True})
for film in ['kodak_portra_400','kodak_vision3_500t','fujifilm_provia_100f']:
 add(film,'kodak_portra_endura',film=='fujifilm_provia_100f',numbers={
  'camera.filter_uv[0]':.65,'camera.filter_uv[1]':430,'camera.filter_uv[2]':12,
  'camera.filter_ir[0]':.8,'camera.filter_ir[1]':655,'camera.filter_ir[2]':25},
  flags={'scanner.black_correction':True,'scanner.white_correction':True})
(ROOT/'Reference/Fixtures/spatial-pipeline.json').write_text(json.dumps(dict(width=16,height=12,input=image.reshape(-1,3).tolist(),cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'spatial pipeline reference cases; stochastic effects off, 8 µm synthetic pitch')
