"""Build the exact resource PAK from the included14 cooked asset files (stdlib only)."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,io,json,struct
ROOT=Path(__file__).resolve().parents[1]
def sha(b):return hashlib.sha256(b).hexdigest()
def fstring(s):
 b=s.encode('utf8')+b'\0';return struct.pack('<i',len(b))+b
def entry(offset,b):return struct.pack('<QQQI',offset,len(b),len(b),0)+hashlib.sha1(b).digest()+struct.pack('<BI',0,0)
def build():
 m=json.loads((ROOT/'assets/manifest.json').read_text('utf8'));assert m['pakVersion']==3 and m['mountPoint']=='../../../'and len(m['files'])==14
 rows=[];names=set()
 for r in m['files']:
  rel=PurePosixPath(r['path']);assert not rel.is_absolute()and'..'not in rel.parts and rel.suffix in('.uasset','.uexp')
  assert r['path'].startswith('EotU/Content/EAA/')and r['path'].casefold()not in names;names.add(r['path'].casefold())
  p=ROOT/'assets/cooked'/str(rel);assert p.resolve().is_relative_to((ROOT/'assets/cooked').resolve())
  b=p.read_bytes();assert len(b)==r['length']and sha(b)==r['sha256'],'Cooked input changed: '+str(rel);rows.append((str(rel),b))
 for rel,_ in rows:assert str(PurePosixPath(rel).with_suffix('.uexp'if rel.endswith('.uasset')else'.uasset')).casefold()in names
 out=io.BytesIO();index=[]
 for rel,b in sorted(rows):index.append((rel,out.tell(),b));out.write(entry(0,b));out.write(b)
 idx=fstring(m['mountPoint'])+struct.pack('<i',len(index))
 for rel,offset,b in index:idx+=fstring(rel)+entry(offset,b)
 pos=out.tell();out.write(idx);out.write(struct.pack('<IIQQ',0x5A6F12E1,3,pos,len(idx))+hashlib.sha1(idx).digest())
 b=out.getvalue();assert sha(b)==m['expectedPakSha256'],'PAK output does not match release pin';return b,m
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,default=ROOT/'build/AntOverhaul_P.pak');p.add_argument('--verify-only',action='store_true');a=p.parse_args()
 b,m=build()
 if not a.verify_only:
  a.output.parent.mkdir(parents=True,exist_ok=True)
  with a.output.open('xb')as f:f.write(b)
 print(json.dumps({'passed':True,'files':len(m['files']),'bytes':len(b),'sha256':sha(b),'output':None if a.verify_only else str(a.output)}))
if __name__=='__main__':main()
