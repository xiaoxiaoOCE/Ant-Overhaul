"""Copy exactly67 pinned runtime inputs from a separately extracted manual package."""
from pathlib import Path,PurePosixPath
import argparse,hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manual',type=Path,required=True);p.add_argument('--output',type=Path,default=ROOT/'build/runtime-payload');a=p.parse_args()
 manual=a.manual.resolve();dest=a.output.resolve();m=json.loads((ROOT/'release-manifest.json').read_text('utf8'));assert m['release']=='0.2.0'and len(m['files'])==67
 assert not dest.exists(),'Output must be a new directory'
 sources=[]
 for r in m['files']:
  rel=PurePosixPath(r['path']);assert not rel.is_absolute()and'..'not in rel.parts
  src=manual/str(rel);assert src.resolve().is_relative_to(manual)and src.is_file()
  assert src.stat().st_size==r['length']and sha(src)==r['sha256'],'Manual input differs: '+str(rel);sources.append((src,str(rel),r['sha256']))
 dest.mkdir(parents=True)
 for src,rel,h in sources:
  target=dest/rel;assert target.resolve().is_relative_to(dest);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,target);assert sha(target)==h
 print(json.dumps({'passed':True,'copiedFiles':len(sources),'output':str(dest),'sourceUnchanged':True}))
if __name__=='__main__':main()
