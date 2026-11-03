// Synthetic, read-only GPU preflight. No photos, camera protocol or firmware.
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <array>
#include <cmath>
#include <cstdio>
#include <string>

namespace {
std::string Json(const char* text) {
  std::string result="\"";
  if (text) for (const char* p=text; *p; ++p) {
    if (*p=='"' || *p=='\\') result+='\\';
    if (static_cast<unsigned char>(*p)>=32) result+=*p;
  }
  return result+'"';
}
const char* GlString(GLenum field) {
  const auto* value=glGetString(field);
  return value ? reinterpret_cast<const char*>(value) : "unavailable";
}
struct Egl {
  EGLDisplay display=EGL_NO_DISPLAY;
  EGLContext context=EGL_NO_CONTEXT;
  EGLSurface surface=EGL_NO_SURFACE;
  bool initialized=false;
  bool Open() {
    display=eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display==EGL_NO_DISPLAY || !eglInitialize(display,nullptr,nullptr)) return false;
    initialized=true;
    if (!eglBindAPI(EGL_OPENGL_ES_API)) return false;
    const EGLint attributes[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,
      EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT_KHR,
      EGL_RED_SIZE,8,EGL_GREEN_SIZE,8,EGL_BLUE_SIZE,8,EGL_ALPHA_SIZE,8,EGL_NONE};
    EGLConfig config=nullptr; EGLint count=0;
    if (!eglChooseConfig(display,attributes,&config,1,&count) || count!=1) return false;
    const EGLint context_attributes[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};
    context=eglCreateContext(display,config,EGL_NO_CONTEXT,context_attributes);
    if (context==EGL_NO_CONTEXT) return false;
    const EGLint surface_attributes[]={EGL_WIDTH,4,EGL_HEIGHT,4,EGL_NONE};
    surface=eglCreatePbufferSurface(display,config,surface_attributes);
    return surface!=EGL_NO_SURFACE && eglMakeCurrent(display,surface,surface,context);
  }
  ~Egl() {
    if (initialized) {
      eglMakeCurrent(display,EGL_NO_SURFACE,EGL_NO_SURFACE,EGL_NO_CONTEXT);
      if (surface!=EGL_NO_SURFACE) eglDestroySurface(display,surface);
      if (context!=EGL_NO_CONTEXT) eglDestroyContext(display,context);
      eglTerminate(display);
    }
  }
};
GLuint Shader(GLenum type, const char* source, std::string* error) {
  const GLuint shader=glCreateShader(type);
  glShaderSource(shader,1,&source,nullptr); glCompileShader(shader);
  GLint valid=0; glGetShaderiv(shader,GL_COMPILE_STATUS,&valid);
  if (!valid) {
    char log[2048]{}; glGetShaderInfoLog(shader,sizeof(log),nullptr,log);
    *error=log; glDeleteShader(shader); return 0;
  }
  return shader;
}
GLuint Program(const char* fragment, std::string* error) {
  constexpr auto vertex=R"(#version 300 es
    precision highp float;
    const vec2 positions[3]=vec2[3](vec2(-1.,-1.),vec2(3.,-1.),vec2(-1.,3.));
    void main(){gl_Position=vec4(positions[gl_VertexID],0.,1.);}
  )";
  const GLuint vs=Shader(GL_VERTEX_SHADER,vertex,error);
  if (!vs) return 0;
  const GLuint fs=Shader(GL_FRAGMENT_SHADER,fragment,error);
  if (!fs) { glDeleteShader(vs); return 0; }
  const GLuint program=glCreateProgram();
  glAttachShader(program,vs); glAttachShader(program,fs); glLinkProgram(program);
  glDeleteShader(vs); glDeleteShader(fs);
  GLint valid=0; glGetProgramiv(program,GL_LINK_STATUS,&valid);
  if (!valid) {
    char log[2048]{}; glGetProgramInfoLog(program,sizeof(log),nullptr,log);
    *error=log; glDeleteProgram(program); return 0;
  }
  return program;
}
bool Target(GLuint texture, GLuint fbo, GLint format, GLenum type) {
  glBindTexture(GL_TEXTURE_2D,texture);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D,0,format,4,4,0,GL_RGBA,type,nullptr);
  glBindFramebuffer(GL_FRAMEBUFFER,fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,texture,0);
  return glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE && glGetError()==GL_NO_ERROR;
}
int Fail(const char* stage, const std::string& detail="") {
  std::printf("{\"ok\":false,\"backend\":\"adb-native-probe\",\"stage\":%s,\"detail\":%s,\"eglError\":%d}\n",
      Json(stage).c_str(),Json(detail.c_str()).c_str(),eglGetError());
  return 2;
}
}  // namespace

