#version 300 es
precision highp float;
precision highp int;
uniform highp sampler2D source;
uniform int processVersion;
uniform float p[10];
uniform vec3 gains;
uniform float exposure,contrast,peak;
out vec4 color;
float luma(vec3 rgb){return dot(rgb,vec3(.2126,.7152,.0722));}
float decode(float x){return x<=.04045?x/12.92:pow((x+.055)/1.055,2.4);}
float encode(float x){return x<=.0031308?x*12.92:1.055*pow(x,1./2.4)-.055;}
float sigmoid(float x){return 1./(1.+exp(-x));}
float luminance(float sourceY) {
    float y=sourceY*exposure;
    if(y>1e-12) {
        const float pivot=-2.473931188;
        float l=pivot+contrast*(log2(y)-pivot);
        l+=p[2]*.8*sigmoid((l+.5)/.55);
        l+=p[3]*1.2*(1.-sigmoid((l+3.5)/.8));
        l+=p[4]*.5*sigmoid((l+.08)/.22);
        y=exp2(l);
    }
    if(p[5]>=0.)y+=p[5]*.02*exp(-y/.06);
    else y+=p[5]*.015*(1.-exp(-y/.03))*exp(-y/.15);
    return max(0.,y);
}
vec3 toneV2(vec3 encoded) {
    vec3 rgb=vec3(decode(encoded.r),decode(encoded.g),decode(encoded.b))*gains;
    float original=luma(rgb),y=luminance(original);
    if(peak>1.&&y>.75){float d=y-.75;y=.75+d/(1.+d*(peak-1.)/((peak-.75)*.25));}
    y=clamp(y,0.,1.);
    float hi=max(rgb.r,max(rgb.g,rgb.b)),lo=min(rgb.r,min(rgb.g,rgb.b));
    float chroma=hi>1e-9?(hi-lo)/hi:0.;
    float saturation=(1.+p[8])*(1.+p[9]*(1.-chroma));
    vec3 delta=original>1e-12?(rgb*y/original-y)*saturation:vec3(0);
    float gamut=1.;
    for(int c=0;c<3;++c) {
        if(delta[c]>1e-9)gamut=min(gamut,(1.-y)/delta[c]);
        if(delta[c]<-1e-9)gamut=min(gamut,-y/delta[c]);
    }
    rgb=clamp(vec3(y)+gamut*delta,0.,1.);
    return vec3(encode(rgb.r),encode(rgb.g),encode(rgb.b));
}
vec3 toneV1(vec3 rgb) {
    rgb=floor(rgb*255.+.5)/255.;
    float e=exp2(p[0]),c=exp2(p[1]*1.5);
    for(int ch=0;ch<3;++ch) {
        float x=clamp(rgb[ch]*e,0.,1.);
        if(p[1]!=0.)x=x<=.5?.5*pow(2.*x,c):1.-.5*pow(2.*(1.-x),c);
        x=clamp(x+p[2]*.8*x*x*(1.-x),0.,1.);
        x=clamp(x+p[3]*.8*x*(1.-x)*(1.-x),0.,1.);
        if(p[4]!=0.)x=pow(x,exp2(-p[4]*.5));
        rgb[ch]=clamp(x+p[5]*.2*(1.-x)*(1.-x),0.,1.);
    }
    rgb*=vec3(1.+p[6]*.18+p[7]*.08,1.-p[7]*.16,1.-p[6]*.18+p[7]*.08);
    float y=luma(rgb),chroma=max(rgb.r,max(rgb.g,rgb.b))-min(rgb.r,min(rgb.g,rgb.b));
    float sat=(1.+p[8])*(1.+p[9]*(1.-clamp(chroma,0.,1.)));
    return floor(clamp(vec3(y)+(rgb-y)*sat,0.,1.)*255.+.5)/255.;
}
void main(){vec4 value=texelFetch(source,ivec2(gl_FragCoord.xy),0);color=vec4(processVersion==1?toneV1(value.rgb):toneV2(value.rgb),value.a);}
