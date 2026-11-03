#include "gpu_context.h"
#include <EGL/eglext.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <mutex>

namespace gremote::gpu {
namespace {
// Android EGL reference-counts eglInitialize/eglTerminate. Keep one balanced
// reference for our sessions, independently of Flutter's own display reference.
// AOSP opengl/libs/EGL/egl_display.cpp initialize()/terminate().
std::mutex display_mutex;
EGLDisplay shared_display=EGL_NO_DISPLAY;
unsigned display_users=0;
EGLDisplay AcquireDisplay(){
  std::lock_guard<std::mutex> lock(display_mutex);
  if(!display_users){
    const auto display=eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if(display==EGL_NO_DISPLAY||!eglInitialize(display,nullptr,nullptr))throw GpuError("gpuEglUnavailable");
    shared_display=display;
  }
  ++display_users;return shared_display;
}
void ReleaseDisplay(){
  std::lock_guard<std::mutex> lock(display_mutex);
  if(display_users&&!--display_users){eglTerminate(shared_display);shared_display=EGL_NO_DISPLAY;}
}
std::string Quote(const std::string& value) {
  std::string result="\"";
  for(char c:value) { if(c=='"'||c=='\\') result+='\\'; if(static_cast<unsigned char>(c)>=32) result+=c; }
  return result+'"';
}
std::string GlString(GLenum name) {
  const auto* value=glGetString(name);
  return value?reinterpret_cast<const char*>(value):"unavailable";
}
GLuint Shader(GLenum type,const char* source) {
  const GLuint shader=glCreateShader(type);
  if(!shader) throw GpuError("gpuShaderAllocation");
  glShaderSource(shader,1,&source,nullptr); glCompileShader(shader);
  GLint valid=0; glGetShaderiv(shader,GL_COMPILE_STATUS,&valid);
  if(!valid) {
    char log[2048]{}; glGetShaderInfoLog(shader,sizeof(log),nullptr,log);
    glDeleteShader(shader); throw GpuError(std::string("gpuShaderCompile: ")+log);
  }
  return shader;
}
}
std::string Capabilities::Json() const {
  return "{\"vendor\":"+Quote(vendor)+",\"renderer\":"+Quote(renderer)+
    ",\"version\":"+Quote(version)+",\"maxTextureSize\":"+std::to_string(max_texture)+
    ",\"maxRenderbufferSize\":"+std::to_string(max_target)+",\"halfFloatTarget\":"+(half_float?"true":"false")+"}";
}
GLuint CompileProgram(const char* fragment) {
  constexpr auto vertex=R"(#version 300 es
    precision highp float;
    const vec2 p[3]=vec2[3](vec2(-1.,-1.),vec2(3.,-1.),vec2(-1.,3.));
    void main(){gl_Position=vec4(p[gl_VertexID],0.,1.);}
  )";
  const GLuint vs=Shader(GL_VERTEX_SHADER,vertex);
  GLuint fs=0,program=0;
  try {
    fs=Shader(GL_FRAGMENT_SHADER,fragment); program=glCreateProgram();
    if(!program) throw GpuError("gpuProgramAllocation");
    glAttachShader(program,vs); glAttachShader(program,fs); glLinkProgram(program);
    GLint valid=0; glGetProgramiv(program,GL_LINK_STATUS,&valid);
    if(!valid) {
      char log[2048]{}; glGetProgramInfoLog(program,sizeof(log),nullptr,log);
      throw GpuError(std::string("gpuProgramLink: ")+log);
    }
  } catch(...) { if(program)glDeleteProgram(program); if(fs)glDeleteShader(fs); glDeleteShader(vs); throw; }
  glDeleteShader(vs); glDeleteShader(fs); return program;
}
void CheckGl(const char* stage) {
  const GLenum error=glGetError();
  if(error!=GL_NO_ERROR) throw GpuError(std::string(stage)+": "+std::to_string(error));
}
Target::Target(int w,int h,GLint format):width(w),height(h) {
  if(w<=0||h<=0) throw GpuError("gpuInvalidTarget");
  try {
    glGenTextures(1,&texture); glBindTexture(GL_TEXTURE_2D,texture);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D,0,format,w,h,0,GL_RGBA,format==GL_RGBA16F?GL_HALF_FLOAT:GL_UNSIGNED_BYTE,nullptr);
    glGenFramebuffers(1,&fbo); glBindFramebuffer(GL_FRAMEBUFFER,fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,texture,0);
    if(glCheckFramebufferStatus(GL_FRAMEBUFFER)!=GL_FRAMEBUFFER_COMPLETE) throw GpuError("gpuFramebufferUnsupported");
    CheckGl("gpuTarget");
  } catch(...) { if(fbo)glDeleteFramebuffers(1,&fbo); if(texture)glDeleteTextures(1,&texture); throw; }
}
Target::~Target(){if(fbo)glDeleteFramebuffers(1,&fbo);if(texture)glDeleteTextures(1,&texture);}
void Target::Bind() const { glBindFramebuffer(GL_FRAMEBUFFER,fbo);glViewport(0,0,width,height); }

