#!/usr/bin/env python3
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg')
import colour,numpy as np
from spektrafilm.utils.autoexposure import measure_autoexposure_ev
from spektrafilm.runtime.services.resize import ResizingService
from spektrafilm.runtime.params_schema import IOParams
rng=np.random.default_rng(20261031);cases=[];resizer=ResizingService(IOParams(),35)
for h,w in [(1,1),(4,3),(16,12),(160,200),(320,400),(513,21)]:
 image=rng.uniform(0,1,(h,w,3));small=resizer.small_preview(image)
 luminance=colour.RGB_to_XYZ(image,colourspace='sRGB',apply_cctf_decoding=False)[...,1]
 small_y=colour.RGB_to_XYZ(small,colourspace='sRGB',apply_cctf_decoding=False)[...,1]
 values={method:float(measure_autoexposure_ev(small,'sRGB',False,method=method)) for method in ['average','median','center_weighted','partial','matrix','multi_zone','highlight_weighted']}
 cases.append(dict(width=w,height=h,luminance=luminance.reshape(-1).tolist(),smallWidth=small.shape[1],smallHeight=small.shape[0],smallLuminance=small_y.reshape(-1).tolist(),expected=values))
(ROOT/'Reference/Fixtures/metering-stages.json').write_text(json.dumps(dict(cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported metering fixtures: 42 methods/images, including exact preview resampling')
