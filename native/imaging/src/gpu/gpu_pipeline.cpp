#include "gpu_pipeline.h"
#include "gpu_shaders_generated.h"
#include "tone_v2.h"
#include <algorithm>
#include <cmath>

namespace gremote::gpu {
namespace {
void Int(GLuint p,const char* name,int value){glUniform1i(glGetUniformLocation(p,name),value);}
void Int2(GLuint p,const char* name,int x,int y){glUniform2i(glGetUniformLocation(p,name),x,y);}
void Float2(GLuint p,const char* name,float x,float y){glUniform2f(glGetUniformLocation(p,name),x,y);}
void Vec3(GLuint p,const char* name,const float* values){glUniform3fv(glGetUniformLocation(p,name),1,values);}
bool ActiveTone(const PhotoEdits& e){for(int i=1;i<=10;++i)if(e.values[i]!=0)return true;return false;}
bool ActiveCurves(const PhotoEdits& e){for(int c=0;c<4;++c)for(int i=0;i<256;++i)if(std::abs(e.values[38+c*256+i]-i/255.f)>1e-7f)return true;return false;}
}
ColorPipeline::ColorPipeline(const Capabilities& caps):caps_(caps){
  try{
    programs_[0]=CompileProgram(shaders::geometry);
    programs_[1]=CompileProgram(shaders::tone);
    programs_[2]=CompileProgram(shaders::lut);
    programs_[3]=CompileProgram(shaders::curves);
    effects_=std::make_unique<EffectsPipeline>(caps);
    glGenVertexArrays(1,&vao_);
  }catch(...){for(auto p:programs_)if(p)glDeleteProgram(p);throw;}
}
ColorPipeline::~ColorPipeline(){
  for(auto p:programs_)if(p)glDeleteProgram(p);
  if(vao_)glDeleteVertexArrays(1,&vao_);
  if(lut_texture_)glDeleteTextures(1,&lut_texture_);
  if(curve_texture_)glDeleteTextures(1,&curve_texture_);
}
void ColorPipeline::Abandon(){
  for(auto& target:targets_)if(target)target->fbo=target->texture=0;
  if(effects_)effects_->Abandon();
  programs_.fill(0);vao_=lut_texture_=curve_texture_=0;previous_.reset();
}
void ColorPipeline::TargetFor(int stage,int width,int height){
  if(width<=0||height<=0||width>caps_.max_texture||height>caps_.max_texture||
      int64_t(width)*height>8*1024*1024)throw GpuError("gpuTargetTooLarge");
  if(!targets_[stage]||targets_[stage]->width!=width||targets_[stage]->height!=height)
    targets_[stage]=std::make_unique<Target>(width,height,caps_.full_float?GL_RGBA32F:GL_RGBA16F);
  targets_[stage]->Bind();outputs_[stage]=targets_[stage]->texture;
}
void ColorPipeline::Source(GLuint program,GLuint texture){
  glUseProgram(program);glBindVertexArray(vao_);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,texture);Int(program,"source",0);
}
void ColorPipeline::Draw(int stage){glDrawArrays(GL_TRIANGLES,0,3);CheckGl("gpuColorStage");++counts_[stage];}
void ColorPipeline::Geometry(GLuint source,const PipelineInputs& inputs){
  const auto& r=inputs.region;const auto& p=inputs.edits.values;
  if(r.source_width<=0||r.source_height<=0||r.source_x<0||r.source_y<0||r.exif<1||r.exif>8||
      r.source_region_width<=0||r.source_region_height<=0||
      int64_t(r.source_x)+r.source_region_width>r.source_width||int64_t(r.source_y)+r.source_region_height>r.source_height||
      r.source_region_width>caps_.max_texture||r.source_region_height>caps_.max_texture||r.output_width<=0||r.output_height<=0||
      r.output_x<0||r.output_y<0||int64_t(r.output_x)+r.target_width>r.output_width||int64_t(r.output_y)+r.target_height>r.output_height)
    throw GpuError("gpuInvalidGeometryRegion");
  const bool exif_swap=r.exif>=5,turn_swap=int(p[34])%2;
  const int normalized_width=exif_swap?r.source_height:r.source_width,normalized_height=exif_swap?r.source_width:r.source_height;
  const int width=turn_swap?normalized_height:normalized_width,height=turn_swap?normalized_width:normalized_height;
  const int crop_width=std::clamp(int(std::lround(width*p[32])),1,width),crop_height=std::clamp(int(std::lround(height*p[33])),1,height);
  const int left=std::clamp(int(std::lround(width*p[30])),0,width-crop_width),top=std::clamp(int(std::lround(height*p[31])),0,height-crop_height);
  if(r.output_width>crop_width||r.output_height>crop_height)throw GpuError("gpuInvalidOutputSize");
  TargetFor(0,r.target_width,r.target_height);const GLuint program=programs_[0];
  glUseProgram(program);glBindVertexArray(vao_);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D_ARRAY,source);Int(program,"source",0);
  Int2(program,"sourceSize",r.source_width,r.source_height);Int2(program,"sourceOrigin",r.source_x,r.source_y);
  Int2(program,"sourceRegionSize",r.source_region_width,r.source_region_height);Int2(program,"rotatedSize",width,height);
  glUniform4i(glGetUniformLocation(program,"crop"),left,top,crop_width,crop_height);
  Float2(program,"fullOutputSize",r.output_width,r.output_height);Float2(program,"outputOrigin",r.output_x,r.output_y);
  constexpr float pi=3.14159265358979323846f;const float angle=p[37]*pi/180,c=std::cos(angle),s=std::sin(angle);
  const float zoom=std::max(std::abs(c)+std::abs(s)*height/width,std::abs(c)+std::abs(s)*width/height);
  glUniform3f(glGetUniformLocation(program,"rotation"),c,s,zoom);
  Int(program,"exif",r.exif);Int(program,"turns",int(p[34]));Int(program,"flipX",int(p[35]));Int(program,"flipY",int(p[36]));
  Int(program,"straighten",p[37]!=0);Int(program,"processVersion",int(p[0]));Draw(0);
}
void ColorPipeline::Tone(GLuint source,const PipelineInputs& inputs){
  const auto tone=ToneV2::Build(inputs.edits);const auto& r=inputs.region;
  TargetFor(1,r.target_width,r.target_height);const auto program=programs_[1];Source(program,source);
  Int(program,"processVersion",int(inputs.edits.values[0]));glUniform1fv(glGetUniformLocation(program,"p[0]"),10,tone.parameters().data());
  Vec3(program,"gains",tone.gains().data());glUniform1f(glGetUniformLocation(program,"exposure"),tone.exposure());
  glUniform1f(glGetUniformLocation(program,"contrast"),tone.contrast());glUniform1f(glGetUniformLocation(program,"peak"),tone.peak());Draw(1);
}
void ColorPipeline::Lut(GLuint source,const PipelineInputs& inputs,const CubeLut& lut){
  GLint maximum=0;glGetIntegerv(GL_MAX_3D_TEXTURE_SIZE,&maximum);
  if(lut.size>maximum)throw GpuError("gpuLutSizeUnsupported");
  if(!lut_texture_||uploaded_lut_!=inputs.lut_serial){
    if(lut_texture_)glDeleteTextures(1,&lut_texture_);lut_texture_=0;glGenTextures(1,&lut_texture_);
    glActiveTexture(GL_TEXTURE1);glBindTexture(GL_TEXTURE_3D,lut_texture_);
    glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_3D,GL_TEXTURE_WRAP_R,GL_CLAMP_TO_EDGE);
    std::vector<float> rgba(size_t(lut.size)*lut.size*lut.size*4,1);
    for(size_t i=0;i<lut.table.size()/3;++i)for(int c=0;c<3;++c)rgba[i*4+c]=lut.table[i*3+c];
    glTexImage3D(GL_TEXTURE_3D,0,GL_RGBA32F,lut.size,lut.size,lut.size,0,GL_RGBA,GL_FLOAT,rgba.data());CheckGl("gpuLutUpload");uploaded_lut_=inputs.lut_serial;
  }
  const auto& r=inputs.region;TargetFor(2,r.target_width,r.target_height);const auto program=programs_[2];Source(program,source);
  glActiveTexture(GL_TEXTURE1);glBindTexture(GL_TEXTURE_3D,lut_texture_);Int(program,"cube",1);Int(program,"cubeSize",lut.size);
  Vec3(program,"domainMin",lut.domain_min.data());Vec3(program,"domainMax",lut.domain_max.data());
  Int(program,"processVersion",int(inputs.edits.values[0]));glUniform1f(glGetUniformLocation(program,"strength"),inputs.strength);Draw(2);
}
void ColorPipeline::Curves(GLuint source,const PipelineInputs& inputs){
  glActiveTexture(GL_TEXTURE1);
  if(!curve_texture_){
    glGenTextures(1,&curve_texture_);glBindTexture(GL_TEXTURE_2D,curve_texture_);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glTexStorage2D(GL_TEXTURE_2D,1,GL_R32F,256,4);
  } else glBindTexture(GL_TEXTURE_2D,curve_texture_);
  glTexSubImage2D(GL_TEXTURE_2D,0,0,0,256,4,GL_RED,GL_FLOAT,inputs.edits.values.data()+38);CheckGl("gpuCurvesUpload");
  const auto& r=inputs.region;TargetFor(3,r.target_width,r.target_height);const auto program=programs_[3];Source(program,source);
  glActiveTexture(GL_TEXTURE1);glBindTexture(GL_TEXTURE_2D,curve_texture_);Int(program,"curves",1);Int(program,"processVersion",int(inputs.edits.values[0]));Draw(3);
}
GLuint ColorPipeline::Render(GLuint source,const PipelineInputs& inputs,const CubeLut* lut){
  const auto dirty=previous_?FirstDirty(*previous_,inputs):Stage::Geometry;
  const int first=int(dirty);
  try{
    if(first<=0)Geometry(source,inputs);
    if(first<=1){if(ActiveTone(inputs.edits))Tone(outputs_[0],inputs);else{targets_[1].reset();outputs_[1]=outputs_[0];}}
    if(first<=2){if(lut&&inputs.strength>0)Lut(outputs_[1],inputs,*lut);else{targets_[2].reset();outputs_[2]=outputs_[1];}}
    if(first<=3){if(ActiveCurves(inputs.edits))Curves(outputs_[2],inputs);else{targets_[3].reset();outputs_[3]=outputs_[2];}}
    const auto final=effects_->Render(outputs_[3],inputs,first<=3);
    const auto& effect_counts=effects_->counts();counts_[4]=effect_counts[0]+effect_counts[1];counts_[5]=effect_counts[2];
    previous_=inputs;return final;
  }catch(...){previous_.reset();throw;}
}
}  // namespace gremote::gpu
