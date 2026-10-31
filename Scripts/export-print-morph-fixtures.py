#!/usr/bin/env python3
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg')
import numpy as np
from spektrafilm.profiles.io import load_profile
from spektrafilm.utils.morph_curves import PrintCurvesMorphParams,apply_print_curves_morph
cases=[]
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 p=load_profile(path.stem)
 if p.info.stage!='printing':continue
 for kwargs in [dict(active=False),{},dict(gamma_factor=1.3),dict(gamma_factor_fast=.7,gamma_factor_slow=1.4),dict(gamma_factor_red=1.2,gamma_factor_blue=.8),dict(developer_exhaustion=.65),dict(gamma_factor=.8,developer_exhaustion=1)]:
  parameters=PrintCurvesMorphParams(**kwargs);m=p.data.density_curves_model;axis=np.asarray(p.data.log_exposure)
  result=apply_print_curves_morph(axis,m,parameters,profile_type=p.info.type)
  cases.append(dict(stock=path.stem,positive=p.info.type=='positive',centers=m.centers.tolist(),amplitudes=m.amplitudes.tolist(),sigmas=m.sigmas.tolist(),axis=axis.tolist(),parameters=parameters.__dict__,expected=result.tolist()))
out=ROOT/'Reference/Fixtures/print-morph-stages.json';out.write_text(json.dumps(dict(cases=cases),allow_nan=False,separators=(',',':'))+'\n');print('Exported print-chemistry fixtures:',len(cases),'cases')
