#version 300 es
precision highp float;
precision highp int;
uniform highp sampler2D source;
uniform highp sampler3D cube;
uniform vec3 domainMin,domainMax;
uniform int cubeSize,processVersion;
uniform float strength;
out vec4 color;
vec3 lookup(vec3 value) {
    vec3 at=clamp((value-domainMin)/(domainMax-domainMin),0.,1.)*float(cubeSize-1);
    ivec3 lo=min(ivec3(at),ivec3(cubeSize-2));vec3 f=at-vec3(lo);
    vec3 a=texelFetch(cube,lo,0).rgb,d=texelFetch(cube,lo+1,0).rgb,b,c;
    float w0,w1,w2,w3;
    if(f.r>f.g) {
        if(f.g>f.b){b=texelFetch(cube,lo+ivec3(1,0,0),0).rgb;c=texelFetch(cube,lo+ivec3(1,1,0),0).rgb;w0=1.-f.r;w1=f.r-f.g;w2=f.g-f.b;w3=f.b;}
        else if(f.r>f.b){b=texelFetch(cube,lo+ivec3(1,0,0),0).rgb;c=texelFetch(cube,lo+ivec3(1,0,1),0).rgb;w0=1.-f.r;w1=f.r-f.b;w2=f.b-f.g;w3=f.g;}
        else{b=texelFetch(cube,lo+ivec3(0,0,1),0).rgb;c=texelFetch(cube,lo+ivec3(1,0,1),0).rgb;w0=1.-f.b;w1=f.b-f.r;w2=f.r-f.g;w3=f.g;}
    } else {
        if(f.b>f.g){b=texelFetch(cube,lo+ivec3(0,0,1),0).rgb;c=texelFetch(cube,lo+ivec3(0,1,1),0).rgb;w0=1.-f.b;w1=f.b-f.g;w2=f.g-f.r;w3=f.r;}
        else if(f.b>f.r){b=texelFetch(cube,lo+ivec3(0,1,0),0).rgb;c=texelFetch(cube,lo+ivec3(0,1,1),0).rgb;w0=1.-f.g;w1=f.g-f.b;w2=f.b-f.r;w3=f.r;}
        else{b=texelFetch(cube,lo+ivec3(0,1,0),0).rgb;c=texelFetch(cube,lo+ivec3(1,1,0),0).rgb;w0=1.-f.g;w1=f.g-f.r;w2=f.r-f.b;w3=f.b;}
    }
    return w0*a+w1*b+w2*c+w3*d;
}
void main() {
    vec4 value=texelFetch(source,ivec2(gl_FragCoord.xy),0);
    if(processVersion==1)value.rgb=floor(value.rgb*255.+.5)/255.;
    vec3 result=value.rgb+(lookup(value.rgb)-value.rgb)*strength;
    if(processVersion==1)result=floor(clamp(result,0.,1.)*255.+.5)/255.;
    color=vec4(result,value.a);
}
