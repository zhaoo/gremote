#pragma once
#include "gpu_context.h"
#include "generation_gate.h"
#include "gpu_pipeline.h"
#include "gpu_source.h"
#include "gpu_export.h"
#include <map>
#include <string>
#include <deque>
#include "image.h"
#include "photo_edits.h"
#include <memory>

namespace gremote::gpu {
class GpuSession {
 public:
  explicit GpuSession(Image source, std::shared_ptr<GenerationGate> gate=std::make_shared<GenerationGate>(),int orientation=1,int process_version=0);
  ~GpuSession();
  GpuSession(const GpuSession&)=delete;
  GpuSession& operator=(const GpuSession&)=delete;
  bool Advance(uint64_t generation){return gate_->Advance(generation);}
  std::shared_ptr<GenerationGate> gate() const {return gate_;}
  bool Render(uint64_t generation,const PhotoEdits& edits,const uint8_t* cube,
      size_t cube_length,float strength,int width,int height);
  void PrepareLut(const std::string& key,const uint8_t* bytes,size_t length);
  bool RenderPrepared(uint64_t generation,const PhotoEdits& edits,const std::string& key,float strength,int width,int height);
  const std::array<uint64_t,6>& stage_counts()const{CheckOpen();static const std::array<uint64_t,6> empty{};return pipeline_?pipeline_->counts():empty;}
  void Attach(ANativeWindow* window,int width,int height);
  void Detach();
  bool Present(uint64_t generation,bool original=false);
  std::vector<float> Histogram(uint64_t generation);
  Image Thumbnail(const PhotoEdits& edits,const uint8_t* cube,size_t length,float strength,int width,int height);
  Image ReadFinal();
  void Export(const PhotoEdits& edits,const uint8_t* cube,size_t length,float strength,const ExportSpec& spec,const volatile int32_t* cancel,std::function<bool()> cancelled={});
  void Close();
  void CheckOwner() const {context_.CheckOwner();}
  const Capabilities& capabilities()const{return context_.capabilities();}
  int source_width()const{return orientation_>=5?source_.height:source_.width;}
  int source_height()const{return orientation_>=5?source_.width:source_.height;}
  void SetIdentity(SourceIdentity value){identity_=value;}
  bool Matches(int fd,int orientation,int version)const{return identity_&&*identity_==IdentifySource(fd)&&orientation_==orientation&&process_version_==version;}
 private:
  void Copy(GLuint source,int width,int height,bool flip);
  void CheckOpen() const;
  bool RenderColor(uint64_t generation,const PhotoEdits& edits,const std::shared_ptr<LutData>& lut,float strength,int width,int height);
  std::shared_ptr<LutData> ParseLut(const uint8_t* bytes,size_t length);
  GpuContext context_;
  Image source_;
  std::shared_ptr<GenerationGate> gate_;
  std::unique_ptr<Target> final_,original_;
  std::unique_ptr<ColorPipeline> pipeline_;
  std::map<std::string,std::shared_ptr<LutData>> luts_;
  std::deque<std::string> lut_order_;
  std::shared_ptr<LutData> inline_lut_;
  uint64_t next_lut_serial_=1;
  int orientation_=1,process_version_=0;
  std::optional<SourceIdentity> identity_;
  int page_width_=0,page_height_=0;
  GLuint source_texture_=0,copy_=0,vao_=0;
  uint64_t rendered_=0;
  int window_width_=0,window_height_=0;
  bool closed_=false;
};
}  // namespace gremote::gpu
