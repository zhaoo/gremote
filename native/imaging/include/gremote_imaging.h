#ifndef GREMOTE_IMAGING_H
#define GREMOTE_IMAGING_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define GREMOTE_EXPORT __declspec(dllexport)
#else
#define GREMOTE_EXPORT __attribute__((visibility("default")))
#endif

enum {
  GREMOTE_OK = 0,
  GREMOTE_INVALID_ARGUMENT = 1,
  GREMOTE_IO = 2,
  GREMOTE_DECODE = 3,
  GREMOTE_LUT_PARSE = 4,
  GREMOTE_LUT_RANGE = 5,
  GREMOTE_TOO_LARGE = 6,
  GREMOTE_OUT_OF_MEMORY = 7,
  GREMOTE_CANCELLED = 8,
  GREMOTE_ENCODE = 9,
};

typedef struct {
  int32_t x;
  int32_t y;
  int32_t width;
  int32_t height;
  /* Straight (non-premultiplied) RGBA8, width * height * 4 bytes. */
  const uint8_t* rgba;
} gremote_overlay;

typedef struct {
  /* Read-only descriptor; always closed by the callee. */
  int32_t fd;
  /* EXIF orientation 1..8 of the source. */
  int32_t orientation;
  /* Optional .cube text; NULL or length 0 means no LUT. */
  const uint8_t* cube;
  int64_t cube_length;
  float lut_strength;
  /* Photo size after orientation and down-scaling. */
  int32_t photo_width;
  int32_t photo_height;
  int32_t photo_x;
  int32_t photo_y;
  int32_t canvas_width;
  int32_t canvas_height;
  uint8_t background_r;
  uint8_t background_g;
  uint8_t background_b;
  const gremote_overlay* overlays;
  int32_t overlay_count;
  int32_t quality;
  /* NUL-terminated UTF-8 path; written atomically by the callee. */
  const char* output_path;
} gremote_export_request;

/* Decodes an oriented RGBA8 preview whose long edge is at most max_edge.
 * The buffer must be released with gremote_free. */
GREMOTE_EXPORT int32_t gremote_decode_preview(int32_t fd, int32_t orientation,
                                        int32_t max_edge, uint8_t** out_rgba,
                                        int32_t* out_width,
                                        int32_t* out_height);

GREMOTE_EXPORT int32_t gremote_lut_validate(const uint8_t* cube, int64_t length,
                                      int32_t* out_size);

/* Applies the LUT in place to an RGBA8 buffer; alpha is untouched. */
GREMOTE_EXPORT int32_t gremote_apply_lut_rgba(uint8_t* rgba, int32_t width,
                                        int32_t height, const uint8_t* cube,
                                        int64_t length, float strength);

GREMOTE_EXPORT int32_t gremote_export_jpeg(const gremote_export_request* request,
                                     const volatile int32_t* cancel);

GREMOTE_EXPORT void gremote_free(void* pointer);

#ifdef __cplusplus
}
#endif

#endif
