#pragma once
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <android/native_window.h>
#include <stdexcept>
#include <string>
#include <thread>

namespace gremote::gpu {
class GpuError : public std::runtime_error {
 public:
  explicit GpuError(const std::string& message) : std::runtime_error(message) {}
};
struct Capabilities {
  int max_texture=0, max_target=0;
  bool half_float=false,full_float=false;
  std::string vendor, renderer, version;
  std::string Json() const;
};
GLuint CompileProgram(const char* fragment);
void CheckGl(const char* stage);

class Target {
 public:
  Target(int width,int height,GLint format=GL_RGBA16F);
  ~Target();
  Target(const Target&)=delete;
  Target& operator=(const Target&)=delete;
  void Bind() const;
  GLuint texture=0, fbo=0;
  int width=0,height=0;
};

class GpuContext {
 public:
  GpuContext();
  ~GpuContext();
  GpuContext(const GpuContext&)=delete;
  GpuContext& operator=(const GpuContext&)=delete;
  void MakeCurrent();
  // Takes ownership of the ANativeWindow reference, including failure paths.
  void Attach(ANativeWindow* window,int width,int height);
  void Detach();
  bool HasWindow() const { return window_surface_!=EGL_NO_SURFACE; }
  void MakeWindowCurrent();
  void Swap();
  const Capabilities& capabilities() const { return caps_; }
  void CheckOwner() const;
 private:
  void Release() noexcept;
  void ValidateFloatTarget();
  std::thread::id owner_;
  EGLDisplay display_=EGL_NO_DISPLAY;
  EGLContext context_=EGL_NO_CONTEXT;
  EGLConfig config_=nullptr;
  EGLSurface pbuffer_=EGL_NO_SURFACE, window_surface_=EGL_NO_SURFACE;
  ANativeWindow* window_=nullptr;
  int window_width_=0,window_height_=0;
  Capabilities caps_;
  bool initialized_=false;
};
}  // namespace gremote::gpu
