#version 300 es
precision highp float;
precision highp sampler2D;
precision highp int;
uniform sampler2D source;
uniform vec2 fullSize,origin;
uniform float p[19]; // descriptor indices 11..29
uniform int processVersion;
out vec4 outputColor;
float clamp01(float x){return clamp(x,0.,1.);}
uint hashValue(uint x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;return x^(x>>16);}
float noise(ivec2 xy,uint seed){return float(hashValue(uint(xy.x)*0x1f123bb5u ^ uint(xy.y)*0x5f356495u ^ seed)&0xffffffu)/16777215.;}
float grain(vec2 xy,float cells,uint seed){vec2 pos=xy*cells;ivec2 at=ivec2(floor(pos));vec2 f=fract(pos);
  return mix(mix(noise(at,seed),noise(at+ivec2(1,0),seed),f.x),mix(noise(at+ivec2(0,1),seed),noise(at+ivec2(1,1),seed),f.x),f.y)*2.-1.;}
float smoothValue(float a,float b,float x){float t=clamp01((x-a)/max(.00001,b-a));return t*t*(3.-2.*t);}
void main(){
  vec4 inputColor=texelFetch(source,ivec2(gl_FragCoord.xy),0);
  if(processVersion==1)inputColor=floor(clamp(inputColor,0.,1.)*255.+.5)/255.;
  vec2 xy=(gl_FragCoord.xy+origin)/fullSize;
  uint seed=uint(p[18]);
  const float pi=3.14159265358979323846;
  float position=(p[13]+(noise(ivec2(5,11),seed)-.5)*.2)*2.*pi;
  vec2 leakCenter=.5+.65*vec2(cos(position),sin(position));
  vec3 leakColor=clamp(.5+.8*cos(2.*pi*(vec3(p[15])-vec3(0.,1./3.,2./3.))),0.,1.);
  float size=.12+p[1]*.9,feather=.04+p[2]*.9;
  float vignette=1.-p[0]*smoothValue(size*(1.-feather),size+feather*.5,length((xy-.5)*1.41421356));
  float spread=.06+p[14]*.75;
  float leak=p[12]*exp(-dot(xy-leakCenter,xy-leakCenter)/(2.*spread*spread));
  float cells=45.+750.*(1.-p[4])*(1.-p[4]);
  float g=(grain(xy,cells,seed)*(1.-p[5]*.75)+grain(xy,cells*3.7,seed+43u)*p[5]*.75)*p[3]*.22;
  float luma=dot(inputColor.rgb,vec3(.2126,.7152,.0722));
  vec3 value=mix(inputColor.rgb,vec3(luma),p[17])*vignette;
  value=value*(1.-p[16]*.35)+p[16]*.13;
  value+=leak*leakColor*(1.-value);value+=g;
  value=clamp(value,0.,1.);
  if(processVersion==1)value=floor(value*255.+.5)/255.;
  outputColor=vec4(value,inputColor.a);
}
