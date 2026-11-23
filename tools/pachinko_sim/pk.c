// Pachinko reference simulator (design validation). Board units: x in [0,1], y in [0,1.25], y up.
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

// ---------- RNG (SplitMix64) ----------
typedef struct { uint64_t s; } Rng;
static uint64_t nxt(Rng*r){ uint64_t z=(r->s+=0x9E3779B97F4A7C15ULL); z=(z^(z>>30))*0xBF58476D1CE4E5B9ULL; z=(z^(z>>27))*0x94D049BB133111EBULL; return z^(z>>31);}
static double uni(Rng*r){ return (nxt(r)>>11)*(1.0/9007199254740992.0);}
static double gauss(Rng*r){ double u=uni(r)+1e-300,v=uni(r); return sqrt(-2*log(u))*cos(6.283185307179586*v);}

// ---------- constants ----------
static double RB=0.0165, RN=0.006, G=7.0, DT=1.0/240, E_NAIL=0.45, E_WALL=0.35, FRIC=0.04, DRAG=0.10;
static double ACX=0.5, ACY=0.75, AR=0.47;
static double WL=0.03, WR=0.97;
static double FIRE_DT=0.6;
// economy
static int PAY_START=1, PAY_TULIP=3, PAY_SIDE=2, PAY_ATK=4, ATK_COUNT=5;
static double P_LOW=2950.0/65536, P_HIGH=1.0/8; static int ST_SPINS=12, JT_SPINS=12;
static int R7=10,RROYAL=5,RPLAIN=2; static double W7=0.08,WROYAL=0.32;
// geometry knobs
static double MEI_HALF=0.0265, MEI_Y=0.452, ROAD_X0=0.115, ROAD_DX=0.036, ROAD_DY=0.0085, ROAD_Y0=0.545; static int ROAD_N=9, ROAD_SKIP=3;
static double JUMP_X=0.0, JUMP_Y=0.0; // 0 = none
static double WARP_X=0.2535, WARP_Y=0.818, WARP_R=0.010, STAGE_SIG=0.025;
static double LAUNCH_SIG=0.05; static int HOLD_CAP=8; static double NECON=200000, SEED=1; static double START_Y0W=0.412; static double FIN_W=0.035; static double PW1=0.25; static double CAP_DY=0.05; static double ROLL=2.0; static double TUL_OFF=0.0; static double GUARD_Y=0.86, GUARD_X=0.247; static double RAMP_Y=0.70; static long NISO=30000; static double LPX=0.056, LPY=0.050;

typedef struct { double x,y,r; int kind; } Circle; // kind 0 nail,1 windmill,2 petal(dynamic)
typedef struct { double x1,y1,x2,y2,r; int zone; } Seg;
static Circle nails[1000]; static int nn=0;
static Seg segs[64]; static int ns=0;
#define GW 16
#define GH 20
static int grid[GW][GH][24]; static int gcount[GW][GH];
static void addNail(double x,double y,double r,int kind){ nails[nn].x=x;nails[nn].y=y;nails[nn].r=r;nails[nn].kind=kind;nn++; }
static void addSegR(double a,double b,double c,double d,double r,int zone){ segs[ns].x1=a;segs[ns].y1=b;segs[ns].x2=c;segs[ns].y2=d;segs[ns].r=r;segs[ns].zone=zone;ns++; }
static void addSeg(double a,double b,double c,double d){ addSegR(a,b,c,d,0,0); }

// LCD housing
static double LX0=0.27,LX1=0.73,LY0=0.60,LY1=0.93,LPEAK=1.04;
// pockets
static double TUL_X=0.19, TUL_Y=0.33; static double SIDE_X=0.085, SIDE_Y=0.235, SIDE_R=0.014;
static double ATK_X0=0.35, ATK_X1=0.63, ATK_Y0=0.195, ATK_Y1=0.22;
static double START_Y0=0.412, START_Y1=0.436, START_HW=0.013, WING_HW=0.10;
static double TUL_M_CLOSED=0.0285, TUL_M_OPEN=0.050, PETAL_R=0.008;
static int tulOpen[2]={0,0}; static int petalIdx[2][2];

