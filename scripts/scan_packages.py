#!/usr/bin/env python3
"""Scan extracted ZIP members and every embedded, unencrypted PCK entry."""
import argparse,hashlib,json,struct,zipfile
from pathlib import Path
from scan_secrets import scan
try:
 import zstandard
except ImportError:
 raise SystemExit("Package bytecode scanning requires: python -m pip install zstandard")
p=argparse.ArgumentParser(description=__doc__);p.add_argument('packages',nargs='+',type=Path);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
records=[];findings=[]
for package in a.packages:
 count=0;members=0;packed_names=set()
 with zipfile.ZipFile(package) as z:
  for info in z.infolist():
   if info.is_dir():continue
   members+=1;b=z.read(info);path=package.name+'/'+info.filename
   findings.extend(scan(b,path))
   start=None
   if b[:4]==b'GDPC':start=0
   elif b[-4:]==b'GDPC':start=len(b)-12-struct.unpack_from('<Q',b,len(b)-12)[0]
   if start is None:continue
   assert b[start:start+4]==b'GDPC'
   version=struct.unpack_from('<I',b,start+4)[0]
   if version!=4:raise ValueError('Unsupported PCK version: '+str(version))
   file_base=struct.unpack_from('<Q',b,start+24)[0]
   table=struct.unpack_from('<Q',b,start+32)[0]+start
   n=struct.unpack_from('<I',b,table)[0];at=table+4
   for _ in range(n):
    length=struct.unpack_from('<I',b,at)[0];at+=4
    name=b[at:at+length].rstrip(b'\0').decode();at+=length
    offset,size=struct.unpack_from('<QQ',b,at);at+=16
    md5=b[at:at+16];at+=16;flags=struct.unpack_from('<I',b,at)[0];at+=4
    if flags&1:raise ValueError('Encrypted pack entry')
    data=b[start+file_base+offset:start+file_base+offset+size]
    assert len(data)==size and hashlib.md5(data).digest()==md5,(name,size,offset)
    findings.extend(scan(data,path+'::'+name))
    if data[:4]==b'GDSC' and data[12:16]==bytes.fromhex('28b52ffd'):
     decoded=zstandard.ZstdDecompressor().decompress(data[12:],max_output_size=128*1024*1024)
     findings.extend(scan(decoded,path+'::'+name+'::decoded_tokens'))
    count+=1;packed_names.add(name)
 assert count>0,'No PCK entries found'
 for needed in ['content/about/about.md','content/about/about.en.md','content/i18n/release.csv','bridge/file_transport.py','content/release/island_thinker.py']:
  assert needed in packed_names,('Missing runtime raw text',needed)
 records.append({'package':package.name,'zip_files':members,'pck_entries_verified':count})
a.output.write_text(json.dumps({'packages':records,'findings':findings,'values_redacted':True},indent=2)+'\n')
print(json.dumps(records));print('findings:',len(findings));raise SystemExit(bool(findings))
