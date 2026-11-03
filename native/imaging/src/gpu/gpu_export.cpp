#include "gpu_session.h"
#include "gpu_shaders_generated.h"
#include "tile_plan.h"
#include "jpeg_io.h"
#include "gremote_imaging.h"
#include <cstring>
#include <cstdio>
#include <cmath>
namespace gremote::gpu {
namespace {
struct Resources {
  GLuint canvas=0,overlay=0,vao=0,texture=0;
  ~Resources(){if(canvas)glDeleteProgram(canvas);if(overlay)glDeleteProgram(overlay);if(vao)glDeleteVertexArrays(1,&vao);if(texture)glDeleteTextures(1,&texture);}
};
void I(GLuint p,const char* key,int v){glUniform1i(glGetUniformLocation(p,key),v);}
void I2(GLuint p,const char* key,int x,int y){glUniform2i(glGetUniformLocation(p,key),x,y);}
}
void GpuSession::Export(const PhotoEdits& edits,const uint8_t* cube,size_t length,float strength,const ExportSpec& spec,const volatile int32_t* cancel,std::function<bool()> cancelled){
  CheckOpen();context_.MakeCurrent();PhotoEdits checked;
  if(ParsePhotoEdits(edits.values.data(),kPhotoEditCount,&checked)!=GREMOTE_OK||
      (process_version_&&int(edits.values[0])!=process_version_)||!std::isfinite(strength)||strength<0||strength>1)throw GpuError("gpuInvalidExportDescriptor");
  auto check=[&](){if((cancelled&&cancelled())||(cancel&&*cancel))throw GpuError("cancelled");};check();
  Image metadata;metadata.width=spec.photo_width;metadata.height=spec.photo_height;metadata.channels=3;
  FrameSpec frame{spec.canvas_width,spec.canvas_height,{spec.background[0],spec.background[1],spec.background[2]},&metadata,spec.photo_x,spec.photo_y,spec.overlays};
  if(ValidateFrame(frame)!=GREMOTE_OK||spec.path.empty()||spec.quality<1||spec.quality>100)throw GpuError("gpuInvalidExportCanvas");
  const int edge=std::min(512,context_.capabilities().max_texture),band=64;
  const auto tiles=TilePlan::Build(spec.canvas_width,spec.canvas_height,edge,band);
  CubeLut lut;if(length&&(!cube||ParseCube(cube,length,&lut)!=GREMOTE_OK))throw GpuError("gpuInvalidLut");
  // Keep only the last RGBA8 display frame and immutable source while exporting.
  // This bounds peak GPU memory; subsequent edits rebuild the stage cache.
  pipeline_.reset();
  ColorPipeline pipeline(context_.capabilities());PipelineInputs inputs;
  inputs.source_serial=1;inputs.context_serial=1;inputs.edits=edits;inputs.strength=strength;inputs.lut_serial=length?1:0;
  inputs.region={source_.width,source_.height,0,0,page_width_,page_height_,orientation_,spec.photo_width,spec.photo_height,0,0,std::min(edge,spec.photo_width),std::min(edge,spec.photo_height)};
  pipeline.PrepareGlobalMasks(source_texture_,inputs,length?&lut:nullptr,check);
  Resources gpu;gpu.canvas=CompileProgram(shaders::canvas);gpu.overlay=CompileProgram(shaders::overlay);glGenVertexArrays(1,&gpu.vao);glGenTextures(1,&gpu.texture);
  glBindTexture(GL_TEXTURE_2D,gpu.texture);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,1,1,0,GL_RGBA,GL_UNSIGNED_BYTE,nullptr);
  JpegRowWriter writer;
  if(writer.Open(spec.path,spec.canvas_width,spec.canvas_height,spec.quality)!=GREMOTE_OK)throw GpuError("gpuExportStorage");
  const Rect photoRect{spec.photo_x,spec.photo_y,spec.photo_width,spec.photo_height};
  std::vector<uint8_t> rows(size_t(spec.canvas_width)*band*3),rgba(size_t(edge)*band*4);
  int currentBand=-1,bandHeight=0;
  auto flush=[&](){for(int y=0;y<bandHeight;++y){check();if(writer.WriteRow(rows.data()+size_t(y)*spec.canvas_width*3)!=GREMOTE_OK)throw GpuError("gpuExportEncode");}};
  for(const auto& tile:tiles){
    check();if(tile.y!=currentBand){if(currentBand>=0)flush();currentBand=tile.y;bandHeight=tile.height;}
    auto intersection=Intersect(tile,photoRect);GLuint photo=gpu.texture;
    if(intersection.width&&intersection.height){auto region=inputs;region.region.output_x=intersection.x-spec.photo_x;region.region.output_y=intersection.y-spec.photo_y;
      region.region.target_width=intersection.width;region.region.target_height=intersection.height;
      photo=pipeline.Render(source_texture_,region,length?&lut:nullptr);}
    Target target(tile.width,tile.height,GL_RGBA8);target.Bind();glUseProgram(gpu.canvas);glBindVertexArray(gpu.vao);
    glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,photo);I(gpu.canvas,"photo",0);I2(gpu.canvas,"tileOrigin",tile.x,tile.y);
    I2(gpu.canvas,"photoOrigin",intersection.x-spec.photo_x,intersection.y-spec.photo_y);
    glUniform4i(glGetUniformLocation(gpu.canvas,"photoRect"),photoRect.x,photoRect.y,photoRect.width,photoRect.height);
    glUniform3f(glGetUniformLocation(gpu.canvas,"background"),spec.background[0]/255.f,spec.background[1]/255.f,spec.background[2]/255.f);
    glDrawArrays(GL_TRIANGLES,0,3);
    for(const auto& overlay:spec.overlays){
      auto area=Intersect(tile,{overlay.x,overlay.y,overlay.width,overlay.height});if(!area.width||!area.height)continue;
      glUseProgram(gpu.overlay);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,gpu.texture);
      glPixelStorei(GL_UNPACK_ROW_LENGTH,overlay.width);
      const auto* pixels=overlay.rgba+(size_t(area.y-overlay.y)*overlay.width+area.x-overlay.x)*4;
      glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,area.width,area.height,0,GL_RGBA,GL_UNSIGNED_BYTE,pixels);glPixelStorei(GL_UNPACK_ROW_LENGTH,0);
      I(gpu.overlay,"source",0);I2(gpu.overlay,"origin",area.x-tile.x,area.y-tile.y);
      glViewport(area.x-tile.x,area.y-tile.y,area.width,area.height);
      glEnable(GL_BLEND);glBlendFuncSeparate(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA,GL_ZERO,GL_ONE);
      glDrawArrays(GL_TRIANGLES,0,3);glDisable(GL_BLEND);
    }
    target.Bind();CheckGl("gpuExportCompose");glReadPixels(0,0,tile.width,tile.height,GL_RGBA,GL_UNSIGNED_BYTE,rgba.data());CheckGl("gpuExportReadback");
    for(int y=0;y<tile.height;++y)for(int x=0;x<tile.width;++x)std::memcpy(rows.data()+(size_t(y)*spec.canvas_width+tile.x+x)*3,rgba.data()+(size_t(y)*tile.width+x)*4,3);
  }
  flush();check();if(writer.Finish()!=GREMOTE_OK)throw GpuError("gpuExportEncode");
  if((cancelled&&cancelled())||(cancel&&*cancel)){std::remove(spec.path.c_str());throw GpuError("cancelled");}
}
}