static double distSeg(double px,double py,Seg*s,double*cx,double*cy){
  double dx=s->x2-s->x1, dy=s->y2-s->y1; double t=((px-s->x1)*dx+(py-s->y1)*dy)/(dx*dx+dy*dy); if(t<0)t=0; if(t>1)t=1;
  *cx=s->x1+t*dx; *cy=s->y1+t*dy; return hypot(px-*cx,py-*cy);
}
static int keepLattice(double x,double y){
  // walls
  if(x-WL<0.046||WR-x<0.046) return 0;
  if(y>ACY){ if(hypot(x-ACX,y-ACY)>AR-0.046) return 0; }
  // LCD keep-out (expanded)
  double m=0.046, cx,cy;
  if(x>LX0-m&&x<LX1+m&&y>LY0-m&&y<LY1) return 0;
  Seg a={LX0-0.03,LY1,0.5,LPEAK,0,0}, b={LX1+0.03,LY1,0.5,LPEAK,0,0};
  if(distSeg(x,y,&a,&cx,&cy)<m||distSeg(x,y,&b,&cx,&cy)<m) return 0;
  // under roof
  if(y>=LY1 && x>LX0-0.03 && x<LX1+0.03){ double yr=LPEAK-(LPEAK-LY1)*fabs(x-0.5)/(0.5-(LX0-0.03)); if(y<yr) return 0; }
  // warp keep-out (both sides)
  if(hypot(fabs(x-0.5)-(0.5-WARP_X),y-WARP_Y)<0.05) return 0;
  if((x<WL+0.09||x>WR-0.09)&&y<RAMP_Y+0.03&&y>RAMP_Y-0.075) return 0;
  return 1;
}
static void setPetals(int t){ double m=tulOpen[t]?TUL_M_OPEN:TUL_M_CLOSED; double cx=t==0?TUL_X:1-TUL_X; nails[petalIdx[t][0]].x=cx-m; nails[petalIdx[t][1]].x=cx+m; }
static void buildBoard(void){
  nn=0; ns=0;
  // upper lattice
  for(int j=0;j<14;j++){ double y=1.15-LPY*j; if(y<0.585) break;
    for(int i=-9;i<=9;i++){ double x=0.5+(i+0.5*(j&1))*LPX; if(x<0||x>1) continue; if(!keepLattice(x,y)) continue;
      // windmill replaces
      if(hypot(fabs(x-0.5)-0.34,y-0.676)<0.058) continue; if(hypot(fabs(x-0.5)-(0.5-GUARD_X),y-GUARD_Y)<0.05) continue;
      addNail(x,y,RN,0);} }
  addNail(0.16,0.676,0.014,1); addNail(0.84,0.676,0.014,1);
  // roads (mirror)
  for(int sgn=-1;sgn<=1;sgn+=2){
    { int i0=0; for(int i=0;i<=ROAD_N;i++){ if(i==ROAD_SKIP||i==ROAD_N){ if(i-1>i0){ double xa=ROAD_X0+ROAD_DX*i0, ya=ROAD_Y0-ROAD_DY*i0, xb=ROAD_X0+ROAD_DX*(i-1), yb=ROAD_Y0-ROAD_DY*(i-1); addSegR(sgn<0?xa:1-xa,ya,sgn<0?xb:1-xb,yb,RN,3);} i0=i+1; continue;} double x=ROAD_X0+ROAD_DX*i, y=ROAD_Y0-ROAD_DY*i; addNail(sgn<0?x:1-x,y,RN,3);} }
    addNail(0.5+sgn*MEI_HALF,MEI_Y,RN,0);
    if(JUMP_X>0) addNail(0.5+sgn*JUMP_X,JUMP_Y,RN,0);
  }
  // lower scatter rows
  double ly[3]={0.405,0.27,0.0}; 
  for(int k=0;k<1;k++) for(int i=-8;i<=7;i++){ double x=0.5+(i+0.5)*LPX; if(fabs(x-0.5)<0.10) continue; if(x-WL<0.046||WR-x<0.046) continue; if(CAP_DY>0&&hypot(fabs(x-0.5)-(0.5-TUL_X),ly[k]-(TUL_Y+CAP_DY))<0.05) continue; addNail(x,ly[k],RN,0);} 
  // tulip petals
  for(int t=0;t<2;t++){ double cx=t==0?TUL_X:1-TUL_X; petalIdx[t][0]=nn; addNail(cx-TUL_M_CLOSED,TUL_Y,PETAL_R,2); petalIdx[t][1]=nn; addNail(cx+TUL_M_CLOSED,TUL_Y,PETAL_R,2);} 
  if(CAP_DY>0) for(int t=0;t<2;t++){ double cx=t==0?TUL_X:1-TUL_X; addNail(cx,TUL_Y+CAP_DY,RN,0);}
  // side pocket guard nails
  for(int sgn=-1;sgn<=1;sgn+=2){ double cx=sgn<0?SIDE_X:1-SIDE_X; addNail(cx+sgn*(-0.0)+ (sgn<0?0.034:-0.034),SIDE_Y+0.005,RN,0);} 
  // attacker side guides (funnel nails toward attacker)
  for(int sgn=-1;sgn<=1;sgn+=2){ addNail(0.5+sgn*0.155,0.262,RN,3); addNail(0.5+sgn*0.185,0.273,RN,3); addNail(0.5+sgn*0.215,0.284,RN,3); addSegR(0.5+sgn*0.155,0.262,0.5+sgn*0.215,0.284,RN,3);
    addNail(0.5+sgn*GUARD_X-sgn*0.5+ (sgn<0?0.5:0.5)-0.5+0.0,0,0,3); nn--; addSegR(sgn<0?LX0:LX1,GUARD_Y+0.025,sgn<0?LX0-FIN_W:LX1+FIN_W,GUARD_Y,0,1);
    addSegR(sgn<0?WL:WR,RAMP_Y,sgn<0?WL+0.045:WR-0.045,RAMP_Y-0.04,0,0); } 
  // segments: LCD housing
  addSegR(LX0-0.03,LY1,0.5,LPEAK,0,1); addSegR(LX1+0.03,LY1,0.5,LPEAK,0,1);
  addSegR(LX0-0.03,LY1,LX0,LY1-0.03,0,1); addSegR(LX1+0.03,LY1,LX1,LY1-0.03,0,1);
  addSegR(LX0,LY1-0.03,LX0,LY0,0,1); addSegR(LX1,LY1-0.03,LX1,LY0,0,1);
  // floor
  addSegR(WL,0.13,0.42,0.055,0,2); addSegR(WR,0.13,0.58,0.055,0,2);
  // grid
  memset(gcount,0,sizeof gcount);
  for(int k=0;k<nn;k++){ if(nails[k].kind==3) continue; // petals: register in a wide span of cells
    double pad = nails[k].kind==2?0.03:0; 
    int x0=(int)((nails[k].x-nails[k].r-RB-pad)*GW), x1=(int)((nails[k].x+nails[k].r+RB+pad)*GW);
    int y0=(int)((nails[k].y-nails[k].r-RB)/1.25*GH), y1=(int)((nails[k].y+nails[k].r+RB)/1.25*GH);
    for(int a=x0;a<=x1;a++)for(int b=y0;b<=y1;b++){ if(a<0||a>=GW||b<0||b>=GH)continue; if(gcount[a][b]>=24){fprintf(stderr,"grid overflow\n");exit(1);} grid[a][b][gcount[a][b]++]=k; }
  }
  tulOpen[0]=tulOpen[1]=0; setPetals(0); setPetals(1);
}

