#!/usr/bin/env python3
"""Prepare attributed native model data from the pinned scientific reference."""
import hashlib,json,math,os,pathlib,shutil,sys
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'Reference/upstream/src'));os.environ.setdefault('MPLBACKEND','Agg')
import colour,numpy as np
from spektrafilm.profiles.io import load_profile
from spektrafilm.config import SPECTRAL_SHAPE,STANDARD_OBSERVER_CMFS
from spektrafilm.model.illuminants import standard_illuminant
from spektrafilm.utils.io import read_neutral_print_filters
from spektrafilm.utils.spectral_upsampling import HANATOS2025_SPECTRA_LUT,eval_spectral_bandpass_window,_quad2tri,_tri2quad,_illuminant_to_xy
from spektrafilm.utils.gamut_compression import compress_xy,InputGamutCompressSpec
F=ROOT/'Reference/Fixtures';OUT=ROOT/'andreavolpato-spektrafilm/Resources/ModelData';OUT.mkdir(exist_ok=True)
upsampling=json.loads((F/'upsampling-stages.json').read_text());gamut=json.loads((F/'gamut-stages.json').read_text())['cases'][0]
tables=(F/'hanatos-tables.f64').read_bytes();assert hashlib.sha256(tables).hexdigest()==upsampling['tablesSHA256']
profiles={};cmfs=np.asarray(STANDARD_OBSERVER_CMFS[:])
spectra=np.asarray(HANATOS2025_SPECTRA_LUT,dtype='<f2');assert np.all(np.isfinite(spectra))
spectral_size=spectra.shape[0];maps=bytearray();map_offsets={}
grid=np.linspace(0,1,spectral_size);tc=np.stack(np.meshgrid(grid,grid,indexing='ij'),axis=-1);xy=_quad2tri(tc)
for path in sorted((ROOT/'Reference/upstream/src/spektrafilm/data/profiles').glob('*.json')):
 p=load_profile(path.stem);m=p.data.density_curves_model
 light=standard_illuminant(p.info.viewing_illuminant)
 whiteXYZ=light@cmfs;whiteXY=colour.XYZ_to_xy(whiteXYZ)
 scanMatrix=colour.XYZ_to_RGB(np.eye(3),colourspace='sRGB',illuminant=whiteXY,apply_cctf_encoding=False)
 profiles[path.stem]=dict(id=path.stem,name=p.info.name,positive=p.info.type=='positive',stage=p.info.stage,
  logExposure=np.asarray(p.data.log_exposure).tolist(),densityCurves=np.asarray(p.data.density_curves).tolist(),
  densityLayers=np.asarray(p.data.density_curves_layers).tolist(),channels=np.asarray(p.data.channel_density).tolist(),base=np.asarray(p.data.base_density).tolist(),
  sensitivity=np.nan_to_num(10**p.data.log_sensitivity).tolist(),viewingIlluminant=light.tolist(),
  centers=m.centers.tolist(),amplitudes=m.amplitudes.tolist(),sigmas=m.sigmas.tolist(),scanMatrix=scanMatrix.tolist())
 if p.info.stage=='filming':
  reference=standard_illuminant(p.info.reference_illuminant)
  adaptation=p.hanatos2025_adaptation();window=eval_spectral_bandpass_window(adaptation.window_params)
  compressed=compress_xy(xy.reshape(-1,2),_illuminant_to_xy(p.info.reference_illuminant),InputGamutCompressSpec()).reshape(spectral_size,spectral_size,2)
  coordinates=np.asarray(_tri2quad(compressed)*(spectral_size-1),dtype='<f8').tobytes()
  digest=hashlib.sha256(coordinates).hexdigest()
  if digest not in map_offsets:map_offsets[digest]=len(maps);maps+=coordinates
  profiles[path.stem].update(referenceIlluminant=reference.tolist(),sensitivityWindow=window.tolist(),compressionMapOffset=map_offsets[digest])
neutral={key:values.get('TH-KG3',{}) for key,values in read_neutral_print_filters().items()}
identity=colour.RGB_to_RGB(np.eye(3),'sRGB','sRGB',apply_cctf_decoding=False,apply_cctf_encoding=False)
meter=colour.RGB_to_XYZ(np.eye(3),colourspace='sRGB',apply_cctf_decoding=False)[:,1]
index=dict(version=1,revision='3bb2c2d2801ff68b92019cf1dbcbb133d60832bc',profiles=profiles,spectralLUTSize=spectral_size,
 exposureTables=[{k:v for k,v in c.items() if k in ['stock','size','byteOffset','byteLength','matrix']} for c in upsampling['cases']],
 wavelengths=SPECTRAL_SHAPE.wavelengths.tolist(),cmfs=cmfs.tolist(),enlargerIlluminant=standard_illuminant('TH-KG3').tolist(),
 neutralFilters=neutral,gamut={k:v for k,v in gamut.items() if k in ['white','lAxis','hAxis','matrixToXYZ','matrixFromXYZ']},
 rgbRoundTrip=identity.tolist(),meteringY=meter.tolist())
def safe(v):
 if isinstance(v,float) and not math.isfinite(v):return 'NaN' if math.isnan(v) else ('Infinity' if v>0 else '-Infinity')
 if isinstance(v,list):return [safe(x) for x in v]
 if isinstance(v,dict):return {k:safe(x) for k,x in v.items()}
 return v
(OUT/'StockProfiles.json').write_text(json.dumps(safe(index),allow_nan=False,sort_keys=True,separators=(',',':'))+'\n')
(OUT/'HanatosTables.f64').write_bytes(tables)
(OUT/'HanatosSpectra.f16').write_bytes(spectra.tobytes())
(OUT/'InputCompressionMaps.f64').write_bytes(maps)
allgamut=(F/'gamut-boundaries.f64').read_bytes();offset=gamut['byteOffset'];(OUT/'GamutBoundary.f64').write_bytes(allgamut[offset:offset+gamut['byteLength']])
for src,dest in [('LICENSE','LICENSE.txt'),('SPEKTRAFILM_LICENSE.txt','SPEKTRAFILM_LICENSE.txt'),('ThirdPartyNotices.txt','ThirdPartyNotices.txt')]:shutil.copyfile(ROOT/src,OUT/dest)
(OUT/'CHANGELOG.txt').write_text('2026-10-31 — Native port data derived from Andrea Volpato, spektrafilm 3bb2c2d2801ff68b92019cf1dbcbb133d60832bc.\nProfile/LUT data: CC BY-SA 4.0; original license retained unchanged.\nChanges: load/unmix upstream profiles with its runtime; serialize processed arrays and stock-specific Hanatos tables; store sRGB CAM16-UCS gamut boundary and color-space matrices. Float64 precision retained. Missing measurements are strings "NaN".\nShared Hanatos irradiance spectra (provided upstream by hanatos/Johannes Hanika) retain their exact Float16 values. Stock spectral windows and input-compression coordinate maps support runtime UV/IR filtering.\nThese data support native calculations; they are not a baked final-look RGB LUT.\nRuntime Metal shader resources implement native code stages (GPLv3), separate from profile-derived CC BY-SA data.\n')
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.iterdir()) if p.is_file() and p.name!='manifest.json'}
(OUT/'manifest.json').write_text(json.dumps(dict(revision=index['revision'],files=manifest),indent=2)+'\n')
print('Prepared native data:',len(profiles),'profiles;',round(sum(p.stat().st_size for p in OUT.iterdir())/1e6,2),'MB; licenses retained')
