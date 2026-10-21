/* Original approximation of Charmera Pixel Filter, not a measured camera LUT.
 * Full-range Y/CbCr 4:2:2: threshold each luma, average chroma for shared pairs.
 * Palette: red FD0100, yellow F9D34E (reference image), blue 0100F9, grey E0E0E0.
 * No allocation, neighbor reads, division helper, RAW access or stride writes. */
#ifndef M10V_CHARMERA_H
#define M10V_CHARMERA_H
static void m10v_charmera_render(m10v_library_image *image,uint32_t color){
 static const uint8_t palette[4][3]={{77,85,254},{207,55,158},{29,252,108},{224,128,128}};
 const uint8_t *p=palette[color];
 for(uint32_t row=0;row<image->height;row++)for(uint32_t x=0;x<image->width;x+=2){
  uint32_t at=row*image->stride+x,a=image->y[at]>=128,b=image->y[at+1]>=128,n=a+b;
  image->y[at]=a?p[0]:0;image->y[at+1]=b?p[0]:0;
  image->chroma[at]=(uint8_t)((256+(int)n*((int)p[1]-128))/2);
  image->chroma[at+1]=(uint8_t)((256+(int)n*((int)p[2]-128))/2);
 }
}
#endif
