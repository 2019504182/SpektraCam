#!/usr/bin/env python3
"""Run upstream runtime tests without its desktop GUI or LUT authoring tests."""
import os,pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
RESULT=ROOT/'Reference'/'results';RESULT.mkdir(exist_ok=True)
env=os.environ.copy();env['PYTHONPATH']=str(ROOT/'Reference/upstream/src');env['MPLBACKEND']='Agg';env['NUMBA_NUM_THREADS']='4'
args=[str(ROOT/'Reference/.venv/bin/python'),'-m','pytest',str(ROOT/'Reference/upstream/tests'), '--ignore='+str(ROOT/'Reference/upstream/tests/gui'),'--ignore='+str(ROOT/'Reference/upstream/tests/lut_creator'),'-q','--disable-warnings','--junitxml='+str(RESULT/'upstream-tests.xml')]
with (RESULT/'upstream-tests.log').open('w') as log:
 result=subprocess.run(args,env=env,stdout=log,stderr=subprocess.STDOUT)
print('\n'.join((RESULT/'upstream-tests.log').read_text().splitlines()[-25:]))
sys.exit(result.returncode)
