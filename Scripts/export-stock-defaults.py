#!/usr/bin/env python3
"""Generate the low-level values reseeded by upstream film selection."""
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg')
from spektrafilm.profiles.io import load_profile
from spektrafilm.runtime.params_builder import init_params,digest_params
fields=['dir_couplers.gamma_samelayer_rgb','dir_couplers.gamma_interlayer_r_to_gb','dir_couplers.gamma_interlayer_g_to_rb','dir_couplers.gamma_interlayer_b_to_rg','halation.halation_first_sigma_um','halation.halation_strength']
lines=['// Stock-specific defaults from spektrafilm 3bb2c2d. Andrea Volpato; GPLv3.','import Foundation','','nonisolated enum StockDefaults {','    static let numbers: [String: [String: Double]] = [']
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 if load_profile(path.stem).info.stage!='filming':continue
 p=digest_params(init_params(film_profile=path.stem));items={}
 for field in fields:
  value=p.film_render
  for part in field.split('.'):value=getattr(value,part)
  for i,number in enumerate(value):items[f'film_render.{field}[{i}]']=float(number)
 lines.append('        '+json.dumps(path.stem)+': [')
 for key,value in items.items():lines.append('            '+json.dumps(key)+': '+str(value)+',')
 lines.append('        ],')
lines+=['    ]','}'];(ROOT/'SpektraCam/Models/StockDefaults.swift').write_text('\n'.join(lines)+'\n')
print('Generated exact stock defaults for 20 films')
