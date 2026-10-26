import os, json, mimetypes, urllib.parse
from playwright.sync_api import sync_playwright
ROOT='/tmp/claude-0/rt/app/src/main/assets'; HOST='https://appassets.androidplatform.net'
def route(r):
    url=r.request.url
    if not url.startswith(HOST+'/assets/'): return r.abort()
    f=os.path.join(ROOT,urllib.parse.unquote(url[len(HOST+'/assets/'):].split('?')[0]))
    if not os.path.isfile(f): return r.fulfill(status=404,body='')
    r.fulfill(status=200,body=open(f,'rb').read(),headers={'content-type':mimetypes.guess_type(f)[0] or 'application/octet-stream'})
with sync_playwright() as p:
    b=p.chromium.launch(executable_path='/opt/pw-browsers/chromium-1194/chrome-linux/chrome',args=['--no-sandbox'])
    ctx=b.new_context(); ctx.route('**/*',route); pg=ctx.new_page()
    pg.goto(HOST+'/assets/www/index.html',wait_until='commit'); pg.wait_for_timeout(5000)
    names=pg.evaluate("""(()=>{const out=[];for(const k of ['MANIFEST','MARK']){try{if(eval('typeof '+k)!=='undefined')out.push(k)}catch(e){}}return out})()""")
    print(names)
    for k in names:
        try:
            s=pg.evaluate(f"JSON.stringify({k}, (key,v)=> (v instanceof HTMLImageElement||v instanceof HTMLCanvasElement)? undefined : v)")
            open(f'dump/{k}.json','w').write(s); print(k,len(s))
        except Exception as e: print('ERR',k,str(e)[:100])
    b.close()
