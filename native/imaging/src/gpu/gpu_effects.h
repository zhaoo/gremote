#pragma once
#include "gpu_context.h"
#include "pipeline_state.h"
#include "spatial_plan.h"
#include <memory>
#include <optional>
#include <array>
#include <functional>
namespace gremote::gpu {
class ScalarAtlas {
 public:
  ScalarAtlas(int width,int height,const Capabilities& caps);
  ~ScalarAtlas();
  void BindPage(int column,int row)const;
  void Sample(GLuint program,int unit,const char* name)const;
  void Abandon(){texture=fbo=0;}
  SpatialPlan layout;
  GLuint texture=0,fbo=0;
};
class EffectsPipeline {
 public:
  explicit EffectsPipeline(const Capabilities& caps);
  ~EffectsPipeline();
  GLuint Render(GLuint source,const PipelineInputs& inputs,bool upstream);
  void PrepareGlobal(const PipelineInputs& inputs,const std::function<GLuint(const GeometryRegion&)>& color,const std::function<void()>& check);
  void Abandon();
  const std::array<uint64_t,3>& counts()const{return counts_;} // halo mask, bloom mask, texture
 private:
  void DrawAtlas(ScalarAtlas& target,GLuint program);
  void BindColor(GLuint source);
  void Fill(ScalarAtlas& mask,GLuint source,const PipelineInputs& inputs,bool halo);
  void Blur(ScalarAtlas& mask,int radius,const std::function<void()>& check=[]{});
  void TargetFor(std::unique_ptr<Target>& target,int w,int h);
  Capabilities caps_;
  GLuint spatial_=0,texture_=0,vao_=0;
  std::unique_ptr<ScalarAtlas> halo_,bloom_,scratch_;
  std::unique_ptr<Target> optics_,textured_;
  std::optional<PipelineInputs> previous_;
  bool global_prepared_=false;
  GLuint optical_output_=0,final_output_=0;
  std::array<uint64_t,3> counts_{};
};
}
