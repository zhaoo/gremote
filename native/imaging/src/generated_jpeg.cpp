#include "gremote_imaging.h"
#include "jpeg_io.h"
#include <vector>
#include <new>

extern "C" int32_t gremote_encode_generated_jpeg(const uint8_t* rgba,
    int32_t width,int32_t height,const char* path,const volatile int32_t* cancel) {
  if (!rgba || !path || !*path || width < 1 || height < 1) return GREMOTE_INVALID_ARGUMENT;
  if (int64_t(width)*height > 4000000) return GREMOTE_TOO_LARGE;
  if (cancel && *cancel) return GREMOTE_CANCELLED;
  try {
    gremote::JpegRowWriter writer;
    int status=writer.Open(path,width,height,92);
    if (status) return status;
    std::vector<uint8_t> row(size_t(width)*3);
    for (int y=0;y<height;++y) {
      if (cancel && *cancel) { writer.Abort(); return GREMOTE_CANCELLED; }
      for (int x=0;x<width;++x) for (int c=0;c<3;++c)
        row[x*3+c]=rgba[(size_t(y)*width+x)*4+c];
      status=writer.WriteRow(row.data());
      if (status) { writer.Abort(); return status; }
    }
    if (cancel && *cancel) { writer.Abort(); return GREMOTE_CANCELLED; }
    return writer.Finish();
  } catch (const std::bad_alloc&) { return GREMOTE_OUT_OF_MEMORY; }
    catch (...) { return GREMOTE_ENCODE; }
}