// ---------- ball ----------
typedef struct { double x,y,vx,vy,age; int alive; int stage; double stageT; double sx,sy; } Ball;
enum { EV_NONE=0, EV_OUT, EV_START, EV_TULIP_L, EV_TULIP_R, EV_SIDE, EV_ATK, EV_STUCK, EV_FOUL };

static void collideCircle(Ball*b,double cx,double cy,double cr,double e){
  double dx=b->x-cx, dy=b->y-cy; double d2=dx*dx+dy*dy; double R=RB+cr; if(d2>=R*R||d2==0) return;
  double d=sqrt(d2), nx=dx/d, ny=dy/d; b->x=cx+nx*R; b->y=cy+ny*R;
  double vn=b->vx*nx+b->vy*ny; if(vn<0){ int rest=(-vn<0.12); double ee=rest?0:e; double tx=-ny,ty=nx; double vt=b->vx*tx+b->vy*ty; vt*=rest?(1-ROLL*DT):(1-FRIC); vn=-ee*vn; b->vx=vn*nx+vt*tx; b->vy=vn*ny+vt*ty; }
}
// launch: power in [0,1] -> k in [0.52,1.12]; returns 0 if foul
static int launch(Ball*b,double power,Rng*pr){
  double k=(0.52+0.60*power)*(1+LAUNCH_SIG*gauss(pr)); double Rb=AR-RB;
  memset(b,0,sizeof *b); b->alive=1;
  if(k<0.574) return 0;
  if(k<1.0){ double th=asin(k); double sp=sqrt(G*Rb*k); b->x=ACX-Rb*cos(th); b->y=ACY+Rb*sin(th); b->vx=sp*sin(th); b->vy=sp*cos(th); }
  else { // over the top, rides to the stopper at 125deg, bounces back softly
    double th=125*M_PI/180; double v2=3*G*Rb*k-2*G*Rb*sin(th); double sp=sqrt(v2)*0.25;
    b->x=ACX-(Rb-0.004)*cos(th); b->y=ACY+(Rb-0.004)*sin(th); // tangent direction clockwise = (sin th, cos th); bounce reverses
    b->vx=-sp*sin(th)*(0.6+0.8*uni(pr)); b->vy=-sp*cos(th)*(0.6+0.8*uni(pr)); }
  return 1;
}
// one physics step; returns event
static int wingsOpen=0, atkOpen=0;
static int stepBall(Ball*b,Rng*pr){
  if(b->stage){ b->stageT-=DT; if(b->stageT<=0){ b->stage=0; b->x=0.5+STAGE_SIG*gauss(pr); if(b->x<0.44)b->x=0.44; if(b->x>0.56)b->x=0.56; b->y=LY0-RB-0.002; b->vx=0; b->vy=0; } return EV_NONE; }
  b->age+=DT;
  b->vy-=G*DT; double dr=1-DRAG*DT; b->vx*=dr; b->vy*=dr; b->x+=b->vx*DT; b->y+=b->vy*DT;
  // arch / walls
  if(b->y>ACY){ double dx=b->x-ACX,dy=b->y-ACY; double d=hypot(dx,dy); double Rb=AR-RB; if(d>Rb){ double nx=-dx/d,ny=-dy/d; b->x=ACX+dx/d*Rb; b->y=ACY+dy/d*Rb; double vn=b->vx*nx+b->vy*ny; if(vn<0){ double ee=(-vn<0.12)?0:E_WALL; b->vx-=(1+ee)*vn*nx; b->vy-=(1+ee)*vn*ny; } } }
  else { if(b->x<WL+RB){ b->x=WL+RB; if(b->vx<0) b->vx=-E_WALL*b->vx; } if(b->x>WR-RB){ b->x=WR-RB; if(b->vx>0) b->vx=-E_WALL*b->vx; } }
  // segments
  for(int k=0;k<ns;k++){ Seg*sg=&segs[k]; double cx,cy; if(sg->zone==1){ if(b->y<LY0-0.02||b->y>LPEAK+0.02||b->x<LX0-0.05||b->x>LX1+0.05) continue; } else if(sg->zone==2){ if(b->y>0.15) continue; } else if(sg->zone==3){ if(b->y>0.60||b->y<0.24) continue; } double d=distSeg(b->x,b->y,sg,&cx,&cy); if(d<RB+sg->r) collideCircle(b,cx,cy,sg->r,sg->zone==3?E_NAIL:E_WALL); }
  // nails via grid
  int gx=(int)(b->x*GW), gy=(int)(b->y/1.25*GH); if(gx>=0&&gx<GW&&gy>=0&&gy<GH){ int c=gcount[gx][gy]; for(int k=0;k<c;k++){ Circle*n=&nails[grid[gx][gy][k]]; collideCircle(b,n->x,n->y,n->r,E_NAIL); } }
  // sensors
  if(b->y<0.03) return EV_OUT;
  if(b->y>START_Y0&&b->y<START_Y1&&fabs(b->x-0.5)<START_HW) return EV_START;
  if(wingsOpen&&b->y>START_Y0W&&b->y<START_Y0W+0.024&&fabs(b->x-0.5)<WING_HW) return EV_START;
  if(hypot(fabs(b->x-0.5)-(0.5-WARP_X),b->y-WARP_Y)<WARP_R && b->vy<0){ b->stage=1; b->stageT=1.2+0.8*uni(pr); return EV_NONE; }
  for(int t=0;t<2;t++){ double cx=t==0?TUL_X:1-TUL_X; double m=(tulOpen[t]?TUL_M_OPEN:TUL_M_CLOSED)-PETAL_R; if(fabs(b->x-cx)<m && b->y<TUL_Y-0.004 && b->y>TUL_Y-0.03) return t==0?EV_TULIP_L:EV_TULIP_R; }
  if(hypot(fabs(b->x-0.5)-(0.5-SIDE_X),b->y-SIDE_Y)<SIDE_R) return EV_SIDE;
  if(atkOpen && b->x>ATK_X0&&b->x<1-ATK_X0&&b->y>ATK_Y0&&b->y<ATK_Y1) return EV_ATK;
  if(b->age>10 && b->sx==0){b->sx=b->x;b->sy=b->y;}
  if(b->age>10 && fmod(b->age,0.5)<DT){ b->vx+=(uni(pr)-0.5)*0.6; b->vy+=0.3; }
  if(b->age>14) return EV_STUCK;
  return EV_NONE;
}

