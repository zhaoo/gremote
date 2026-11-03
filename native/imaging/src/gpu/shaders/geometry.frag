#version 300 es
precision highp float;
precision highp int;
uniform highp sampler2DArray source;
uniform ivec2 sourceSize, sourceOrigin, sourceRegionSize, rotatedSize;
uniform ivec4 crop;
uniform vec2 fullOutputSize, outputOrigin;
uniform vec3 rotation; // cosine, sine, enlarged-rotation zoom
uniform int exif, turns, flipX, flipY, straighten, processVersion;
out vec4 color;
vec4 rawPixel(ivec2 p) {
    p=clamp(p,ivec2(0),sourceSize-1);
    ivec2 page=p/sourceRegionSize;
    int columns=(sourceSize.x+sourceRegionSize.x-1)/sourceRegionSize.x;
    return texelFetch(source,ivec3(p%sourceRegionSize,page.y*columns+page.x),0);
}
vec4 orientedPixel(ivec2 p) {
    if(flipX==1)p.x=rotatedSize.x-1-p.x;
    if(flipY==1)p.y=rotatedSize.y-1-p.y;
    ivec2 normalizedSize=exif>=5?sourceSize.yx:sourceSize;
    ivec2 s=p;
    if(turns==1)s=ivec2(p.y,normalizedSize.y-1-p.x);
    else if(turns==2)s=normalizedSize-1-p;
    else if(turns==3)s=ivec2(normalizedSize.x-1-p.y,p.x);
    p=s;
    if(exif==2)s=ivec2(sourceSize.x-1-p.x,p.y);
    else if(exif==3)s=sourceSize-1-p;
    else if(exif==4)s=ivec2(p.x,sourceSize.y-1-p.y);
    else if(exif==5)s=p.yx;
    else if(exif==6)s=ivec2(p.y,sourceSize.y-1-p.x);
    else if(exif==7)s=ivec2(sourceSize.x-1-p.y,sourceSize.y-1-p.x);
    else if(exif==8)s=ivec2(sourceSize.x-1-p.y,p.x);
    return rawPixel(s);
}
vec4 straightenedPixel(ivec2 p) {
    if(straighten==0)return orientedPixel(p);
    vec2 center=(vec2(rotatedSize)-1.)*.5;
    vec2 d=(vec2(p)-center)/rotation.z;
    vec2 q=clamp(vec2(rotation.x*d.x+rotation.y*d.y,-rotation.y*d.x+rotation.x*d.y)+center,
                 vec2(0),vec2(rotatedSize)-1.);
    ivec2 a=ivec2(floor(q)),b=min(a+1,rotatedSize-1);
    vec2 f=fract(q);
    vec4 value=mix(mix(orientedPixel(a),orientedPixel(ivec2(b.x,a.y)),f.x),
                   mix(orientedPixel(ivec2(a.x,b.y)),orientedPixel(b),f.x),f.y);
    return processVersion==1?floor(value*255.+.5)/255.:value;
}
void main() {
    vec2 pixel=floor(gl_FragCoord.xy)+outputOrigin;
    vec2 scale=vec2(crop.zw)/fullOutputSize;
    vec2 begin=vec2(crop.xy)+pixel*scale;
    vec2 end=vec2(crop.xy)+(pixel+1.)*scale;
    ivec2 first=ivec2(floor(begin));
    ivec2 last=min(crop.xy+crop.zw-1,ivec2(ceil(end))-1);
    vec4 total=vec4(0);
    for(int y=first.y;y<=last.y;++y) {
        vec4 row=vec4(0);
        for(int x=first.x;x<=last.x;++x) {
            float weight=(min(end.x,float(x+1))-max(begin.x,float(x)))/scale.x;
            row+=weight*straightenedPixel(ivec2(x,y));
        }
        float weight=(min(end.y,float(y+1))-max(begin.y,float(y)))/scale.y;
        total+=weight*row;
    }
    color=processVersion==1?floor(clamp(total,0.,1.)*255.+.5)/255.:total;
}
