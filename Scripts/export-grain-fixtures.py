#!/usr/bin/env python3
"""Deterministic grain-stage fixtures; random sequence parity is tested statistically."""
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('NUMBA_NUM_THREADS','4')
import numpy as np
from spektrafilm.profiles.io import load_profile
from spektrafilm.model.density_curves import interp_density_cmy_layers
from spektrafilm.model import grain
rng=np.random.default_rng(20261031);cases=[];particles=[]
for file in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 p=load_profile(file.stem)
 if p.info.stage!='filming':continue
 curves=np.asarray(p.data.density_curves);curves=curves-np.nanmin(curves,axis=0)
 layers=np.asarray(p.data.density_curves_layers);positive=p.info.type=='positive'
 maximum=np.nanmax(curves,axis=0)
 values=np.concatenate([curves,curves-1e-7,curves+1e-7,rng.uniform(-.1,1.1,(64,3))*maximum]).reshape(-1,1,3)
 expected=interp_density_cmy_layers(values,curves,layers,positive_film=positive)
 maxlayers=np.nanmax(layers,axis=0)
 pitch=8.7;area=.2;scale=np.array([1.6,1.6,3.2]);layerScale=np.array([2,1,.5]);minimum=np.array([.03,.03,.03])
 captured=[]
 def record(density,density_max,n_particles_per_pixel,grain_uniformity,**kwargs):
  captured.append([float(density_max),float(n_particles_per_pixel)])
  return np.zeros_like(density)
 original=grain.layer_particle_model;grain.layer_particle_model=record
 try:
  grain.apply_grain_to_density_layers(expected[:1].copy(),maxlayers,pixel_size_um=pitch,particle_area_um2=area,
   particle_scale=scale,particle_scale_layers=layerScale,density_min=minimum,grain_blur=0,grain_micro_structure=(0,0))
 finally:grain.layer_particle_model=original
 cases.append(dict(stock=file.stem,positive=positive,curves=curves.tolist(),layers=layers.tolist(),
  input=values[:,0,:].tolist(),expected=expected[:,0,:,:].tolist(),maximum=maxlayers.tolist(),
  pitch=pitch,area=area,scale=scale.tolist(),layerScale=layerScale.tolist(),minimum=minimum.tolist(),captured=captured))
for maximum in [0.2,2.2,5]:
 for particlesCount in [.1,10,1e3,1e8]:
  for uniformity in [0,.97,1]:
   for fraction in [-.1,0,1e-6,.1,.5,1,1.1]:
    probability=np.clip(fraction,1e-6,1-1e-6);saturation=1-probability*uniformity*(1-1e-6)
    rate=particlesCount*probability/saturation;od=maximum/particlesCount*saturation
    particles.append(dict(density=float(fraction*maximum),maximum=maximum,particles=particlesCount,uniformity=uniformity,
     rate=float(rate),scale=float(od),mean=float(rate*od),variance=float(rate*od*od)))
out=ROOT/'Reference/Fixtures/grain-stages.json'
out.write_text(json.dumps(dict(cases=cases,particles=particles),allow_nan=False,separators=(',',':'))+'\n')
print('Exported',len(cases),'stock layer maps and',len(particles),'particle distribution cases')
