import re,json
src=open('/tmp/claude-0/pmdred_full/src/dungeon_info.c').read()
items=json.load(open('/tmp/claude-0/pmd1/game/data/items.json'))
# ITEM_ enum -> red id
enum={}
hdr=open('/tmp/claude-0/pmdred_full/include/constants/item.h').read()
for m in re.finditer(r'#define (ITEM_\w+)\s+(0x[0-9a-fA-F]+|\d+)\b',hdr):
    enum[m.group(1)]=int(m.group(2),0)
by_red={v['red_id']:k for k,v in items.items() if 'red_id' in v}
out={}
for name in ['KecleonShop1','KecleonWares1','KecleonShop2','KecleonWares2','KecleonShop3','KecleonWares3','KecleonShop4','KecleonWares4']:
    body=re.search(r'sRandomItemsSet'+name+r'\[\] = \{(.*?)\};',src,re.S).group(1)
    cats=[];its=[]
    for m in re.finditer(r'(?:FIRST_CATEGORY_CHANCE|NEXT_CHANCE)\s*\((\w+),\s*ODDS\(([\d.]+)\)\)',body):
        k,p=m.group(1),float(m.group(2))
        if k.startswith('CATEGORY_'): cats.append([k[9:].lower(),p])
        else:
            rid=enum.get(k); key=by_red.get(rid)
            its.append([key or k,p])
    out[name]={'cats':cats,'items':its}
json.dump(out,open('/tmp/claude-0/pmd1/game/data/kecleon_sets.json','w'),indent=0)
for k,v in out.items(): print(k,v['cats'],v['items'][:30])
for name,v in out.items():
    new=[]
    for k,p in v['items']:
        if k not in items:
            alt=k.replace('ITEM_TM_','').replace('ITEM_','').replace('_','').lower()
            print('unresolved',k,alt,alt in items)
            if alt in items: k=alt
            else: continue
        new.append([k,p,items[k].get('red_cat','')])
    v['items']=new
json.dump(out,open('/tmp/claude-0/pmd1/game/data/kecleon_sets.json','w'))
