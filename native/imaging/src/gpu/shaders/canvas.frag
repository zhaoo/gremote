#version 300 es
precision highp float;
precision highp sampler2D;
precision highp int;
uniform sampler2D photo;
uniform ivec2 tileOrigin,photoOrigin;
uniform ivec4 photoRect;
uniform vec3 background;
out vec4 outputColor;
void main(){ivec2 global=ivec2(gl_FragCoord.xy)+tileOrigin;
  if(all(greaterThanEqual(global,photoRect.xy))&&all(lessThan(global,photoRect.xy+photoRect.zw)))
    outputColor=vec4(texelFetch(photo,global-photoRect.xy-photoOrigin,0).rgb,1.);
  else outputColor=vec4(background,1.);
}
