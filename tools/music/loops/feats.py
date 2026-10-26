import numpy as np, scipy.signal as ss
SR=22050; HOP=256; NFFT=2048
def melfb(n=64,fmin=40,fmax=10000):
    m=lambda f:2595*np.log10(1+f/700); im=lambda m:700*(10**(m/2595)-1)
    pts=im(np.linspace(m(fmin),m(fmax),n+2)); fr=np.fft.rfftfreq(NFFT,1/SR)
    fb=np.zeros((n,len(fr)))
    for i in range(n):
        a,b,c=pts[i:i+3]; fb[i]=np.clip(np.minimum((fr-a)/(b-a),(c-fr)/(c-b)),0,None)
    return fb
def chromafb():
    fr=np.fft.rfftfreq(NFFT,1/SR); fb=np.zeros((12,len(fr)))
    ok=(fr>60)&(fr<5000); p=12*np.log2(fr[ok]/440)+69
    for c in range(12):
        d=((p-c)%12); d=np.minimum(d,12-d); fb[c,ok]=np.exp(-0.5*(d/0.3)**2)
    return fb
MEL=melfb(); CH=chromafb()
def spec(x):
    f,t,Z=ss.stft(x,SR,nperseg=NFFT,noverlap=NFFT-HOP,boundary=None,padded=False)
    return np.abs(Z)  # frame i centered at i*HOP+NFFT/2
def feats(x):
    # pad so frame i centers at i*HOP
    xp=np.concatenate([np.zeros(NFFT//2,np.float32),x,np.zeros(NFFT,np.float32)])
    P=spec(xp)**2
    mel=np.log(MEL@P+1e-8)
    ch=CH@P; ch=ch/(ch.sum(0,keepdims=True)+1e-9)
    rms=np.sqrt(P.sum(0))
    return mel,ch,rms
