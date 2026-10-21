#include "test_main.h"
#include "gremote_imaging.h"
#include <vector>
#include <cstring>

TEST(FilmPreviewUsesRealFilmColorAndPreservesSourceAndAlpha) {
  const uint32_t w=65,h=17,pitch=w*4+12;
  std::vector<uint8_t> pixels(pitch*h,77),out(pitch*h,199);
  for(uint32_t y=0;y<h;y++)for(uint32_t x=0;x<w;x++){
    auto p=&pixels[y*pitch+x*4];p[0]=uint8_t(x*3);p[1]=uint8_t(y*12);p[2]=92;p[3]=123;
  }
  const auto before=pixels;
  // Version 1: LE film uint16, grain, grain-size, halo gain/spread/threshold/profile,
  // leak gain/position/spread/variation, film EI, charmera color, two reserved zero.
  uint8_t recipe[16]={75,0,0,1,0,3,5,0,0,0,4,0,0,0,0,0};
  EXPECT_EQ(gr_film_preview_v1(pixels.data(),w,h,pitch,recipe,16,0,out.data(),nullptr),0);
  EXPECT_TRUE(pixels==before);
  bool differs=false;
  for(uint32_t y=0;y<h;y++){
    for(uint32_t x=0;x<w;x++){
      const auto p=&out[y*pitch+x*4];EXPECT_EQ(p[3],123);
      EXPECT_TRUE(std::abs(int(p[0])-int(p[1]))<=2);EXPECT_TRUE(std::abs(int(p[1])-int(p[2]))<=2);
      differs|=p[0]!=pixels[y*pitch+x*4];
    }
    for(uint32_t x=w*4;x<pitch;x++)EXPECT_EQ(out[y*pitch+x],199);
  }
  EXPECT_TRUE(differs);
}

TEST(FilmPreviewRejectsBadRecipesAndCancellationWithoutPublishing) {
  std::vector<uint8_t> input(8*8*4,80),out(input.size(),177);
  uint8_t recipe[16]={33,0,0,1,0,3,5,0,0,0,4,0,0,0,0,0};
  int32_t cancel=1;
  EXPECT_TRUE(gr_film_preview_v1(input.data(),8,8,32,recipe,16,0,out.data(),&cancel)!=0);
  EXPECT_EQ(out[0],177);
  recipe[2]=4;
  EXPECT_TRUE(gr_film_preview_v1(input.data(),8,8,32,recipe,16,0,out.data(),nullptr)!=0);
  EXPECT_EQ(out[0],177);
}

TEST(FilmPreviewCarriesItsArtifactSourceIdentity) {
  const char* value=gr_film_identity_v1();
  EXPECT_TRUE(value!=nullptr);
  EXPECT_EQ(std::strlen(value),210u);
  EXPECT_EQ(std::strncmp(value,"GREMOTE_FILM_V1:",16),0);
  for(unsigned i=16;i<210;i++){
    if(i==80||i==145)EXPECT_EQ(value[i],':');
    else EXPECT_TRUE((value[i]>='0'&&value[i]<='9')||(value[i]>='a'&&value[i]<='f'));
  }
}
