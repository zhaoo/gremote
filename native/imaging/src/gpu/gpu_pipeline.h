#pragma once
#include "gpu_context.h"
#include "gpu_effects.h"
#include "pipeline_state.h"
#include <array>
#include <memory>
#include <optional>

namespace gremote::gpu {
struct LutData {
  uint64_t serial=0;
  CubeLut lut;
  std::vector<uint8_t> bytes;
};
class ColorPipeline {
 public:
  explicit ColorPipeline(const Capabilities& capabilities);
  ~ColorPipeline();
  ColorPipeline(const ColorPipeline&)=delete;
  ColorPipeline& operator=(const ColorPipeline&)=delete;
  GLuint Render(GLuint source,const PipelineInputs& inputs,const CubeLut* lut);
  void Abandon();
  const std::array<uint64_t,6>& counts()const{return counts_;}
  GLuint curve_input()const{return outputs_[2];}
 private:
  void TargetFor(int stage,int width,int height);
  void Source(GLuint program,GLuint texture);
  void Draw(int stage);
  void Geometry(GLuint source,const PipelineInputs& inputs);
  void Tone(GLuint source,const PipelineInputs& inputs);
  void Lut(GLuint source,const PipelineInputs& inputs,const CubeLut& lut);
  void Curves(GLuint source,const PipelineInputs& inputs);
  Capabilities caps_;
  std::unique_ptr<EffectsPipeline> effects_;
  std::optional<PipelineInputs> previous_;
  std::array<std::unique_ptr<Target>,4> targets_;
  std::array<GLuint,4> programs_{};
  std::array<GLuint,4> outputs_{};
  std::array<uint64_t,6> counts_{};
  GLuint vao_=0,lut_texture_=0,curve_texture_=0;
  uint64_t uploaded_lut_=0;
};
}  // namespace gremote::gpu
