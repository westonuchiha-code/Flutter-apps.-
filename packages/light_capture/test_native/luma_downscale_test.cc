// Plain C++ test (no framework) for common/luma_downscale.h.
// Build & run: c++ -std=c++17 -I common test_native/luma_downscale_test.cc && ./a.out
#include "luma_downscale.h"

#include <cstdio>
#include <cstdlib>

using light_capture::DownscaleLuma;
using light_capture::PixelLayout;

static int failures = 0;
#define CHECK_EQ(a, b)                                                    \
  do {                                                                    \
    long _a = (a), _b = (b);                                              \
    if (_a != _b) {                                                       \
      std::printf("%s:%d: %s == %ld, expected %ld\n", __FILE__, __LINE__, \
                  #a, _a, _b);                                            \
      ++failures;                                                         \
    }                                                                     \
  } while (0)

int main() {
  CHECK_EQ(light_capture::ThumbnailHeight(640, 480), 120);
  CHECK_EQ(light_capture::ThumbnailHeight(1280, 720), 90);
  CHECK_EQ(light_capture::ThumbnailHeight(0, 480), 0);

  // 4x2 luma image, left half 0, right half 200 -> 2x1 thumbnail.
  {
    const uint8_t src[] = {0, 0, 200, 200, 0, 0, 200, 200};
    std::vector<uint8_t> dst;
    DownscaleLuma(src, 4, 2, 4, PixelLayout::kLuma8, 2, 1, &dst);
    CHECK_EQ(dst[0], 0);
    CHECK_EQ(dst[1], 200);
  }
  // YUYV: Y values 10,30 | 50,70 with chroma bytes 128 in between.
  {
    const uint8_t src[] = {10, 128, 30, 128, 50, 128, 70, 128};
    std::vector<uint8_t> dst;
    DownscaleLuma(src, 4, 1, 8, PixelLayout::kYuyv, 2, 1, &dst);
    CHECK_EQ(dst[0], 20);
    CHECK_EQ(dst[1], 60);
  }
  // UYVY.
  {
    const uint8_t src[] = {128, 10, 128, 30};
    std::vector<uint8_t> dst;
    DownscaleLuma(src, 2, 1, 4, PixelLayout::kUyvy, 1, 1, &dst);
    CHECK_EQ(dst[0], 20);
  }
  // BGRA white and black, bottom-up (negative stride).
  {
    // Memory: row0 = black (bottom), row1 = white (top).
    const uint8_t src[] = {0, 0, 0, 255, 255, 255, 255, 255};
    std::vector<uint8_t> dst;
    DownscaleLuma(src + 4, 1, 2, -4, PixelLayout::kBgra32, 1, 2, &dst);
    CHECK_EQ(dst[0], 255);  // top row is white
    CHECK_EQ(dst[1], 0);
  }
  // Colour: BGRA passes through (averaged); YUYV converts to RGB.
  CHECK_EQ(light_capture::ThumbnailHeight(640, 480, 320), 240);
  {
    // 2x1 BGRA: blue and red -> 1x1 average.
    const uint8_t src[] = {255, 0, 0, 255, 0, 0, 255, 255};
    std::vector<uint8_t> dst;
    light_capture::DownscaleBgra(src, 2, 1, 8, PixelLayout::kBgra32, 1, 1, &dst);
    CHECK_EQ(dst.size(), 4);
    CHECK_EQ(dst[0], 127);
    CHECK_EQ(dst[2], 127);
    CHECK_EQ(dst[3], 255);
  }
  {
    // YUYV pure red is about Y=76 U=85 V=255.
    const uint8_t src[] = {76, 85, 76, 255};
    std::vector<uint8_t> dst;
    light_capture::DownscaleBgra(src, 2, 1, 4, PixelLayout::kYuyv, 2, 1, &dst);
    CHECK_EQ(dst[2] > 240, 1);  // R high
    CHECK_EQ(dst[1] < 20, 1);   // G low
    CHECK_EQ(dst[0] < 20, 1);   // B low
    // Same colour as UYVY.
    const uint8_t uyvy[] = {85, 76, 255, 76};
    std::vector<uint8_t> dst2;
    light_capture::DownscaleBgra(uyvy, 2, 1, 4, PixelLayout::kUyvy, 2, 1, &dst2);
    CHECK_EQ(dst2[2], dst[2]);
    CHECK_EQ(dst2[0], dst[0]);
  }
  {
    // Grey-only sources come out grey.
    const uint8_t src[] = {100};
    std::vector<uint8_t> dst;
    light_capture::DownscaleBgra(src, 1, 1, 1, PixelLayout::kLuma8, 1, 1, &dst);
    CHECK_EQ(dst[0], 100);
    CHECK_EQ(dst[1], 100);
    CHECK_EQ(dst[2], 100);
  }

  if (failures == 0) std::printf("All luma_downscale tests passed.\n");
  return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
