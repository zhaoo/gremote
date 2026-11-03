#pragma once
#include "gpu_context.h"
#include "generation_gate.h"
#include "image.h"
#include "photo_edits.h"
#include <memory>

namespace gremote::gpu {
class GpuSession {
 public:
  explicit GpuSession(Image source, std::shared_ptr<GenerationGate> gate=std::make_shared<GenerationGate>());
  ~GpuSession();
  GpuSession(const GpuSession&)=delete;
  GpuSession& operator=(const GpuSession&)=delete;
  bool Advance(uint64_t generation){return gate_->Advance(generation);}
  std::shared_ptr<GenerationGate> gate() const {return gate_;}
  bool Render(uint64_t generation,const PhotoEdits& edits,const uint8_t* cube,
      size_t cube_length,float strength,int width,int height);
  void Attach(ANativeWindow* window,int width,int height);
  void Detach();
  bool Present(uint64_t generation);
  Image ReadFinal();
  void Close();
  void CheckOwner() const {context_.CheckOwner();}
  const Capabilities& capabilities()const{return context_.capabilities();}
  int source_width()const{return source_.width;}
  int source_height()const{return source_.height;}
 private:
  void Copy(GLuint source,int width,int height,bool flip);
  void CheckOpen() const;
  GpuContext context_;
  Image source_;
  std::shared_ptr<GenerationGate> gate_;
  std::unique_ptr<Target> linear_,final_;
  GLuint source_texture_=0,copy_=0,vao_=0;
  uint64_t rendered_=0;
  int window_width_=0,window_height_=0;
  bool closed_=false;
};
}  // namespace gremote::gpu
