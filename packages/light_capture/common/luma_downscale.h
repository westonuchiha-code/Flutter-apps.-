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

inline int ThumbnailHeight(int src_width, int src_height,
                           int dst_width = kThumbnailWidth) {
  if (src_width <= 0 || src_height <= 0) return 0;
  int h = (dst_width * src_height + src_width / 2) / src_width;
  return h < 1 ? 1 : h;
}

// Largest colour thumbnail width a caller may ask for.
constexpr int kMaxThumbnailWidth = 640;

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

// Averages blocks of the source into a dst_width x dst_height colour image,
// 4 bytes per pixel in B, G, R, A order (alpha 255). YUV sources are
// converted with ITU-R BT.601. kLuma8 sources (planar YUV, where only the
// luma plane is read) come out grey.
inline void DownscaleBgra(const uint8_t* first_row, int src_width,
                          int src_height, std::ptrdiff_t row_stride,
                          PixelLayout layout, int dst_width, int dst_height,
                          std::vector<uint8_t>* dst) {
  dst->assign(static_cast<size_t>(dst_width) * dst_height * 4, 0);
  if (src_width <= 0 || src_height <= 0 || dst_width <= 0 || dst_height <= 0) {
    return;
  }
  auto clamp8 = [](int v) -> uint8_t {
    return static_cast<uint8_t>(v < 0 ? 0 : (v > 255 ? 255 : v));
  };
  for (int ty = 0; ty < dst_height; ++ty) {
    const int y0 = ty * src_height / dst_height;
    int y1 = (ty + 1) * src_height / dst_height;
    if (y1 <= y0) y1 = y0 + 1;
    for (int tx = 0; tx < dst_width; ++tx) {
      const int x0 = tx * src_width / dst_width;
      int x1 = (tx + 1) * src_width / dst_width;
      if (x1 <= x0) x1 = x0 + 1;
      // Sums of either (Y, U, V) or (B, G, R).
      uint32_t a = 0, b = 0, c = 0, count = 0;
      for (int y = y0; y < y1; ++y) {
        const uint8_t* row = first_row + row_stride * y;
        for (int x = x0; x < x1; ++x) {
          const int pair = (x & ~1) * 2;  // start of the 4-byte YUV pair
          switch (layout) {
            case PixelLayout::kLuma8:
              a += row[x];
              b += 128;
              c += 128;
              break;
            case PixelLayout::kYuyv:  // Y0 U Y1 V
              a += row[x * 2];
              b += row[pair + 1];
              c += row[pair + 3];
              break;
            case PixelLayout::kUyvy:  // U Y0 V Y1
              a += row[x * 2 + 1];
              b += row[pair];
              c += row[pair + 2];
              break;
            case PixelLayout::kBgra32:
            default: {
              const uint8_t* p = row + x * 4;
              a += p[0];
              b += p[1];
              c += p[2];
              break;
            }
          }
          ++count;
        }
      }
      uint8_t* out = dst->data() + (static_cast<size_t>(ty) * dst_width + tx) * 4;
      if (layout == PixelLayout::kBgra32) {
        out[0] = static_cast<uint8_t>(a / count);
        out[1] = static_cast<uint8_t>(b / count);
        out[2] = static_cast<uint8_t>(c / count);
      } else {
        const int yy = static_cast<int>(a / count);
        const int u = static_cast<int>(b / count) - 128;
        const int v = static_cast<int>(c / count) - 128;
        out[2] = clamp8(yy + ((359 * v) >> 8));             // R = Y + 1.402 V
        out[1] = clamp8(yy - ((88 * u + 183 * v) >> 8));    // G
        out[0] = clamp8(yy + ((454 * u) >> 8));             // B = Y + 1.772 U
      }
      out[3] = 255;
    }
  }
}

}  // namespace light_capture

#endif  // LIGHT_CAPTURE_LUMA_DOWNSCALE_H_
