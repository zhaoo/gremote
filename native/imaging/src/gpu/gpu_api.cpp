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
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_create(JNIEnv* env,jobject,jint fd,jint orientation,jint max_edge,jint version,jboolean adobe){
  if(orientation<1||orientation>8||max_edge<1||max_edge>4096){if(fd>=0)::close(fd);Error(env,"gpuInvalidSourceDescriptor");return 0;}
  try {
    SourceIdentity identity;auto source=LoadSource(fd,version,adobe,&identity);
    auto session=std::make_unique<GpuSession>(std::move(source),std::make_shared<GenerationGate>(),orientation,version);session->SetIdentity(identity);auto gate=session->gate();
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

namespace {
std::mutex jobs_mutex;
std::unordered_map<jlong,std::shared_ptr<std::atomic<bool>>> jobs;
std::string Text(JNIEnv* env,jstring value){
  if(!value)throw GpuError("gpuInvalidString");const char* p=env->GetStringUTFChars(value,nullptr);if(!p)throw GpuError("gpuStringAllocation");
  std::string out;try{out=p;}catch(...){env->ReleaseStringUTFChars(value,p);throw;}env->ReleaseStringUTFChars(value,p);return out;
}
std::shared_ptr<std::atomic<bool>> Job(jlong id){std::lock_guard<std::mutex> lock(jobs_mutex);auto it=jobs.find(id);if(it==jobs.end())throw GpuError("gpuInvalidExportJob");return it->second;}
}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_createExport(JNIEnv* env,jobject,jlong id){try{std::lock_guard<std::mutex> lock(jobs_mutex);if(id<=0||jobs.count(id)||jobs.size()>=4)throw GpuError("gpuInvalidExportJob");jobs[id]=std::make_shared<std::atomic<bool>>(false);}catch(const std::exception& e){Error(env,e.what());}}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_cancelExport(JNIEnv*,jobject,jlong id){std::lock_guard<std::mutex> lock(jobs_mutex);auto it=jobs.find(id);if(it!=jobs.end())it->second->store(true);}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_cancelExports(JNIEnv*,jobject){std::lock_guard<std::mutex> lock(jobs_mutex);for(auto& entry:jobs)entry.second->store(true);}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_finishExport(JNIEnv*,jobject,jlong id){std::lock_guard<std::mutex> lock(jobs_mutex);jobs.erase(id);}
extern "C" JNIEXPORT void JNICALL
Java_com_izhaoo_gremote_imaging_GpuNativeBridge_exportJpeg(JNIEnv* env,jobject,jlong job,jlong id,jint fd,jint orientation,jboolean adobe,
  jfloatArray parameters,jbyteArray cube,jfloat strength,jintArray geometry,jobjectArray images,jintArray rectangles,jstring destination){
  struct Guard{int fd;~Guard(){if(fd>=0)::close(fd);}}guard{fd};
  try{
    const auto cancelled=Job(job);if(cancelled->load())throw GpuError("cancelled");
    if(!parameters||env->GetArrayLength(parameters)!=kPhotoEditCount||!geometry||env->GetArrayLength(geometry)!=8)throw GpuError("gpuInvalidExportDescriptor");
    PhotoEdits edits;env->GetFloatArrayRegion(parameters,0,kPhotoEditCount,edits.values.data());
    jint g[8];env->GetIntArrayRegion(geometry,0,8,g);if(env->ExceptionCheck())return;
    ExportSpec spec;spec.photo_width=g[0];spec.photo_height=g[1];spec.photo_x=g[2];spec.photo_y=g[3];spec.canvas_width=g[4];spec.canvas_height=g[5];spec.quality=g[6];
    spec.background[0]=(uint32_t(g[7])>>16)&255;spec.background[1]=(uint32_t(g[7])>>8)&255;spec.background[2]=uint32_t(g[7])&255;spec.path=Text(env,destination);
    const int count=images?env->GetArrayLength(images):0;
    if(count>64||!rectangles||env->GetArrayLength(rectangles)!=count*4)throw GpuError("gpuInvalidExportOverlays");
    std::vector<jint> rects(size_t(count)*4);env->GetIntArrayRegion(rectangles,0,count*4,rects.data());
    std::vector<std::vector<uint8_t>> overlayBytes;overlayBytes.reserve(count);size_t total=0;
    for(int i=0;i<count;++i){auto data=static_cast<jbyteArray>(env->GetObjectArrayElement(images,i));
      if(!data)throw GpuError("gpuInvalidExportOverlay");const auto n=env->GetArrayLength(data);const int w=rects[i*4+2],h=rects[i*4+3];
      total+=size_t(n);if(w<=0||h<=0||uint64_t(w)*h*4!=uint64_t(n)||total>64*1024*1024){env->DeleteLocalRef(data);throw GpuError("gpuOverlayMemoryLimit");}
      overlayBytes.emplace_back(size_t(n));env->GetByteArrayRegion(data,0,n,reinterpret_cast<jbyte*>(overlayBytes.back().data()));env->DeleteLocalRef(data);
      spec.overlays.push_back({rects[i*4],rects[i*4+1],w,h,overlayBytes.back().data()});
    }
    std::vector<uint8_t> lut;if(cube){const int n=env->GetArrayLength(cube);if(n>16*1024*1024)throw GpuError("gpuLutTooLarge");lut.resize(size_t(n));env->GetByteArrayRegion(cube,0,n,reinterpret_cast<jbyte*>(lut.data()));}
    if(env->ExceptionCheck())return;
    std::unique_ptr<GpuSession> owned;GpuSession* session=nullptr;
    if(id){session=Find(id);if(!session->Matches(fd,orientation,int(edits.values[0])))throw GpuError("gpuExportSourceChanged");}
    else{
      int ownedFd=guard.fd;guard.fd=-1;SourceIdentity identity;auto source=LoadSource(ownedFd,int(edits.values[0]),adobe,&identity);
      owned=std::make_unique<GpuSession>(std::move(source),std::make_shared<GenerationGate>(),orientation,int(edits.values[0]));owned->SetIdentity(identity);session=owned.get();
    }
    session->Export(edits,lut.empty()?nullptr:lut.data(),lut.size(),strength,spec,nullptr,[cancelled]{return cancelled->load();});
  }catch(const std::exception& e){Error(env,e.what());}
}
