import re,json,glob,os
D='/tmp/claude-0/pmdred_full/src/data/'
out={}
def cstr(body):
    parts=re.findall(r'"((?:[^"\\]|\\.)*)"',body)
    s=''.join(parts)
    return s.replace('\\n','\n').replace('\\"','"')
for fn in glob.glob(D+'locale/*_usa.h'):
    t=open(fn,encoding='utf-8').read()
    for m in re.finditer(r'#define\s+(\w+)\s+\(_\(((?:.|\n)*?)\)\)\s*\n',t):
        out[m.group(1)]=cstr(m.group(2))
# static strings in data headers we need
for fn in glob.glob(D+'*.h')+['/tmp/claude-0/pmdred_full/src/common_strings.c','/tmp/claude-0/pmdred_full/src/friend_rescue.c','/tmp/claude-0/pmdred_full/src/mailbox.c','/tmp/claude-0/pmdred_full/src/thank_you_wonder_mail.c','/tmp/claude-0/pmdred_full/src/rescue_password_menu.c','/tmp/claude-0/pmdred_full/src/wonder_mail_2.c']:
    base=os.path.basename(fn).rsplit('.',1)[0]
    t=open(fn,encoding='utf-8').read()
    for m in re.finditer(r'(?:ALIGNED\(4\) )?(?:static )?(?:ALIGNED\(4\) )?const u8 (\w+)\[\]\s*=\s*_?\(?((?:\s*"(?:[^"\\]|\\.)*"\s*)+)\)?\s*;',t):
        out[base+':'+m.group(1)]=cstr(m.group(2))
json.dump(out,open('/tmp/claude-0/pmd1/game/data/red_town_text.json','w'),ensure_ascii=False,indent=0)
print(len(out))
for k in ['KEC_ITEMS_AWAKE_DLG_05','FEL_AWAKE_WELCOME','code_801D014:sFmtMoneyCyan','options_menu2:sUnknown_80DC064']:
    print(k, repr(out.get(k)))
t=open(D+'pokemon_mail.h',encoding='utf-8').read()
news=[]
for m in re.finditer(r'\[(\d+)\] = \{ (\w+), (\w+) \}',t):
    news.append([out.get('pokemon_mail:'+m.group(2),'?'),out.get('pokemon_mail:'+m.group(3),'?')])
out['_pokemon_news']=news
json.dump(out,open('/tmp/claude-0/pmd1/game/data/red_town_text.json','w'),ensure_ascii=False,indent=0)
print(len(news), news[0], news[55][0], sum(1 for n in news if n[0]=='?' or n[1]=='?'))
