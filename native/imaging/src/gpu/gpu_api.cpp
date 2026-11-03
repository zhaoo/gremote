#include "gpu_session.h"
#include "gremote_imaging.h"
#include <android/native_window_jni.h>
#include <jni.h>
#include <unistd.h>
#include <cstring>
#include <limits>
#include <mutex>
#include <unordered_map>

namespace {
using namespace gremote;
using namespace gremote::gpu;
struct Entry{std::unique_ptr<GpuSession> session;std::shared_ptr<GenerationGate> gate;};
std::mutex registry_mutex;
std::unordered_map<jlong,Entry> registry;
jlong next_id=1;
GpuSession* Find(jlong id){
  std::lock_guard<std::mutex> lock(registry_mutex);
  const auto it=registry.find(id);if(it==registry.end())throw GpuError("gpuInvalidSession");
  it->second.session->CheckOwner();return it->second.session.get();
}
std::shared_ptr<GenerationGate> Gate(jlong id){
  std::lock_guard<std::mutex> lock(registry_mutex);
  const auto it=registry.find(id);return it==registry.end()?nullptr:it->second.gate;
}
void Error(JNIEnv* env,const char* message){
  if(!env->ExceptionCheck())env->ThrowNew(env->FindClass("java/lang/IllegalStateException"),message);
}
}
extern "C" JNIEXPORT jlong JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_create(JNIEnv* env,jobject,jint fd,jint orientation,jint max_edge){
  // The Java host passes an owned duplicate; never close the Dart caller's FD.
  if(orientation<1||orientation>8||max_edge<1||max_edge>4096){
    if(fd>=0)::close(fd);Error(env,"gpuInvalidSourceDescriptor");return 0;
  }
  // The decoder always consumes fd, including bad-input and allocation paths.
  uint8_t* rgba=nullptr;int32_t width=0,height=0;
  const int status=gremote_decode_preview(fd,orientation,max_edge,&rgba,&width,&height);
  std::unique_ptr<uint8_t,decltype(&gremote_free)> pixels(rgba,gremote_free);
  if(status!=GREMOTE_OK){Error(env,"gpuSourceDecode");return 0;}
  try {
    Image source(width,height,4);std::memcpy(source.pixels.data(),pixels.get(),source.pixels.size());
    pixels.reset();
    auto session=std::make_unique<GpuSession>(std::move(source));auto gate=session->gate();
    std::lock_guard<std::mutex> lock(registry_mutex);
    if(next_id==std::numeric_limits<jlong>::max())throw GpuError("gpuSessionIdsExhausted");
    const auto id=next_id++;registry.emplace(id,Entry{std::move(session),std::move(gate)});return id;
  } catch(const std::exception& e){Error(env,e.what());return 0;}
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_info(JNIEnv* env,jobject,jlong id){
  try{
    const auto* session=Find(id);
    const std::string json="{\"sourceWidth\":"+std::to_string(session->source_width())+
      ",\"sourceHeight\":"+std::to_string(session->source_height())+",\"capabilities\":"+session->capabilities().Json()+"}";
    return env->NewStringUTF(json.c_str());
  }catch(const std::exception& e){Error(env,e.what());return nullptr;}
}
extern "C" JNIEXPORT jboolean JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_advance(JNIEnv*,jobject,jlong id,jlong generation){
  const auto gate=Gate(id);return gate&&generation>0&&gate->Advance(uint64_t(generation));
}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_revoke(JNIEnv*,jobject,jlong id){if(auto gate=Gate(id))gate->Close();}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_prepareLut(JNIEnv* env,jobject,jlong id,jstring key,jbyteArray data){
  try{
    auto* session=Find(id);
    if(!key||!data||env->GetStringLength(key)>128)throw GpuError("gpuInvalidLut");
    const auto length=env->GetArrayLength(data);if(length<=0||length>16*1024*1024)throw GpuError("gpuLutTooLarge");
    const char* text=env->GetStringUTFChars(key,nullptr);if(!text)return;
    std::string name;
    try{name=text;}catch(...){env->ReleaseStringUTFChars(key,text);throw;}
    env->ReleaseStringUTFChars(key,text);
    std::vector<uint8_t> bytes(size_t(length),0);
    env->GetByteArrayRegion(data,0,length,reinterpret_cast<jbyte*>(bytes.data()));if(env->ExceptionCheck())return;
    session->PrepareLut(name,bytes.data(),bytes.size());
  }catch(const std::exception& e){Error(env,e.what());}
}
extern "C" JNIEXPORT jboolean JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_render(JNIEnv* env,jobject,jlong id,jlong generation,
    jfloatArray parameters,jstring key,jfloat strength,jint width,jint height){
  try{
    auto* session=Find(id);
    if(!parameters||env->GetArrayLength(parameters)!=kPhotoEditCount)throw GpuError("gpuInvalidParameters");
    PhotoEdits edits;env->GetFloatArrayRegion(parameters,0,kPhotoEditCount,edits.values.data());
    if(env->ExceptionCheck())return false;
    std::string name;
    if(key){
      if(env->GetStringLength(key)>128)throw GpuError("gpuInvalidLutKey");
      const char* text=env->GetStringUTFChars(key,nullptr);if(!text)return false;
      try{name=text;}catch(...){env->ReleaseStringUTFChars(key,text);throw;}
      env->ReleaseStringUTFChars(key,text);
    }
    return session->RenderPrepared(uint64_t(generation),edits,name,strength,width,height);
  }catch(const std::exception& e){Error(env,e.what());return false;}
}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_attach(JNIEnv* env,jobject,jlong id,jobject surface,jint width,jint height){
  try{auto* session=Find(id);ANativeWindow* window=ANativeWindow_fromSurface(env,surface);
    if(!window)throw GpuError("gpuInvalidSurface");session->Attach(window,width,height);
  }catch(const std::exception& e){Error(env,e.what());}
}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_detach(JNIEnv* env,jobject,jlong id){
  try{Find(id)->Detach();}catch(const std::exception& e){Error(env,e.what());}
}
extern "C" JNIEXPORT jboolean JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_present(JNIEnv* env,jobject,jlong id,jlong generation){
  try{return Find(id)->Present(uint64_t(generation));}catch(const std::exception& e){Error(env,e.what());return false;}
}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_close(JNIEnv* env,jobject,jlong id){
  try{
    std::unique_ptr<GpuSession> session;
    {std::lock_guard<std::mutex> lock(registry_mutex);auto it=registry.find(id);if(it==registry.end())return;
      it->second.session->CheckOwner();session=std::move(it->second.session);registry.erase(it);}
    session->Close();
  }catch(const std::exception& e){Error(env,e.what());}
}
