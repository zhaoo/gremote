#version 300 es
precision highp float;
precision highp int;
uniform highp sampler2D source;
uniform vec2 outputSize;
uniform int flip;
out vec4 color;
void main(){vec2 uv=gl_FragCoord.xy/outputSize;if(flip==1)uv.y=1.-uv.y;color=texture(source,uv);}
