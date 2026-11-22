// Shared by the Windows and Linux implementations: shrinks a camera frame to
// a small 8-bit luminance (brightness) image by averaging blocks of pixels.
#ifndef LIGHT_CAPTURE_LUMA_DOWNSCALE_H_
#define LIGHT_CAPTURE_LUMA_DOWNSCALE_H_

#include <cstddef>
#include <cstdint>
#include <vector>

namespace light_capture {

// Width of the thumbnail sent to Dart. Height follows the camera aspect ratio.
constexpr int kThumbnailWidth = 160;

inline int ThumbnailHeight(int src_width, int src_height) {
  if (src_width <= 0 || src_height <= 0) return 0;
  int h = (kThumbnailWidth * src_height + src_width / 2) / src_width;
  return h < 1 ? 1 : h;
}

// Pixel layouts supported by the downscaler.
enum class PixelLayout {
  kLuma8,   // 8-bit luma plane (GREY, or the Y plane of NV12 / I420).
  kYuyv,    // Packed YUYV 4:2:2 (Y at every even byte).
  kUyvy,    // Packed UYVY 4:2:2 (Y at every odd byte).
  kBgra32,  // 32-bit BGRA / BGRX (Windows RGB32).
};

// Averages blocks of the source into a dst_width x dst_height luma image.
// `first_row` points at the top row of the image; `row_stride` is the byte
// distance between rows and may be negative (bottom-up bitmaps).
inline void DownscaleLuma(const uint8_t* first_row, int src_width,
                          int src_height, std::ptrdiff_t row_stride,
                          PixelLayout layout, int dst_width, int dst_height,
                          std::vector<uint8_t>* dst) {
  dst->assign(static_cast<size_t>(dst_width) * dst_height, 0);
  if (src_width <= 0 || src_height <= 0 || dst_width <= 0 || dst_height <= 0) {
    return;
  }
  for (int ty = 0; ty < dst_height; ++ty) {
    const int y0 = ty * src_height / dst_height;
    int y1 = (ty + 1) * src_height / dst_height;
    if (y1 <= y0) y1 = y0 + 1;
    for (int tx = 0; tx < dst_width; ++tx) {
      const int x0 = tx * src_width / dst_width;
      int x1 = (tx + 1) * src_width / dst_width;
      if (x1 <= x0) x1 = x0 + 1;
      uint32_t sum = 0;
      uint32_t count = 0;
      for (int y = y0; y < y1; ++y) {
        const uint8_t* row = first_row + row_stride * y;
        for (int x = x0; x < x1; ++x) {
          uint32_t luma;
          switch (layout) {
            case PixelLayout::kLuma8:
              luma = row[x];
              break;
            case PixelLayout::kYuyv:
              luma = row[x * 2];
              break;
            case PixelLayout::kUyvy:
              luma = row[x * 2 + 1];
              break;
            case PixelLayout::kBgra32:
            default: {
              const uint8_t* p = row + x * 4;
              // ITU-R BT.601 luma: 0.114 B + 0.587 G + 0.299 R.
              luma = (29u * p[0] + 150u * p[1] + 77u * p[2]) >> 8;
              break;
            }
          }
          sum += luma;
          ++count;
        }
      }
      (*dst)[static_cast<size_t>(ty) * dst_width + tx] =
          static_cast<uint8_t>(sum / count);
    }
  }
}

}  // namespace light_capture

#endif  // LIGHT_CAPTURE_LUMA_DOWNSCALE_H_
