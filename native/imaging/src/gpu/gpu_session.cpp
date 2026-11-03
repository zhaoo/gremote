#include "gpu_session.h"
#include "gremote_imaging.h"
#include <cmath>

namespace gremote::gpu {
namespace {
bool Neutral(const PhotoEdits& edits) {
  const auto& p=edits.values;
  for(int i=1;i<=11;++i)if(p[i]!=0)return false;
  for(int i:{14,17,20,23,27,28,30,31,34,35,36,37})if(p[i]!=0)return false;
  if(p[32]!=1||p[33]!=1)return false;
  for(int c=0;c<4;++c)for(int i=0;i<256;++i)if(std::abs(p[38+c*256+i]-i/255.f)>1e-7f)return false;
  return true;
}
}
GpuSession::GpuSession(Image source,std::shared_ptr<GenerationGate> gate)
    :source_(std::move(source)),gate_(std::move(gate)) {
  const auto& caps=context_.capabilities();
  if(!gate_||source_.channels!=4||source_.width<=0||source_.height<=0||
      source_.width>caps.max_texture||source_.height>caps.max_texture||
      int64_t(source_.width)*source_.height>8*1024*1024||
      source_.pixels.size()!=size_t(source_.width)*source_.height*4)throw GpuError("gpuInvalidSource");
  glGenTextures(1,&source_texture_);glBindTexture(GL_TEXTURE_2D,source_texture_);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,source_.width,source_.height,0,GL_RGBA,GL_UNSIGNED_BYTE,source_.pixels.data());
  copy_=CompileProgram(R"(#version 300 es
    precision highp float;
    uniform sampler2D source;uniform vec2 outputSize;uniform int flip;
    out vec4 color;
    void main(){vec2 uv=gl_FragCoord.xy/outputSize;if(flip==1)uv.y=1.-uv.y;color=texture(source,uv);}
  )");
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
bool GpuSession::Render(uint64_t generation,const PhotoEdits& edits,const uint8_t* cube,
    size_t cube_length,float strength,int width,int height){
  CheckOpen();
  PhotoEdits checked;
  if(ParsePhotoEdits(edits.values.data(),kPhotoEditCount,&checked)!=GREMOTE_OK||
      width<=0||height<=0||!std::isfinite(strength)||strength<0||strength>1||
      (cube_length&&!cube))throw GpuError("gpuInvalidDescriptor");
  if(!gate_->Accepts(generation))return false;
  // This lifecycle milestone intentionally rejects effects until the shader
  // graph is connected. It never silently substitutes a neutral photograph.
  if(!Neutral(edits)||cube_length||width!=source_.width||height!=source_.height)
    throw GpuError("gpuPipelinePending");
  context_.MakeCurrent();
  if(!linear_||linear_->width!=width||linear_->height!=height){
    auto linear=std::make_unique<Target>(width,height);
    auto final=std::make_unique<Target>(width,height,GL_RGBA8);
    linear_=std::move(linear);final_=std::move(final);
  }
  linear_->Bind();Copy(source_texture_,width,height,false);
  final_->Bind();Copy(linear_->texture,width,height,false);CheckGl("gpuRender");
  rendered_=generation;
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
    if(linear_)linear_->fbo=linear_->texture=0;
    if(final_)final_->fbo=final_->texture=0;
    source_texture_=copy_=vao_=0;
  }
  linear_.reset();final_.reset();
  if(source_texture_)glDeleteTextures(1,&source_texture_);
  if(copy_)glDeleteProgram(copy_);if(vao_)glDeleteVertexArrays(1,&vao_);
  source_texture_=copy_=vao_=0;
  if(current){try{context_.Detach();}catch(...){}}
}
}  // namespace gremote::gpu