// ---------- modes ----------
static void dumpBoard(const char*path){ FILE*f=fopen(path,"w"); for(int k=0;k<nn;k++) fprintf(f,"N %.4f %.4f %.4f %d\n",nails[k].x,nails[k].y,nails[k].r,nails[k].kind); for(int k=0;k<ns;k++) fprintf(f,"S %.4f %.4f %.4f %.4f\n",segs[k].x1,segs[k].y1,segs[k].x2,segs[k].y2); fclose(f);} 

// isolated-ball stats (static board state): mode: wings/atk flags fixed
static void isolated(double power,long N,int wings,int atk,uint64_t seed,int verbose,const char*trace){
  Rng pr={seed}; long cnt[10]={0}; double tsum=0,tmax=0; long warp=0; FILE*tf=trace?fopen(trace,"w"):NULL;
  wingsOpen=wings; atkOpen=atk; tulOpen[0]=tulOpen[1]=0; setPetals(0); setPetals(1);
  for(long i=0;i<N;i++){ Ball b; if(!launch(&b,power,&pr)){cnt[EV_FOUL]++;continue;} int ev=0; int w=0; while(!(ev=stepBall(&b,&pr))){ if(b.stage) w=1; if(tf&&i<40) fprintf(tf,"%ld %.4f %.4f\n",i,b.x,b.y);} cnt[ev]++; if(ev==EV_STUCK&&verbose&&cnt[ev]<40) printf("stuck at %.2f %.2f\n",b.sx,b.sy); warp+=w; tsum+=b.age; if(b.age>tmax)tmax=b.age;
    if(ev==EV_TULIP_L){tulOpen[0]^=1;setPetals(0);} if(ev==EV_TULIP_R){tulOpen[1]^=1;setPetals(1);} }
  if(tf) fclose(tf);
  double n=N-cnt[EV_FOUL];
  fflush(stdout); printf("pw=%.2f w%d a%d | foul %.3f | start %.4f tulL %.4f tulR %.4f side %.4f atk %.4f out %.4f stuck %.6f warp %.4f | t_mean %.2f t_max %.1f | base %.4f\n",power,wings,atk,cnt[EV_FOUL]/(double)N,cnt[EV_START]/n,cnt[EV_TULIP_L]/n,cnt[EV_TULIP_R]/n,cnt[EV_SIDE]/n,cnt[EV_ATK]/n,cnt[EV_OUT]/n,cnt[EV_STUCK]/n,warp/n,tsum/n,tmax,
    (cnt[EV_START]*PAY_START+(cnt[EV_TULIP_L]+cnt[EV_TULIP_R])*PAY_TULIP+cnt[EV_SIDE]*PAY_SIDE)/n);
}


