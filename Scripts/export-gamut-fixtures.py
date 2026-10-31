#!/usr/bin/env python3
import hashlib,json,os,pathlib,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg')
import colour,numpy as np
from spektrafilm.utils.gamut_compression import _get_output_c_max_table,OutputGamutCompressSpec,compress_rgb
rng=np.random.default_rng(20261031);cases=[];binary=bytearray()
for space in ['sRGB','Display P3','ProPhoto RGB']:
 cs=colour.RGB_COLOURSPACES[space];white=colour.xy_to_XYZ(cs.whitepoint)
 l,h,table=_get_output_c_max_table('cam16ucs',space)
 inputs=rng.uniform(0,2,(180,3));inputs[:8]=[[0,0,0],[1,1,1],[.184]*3,[4,.1,.001],[1,0,0],[0,1,0],[0,0,1],[-.05,.3,.8]]
 output=compress_rgb(inputs,OutputGamutCompressSpec(),output_color_space=space)
 forward=colour.RGB_to_XYZ(np.eye(3),colourspace=space,illuminant=cs.whitepoint,apply_cctf_decoding=False)
 inverse=colour.XYZ_to_RGB(np.eye(3),colourspace=space,illuminant=cs.whitepoint,apply_cctf_encoding=False)
 payload=np.asarray(table,dtype='<f8').tobytes();offset=len(binary);binary+=payload
 cases.append(dict(space=space,white=white.tolist(),lAxis=l.tolist(),hAxis=h.tolist(),byteOffset=offset,byteLength=len(payload),matrixToXYZ=forward.tolist(),matrixFromXYZ=inverse.tolist(),input=inputs.tolist(),expected=output.tolist()))
out=ROOT/'Reference/Fixtures';(out/'gamut-boundaries.f64').write_bytes(binary)
(out/'gamut-stages.json').write_text(json.dumps(dict(tablesSHA256=hashlib.sha256(binary).hexdigest(),cases=cases),allow_nan=False,separators=(',',':'))+'\n')
print('Exported gamut fixtures:',len(cases),'spaces;',len(binary),'boundary bytes')