GpuContext::GpuContext():owner_(std::this_thread::get_id()) {
  try {
    display_=AcquireDisplay();initialized_=true;
    if(!eglBindAPI(EGL_OPENGL_ES_API))throw GpuError("gpuEglApi");
    const EGLint attributes[]={EGL_SURFACE_TYPE,EGL_WINDOW_BIT|EGL_PBUFFER_BIT,
      EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT_KHR,EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_NONE};
    EGLint count=0;
    if(!eglChooseConfig(display_,attributes,&config_,1,&count)||count!=1)throw GpuError("gpuEs3Unavailable");
    const EGLint context_attributes[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};
    context_=eglCreateContext(display_,config_,EGL_NO_CONTEXT,context_attributes);
    if(context_==EGL_NO_CONTEXT)throw GpuError("gpuEs3Context");
    const EGLint surface_attributes[]={EGL_WIDTH,4,EGL_HEIGHT,4,EGL_NONE};
    pbuffer_=eglCreatePbufferSurface(display_,config_,surface_attributes);
    if(pbuffer_==EGL_NO_SURFACE)throw GpuError("gpuPbuffer");
    MakeCurrent();
    glDisable(GL_DITHER); glDisable(GL_BLEND); glDisable(GL_DEPTH_TEST);
    glGetIntegerv(GL_MAX_TEXTURE_SIZE,&caps_.max_texture);
    glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE,&caps_.max_target);
    caps_.vendor=GlString(GL_VENDOR);caps_.renderer=GlString(GL_RENDERER);caps_.version=GlString(GL_VERSION);
    ValidateFloatTarget();
  } catch(...) { Release(); throw; }
}
GpuContext::~GpuContext(){Release();}
void GpuContext::CheckOwner() const { if(owner_!=std::this_thread::get_id())throw GpuError("gpuWrongThread"); }
void GpuContext::MakeCurrent(){
  CheckOwner();
  if(!eglMakeCurrent(display_,pbuffer_,pbuffer_,context_))throw GpuError("gpuContextLost");
}
void GpuContext::Attach(ANativeWindow* window,int width,int height) {
  try{CheckOwner();}catch(...){if(window)ANativeWindow_release(window);throw;}
  if(!window)throw GpuError("gpuInvalidSurface");
  if(width<=0||height<=0) { ANativeWindow_release(window);throw GpuError("gpuInvalidSurfaceSize"); }
  // A new native reference may point to the same underlying Surface.
  if(window==window_&&width==window_width_&&height==window_height_){ANativeWindow_release(window);return;}
  Detach();
  if(ANativeWindow_setBuffersGeometry(window,width,height,WINDOW_FORMAT_RGBA_8888)!=0) {
    ANativeWindow_release(window);throw GpuError("gpuSurfaceSize");
  }
  window_=window;window_width_=width;window_height_=height;
  window_surface_=eglCreateWindowSurface(display_,config_,window_,nullptr);
  if(window_surface_==EGL_NO_SURFACE){ANativeWindow_release(window_);window_=nullptr;throw GpuError("gpuWindowSurface");}
}
void GpuContext::Detach(){
  CheckOwner();MakeCurrent();
  if(window_surface_!=EGL_NO_SURFACE)eglDestroySurface(display_,window_surface_);
  window_surface_=EGL_NO_SURFACE;
  if(window_)ANativeWindow_release(window_);
  window_=nullptr;
}
void GpuContext::MakeWindowCurrent(){
  CheckOwner();
  if(!HasWindow()||!eglMakeCurrent(display_,window_surface_,window_surface_,context_))throw GpuError("gpuSurfaceUnavailable");
}
void GpuContext::Swap(){if(!eglSwapBuffers(display_,window_surface_))throw GpuError("gpuSurfaceSwap");}
void GpuContext::Release() noexcept {
  if(!initialized_)return;
  eglMakeCurrent(display_,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
  if(window_surface_!=EGL_NO_SURFACE)eglDestroySurface(display_,window_surface_);
  if(window_)ANativeWindow_release(window_);
  if(pbuffer_!=EGL_NO_SURFACE)eglDestroySurface(display_,pbuffer_);
  if(context_!=EGL_NO_CONTEXT)eglDestroyContext(display_,context_);
  ReleaseDisplay();
  initialized_=false;window_=nullptr;window_surface_=pbuffer_=EGL_NO_SURFACE;context_=EGL_NO_CONTEXT;
}
void GpuContext::ValidateFloatTarget(){
  Target half(4,4), output(4,4,GL_RGBA8);
  GLuint vao=0,write=0,present=0;
  try {
    glGenVertexArrays(1,&vao);glBindVertexArray(vao);
    write=CompileProgram(R"(#version 300 es
      precision highp float;out vec4 color;
      void main(){color=vec4(2.,.5,.25,1.);}
    )");
    present=CompileProgram(R"(#version 300 es
      precision highp float;uniform sampler2D source;out vec4 color;
      void main(){vec4 c=texture(source,gl_FragCoord.xy/vec2(4.));color=vec4(c.r*.25,c.gba);}
    )");
    half.Bind();glUseProgram(write);glDrawArrays(GL_TRIANGLES,0,3);
    output.Bind();glUseProgram(present);glActiveTexture(GL_TEXTURE0);glBindTexture(GL_TEXTURE_2D,half.texture);
    glUniform1i(glGetUniformLocation(present,"source"),0);glDrawArrays(GL_TRIANGLES,0,3);
    std::array<unsigned char,64> pixels{};
    glReadPixels(0,0,4,4,GL_RGBA,GL_UNSIGNED_BYTE,pixels.data());CheckGl("gpuFloatReadback");
    for(int i=0;i<16;++i)for(int c=0;c<4;++c){
      constexpr int expected[]={128,128,64,255};
      if(std::abs(int(pixels[i*4+c])-expected[c])>1)throw GpuError("gpuFloatHeadroomUnavailable");
    }
    caps_.half_float=true;
  } catch(...) {if(vao)glDeleteVertexArrays(1,&vao);if(write)glDeleteProgram(write);if(present)glDeleteProgram(present);throw;}
  glDeleteVertexArrays(1,&vao);glDeleteProgram(write);glDeleteProgram(present);
}
}  // namespace gremote::gpu
