// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef VIDEO_OUTPUT_H_
#define VIDEO_OUTPUT_H_

#include <flutter_linux/flutter_linux.h>
#include <epoxy/egl.h>

#include "mpv/client.h"
#include "mpv/render.h"
#include "mpv/render_gl.h"

typedef struct _VideoOutputConfiguration {
  gint64 width;
  gint64 height;
  bool enable_hardware_acceleration;

  _VideoOutputConfiguration(gint64 width = NULL,
                            gint64 height = NULL,
                            bool enable_hardware_acceleration = true)
      : width(width),
        height(height),
        enable_hardware_acceleration(enable_hardware_acceleration) {}
} VideoOutputConfiguration;

// Callback invoked when the texture ID updates i.e. video dimensions changes.
typedef void (*TextureUpdateCallback)(gint64 id,
                                      gint64 width,
                                      gint64 height,
                                      gpointer context);

#define VIDEO_OUTPUT_TYPE (video_output_get_type())

G_DECLARE_FINAL_TYPE(VideoOutput,
                     video_output,
                     VIDEO_OUTPUT,
                     VIDEO_OUTPUT,
                     GObject)

#define VIDEO_OUTPUT(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), video_output_get_type(), VideoOutput))

/**
 * @brief Creates a new |VideoOutput| instance for given |handle|.
 *
 * @param texture_registrar |FlTextureRegistrar| reference.
 * @param handle |mpv_handle| reference casted to gint64.
 * @param width Preferred width of the video. Pass `NULL` for using texture
 * dimensions based on video's resolution.
 * @param height Preferred height of the video. Pass `NULL` for using texture
 * dimensions based on video's resolution.
 * @param enable_hardware_acceleration Whether to enable hardware acceleration.
 * @return VideoOutput*
 */
VideoOutput* video_output_new(FlTextureRegistrar* texture_registrar,
                              FlView* view,
                              gint64 handle,
                              VideoOutputConfiguration configuration);

/**
 * @brief Sets the callback invoked when the texture ID updates i.e. video
 * dimensions changes.
 *
 * @param self |VideoOutput| reference.
 * @param texture_update_callback Callback.
 * @param texture_update_callback_context Callback context.
 */
void video_output_set_texture_update_callback(
    VideoOutput* self,
    TextureUpdateCallback texture_update_callback,
    gpointer texture_update_callback_context);

/**
 * @brief Sets the required video output size. This forces |VideoOutput| to
 * resize the internal OpenGL surface / texture.
 *
 * @param texture_registrar |FlTextureRegistrar| reference.
 * @param width Preferred width of the video. Pass `NULL` for using texture
 * dimensions based on video's resolution.
 * @param height Preferred height of the video. Pass `NULL` for using texture
 * dimensions based on video's resolution.
 */
void video_output_set_size(VideoOutput* self, gint64 width, gint64 height);

mpv_render_context* video_output_get_render_context(VideoOutput* self);

GdkGLContext* video_output_get_gdk_gl_context(VideoOutput* self);

EGLDisplay video_output_get_egl_display(VideoOutput* self);

EGLContext video_output_get_egl_context(VideoOutput* self);

EGLSurface video_output_get_egl_surface(VideoOutput* self);

guint8* video_output_get_pixel_buffer(VideoOutput* self);

// CRT TV change (see third_party/README.md): the lock that guards the S/W pixel buffer.
void video_output_lock(VideoOutput* self);
void video_output_unlock(VideoOutput* self);

// CRT TV change (see third_party/README.md): troubleshooting counters, printed every ten
// seconds when CRT_TV_DIAG=1. "offered" = the player has a new frame,
// "drawn" = the frame was drawn into the texture Flutter shows.
void media_kit_diag_offered(void);
void media_kit_diag_drawn(double milliseconds);
double media_kit_diag_now(void);

// CRT TV change (see third_party/README.md): whether drawing a frame should wait inside the
// player until the moment the frame is due (the player's default). It hands
// frames over up to 50 ms early and expects the caller to be a thread that
// has nothing else to do. Here the caller is Flutter's drawing thread (or,
// for S/W, the main thread), so every video frame froze the whole interface
// for up to 50 ms and capped the picture at about 20 frames a second.
// Returns 0 (don't wait) unless CRT_TV_VIDEO_BLOCK=1.
int* media_kit_block_for_target_time(void);

gint64 video_output_get_width(VideoOutput* self);

gint64 video_output_get_height(VideoOutput* self);

gint64 video_output_get_texture_id(VideoOutput* self);

void video_output_notify_texture_update(VideoOutput* self);

#endif  // VIDEO_OUTPUT_H_