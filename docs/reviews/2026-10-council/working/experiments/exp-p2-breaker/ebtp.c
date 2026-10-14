#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "ebur128.h"
int main(int argc,char**argv){ FILE*f=fopen(argv[1],"rb"); unsigned fs=atoi(argv[2]); unsigned ch=argc>3?atoi(argv[3]):2;
 fseek(f,0,SEEK_END); long n=ftell(f)/4; fseek(f,0,SEEK_SET); float*x=malloc(n*4); fread(x,4,n,f); fclose(f);
 ebur128_state*s=ebur128_init(ch,fs,EBUR128_MODE_TRUE_PEAK|EBUR128_MODE_I); ebur128_add_frames_float(s,x,n/ch);
 double mx=0,v; for(unsigned c=0;c<ch;c++){ebur128_true_peak(s,c,&v); if(v>mx)mx=v;} double I; ebur128_loudness_global(s,&I);
 printf("%s ebur128_TP=%.3f dBTP I=%.2f\n",argv[1],20*log10(mx),I); return 0;}
