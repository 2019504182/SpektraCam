#!/usr/bin/env python3
"""Download the pinned upstream source for an isolated numerical reference."""
import hashlib,io,json,pathlib,tarfile,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
REV='3bb2c2d2801ff68b92019cf1dbcbb133d60832bc'
DEST=ROOT/'Reference'/'upstream'
URL=f'https://codeload.github.com/andreavolpato/spektrafilm/tar.gz/{REV}'
if (DEST/'reference-source.json').exists():
 print('Pinned source already prepared.');raise SystemExit
payload=urllib.request.urlopen(URL,timeout=120).read()
DEST.mkdir(parents=True,exist_ok=True)
count=0
with tarfile.open(fileobj=io.BytesIO(payload),mode='r:gz') as archive:
 for member in archive.getmembers():
  parts=pathlib.PurePosixPath(member.name).parts[1:]
  if not parts or not member.isfile():continue
  rel=pathlib.PurePosixPath(*parts)
  if '..' in rel.parts:raise ValueError('Unsafe archive path')
  if parts[0] not in ['src','tests','pyproject.toml','README.md','LICENSE','SPEKTRAFILM_LICENSE.txt']:continue
  target=DEST/rel;target.parent.mkdir(parents=True,exist_ok=True)
  target.write_bytes(archive.extractfile(member).read());count+=1
(DEST/'reference-source.json').write_text(json.dumps({'revision':REV,'url':URL,'archive_sha256':hashlib.sha256(payload).hexdigest(),'files':count},indent=2)+'\n')
print(f'Prepared {count} upstream files; archive {len(payload)/1e6:.1f} MB')
