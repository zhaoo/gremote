#include "gpu_source.h"
#include "input_color.h"
#include "jpeg_io.h"
#include "gremote_imaging.h"
#include <unistd.h>
#include <stdexcept>
#include <cerrno>
namespace gremote::gpu {
SourceIdentity IdentifySource(int fd){
  struct stat s{};if(fd<0||fstat(fd,&s))throw std::runtime_error("gpuSourceRead");
#ifdef __APPLE__
  auto mt=s.st_mtimespec,ct=s.st_ctimespec;
#else
  auto mt=s.st_mtim,ct=s.st_ctim;
#endif
  return {s.st_dev,s.st_ino,s.st_size,int64_t(mt.tv_sec)*1000000000+mt.tv_nsec,int64_t(ct.tv_sec)*1000000000+ct.tv_nsec};
}
Image LoadSource(int fd,int version,bool adobe,SourceIdentity* identity){
  struct Guard{int fd;~Guard(){if(fd>=0)::close(fd);}}guard{fd};
  if(version!=1&&version!=2)throw std::runtime_error("gpuInvalidProcessVersion");
  const auto source=IdentifySource(fd);
  if(source.size<4||source.size>128*1024*1024)throw std::runtime_error("gpuSourceSizeLimit");
  std::vector<uint8_t> bytes(size_t(source.size),0);size_t offset=0;
  while(offset<bytes.size()){
    const auto count=pread(fd,bytes.data()+offset,bytes.size()-offset,off_t(offset));
    if(count<0&&errno==EINTR)continue;if(count<=0)throw std::runtime_error("gpuSourceRead");offset+=size_t(count);
  }
  int w=0,h=0;
  if(ReadJpegSize(bytes.data(),bytes.size(),&w,&h)!=GREMOTE_OK)throw std::runtime_error("gpuSourceDecode");
  // Includes RGBA source atlas padding. Optical masks have a separate preflight.
  if(w<=0||h<=0||w>65535||h>65535||int64_t(w)*h>64*1024*1024)throw std::runtime_error("gpuSourceMemoryLimit");
  Image rgb;if(DecodeJpeg(bytes.data(),bytes.size(),1,&rgb)!=GREMOTE_OK)throw std::runtime_error("gpuSourceDecode");
  if(version==2){std::vector<uint8_t> profile;if(!ReadJpegIcc(bytes.data(),bytes.size(),&profile)||!NormalizeToSrgb(&rgb,profile,adobe))throw std::runtime_error("gpuUnsupportedColorProfile");}
  if(!(IdentifySource(fd)==source))throw std::runtime_error("gpuSourceChanged");
  const size_t pixels=size_t(w)*h;rgb.pixels.resize(pixels*4);
  for(size_t i=pixels;i-->0;){const auto r=rgb.pixels[i*3],g=rgb.pixels[i*3+1],b=rgb.pixels[i*3+2];rgb.pixels[i*4]=r;rgb.pixels[i*4+1]=g;rgb.pixels[i*4+2]=b;rgb.pixels[i*4+3]=255;}
  rgb.channels=4;if(identity)*identity=source;return rgb;
}
}
