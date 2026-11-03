#version 300 es
precision highp float;
precision highp int;
uniform highp sampler2D source;
uniform highp sampler2D curves;
uniform int processVersion;
out vec4 color;
float curve(int channel,float value) {
    float at=clamp(value,0.,1.)*255.;int lo=int(at),hi=min(255,lo+1);
    float a=texelFetch(curves,ivec2(lo,channel),0).r;
    float b=texelFetch(curves,ivec2(hi,channel),0).r;
    return a+(b-a)*(at-float(lo));
}
void main() {
    vec4 value=texelFetch(source,ivec2(gl_FragCoord.xy),0);
    if(processVersion==1)value.rgb=floor(value.rgb*255.+.5)/255.;
    for(int c=0;c<3;++c)value[c]=curve(c+1,curve(0,value[c]));
    if(processVersion==1)value.rgb=floor(clamp(value.rgb,0.,1.)*255.+.5)/255.;
    color=value;
}