// ---------- coupled economy simulation ----------
typedef struct { double r, sym, reach; } Ticket;
typedef struct { long fired, paid, jackpots, firstHits, spins, startIn, startOver, reachN, fouls; double time; long chainMax; long payStart,payTul,paySide,payAtk; long ballsNormal, ballsOther; long maxFlight; long chainMax2; long ballsRound, ballsSupport; } Stats;
static double SPIN_T_VFAST=0.8; static double SPIN_T=3.0, SPIN_T_FAST=1.5, SPIN_T_SUPPORT=1.0, REACH_T=8.0, REACH_HIT_T=10.0, REACH_T_SUPPORT=4.0, FANFARE_T=3.0, INTER_T=0.8, ENDING_T=2.0, FAKE_REACH=0.10;
static int STRAT=0; static double PW_NORMAL=0.25, PW_ROUND=0.25, PW_SUPPORT=0.25;
// runs until maxBalls fired (bankroll<0 => unlimited) ; returns stats. session mode: bankroll>0, stop when broke and idle
static void runEcon(long maxBalls,long bankroll,uint64_t seed,Stats*st,int*sawJackpot,long*peak){
  Rng pr={seed}, lr={seed*7919+12345};
  Ball balls[64]; int nb=0; memset(balls,0,sizeof balls);
  int mode=0, modeSpins=0; static Ticket holds[4096]; int nh=0; int spinning=0; double spinT=0; int spinHit=0; Ticket cur;
  int phase=0; double phaseT=0; int roundsLeft=0, cnt=0, nextMode=0; long chain=0; double fireT=0; long bank=bankroll; int unlimited=bankroll<0;
  tulOpen[0]=tulOpen[1]=0; setPetals(0); setPetals(1); if(sawJackpot)*sawJackpot=0; if(peak)*peak=bank;
  long steps=0;
  for(;;){
    wingsOpen=(mode!=0&&phase==0); atkOpen=(phase==2);
    // fire
    fireT-=DT; if(fireT<=0){ int want=1; if(st->fired>=maxBalls) want=0; if(!unlimited&&bank<1) want=0;
      if(STRAT==1){ if(phase==0&&nh>=HOLD_CAP) want=0; if(phase==1||phase==4) want=0; }
      if(want&&nb<64){ double pw=phase?PW_ROUND:(mode?PW_SUPPORT:PW_NORMAL); Ball b; if(launch(&b,pw,&pr)){ balls[nb++]=b; st->fired++; bank--; if(mode==0&&phase==0) st->ballsNormal++; else st->ballsOther++; if(phase) st->ballsRound++; else if(mode) st->ballsSupport++; if(nb>st->maxFlight) st->maxFlight=nb; } else st->fouls++; fireT=FIRE_DT; } else fireT=0; }
    // balls
    for(int i=0;i<nb;i++){ int ev=stepBall(&balls[i],&pr); if(!ev) continue; long pay=0;
      if(ev==EV_START){ pay=PAY_START; st->payStart+=pay; st->startIn++; if(nh<HOLD_CAP){ holds[nh].r=uni(&lr); holds[nh].sym=uni(&lr); holds[nh].reach=uni(&lr); nh++; } else st->startOver++; if(nh>st->chainMax2) st->chainMax2=nh; }
      else if(ev==EV_TULIP_L||ev==EV_TULIP_R){ int t=ev==EV_TULIP_R; pay=PAY_TULIP; st->payTul+=pay; tulOpen[t]^=1; setPetals(t); }
      else if(ev==EV_SIDE){ pay=PAY_SIDE; st->paySide+=pay; }
      else if(ev==EV_ATK){ pay=PAY_ATK; st->payAtk+=pay; cnt++; if(cnt>=ATK_COUNT){ roundsLeft--; cnt=0; atkOpen=0; if(roundsLeft>0){ phase=3; phaseT=INTER_T; } else { phase=4; phaseT=ENDING_T; } } }
      st->paid+=pay; bank+=pay; if(peak&&bank>*peak)*peak=bank;
      balls[i]=balls[--nb]; i--; }
    // phases
    if(phase==1||phase==3||phase==4){ phaseT-=DT; if(phaseT<=0){ if(phase==4){ phase=0; mode=nextMode; modeSpins=(mode==1)?ST_SPINS:JT_SPINS; } else { phase=2; cnt=0; } } }
    // lottery
    if(phase==0){
      if(spinning){ spinT-=DT; if(spinT<=0){ spinning=0; if(spinHit){ st->jackpots++; if(mode==0&&chain==0) st->firstHits++; chain++; if(chain>st->chainMax) st->chainMax=chain; if(sawJackpot)*sawJackpot=1;
            double u=cur.sym; if(u<W7){ roundsLeft=R7; nextMode=1; } else if(u<W7+WROYAL){ roundsLeft=RROYAL; nextMode=1; } else { roundsLeft=RPLAIN; nextMode=2; }
            phase=1; phaseT=FANFARE_T; }
          else if(mode!=0){ if(--modeSpins<=0){ mode=0; chain=0; } } } }
      if(!spinning&&phase==0&&nh>0){ cur=holds[0]; for(int k=1;k<nh;k++) holds[k-1]=holds[k]; nh--; st->spins++; double p=(mode==1)?P_HIGH:P_LOW; spinHit=cur.r<p; spinning=1;
        if(mode!=0) spinT=spinHit?REACH_T_SUPPORT:SPIN_T_SUPPORT; else if(spinHit){ spinT=REACH_HIT_T; st->reachN++; } else if(cur.reach<FAKE_REACH){ spinT=REACH_T; st->reachN++; } else spinT=(nh>=4)?SPIN_T_VFAST:(nh>=2)?SPIN_T_FAST:SPIN_T; }
    }
    st->time+=DT; steps++;
    int canFire=(st->fired<maxBalls)&&(unlimited||bank>=1);
    if(!canFire&&nb==0&&!spinning&&nh==0&&phase==0) break;
    if(!canFire&&nb==0&&phase==2) break; // broke mid-round cannot happen (attacker pays) but guard
  }
}
static void econReport(long N,uint64_t seed){ Stats st; memset(&st,0,sizeof st); runEcon(N,-1,seed,&st,NULL,NULL);
  printf("seed %llu strat %d pw %.2f/%.2f/%.2f | balls %ld RTP %.4f | start %.4f tul %.4f side %.4f atk %.4f | s(all) %.4f over %.4f | spins %ld jackpots %ld first %ld (per100coins jp %.3f first %.3f) avgchain %.2f maxchain %ld | reach/spin %.3f | normalFrac %.3f | maxFlight %ld maxQueue %ld | roundFrac %.3f supFrac %.3f | coins/min %.1f\n",(unsigned long long)seed,STRAT,PW_NORMAL,PW_ROUND,PW_SUPPORT,st.fired,(double)st.paid/st.fired,
   (double)st.payStart/st.fired,(double)st.payTul/st.fired,(double)st.paySide/st.fired,(double)st.payAtk/st.fired,(double)st.startIn/st.fired,(double)st.startOver/(st.startIn+1e-9),st.spins,st.jackpots,st.firstHits,100.0*st.jackpots/st.fired,100.0*st.firstHits/st.fired,(double)st.jackpots/(st.firstHits+1e-9),st.chainMax,(double)st.reachN/st.spins,(double)st.ballsNormal/st.fired,st.maxFlight,st.chainMax2,(double)st.ballsRound/st.fired,(double)st.ballsSupport/st.fired,st.fired/(st.time/60)); fflush(stdout); }
