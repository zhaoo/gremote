#include "gpu_effects.h"
#include "gpu_shaders_generated.h"
#include <string>
namespace gremote::gpu {
namespace {
void I(GLuint p,const char* name,int v){glUniform1i(glGetUniformLocation(p,name),v);}
void I2(GLuint p,const char* name,int x,int y){glUniform2i(glGetUniformLocation(p,name),x,y);}
void F(GLuint p,const char* name,float v){glUniform1f(glGetUniformLocation(p,name),v);}
bool Textured(const PhotoEdits& e){for(int i:{11,14,23,27,28})if(e.values[i]!=0)return true;return false;}
}
ScalarAtlas::ScalarAtlas(int w,int h,const Capabilities& caps):layout(SpatialPlan::Build(w,h,caps.max_texture,256,1,320ull*1024*1024)){
  GLint maximum=0;glGetIntegerv(GL_MAX_ARRAY_TEXTURE_LAYERS,&maximum);
  if(layout.columns*layout.rows>maximum)throw GpuError("gpuSpatialLayersUnsupported");
  try{
    glGenTextures(1,&texture);glBindTexture(GL_TEXTURE_2D_ARRAY,texture);
    glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D_ARRAY,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glTexStorage3D(GL_TEXTURE_2D_ARRAY,1,GL_R32F,layout.page_width,layout.page_height,layout.columns*layout.rows);
    glGenFramebuffers(1,&fbo);BindPage(0,0);CheckGl("gpuSpatialAllocation");
  }catch(...){if(fbo)glDeleteFramebuffers(1,&fbo);if(texture)glDeleteTextures(1,&texture);throw;}
}
ScalarAtlas::~ScalarAtlas(){if(fbo)glDeleteFramebuffers(1,&fbo);if(texture)glDeleteTextures(1,&texture);}
void ScalarAtlas::BindPage(int col,int row)const{
  glBindFramebuffer(GL_FRAMEBUFFER,fbo);glFramebufferTextureLayer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,texture,0,row*layout.columns+col);
  if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE)throw GpuError("gpuSpatialFloatUnsupported");
  glViewport(0,0,std::min(layout.page_width,layout.width-col*layout.page_width),std::min(layout.page_height,layout.height-row*layout.page_height));
}
void ScalarAtlas::Sample(GLuint program,int unit,const char* name)const{
  glActiveTexture(GL_TEXTURE0+unit);glBindTexture(GL_TEXTURE_2D_ARRAY,texture);I(program,name,unit);
  I2(program,(std::string(name)+"Size").c_str(),layout.width,layout.height);
  I2(program,(std::string(name)+"Page").c_str(),layout.page_width,layout.page_height);
}
EffectsPipeline::EffectsPipeline(const Capabilities& caps):caps_(caps){
  try{spatial_=CompileProgram(shaders::spatial);texture_=CompileProgram(shaders::texture);glGenVertexArrays(1,&vao_);}
  catch(...){if(spatial_)glDeleteProgram(spatial_);if(texture_)glDeleteProgram(texture_);throw;}
}
EffectsPipeline::~EffectsPipeline(){if(spatial_)glDeleteProgram(spatial_);if(texture_)glDeleteProgram(texture_);if(vao_)glDeleteVertexArrays(1,&vao_);}
void EffectsPipeline::Abandon(){
  for(auto* a:{halo_.get(),bloom_.get(),scratch_.get()})if(a)a->Abandon();
  for(auto* t:{optics_.get(),textured_.get()})if(t)t->texture=t->fbo=0;
  spatial_=texture_=vao_=0;previous_.reset();
}
void EffectsPipeline::TargetFor(std::unique_ptr<Target>& target,int w,int h){
  if(!target||target->width!=w||target->height!=h)target=std::make_unique<Target>(w,h,caps_.full_float?GL_RGBA32F:GL_RGBA16F);
  target->Bind();
}
void EffectsPipeline::DrawAtlas(ScalarAtlas& target,GLuint program){
  for(int y=0;y<target.layout.rows;++y)for(int x=0;x<target.layout.columns;++x){
    target.BindPage(x,y);I2(program,"pageOrigin",x*target.layout.page_width,y*target.layout.page_height);
    glDrawArrays(GL_TRIANGLES,0,3);CheckGl("gpuSpatialPass");
  }
}
void EffectsPipeline::BindColor(GLuint source){glActiveTexture(GL_TEXTURE2);glBindTexture(GL_TEXTURE_2D,source);I(spatial_,"color",2);}
void EffectsPipeline::Fill(ScalarAtlas& mask,GLuint source,const PipelineInputs& inputs,bool halo){
  const auto& p=inputs.edits.values;
  glUseProgram(spatial_);glBindVertexArray(vao_);BindColor(source);I(spatial_,"operation",0);
  I(spatial_,"processVersion",int(p[0]));F(spatial_,"threshold",p[halo?19:22]);
  F(spatial_,"haloGain",!halo&&halo_?p[17]:0);I2(spatial_,"colorOrigin",inputs.region.output_x,inputs.region.output_y);
  // Always bind complete textures even when the branch is inactive: ES drivers
  // validate all active sampler types, regardless of uniform control flow.
  (halo_&& !halo?*halo_:*scratch_).Sample(spatial_,0,"a");scratch_->Sample(spatial_,1,"b");
  const auto& r=inputs.region;
  if(r.target_width==r.output_width&&r.target_height==r.output_height)DrawAtlas(mask,spatial_);
  else{
    const auto& a=mask.layout;const int col=r.output_x/a.page_width,row=r.output_y/a.page_height;
    if((r.output_x+r.target_width-1)/a.page_width!=col||(r.output_y+r.target_height-1)/a.page_height!=row)throw GpuError("gpuMaskTileCrossesPage");
    mask.BindPage(col,row);glViewport(r.output_x%a.page_width,r.output_y%a.page_height,r.target_width,r.target_height);
    I2(spatial_,"pageOrigin",col*a.page_width,row*a.page_height);glDrawArrays(GL_TRIANGLES,0,3);CheckGl("gpuMaskTile");
  }
}
void EffectsPipeline::Blur(ScalarAtlas& mask,int radius,const std::function<void()>& check){
  const int width=mask.layout.width,height=mask.layout.height;
  glUseProgram(spatial_);glBindVertexArray(vao_);
  for(int pass=0;pass<3;++pass)for(int axis=0;axis<2;++axis){
    I2(spatial_,"axis",axis==0,axis==1);
    ScalarAtlas* read=&mask;ScalarAtlas* write=scratch_.get();
    I(spatial_,"operation",1);
    for(int offset=1;offset<128;offset*=2){check();
      read->Sample(spatial_,0,"a");read->Sample(spatial_,1,"b");I(spatial_,"offset",offset);DrawAtlas(*write,spatial_);std::swap(read,write);
    }
    const int groups=((axis==0?width:height)+127)/128,lines=axis==0?height:width;
    auto groupA=std::make_unique<ScalarAtlas>(groups,lines,caps_);
    auto groupB=std::make_unique<ScalarAtlas>(groups,lines,caps_);
    read->Sample(spatial_,0,"a");read->Sample(spatial_,1,"b");I(spatial_,"operation",2);DrawAtlas(*groupA,spatial_);
    I(spatial_,"operation",3);
    for(int offset=1;offset<groups;offset*=2){check();groupA->Sample(spatial_,0,"a");groupA->Sample(spatial_,1,"b");I(spatial_,"offset",offset);DrawAtlas(*groupB,spatial_);groupA.swap(groupB);}
    read->Sample(spatial_,0,"a");groupA->Sample(spatial_,1,"b");I(spatial_,"operation",4);I(spatial_,"radius",radius);
    DrawAtlas(*write,spatial_);
    // Seven local scan passes + one reconstruction always finish in `mask`.
    if(write!=&mask)throw GpuError("gpuSpatialScanParity");
  }
}
void EffectsPipeline::PrepareGlobal(const PipelineInputs& inputs,const std::function<GLuint(const GeometryRegion&)>& color,const std::function<void()>& check){
  const auto& p=inputs.edits.values;const auto& r=inputs.region;
  if(p[17]==0&&p[20]==0){global_prepared_=true;return;}
  GLint layers=0;glGetIntegerv(GL_MAX_ARRAY_TEXTURE_LAYERS,&layers);
  auto plan=SpatialPlan::Build(r.output_width,r.output_height,caps_.max_texture,layers,p[17]!=0&&p[20]!=0?3:2,320ull*1024*1024);
  scratch_=std::make_unique<ScalarAtlas>(r.output_width,r.output_height,caps_);
  auto fill=[&](ScalarAtlas& mask,bool halo){
    for(int py=0;py<plan.rows;++py)for(int px=0;px<plan.columns;++px){
      const int left=px*plan.page_width,top=py*plan.page_height;
      for(int y=top;y<std::min(top+plan.page_height,r.output_height);y+=512)for(int x=left;x<std::min(left+plan.page_width,r.output_width);x+=512){
        check();auto tile=inputs;tile.region.output_x=x;tile.region.output_y=y;
        tile.region.target_width=std::min({512,left+plan.page_width-x,r.output_width-x});tile.region.target_height=std::min({512,top+plan.page_height-y,r.output_height-y});
        const GLuint texture=color(tile.region);Fill(mask,texture,tile,halo);
      }
    }
  };
  if(p[17]!=0){halo_=std::make_unique<ScalarAtlas>(r.output_width,r.output_height,caps_);fill(*halo_,true);check();Blur(*halo_,GlowRadius(r.output_width,r.output_height,p[18]),check);++counts_[0];}
  if(p[20]!=0){bloom_=std::make_unique<ScalarAtlas>(r.output_width,r.output_height,caps_);fill(*bloom_,false);check();Blur(*bloom_,GlowRadius(r.output_width,r.output_height,p[21]),check);++counts_[1];}
  global_prepared_=true;
}
GLuint EffectsPipeline::Render(GLuint source,const PipelineInputs& inputs,bool upstream){
  const auto& p=inputs.edits.values;const auto& r=inputs.region;
  const auto dirty=previous_?FirstDirty(*previous_,inputs):Stage::Geometry;
  const bool changed=upstream||!previous_;
  try{
    if(global_prepared_||changed||int(dirty)<=int(Stage::Optics)){
      if(p[17]!=0||p[20]!=0){
        if(!global_prepared_&&(r.output_x||r.output_y||r.target_width!=r.output_width||r.target_height!=r.output_height))throw GpuError("gpuSpatialTileRequiresGlobalMasks");
        if(!global_prepared_){
        GLint layers=0;glGetIntegerv(GL_MAX_ARRAY_TEXTURE_LAYERS,&layers);
        SpatialPlan::Build(r.output_width,r.output_height,caps_.max_texture,layers,(p[17]!=0&&p[20]!=0)?3:2,320ull*1024*1024);
        const bool resized=!scratch_||scratch_->layout.width!=r.output_width||scratch_->layout.height!=r.output_height;
        if(resized){halo_.reset();bloom_.reset();scratch_=std::make_unique<ScalarAtlas>(r.output_width,r.output_height,caps_);}
        auto maskDirty=previous_?DirtyMasks(*previous_,inputs,changed||resized):MaskDirty{true,true};
        if(p[17]!=0){if(!halo_){halo_=std::make_unique<ScalarAtlas>(r.output_width,r.output_height,caps_);maskDirty.halo=true;}
          if(maskDirty.halo){Fill(*halo_,source,inputs,true);Blur(*halo_,GlowRadius(r.output_width,r.output_height,p[18]));++counts_[0];}}
        else halo_.reset();
        if(p[20]!=0){if(!bloom_){bloom_=std::make_unique<ScalarAtlas>(r.output_width,r.output_height,caps_);maskDirty.bloom=true;}
          if(maskDirty.bloom){Fill(*bloom_,source,inputs,false);Blur(*bloom_,GlowRadius(r.output_width,r.output_height,p[21]));++counts_[1];}}
        else bloom_.reset();
        }
        TargetFor(optics_,r.target_width,r.target_height);glUseProgram(spatial_);glBindVertexArray(vao_);BindColor(source);
        (halo_?*halo_:*scratch_).Sample(spatial_,0,"a");(bloom_?*bloom_:*scratch_).Sample(spatial_,1,"b");
        I(spatial_,"operation",5);I(spatial_,"processVersion",int(p[0]));I2(spatial_,"pageOrigin",r.output_x,r.output_y);I2(spatial_,"colorOrigin",r.output_x,r.output_y);
        F(spatial_,"haloGain",p[17]);F(spatial_,"bloomGain",p[20]);glDrawArrays(GL_TRIANGLES,0,3);CheckGl("gpuOpticsCompose");optical_output_=optics_->texture;
      }else{halo_.reset();bloom_.reset();scratch_.reset();optics_.reset();optical_output_=source;}
    }
    if(global_prepared_||changed||int(dirty)<=int(Stage::Texture)){
      if(Textured(inputs.edits)){
        TargetFor(textured_,r.target_width,r.target_height);glUseProgram(texture_);glBindVertexArray(vao_);
        glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,optical_output_);I(texture_,"source",0);I(texture_,"processVersion",int(p[0]));
        glUniform2f(glGetUniformLocation(texture_,"fullSize"),r.output_width,r.output_height);glUniform2f(glGetUniformLocation(texture_,"origin"),r.output_x,r.output_y);
        glUniform1fv(glGetUniformLocation(texture_,"p[0]"),19,p.data()+11);glDrawArrays(GL_TRIANGLES,0,3);CheckGl("gpuTexturePass");++counts_[2];final_output_=textured_->texture;
      }else{textured_.reset();final_output_=optical_output_;}
    }
    previous_=inputs;return final_output_;
  }catch(...){previous_.reset();throw;}
}
}
