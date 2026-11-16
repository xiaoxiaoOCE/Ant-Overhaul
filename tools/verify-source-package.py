"""Read-only verification of the source inventory (build outputs are allowed)."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
def main():
 d=json.loads((ROOT/'source-file-hashes.json').read_text('utf8'));assert d['release']=='0.2.0'
 for r in d['files']:
  p=ROOT/r['path'];assert p.resolve().is_relative_to(ROOT.resolve())and p.is_file()
  assert p.stat().st_size==r['length']and hashlib.sha256(p.read_bytes()).hexdigest()==r['sha256'],'Changed source input: '+r['path']
 print(json.dumps({'passed':True,'sourceFiles':len(d['files']),'scope':'Read-only source verification; additional local build outputs are not evaluated.'}))
if __name__=='__main__':main()