int main() {
  Egl egl;
  if (!egl.Open()) return Fail("EGL ES3 pbuffer");
  GLint maximum_texture=0, maximum_target=0, major=0, minor=0;
  glGetIntegerv(GL_MAX_TEXTURE_SIZE,&maximum_texture);
  glGetIntegerv(GL_MAX_RENDERBUFFER_SIZE,&maximum_target);
  glGetIntegerv(GL_MAJOR_VERSION,&major); glGetIntegerv(GL_MINOR_VERSION,&minor);
  std::string error;
  const GLuint write=Program(R"(#version 300 es
    precision highp float;
    out vec4 color;
    void main(){color=vec4(2.,.5,.25,1.);}
  )",&error);
  if (!write) return Fail("half-float write shader",error);
  const GLuint present=Program(R"(#version 300 es
    precision highp float;
    uniform sampler2D source;
    out vec4 color;
    void main(){vec4 c=texelFetch(source,ivec2(gl_FragCoord.xy),0);color=vec4(c.r*.25,c.gba);}
  )",&error);
  if (!present) return Fail("present shader",error);
  GLuint textures[2]{}, targets[2]{}, vao=0;
  glGenTextures(2,textures); glGenFramebuffers(2,targets);
  if (!Target(textures[0],targets[0],GL_RGBA16F,GL_HALF_FLOAT)) return Fail("RGBA16F framebuffer");
  if (!Target(textures[1],targets[1],GL_RGBA8,GL_UNSIGNED_BYTE)) return Fail("RGBA8 framebuffer");
  glGenVertexArrays(1,&vao); glBindVertexArray(vao);
  glDisable(GL_DITHER); glDisable(GL_BLEND); glViewport(0,0,4,4);
  glBindFramebuffer(GL_FRAMEBUFFER,targets[0]);
  glUseProgram(write); glDrawArrays(GL_TRIANGLES,0,3);
  glBindFramebuffer(GL_FRAMEBUFFER,targets[1]);
  glUseProgram(present); glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D,textures[0]);
  glUniform1i(glGetUniformLocation(present,"source"),0);
  glDrawArrays(GL_TRIANGLES,0,3);
  std::array<unsigned char,64> pixels{};
  glReadPixels(0,0,4,4,GL_RGBA,GL_UNSIGNED_BYTE,pixels.data());
  if (glGetError()!=GL_NO_ERROR) return Fail("draw/readback");
  // Red would be 64 if the intermediate buffer silently clipped at 1.
  for (int i=0; i<16; ++i) for (int c=0; c<4; ++c) {
    constexpr int expected[]={128,128,64,255};
    if (std::abs(int(pixels[i*4+c])-expected[c])>1) return Fail("half-float headroom readback");
  }
  std::printf("{\"ok\":true,\"backend\":\"adb-native-probe\",\"vendor\":%s,\"renderer\":%s,\"version\":%s,\"major\":%d,\"minor\":%d,\"maxTextureSize\":%d,\"maxRenderbufferSize\":%d,\"halfFloatDrawReadback\":true,\"rgba\":[%u,%u,%u,%u]}\n",
      Json(GlString(GL_VENDOR)).c_str(),Json(GlString(GL_RENDERER)).c_str(),
      Json(GlString(GL_VERSION)).c_str(),major,minor,maximum_texture,maximum_target,
      pixels[0],pixels[1],pixels[2],pixels[3]);
  glDeleteVertexArrays(1,&vao); glDeleteTextures(2,textures); glDeleteFramebuffers(2,targets);
  glDeleteProgram(write); glDeleteProgram(present);
  return 0;
}
