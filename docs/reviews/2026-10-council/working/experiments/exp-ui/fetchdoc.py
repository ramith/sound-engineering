import json, sys, urllib.request
def text(nodes):
    out=[]
    for n in nodes:
        t=n.get('type')
        if t=='text': out.append(n['text'])
        elif t=='codeVoice': out.append('`'+n['code']+'`')
        elif t=='reference': out.append('['+n.get('identifier','').split('/')[-1]+']')
        elif 'inlineContent' in n: out.append(text(n['inlineContent']))
    return ''.join(out)
def walk(content, depth=0):
    for c in content:
        t=c.get('type')
        if t=='paragraph': print('  '*depth+'- '+text(c['inlineContent']))
        elif t=='heading': print('  '*depth+'## '+c.get('text',''))
        elif t in ('unorderedList','orderedList'):
            for it in c.get('items',[]): walk(it.get('content',[]), depth+1)
        elif t=='aside':
            print('  '*depth+'['+c.get('style','aside')+']'); walk(c.get('content',[]), depth+1)
for path in sys.argv[1:]:
    url='https://developer.apple.com/tutorials/data/'+path+'.json'
    try:
        d=json.load(urllib.request.urlopen(url, timeout=30))
    except Exception as e:
        print('=== FAIL', path, e); continue
    print('===', path)
    print('TITLE:', d.get('metadata',{}).get('title'))
    print('ABSTRACT:', text(d.get('abstract',[])))
    plats=d.get('metadata',{}).get('platforms',[])
    print('PLATFORMS:', ', '.join(f"{p.get('name')} {p.get('introducedAt')}" + (' (deprecated)' if p.get('deprecated') else '') for p in plats))
    for s in d.get('primaryContentSections',[]):
        if s.get('kind')=='content': walk(s.get('content',[]))
