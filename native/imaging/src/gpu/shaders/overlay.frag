#version 300 es
precision highp float;
precision highp int;
uniform sampler2D source;
uniform ivec2 origin;
out vec4 outputColor;
void main(){outputColor=texelFetch(source,ivec2(gl_FragCoord.xy)-origin,0);}
