#include "gpu_session.h"
#include "gremote_imaging.h"
#include "gpu_shaders_generated.h"
#include <cstring>
#include <cmath>
#include <algorithm>

namespace gremote::gpu {
namespace {
bool PendingEffects(const PhotoEdits& edits) {
  for(int i:{11,14,17,20,23,27,28})if(edits.values[i]!=0)return true;
  return false;
}
}
GpuSession::GpuSession(Image source,std::shared_ptr<GenerationGate> gate)
    :source_(std::move(source)),gate_(std::move(gate)) {
  const auto& caps=context_.capabilities();
  if(!gate_||source_.channels!=4||source_.width<=0||source_.height<=0||
      int64_t(source_.width)*source_.height>8*1024*1024||
      source_.pixels.size()!=size_t(source_.width)*source_.height*4)throw GpuError("gpuInvalidSource");
  page_width_=std::min({source_.width,caps.max_texture,2048});
  page_height_=std::min({source_.height,caps.max_texture,2048});
  const int columns=(source_.width+page_width_-1)/page_width_,rows=(source_.height+page_height_-1)/page_height_;
  GLint maximum_layers=0;glGetIntegerv(GL_MAX_ARRAY_TEXTURE_LAYERS,&maximum_layers);
  if(int64_t(columns)*rows>maximum_layers)throw GpuError("gpuSourceLayersUnsupported");
  glGenTextures(1,&source_texture_);glBindTexture(GL_TEXTURE_2D_ARRAY,source_texture_);
  glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
  glTexStorage3D(GL_TEXTURE_2D_ARRAY,1,GL_RGBA8,page_width_,page_height_,columns*rows);
  glPixelStorei(GL_UNPACK_ROW_LENGTH,source_.width);
  for(int y=0;y<rows;++y)for(int x=0;x<columns;++x){
    const int left=x*page_width_,top=y*page_height_;
    glTexSubImage3D(GL_TEXTURE_2D_ARRAY,0,0,0,y*columns+x,
      std::min(page_width_,source_.width-left),std::min(page_height_,source_.height-top),1,
      GL_RGBA,GL_UNSIGNED_BYTE,source_.Row(top)+left*4);
  }
  glPixelStorei(GL_UNPACK_ROW_LENGTH,0);CheckGl("gpuSourceUpload");
  source_.pixels.clear();source_.pixels.shrink_to_fit();
  pipeline_=std::make_unique<ColorPipeline>(caps);
  copy_=CompileProgram(shaders::present);
  glGenVertexArrays(1,&vao_);CheckGl("gpuSourceUpload");
}
GpuSession::~GpuSession(){try{Close();}catch(...){}}
void GpuSession::CheckOpen()const{CheckOwner();if(closed_)throw GpuError("gpuSessionClosed");}
void GpuSession::Copy(GLuint source,int width,int height,bool flip){
  glUseProgram(copy_);glBindVertexArray(vao_);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,source);
  glUniform1i(glGetUniformLocation(copy_,"source"),0);
  glUniform2f(glGetUniformLocation(copy_,"outputSize"),width,height);
  glUniform1i(glGetUniformLocation(copy_,"flip"),flip?1:0);glDrawArrays(GL_TRIANGLES,0,3);
}
std::shared_ptr<LutData> GpuSession::ParseLut(const uint8_t* bytes,size_t length){
  auto result=std::make_shared<LutData>();
  if(ParseCube(bytes,length,&result->lut)!=GREMOTE_OK)throw GpuError("gpuInvalidLut");
  result->bytes.assign(bytes,bytes+length);result->serial=next_lut_serial_++;return result;
}
void GpuSession::PrepareLut(const std::string& key,const uint8_t* bytes,size_t length){
  CheckOpen();if(!bytes||!length||length>16*1024*1024||key.empty()||key.size()>128)throw GpuError("gpuInvalidLutKey");
  const auto found=luts_.find(key);
  if(found!=luts_.end()){
    if(found->second->bytes.size()!=length||std::memcmp(found->second->bytes.data(),bytes,length)!=0)throw GpuError("gpuLutKeyMismatch");
    return;
  }
  auto lut=ParseLut(bytes,length);
  luts_.emplace(key,std::move(lut));lut_order_.push_back(key);
  while(lut_order_.size()>2){luts_.erase(lut_order_.front());lut_order_.pop_front();}
}
bool GpuSession::RenderPrepared(uint64_t generation,const PhotoEdits& edits,const std::string& key,float strength,int width,int height){
  CheckOpen();if(!gate_->Accepts(generation))return false;
  std::shared_ptr<LutData> lut;
  if(!key.empty()){
    const auto found=luts_.find(key);if(found==luts_.end())throw GpuError("gpuLutNotPrepared");lut=found->second;
  }
  return RenderColor(generation,edits,lut,strength,width,height);
}
bool GpuSession::Render(uint64_t generation,const PhotoEdits& edits,const uint8_t* cube,
    size_t cube_length,float strength,int width,int height){
  CheckOpen();if(!gate_->Accepts(generation))return false;
  std::shared_ptr<LutData> lut;
  if(cube_length){
    if(!cube)throw GpuError("gpuInvalidLut");
    if(!inline_lut_||inline_lut_->bytes.size()!=cube_length||std::memcmp(inline_lut_->bytes.data(),cube,cube_length)!=0)
      inline_lut_=ParseLut(cube,cube_length);
    lut=inline_lut_;
  }
  return RenderColor(generation,edits,lut,strength,width,height);
}
bool GpuSession::RenderColor(uint64_t generation,const PhotoEdits& edits,const std::shared_ptr<LutData>& lut,
    float strength,int width,int height){
  PhotoEdits checked;
  if(ParsePhotoEdits(edits.values.data(),kPhotoEditCount,&checked)!=GREMOTE_OK||width<=0||height<=0||
      !std::isfinite(strength)||strength<0||strength>1)throw GpuError("gpuInvalidDescriptor");
  if(PendingEffects(edits))throw GpuError("gpuPipelinePending");
  context_.MakeCurrent();
  PipelineInputs inputs;
  inputs.source_serial=1;inputs.context_serial=1;inputs.lut_serial=lut?lut->serial:0;inputs.strength=strength;inputs.edits=edits;
  inputs.region={source_.width,source_.height,0,0,page_width_,page_height_,1,width,height,0,0,width,height};
  const auto photo=pipeline_->Render(source_texture_,inputs,lut?&lut->lut:nullptr);
  if(!final_||final_->width!=width||final_->height!=height)final_=std::make_unique<Target>(width,height,GL_RGBA8);
  final_->Bind();Copy(photo,width,height,false);CheckGl("gpuRender");rendered_=generation;
  return gate_->Accepts(generation);
}
void GpuSession::Attach(ANativeWindow* window,int width,int height){
  CheckOpen();context_.Attach(window,width,height);window_width_=width;window_height_=height;
}
void GpuSession::Detach(){CheckOpen();context_.Detach();window_width_=window_height_=0;}
bool GpuSession::Present(uint64_t generation){
  CheckOpen();
  if(!final_||rendered_!=generation||!gate_->Accepts(generation)||!context_.HasWindow())return false;
  context_.MakeWindowCurrent();glBindFramebuffer(GL_FRAMEBUFFER,0);glViewport(0,0,window_width_,window_height_);
  Copy(final_->texture,window_width_,window_height_,true);CheckGl("gpuPresent");
  if(!gate_->Accepts(generation))return false;
  context_.Swap();return true;
}
Image GpuSession::ReadFinal(){
  CheckOpen();if(!final_)throw GpuError("gpuNoFrame");context_.MakeCurrent();final_->Bind();
  Image out(final_->width,final_->height,4);
  glReadPixels(0,0,out.width,out.height,GL_RGBA,GL_UNSIGNED_BYTE,out.pixels.data());CheckGl("gpuReadback");return out;
}
void GpuSession::Close(){
  CheckOwner();if(closed_)return;closed_=true;gate_->Close();
  // If the driver lost the context, deleting numeric names in another current
  // context would be unsafe. Abandon them; EGL destroys the lost context.
  bool current=false;try{context_.MakeCurrent();current=true;}catch(...){}
  if(!current){
    if(pipeline_)pipeline_->Abandon();
    if(final_)final_->fbo=final_->texture=0;
    source_texture_=copy_=vao_=0;
  }
  pipeline_.reset();final_.reset();luts_.clear();inline_lut_.reset();
  if(source_texture_)glDeleteTextures(1,&source_texture_);
  if(copy_)glDeleteProgram(copy_);if(vao_)glDeleteVertexArrays(1,&vao_);
  source_texture_=copy_=vao_=0;
  if(current){try{context_.Detach();}catch(...){}}
}
}  // namespace gremote::gpu
