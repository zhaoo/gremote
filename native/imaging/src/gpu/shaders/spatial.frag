#version 300 es
precision highp float;
precision highp int;
precision highp sampler2DArray;
uniform sampler2DArray a,b;
uniform sampler2D color;
uniform ivec2 aSize,aPage,bSize,bPage,pageOrigin,axis,fullSize,colorOrigin;
uniform int operation,offset,radius,processVersion;
uniform float threshold,haloGain,bloomGain;
out vec4 outputColor;
float readA(ivec2 p){p=clamp(p,ivec2(0),aSize-1);ivec2 page=p/aPage;int columns=(aSize.x+aPage.x-1)/aPage.x;return texelFetch(a,ivec3(p%aPage,page.y*columns+page.x),0).r;}
float readB(ivec2 p){p=clamp(p,ivec2(0),bSize-1);ivec2 page=p/bPage;int columns=(bSize.x+bPage.x-1)/bPage.x;return texelFetch(b,ivec3(p%bPage,page.y*columns+page.x),0).r;}
float prefix(int index,int line){if(index<0)return 0.;return readA(axis.x==1?ivec2(index,line):ivec2(line,index));}
float interval(int left,int right,int line){
  int first=left/128,last=right/128;
  if(first==last)return prefix(right,line)-(left%128==0?0.:prefix(left-1,line));
  float sum=prefix(min((first+1)*128-1,(axis.x==1?aSize.x:aSize.y)-1),line)-(left%128==0?0.:prefix(left-1,line))+prefix(right,line);
  if(last>first+1)sum+=readB(ivec2(last-1,line))-readB(ivec2(first,line));
  return sum;
}
vec3 legacy(vec3 value){return processVersion==1?floor(clamp(value,0.,1.)*255.+.5)/255.:value;}
void main(){
  ivec2 p=ivec2(gl_FragCoord.xy)+pageOrigin;
  float value=0.;
  if(operation==0){ // Mask from the upstream color tile, optional preceding halation.
    vec3 rgb=legacy(texelFetch(color,p-colorOrigin,0).rgb);
    if(haloGain!=0.)rgb=legacy(rgb+(1.-rgb)*readA(p)*haloGain*vec3(1.,.25,.08)*.8);
    float t=clamp((dot(rgb,vec3(.2126,.7152,.0722))-threshold)/max(.00001,1.-threshold),0.,1.);value=t*t*(3.-2.*t);
  }else if(operation==1){ // Block-local inclusive scan; never accumulates more than128 pixels.
    int at=axis.x==1?p.x:p.y;value=readA(p);
    if(at%128>=offset)value+=readA(p-axis*offset);
  }else if(operation==2){ // Extract one total per block into a compact groups-by-lines atlas.
    int length=axis.x==1?aSize.x:aSize.y;
    int end=min((p.x+1)*128-1,length-1);value=prefix(end,p.y);
  }else if(operation==3){value=readA(p);if(p.x>=offset)value+=readA(p-ivec2(offset,0));
  }else if(operation==4){
    int at=axis.x==1?p.x:p.y,line=axis.x==1?p.y:p.x,length=axis.x==1?aSize.x:aSize.y;
    int left=max(0,at-radius),right=min(length-1,at+radius);
    float first=prefix(0,line),last=prefix(length-1,line)-( (length-1)%128==0?0.:prefix(length-2,line));
    value=(interval(left,right,line)+float(max(0,radius-at))*first+float(max(0,at+radius-length+1))*last)/float(2*radius+1);
  }else{ // Compose both masks after all spatial work. Coordinates remain global across tiles.
    vec4 rgba=texelFetch(color,p-colorOrigin,0);vec3 rgb=legacy(rgba.rgb);
    if(haloGain!=0.)rgb=legacy(rgb+(1.-rgb)*readA(p)*haloGain*vec3(1.,.25,.08)*.8);
    if(bloomGain!=0.)rgb=legacy(rgb+(1.-rgb)*readB(p)*bloomGain*.8);
    outputColor=vec4(rgb,rgba.a);return;
  }
  outputColor=vec4(value,0.,0.,1.);
}