static int cmpl(const void*a,const void*b){ long x=*(long*)a,y=*(long*)b; return x<y?-1:x>y; }
static void sessions(int n,long start,long cap,uint64_t seed){ long*balls=malloc(n*sizeof(long)); long*endb=malloc(n*sizeof(long)); int saw=0,bust=0,up=0; long dbl=0;
  for(int i=0;i<n;i++){ Stats st; memset(&st,0,sizeof st); int sj; long pk; long fired0=0; (void)fired0; runEcon(cap,start,seed+i*1000003ULL,&st,&sj,&pk); balls[i]=st.fired; long end=start-st.fired+st.paid; endb[i]=end; saw+=sj; if(end<1) bust++; if(end>start) up++; if(pk>=2*start) dbl++; }
  qsort(balls,n,sizeof(long),cmpl); qsort(endb,n,sizeof(long),cmpl);
  printf("sessions n=%d start=%ld cap=%ld balls: sawJackpot %.3f bust %.3f endUp %.3f peak>=2x %.3f | balls fired p10 %ld p50 %ld p90 %ld | end bankroll p10 %ld p50 %ld p90 %ld p99 %ld\n",n,start,cap,(double)saw/n,(double)bust/n,(double)up/n,(double)dbl/n,balls[n/10],balls[n/2],balls[n*9/10],endb[n/10],endb[n/2],endb[n*9/10],endb[n*99/100]); }

