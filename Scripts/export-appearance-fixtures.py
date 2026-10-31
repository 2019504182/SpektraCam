#!/usr/bin/env python3
import json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg')
import colour,numpy as np
rng=np.random.default_rng(20261031);cases=[]
for illuminant in ['D50','D55','D65']:
 white=colour.xy_to_XYZ(colour.CCS_ILLUMINANTS['CIE 1931 2 Degree Standard Observer'][illuminant])
 xyz=rng.uniform(.001,2,(120,3));xyz[:5]=[[0,0,0],white,white*.184,white*2,[.1,.2,.3]]
 jab=colour.XYZ_to_CAM16UCS(xyz,XYZ_w=white,L_A=64,Y_b=20)
 inverse=colour.CAM16UCS_to_XYZ(jab,XYZ_w=white,L_A=64,Y_b=20)
 cases.append(dict(illuminant=illuminant,white=white.tolist(),input=xyz.tolist(),jab=jab.tolist(),inverse=inverse.tolist()))
(ROOT/'Reference/Fixtures/appearance-stages.json').write_text(json.dumps(dict(cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported CAM16-UCS fixtures:',len(cases)*120,'vectors')
