#include "jpeg_io.h"

#include <csetjmp>
#include <cstdio>
#include <new>

extern "C" {
#include <jpeglib.h>
}

#include "gremote_imaging.h"

namespace gremote {
namespace {

struct ErrorManager {
  jpeg_error_mgr base;
  jmp_buf jump;
};

void OnError(j_common_ptr info) {
  auto* manager = reinterpret_cast<ErrorManager*>(info->err);
  longjmp(manager->jump, 1);
}

void Silence(j_common_ptr, int) {}

void InstallErrorManager(jpeg_common_struct* info, ErrorManager* manager) {
  info->err = jpeg_std_error(&manager->base);
  manager->base.error_exit = OnError;
  manager->base.emit_message = Silence;
}

bool ValidSource(const uint8_t* data, size_t length) {
  return data != nullptr && length >= 4 && data[0] == 0xFF && data[1] == 0xD8;
}

}  // namespace

int ReadJpegSize(const uint8_t* data, size_t length, int* width, int* height) {
  if (!ValidSource(data, length)) return GREMOTE_DECODE;
  jpeg_decompress_struct info;
  ErrorManager errors;
  InstallErrorManager(reinterpret_cast<jpeg_common_struct*>(&info), &errors);
  if (setjmp(errors.jump)) {
    jpeg_destroy_decompress(&info);
    return GREMOTE_DECODE;
  }
  jpeg_create_decompress(&info);
  jpeg_mem_src(&info, data, static_cast<unsigned long>(length));
  jpeg_read_header(&info, TRUE);
  *width = int(info.image_width);
  *height = int(info.image_height);
  jpeg_destroy_decompress(&info);
  return GREMOTE_OK;
}

int DecodeJpeg(const uint8_t* data, size_t length, int scale_denom,
               Image* out) {
  if (!ValidSource(data, length) || out == nullptr) return GREMOTE_DECODE;
  if (scale_denom != 1 && scale_denom != 2 && scale_denom != 4 &&
      scale_denom != 8) {
    return GREMOTE_INVALID_ARGUMENT;
  }
  jpeg_decompress_struct info;
  ErrorManager errors;
  InstallErrorManager(reinterpret_cast<jpeg_common_struct*>(&info), &errors);
  if (setjmp(errors.jump)) {
    jpeg_destroy_decompress(&info);
    return GREMOTE_DECODE;
  }
  jpeg_create_decompress(&info);
  jpeg_mem_src(&info, data, static_cast<unsigned long>(length));
  jpeg_read_header(&info, TRUE);
  if (int64_t(info.image_width) * info.image_height > kMaxPixels) {
    jpeg_destroy_decompress(&info);
    return GREMOTE_TOO_LARGE;
  }
  info.out_color_space = JCS_RGB;
  info.scale_num = 1;
  info.scale_denom = unsigned(scale_denom);
  info.dct_method = JDCT_ISLOW;
  jpeg_start_decompress(&info);
  // Allocation failures must not longjmp over the vector; resize up front.
  try {
    *out = Image(int(info.output_width), int(info.output_height), 3);
  } catch (const std::bad_alloc&) {
    jpeg_destroy_decompress(&info);
    return GREMOTE_OUT_OF_MEMORY;
  }
  while (info.output_scanline < info.output_height) {
    JSAMPROW row = out->Row(int(info.output_scanline));
    jpeg_read_scanlines(&info, &row, 1);
  }
  jpeg_finish_decompress(&info);
  jpeg_destroy_decompress(&info);
  return GREMOTE_OK;
}

int ChooseScaleDenom(int width, int height, int max_edge) {
  const int long_edge = width > height ? width : height;
  for (int denom : {8, 4, 2}) {
    if (long_edge / denom >= max_edge) return denom;
  }
  return 1;
}

struct JpegRowWriter::State {
  jpeg_compress_struct info;
  ErrorManager errors;
  FILE* file = nullptr;
  std::string path;
  std::string part_path;
  int height = 0;
  int rows = 0;
  bool active = false;
};

JpegRowWriter::JpegRowWriter() : state_(new State) {}

JpegRowWriter::~JpegRowWriter() { Abort(); }

int JpegRowWriter::Open(const std::string& path, int width, int height,
                        int quality) {
  if (state_->active || width <= 0 || height <= 0 || quality < 1 ||
      quality > 100 || path.empty() ||
      int64_t(width) * height > 4 * kMaxPixels) {
    return GREMOTE_INVALID_ARGUMENT;
  }
  State& s = *state_;
  s.path = path;
  s.part_path = path + ".part";
  s.file = std::fopen(s.part_path.c_str(), "wb");
  if (s.file == nullptr) return GREMOTE_IO;
  InstallErrorManager(reinterpret_cast<jpeg_common_struct*>(&s.info),
                      &s.errors);
  if (setjmp(s.errors.jump)) {
    s.active = true;
    Abort();
    return GREMOTE_ENCODE;
  }
  jpeg_create_compress(&s.info);
  s.active = true;
  jpeg_stdio_dest(&s.info, s.file);
  s.info.image_width = JDIMENSION(width);
  s.info.image_height = JDIMENSION(height);
  s.info.input_components = 3;
  s.info.in_color_space = JCS_RGB;
  jpeg_set_defaults(&s.info);
  jpeg_set_quality(&s.info, quality, TRUE);
  for (int i = 0; i < s.info.num_components; ++i) {
    s.info.comp_info[i].h_samp_factor = 1;
    s.info.comp_info[i].v_samp_factor = 1;
  }
  s.info.optimize_coding = TRUE;
  s.info.dct_method = JDCT_ISLOW;
  jpeg_start_compress(&s.info, TRUE);
  s.height = height;
  s.rows = 0;
  return GREMOTE_OK;
}

int JpegRowWriter::WriteRow(const uint8_t* rgb) {
  State& s = *state_;
  if (!s.active || rgb == nullptr) return GREMOTE_INVALID_ARGUMENT;
  if (s.rows >= s.height) return GREMOTE_ENCODE;
  if (setjmp(s.errors.jump)) {
    Abort();
    return GREMOTE_ENCODE;
  }
  JSAMPROW row = const_cast<JSAMPROW>(rgb);
  jpeg_write_scanlines(&s.info, &row, 1);
  ++s.rows;
  return GREMOTE_OK;
}

int JpegRowWriter::Finish() {
  State& s = *state_;
  if (!s.active) return GREMOTE_INVALID_ARGUMENT;
  if (s.rows != s.height) {
    Abort();
    return GREMOTE_ENCODE;
  }
  if (setjmp(s.errors.jump)) {
    Abort();
    return GREMOTE_ENCODE;
  }
  jpeg_finish_compress(&s.info);
  jpeg_destroy_compress(&s.info);
  s.active = false;
  const bool flushed = std::fclose(s.file) == 0;
  s.file = nullptr;
  if (!flushed || std::rename(s.part_path.c_str(), s.path.c_str()) != 0) {
    std::remove(s.part_path.c_str());
    return GREMOTE_IO;
  }
  return GREMOTE_OK;
}

void JpegRowWriter::Abort() {
  State& s = *state_;
  if (s.active) {
    jpeg_destroy_compress(&s.info);
    s.active = false;
  }
  if (s.file != nullptr) {
    std::fclose(s.file);
    s.file = nullptr;
    std::remove(s.part_path.c_str());
  }
}

int EncodeJpegFile(const Image& image, const std::string& path, int quality) {
  if (image.channels != 3) return GREMOTE_INVALID_ARGUMENT;
  JpegRowWriter writer;
  int status = writer.Open(path, image.width, image.height, quality);
  for (int y = 0; status == GREMOTE_OK && y < image.height; ++y) {
    status = writer.WriteRow(image.Row(y));
  }
  return status == GREMOTE_OK ? writer.Finish() : status;
}

}  // namespace gremote