// ---------- stage-B fast model: one ball per 0.6 s, outcomes sampled from measured rates ----------
static double RS_N=0.0757, RS_W=0.2188, RT=0.0889, RD=0.1283, RA=0.399;
static void fastEcon(long maxBalls,uint64_t seed,Stats*st){ Rng lr={seed};
  int mode=0,modeSpins=0; long nh=0; int spinning=0; double spinT=0; int spinHit=0; double curSym=0; int phase=0; double phaseT=0; int roundsLeft=0,cnt=0,nextMode=0; long chain=0; const double dt=0.1; int sub=0;
  while(st->fired<maxBalls){
    if(sub==0){ st->fired++; if(mode==0&&phase==0) st->ballsNormal++; if(phase) st->ballsRound++; else if(mode) st->ballsSupport++;
      double u=uni(&lr); double ps=(mode!=0&&phase==0)?RS_W:RS_N; long pay=0;
      if(u<ps){ pay=PAY_START; st->payStart+=pay; st->startIn++; if(nh<HOLD_CAP) nh++; }
      else if(u<ps+RT){ pay=PAY_TULIP; st->payTul+=pay; }
      else if(u<ps+RT+RD){ pay=PAY_SIDE; st->paySide+=pay; }
      else if(phase==2&&u<ps+RT+RD+RA){ pay=PAY_ATK; st->payAtk+=pay; cnt++; if(cnt>=ATK_COUNT){ roundsLeft--; cnt=0; if(roundsLeft>0){phase=3;phaseT=INTER_T;} else {phase=4;phaseT=ENDING_T;} } }
      st->paid+=pay; }
    sub=(sub+1)%6;
    if(phase==1||phase==3||phase==4){ phaseT-=dt; if(phaseT<=0){ if(phase==4){ phase=0; mode=nextMode; modeSpins=(mode==1)?ST_SPINS:JT_SPINS; } else { phase=2; cnt=0; } } }
    if(phase==0){
      if(spinning){ spinT-=dt; if(spinT<=0){ spinning=0; if(spinHit){ st->jackpots++; if(mode==0&&chain==0) st->firstHits++; chain++; double u=curSym; if(u<W7){roundsLeft=R7;nextMode=1;} else if(u<W7+WROYAL){roundsLeft=RROYAL;nextMode=1;} else {roundsLeft=RPLAIN;nextMode=2;} phase=1; phaseT=FANFARE_T; }
          else if(mode!=0){ if(--modeSpins<=0){ mode=0; chain=0; } } } }
      if(!spinning&&phase==0&&nh>0){ nh--; st->spins++; double r=uni(&lr); curSym=uni(&lr); double rc=uni(&lr); double p=(mode==1)?P_HIGH:P_LOW; spinHit=r<p; spinning=1;
        if(mode!=0) spinT=spinHit?REACH_T_SUPPORT:SPIN_T_SUPPORT; else if(spinHit) spinT=REACH_HIT_T; else if(rc<FAKE_REACH) spinT=REACH_T; else spinT=(nh>=4)?SPIN_T_VFAST:(nh>=2)?SPIN_T_FAST:SPIN_T; }
    }
    st->time+=dt;
  }
}
static void fastReport(long N,uint64_t seed){ Stats st; memset(&st,0,sizeof st); fastEcon(N,seed,&st);
  printf("FAST seed %llu balls %ld RTP %.4f | start %.4f tul %.4f side %.4f atk %.4f | jp/100 %.3f first/100 %.3f avgchain %.2f | normalFrac %.3f roundFrac %.3f supFrac %.3f\n",(unsigned long long)seed,st.fired,(double)st.paid/st.fired,(double)st.payStart/st.fired,(double)st.payTul/st.fired,(double)st.paySide/st.fired,(double)st.payAtk/st.fired,100.0*st.jackpots/st.fired,100.0*st.firstHits/st.fired,(double)st.jackpots/(st.firstHits+1e-9),(double)st.ballsNormal/st.fired,(double)st.ballsRound/st.fired,(double)st.ballsSupport/st.fired); }

