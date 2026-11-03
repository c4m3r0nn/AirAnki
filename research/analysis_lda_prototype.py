import csv, sys, math
rows=list(csv.DictReader(open(sys.argv[1])))
ONSET,QUIET,QT,PEAKMIN,NS=float(sys.argv[3]),float(sys.argv[4]),float(sys.argv[5]),float(sys.argv[6]),3
seg=0; S=[]
for r in rows:
    if r['event']=='marker': seg+=1; continue
    if r['event']!='motion': continue
    S.append((seg,float(r['t_monotonic']),[float(r[k]) for k in ('rr_x','rr_y','rr_z')]))
mag=lambda v: math.sqrt(sum(x*x for x in v))
ev=[]; last=-9; i=0
while i<len(S):
    seg,t,w=S[i]
    if mag(w)>ONSET and t-last>QT:
        win=[x[2] for x in S[i:i+NS]]
        sm=[sum(v[k] for v in win) for k in range(3)]
        pk=max(mag(v) for v in win)
        ev.append((seg,t,sm,pk))
    if mag(w)>QUIET: last=t
    i+=1
lab={1:'R',2:'L',3:'S',4:'I'}
R=[e for e in ev if e[0]==1]; L=[e for e in ev if e[0]==2]
k=int(sys.argv[2]) if len(sys.argv)>2 else 3
mean=lambda es:[sum(e[2][j] for e in es)/len(es) for j in range(3)]
mR,mL=mean(R[:k]),mean(L[:k]); d=[mR[j]-mL[j] for j in range(3)]; n=mag(d); a=[x/n for x in d]
pr=lambda v: sum(v[j]*a[j] for j in range(3))
mid=(pr(mR)+pr(mL))/2; half=(pr(mR)-pr(mL))/2
print('axis',[round(x,2) for x in a],'mid %.1f half %.1f'%(mid,half))
for e in ev:
    if e[0] not in lab: continue
    p=pr(e[2])-mid
    c = '-' if e[3]<PEAKMIN else ('R' if p>0.35*half else ('L' if p<-0.35*half else '?'))
    train = (e in R[:k]) or (e in L[:k])
    print(lab[e[0]], c, 'p=%+.1f peak=%.1f'%(p,e[3]), 'TRAIN' if train else '')
