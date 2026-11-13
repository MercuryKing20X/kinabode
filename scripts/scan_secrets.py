#!/usr/bin/env python3
"""Scan reachable Git objects or a directory. Reports locations/rules, never values."""
import argparse,json,re,subprocess,sys,time
from pathlib import Path
RULES={
 'private-key':rb'-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=\r\n]{64,}-----END (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',
 'openai-style-key':rb'(?<![A-Za-z0-9])sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}',
 'aws-access-key':rb'(?<![A-Z0-9])(?:AKIA|ASIA)[A-Z0-9]{16}(?![A-Z0-9])',
 'github-token':rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})',
 'google-api-key':rb'AIza[A-Za-z0-9_-]{35}',
 'slack-token':rb'xox[baprs]-[A-Za-z0-9-]{20,}',
 'stripe-live-key':rb'(?:sk|rk)_live_[A-Za-z0-9]{20,}',
 'jwt':rb'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{12,}',
 'url-password':rb'(?i)https?://[^\s/:@]{1,100}:[^\s/@]{8,100}@',
 'private-endpoint':rb'(?i)api[.]dingdong[.]work|api[.]kootapi[.]com',
 'private-key-filename':rb'(?i)(?:\xe7\x94\x9f\xe5\x9b\xbe)?api[.]txt',
 'personal-absolute-path':rb'/' + rb'Users/[^\s\"\x27]+|~/' + rb'Desktop/[^\s\"\x27]+|[A-Za-z]:\\Users\\[^\s\"\x27]+',
 'literal-secret':rb'''(?i)(?:api[_-]?key|access[_-]?token|client[_-]?secret|password|authorization|secret[_-]?key)["']?\s*[:=]\s*["'](?:Bearer\s+)?([A-Za-z0-9_+/.=-]{16,})["']''',
}
RX={k:re.compile(v) for k,v in RULES.items()}
EXAMPLE=re.compile(rb'(?i)(?:example|placeholder|dummy|fake|test|sample|your[_-]|replace|not[_-]?a[_-]?real|redacted|abcdef|123456|xxxx)')
def scan(data,path,oid=None):
 out=[]
 for rule,rx in RX.items():
  for m in rx.finditer(data):
   value=m.group(1) if rule=='literal-secret' else m.group()
   # Public regexes and exact protocol fixture values are recorded, never leaked.
   example=bool(EXAMPLE.search(value))
   out.append({'path':path,'object':oid,'line':data.count(b'\n',0,m.start())+1,'rule':rule,'classification':'example_or_fixture_candidate' if example else 'review_required'})
 return out
def main():
 p=argparse.ArgumentParser();p.add_argument('--git',type=Path);p.add_argument('--directory',type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
 findings=[];objects=0;total=0;started=time.monotonic();commits=0
 if a.git:
  refs=subprocess.check_output(['git','rev-list','--objects','--all'],cwd=a.git).splitlines()
  commits=int(subprocess.check_output(['git','rev-list','--all','--count'],cwd=a.git))
  child=subprocess.Popen(['git','cat-file','--batch'],cwd=a.git,stdin=subprocess.PIPE,stdout=subprocess.PIPE)
  for row in refs:
   oid,_,rawpath=row.partition(b' ');path=rawpath.decode('utf-8','replace') or '(commit metadata)'
   child.stdin.write(oid+b'\n');child.stdin.flush();header=child.stdout.readline().split()
   size=int(header[2]);data=child.stdout.read(size);child.stdout.read(1)
   if header[1] not in (b'blob',b'commit'):continue
   objects+=1;total+=size;findings.extend(scan(data,path,oid.decode()))
  child.stdin.close();child.wait()
  for hit in findings:
   hit['commits']=subprocess.check_output(['git','log','--all','--format=%H','--find-object='+hit['object']],cwd=a.git).decode().splitlines()
 elif a.directory:
  for file in sorted(a.directory.rglob('*')):
   if not file.is_file() or '.git' in file.relative_to(a.directory).parts or '.godot' in file.relative_to(a.directory).parts:continue
   data=file.read_bytes();objects+=1;total+=len(data);findings.extend(scan(data,str(file.relative_to(a.directory))))
 else:p.error('select --git or --directory')
 report={'mode':'all_reachable_history' if a.git else 'directory','commits':commits,'objects_scanned':objects,'bytes_scanned':total,'rules':list(RULES),'findings':findings,'seconds':round(time.monotonic()-started,3),'values_redacted':True}
 a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2))
 print(json.dumps({k:v for k,v in report.items() if k!='findings'},ensure_ascii=False));print('findings:',len(findings))
 sys.exit(1 if any(f['classification']=='review_required' for f in findings) else 0)

if __name__=="__main__":main()
