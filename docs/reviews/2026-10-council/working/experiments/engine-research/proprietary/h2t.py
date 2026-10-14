import re,html,sys
t=open(sys.argv[1],encoding='utf-8',errors='replace').read()
s=re.sub(r'<(br|/p|/li|/h[1-6]|/tr|/pre|/dt|/dd|/div)\b[^>]*>','\n',t); s=re.sub(r'<[^>]+>','',s); s=html.unescape(s)
lines=[l.rstrip() for l in s.split('\n') if l.strip()]
open(sys.argv[2],'w').write('\n'.join(lines))
