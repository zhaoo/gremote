#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>

#include "image.h"

namespace gremote {

int ReadJpegSize(const uint8_t* data, size_t length, int* width, int* height);

// Decodes to RGB8; scale_denom is 1, 2, 4 or 8.
int DecodeJpeg(const uint8_t* data, size_t length, int scale_denom,
               Image* out);

// Largest denominator whose scaled long edge still reaches max_edge.
int ChooseScaleDenom(int width, int height, int max_edge);

// Streams RGB8 rows into "<path>.part" and renames it to path on success.
class JpegRowWriter {
 public:
  JpegRowWriter();
  ~JpegRowWriter();
  JpegRowWriter(const JpegRowWriter&) = delete;
  JpegRowWriter& operator=(const JpegRowWriter&) = delete;

  int Open(const std::string& path, int width, int height, int quality);
  int WriteRow(const uint8_t* rgb);
  int Finish();
  // Discards partial output.
  void Abort();

 private:
  struct State;
  std::unique_ptr<State> state_;
};

int EncodeJpegFile(const Image& image, const std::string& path, int quality);

}  // namespace gremote