int main(int argc,char**argv){
  const char*cmd=argc>1?argv[1]:"iso";
  for(int i=2;i+1<argc;i+=2){ const char*k=argv[i]; double v=atof(argv[i+1]);
    #define P(name,var) if(!strcmp(k,name)) var=v;
    P("g",G) P("e",E_NAIL) P("mei",MEI_HALF) P("meiy",MEI_Y) P("roadn",ROAD_N) P("skip",ROAD_SKIP) P("jx",JUMP_X) P("jy",JUMP_Y) P("warpr",WARP_R) P("stagesig",STAGE_SIG) P("fric",FRIC) P("drag",DRAG)
    P("roadx0",ROAD_X0) P("roaddx",ROAD_DX) P("roaddy",ROAD_DY) P("roady0",ROAD_Y0) P("tuly",TUL_Y) P("tulx",TUL_X) P("lsig",LAUNCH_SIG) P("cap",HOLD_CAP) P("rsn",RS_N) P("rsw",RS_W) P("rt",RT) P("rd",RD) P("ra",RA) P("plow",P_LOW) P("phigh",P_HIGH) P("st",ST_SPINS) P("jt",JT_SPINS) P("patk",PAY_ATK) P("cnt",ATK_COUNT) P("strat",STRAT) P("pwn",PW_NORMAL) P("pwr",PW_ROUND) P("pws",PW_SUPPORT) P("n",NECON) P("seed",SEED) P("r7",R7) P("rroyal",RROYAL) P("rplain",RPLAIN) P("w7",W7) P("wroyal",WROYAL) P("pstart",PAY_START) P("winghw",WING_HW) P("atkx0",ATK_X0) P("wingy0",START_Y0W) P("warpy",WARP_Y) P("warpx",WARP_X) P("finw",FIN_W) P("capdy",CAP_DY) P("sider",SIDE_R) P("pw",PW1) P("tulopen",TUL_M_OPEN) P("tulclosed",TUL_M_CLOSED) P("roll",ROLL) P("guardy",GUARD_Y) P("guardx",GUARD_X) P("rampy",RAMP_Y) P("ptul",PAY_TULIP) P("pside",PAY_SIDE) P("niso",NISO) P("lpx",LPX) P("lpy",LPY)
  }
  buildBoard();
  if(!strcmp(cmd,"dump")){ dumpBoard("board.txt"); isolated(0.45,40,0,0,1,0,"trace.txt"); printf("nails %d\n",nn); return 0; }
  if(!strcmp(cmd,"stuck")){ isolated(0.1,6000,0,0,7,1,NULL); isolated(0.3,6000,0,0,7,1,NULL); isolated(0.9,6000,0,0,7,1,NULL); return 0; }
  if(!strcmp(cmd,"m")){ isolated(0.3,NISO,1,0,42,0,NULL); isolated(0.3,NISO,0,1,42,0,NULL); return 0; }
  if(!strcmp(cmd,"econ")){ econReport((long)NECON,(uint64_t)SEED); return 0; }
  if(!strcmp(cmd,"sess")){ sessions((int)NECON,100,3000,(uint64_t)SEED); return 0; }
  if(!strcmp(cmd,"fast")){ fastReport((long)NECON,(uint64_t)SEED); return 0; }
  if(!strcmp(cmd,"rates")){ isolated(PW1,NISO,0,0,(uint64_t)SEED,0,NULL); isolated(PW1,NISO,1,0,(uint64_t)SEED,0,NULL); isolated(PW1,NISO,0,1,(uint64_t)SEED,0,NULL); return 0; }
  if(!strcmp(cmd,"one")){ isolated(PW1,NISO,0,0,(uint64_t)SEED,0,NULL); return 0; }
  if(!strcmp(cmd,"q")){ isolated(0.3,NISO,0,0,42,0,NULL); isolated(0.95,NISO,0,0,42,0,NULL); return 0; }
  if(!strcmp(cmd,"lint")){ int bad=0; for(int a=0;a<nn;a++){ if(nails[a].kind==3) continue; for(int b=a+1;b<nn;b++){ if(nails[b].kind==3) continue; double d=hypot(nails[a].x-nails[b].x,nails[a].y-nails[b].y)-nails[a].r-nails[b].r; if(d<2*RB+0.004){ printf("tight pair (%.3f,%.3f)-(%.3f,%.3f) gap %.3f\n",nails[a].x,nails[a].y,nails[b].x,nails[b].y,d); bad++; } }
      for(int k=0;k<ns;k++){ double cx,cy; double d=distSeg(nails[a].x,nails[a].y,&segs[k],&cx,&cy)-nails[a].r-segs[k].r; if(d<2*RB+0.004){ printf("tight nail-seg (%.3f,%.3f) seg%d gap %.3f\n",nails[a].x,nails[a].y,k,d); bad++; } }
      if(nails[a].y<=ACY){ double d=fmin(nails[a].x-WL,WR-nails[a].x)-nails[a].r; if(d<2*RB+0.004){ printf("tight nail-wall (%.3f,%.3f) gap %.3f\n",nails[a].x,nails[a].y,d); bad++; } } }
    printf("lint: %d issues, %d nails\n",bad,nn); return 0; }
  if(!strcmp(cmd,"iso")){ for(double pw=0.1;pw<=1.001;pw+=0.1) isolated(pw,NISO,0,0,42,0,NULL); isolated(0.5,NISO,1,0,42,0,NULL); isolated(0.5,NISO,0,1,42,0,NULL); return 0; }
  return 0;
}
