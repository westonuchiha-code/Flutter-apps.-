/* Works around faults in how Flutter's Linux window code (3.50) puts its
 * picture on screen with NVIDIA cards under Wayland, and measures it.
 *
 * Loaded with LD_PRELOAD by the launcher; each part is switched on by its
 * own environment variable, so they can be tried one at a time:
 *
 *   CRT_TV_GL_FIX=offset
 *     The picture landing in the wrong place. On NVIDIA the window code
 *     draws the frame as a textured square, and works its position out
 *     wrongly (fl_compositor_opengl.cc, composite_layer): (-1, -1) where a
 *     full-size picture needs (0, 0). Only the top-right quarter showed, in
 *     the bottom-left corner. This program only ever draws one full-size
 *     layer, so (-1, -1) is always that mistake; it is corrected on its way
 *     to the driver.
 *
 *   CRT_TV_GL_DESYNC=1
 *     Slow, juddering picture. The picture lives on its own Wayland
 *     surface, set to "synchronised": nothing drawn on it reaches the
 *     screen until the window beneath it is redrawn too, which is done by
 *     a different thread at its own pace. This asks for "desynchronised"
 *     instead, so each finished frame goes straight to the screen.
 *
 *   CRT_TV_GL_VSYNC=1
 *     Hands frames over in step with the screen's refresh (the window code
 *     asks for "as fast as possible").
 *
 *   CRT_TV_GL_FINISH=1
 *     Waits for the graphics card to finish each frame before it is handed
 *     over, in case half-drawn frames are being shown.
 *
 *   CRT_TV_GL_STATS=1
 *     Every ten seconds, prints how many frames were handed to the screen
 *     and how long the hand-over took.
 *
 *   CRT_TV_GL_VENDOR=name
 *     Reports a different graphics-card maker to the window code. Setting
 *     "NVIDIA Corporation" on another machine reproduces the faults there.
 *
 * Only Flutter's window code goes through these routes (libepoxy, and
 * wl_proxy_marshal); the drawing engine and the video player talk to the
 * driver directly and are not touched.
 *
 * Build: cc -shared -fPIC -O2 -o libcrtglfix.so gl_fix_shim.c -lepoxy
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define GL_VENDOR 0x1F00

/* libepoxy's dispatch pointers. Each starts as a resolver that replaces
 * itself with the driver's function the first time it is called. A hook
 * steps aside for that first call (the resolver calls through the pointer
 * itself), keeps what the resolver found, and steps back in.
 * (Functions that return nothing are declared as returning int here; the
 * value is never looked at.) */
#define HOOK(name, ret, params, args, before, after)                 \
  extern ret (*epoxy_##name) params;                                  \
  static ret (*real_##name) params;                                   \
  static int settled_##name;                                          \
  static ret shim_##name params {                                     \
    ret result;                                                       \
    before;                                                           \
    if (settled_##name) {                                             \
      result = real_##name args;                                      \
    } else {                                                          \
      ret (*resolver) params = real_##name;                           \
      epoxy_##name = resolver;                                        \
      result = resolver args;                                         \
      if (epoxy_##name != resolver) {                                 \
        real_##name = epoxy_##name;                                   \
        settled_##name = 1;                                           \
      }                                                               \
      epoxy_##name = shim_##name;                                     \
    }                                                                 \
    after;                                                            \
    return result;                                                    \
  }                                                                   \
  static void install_##name(void) {                                  \
    real_##name = epoxy_##name;                                       \
    epoxy_##name = shim_##name;                                       \
  }

static double now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

/* --- the maker's name ---------------------------------------------------- */

static const char *vendor;
typedef const unsigned char *gl_string;
HOOK(glGetString, gl_string, (unsigned int name), (name),
     if (name == GL_VENDOR && vendor != NULL) return (gl_string)vendor, (void)0)

/* --- the misplaced picture ----------------------------------------------- */

HOOK(glUniform2f, int, (int location, float x, float y), (location, x, y),
     if (x == -1.0f && y == -1.0f) { x = 0.0f; y = 0.0f; }, (void)0)

/* --- handing frames to the screen ---------------------------------------- */

static int stats_on;
static double swap_started, stats_since, swap_total, swap_worst;
static int swaps;

static void swap_done(void) {
  if (!stats_on) return;
  double now = now_ms();
  double took = now - swap_started;
  swaps++;
  swap_total += took;
  if (took > swap_worst) swap_worst = took;
  if (stats_since == 0) stats_since = swap_started;
  double span = now - stats_since;
  if (span < 10000) return;
  fprintf(stderr,
          "CRT_TV_DIAG frames handed to the screen: %d in %.0fs (%.1f per second); hand-over avg %.1f worst %.1f ms\n",
          swaps, span / 1000, swaps * 1000.0 / span, swap_total / swaps, swap_worst);
  swaps = 0;
  swap_total = swap_worst = 0;
  stats_since = now;
}

HOOK(eglSwapBuffers, unsigned int, (void *display, void *surface), (display, surface),
     if (stats_on) swap_started = now_ms(), swap_done())

static int vsync_on;
HOOK(eglSwapInterval, unsigned int, (void *display, int interval), (display, interval),
     if (vsync_on) interval = 1, (void)0)

extern void (*epoxy_glFinish)(void);
HOOK(eglCreateSyncKHR, void *, (void *display, unsigned int type, const int *attributes),
     (display, type, attributes), epoxy_glFinish(), (void)0)

/* --- synchronised -> desynchronised --------------------------------------
 * wl_proxy_marshal(proxy, opcode, ...) sends a Wayland request. It takes a
 * variable number of arguments, so it can't be wrapped in C; a few lines of
 * assembly keep the arguments exactly as they came, let crt_marshal_opcode
 * choose the opcode, and jump on to the real function. */

struct wl_proxy;
extern const char *wl_proxy_get_class(struct wl_proxy *proxy);

void *crt_real_marshal;
static int desync_on;

unsigned int crt_marshal_opcode(struct wl_proxy *proxy, unsigned int opcode) {
  if (crt_real_marshal == NULL) {
    crt_real_marshal = dlsym(RTLD_NEXT, "wl_proxy_marshal");
  }
  /* wl_subsurface: request 4 is set_sync, 5 is set_desync; neither takes
   * any arguments. */
  if (desync_on && opcode == 4 && proxy != NULL) {
    const char *kind = wl_proxy_get_class(proxy);
    if (kind != NULL && strcmp(kind, "wl_subsurface") == 0) {
      fprintf(stderr, "CRT_TV_DIAG picture surface set to desynchronised\n");
      return 5;
    }
  }
  return opcode;
}

#if defined(__x86_64__)
__asm__(
    ".text\n"
    ".globl wl_proxy_marshal\n"
    ".type wl_proxy_marshal,@function\n"
    "wl_proxy_marshal:\n"
    "  push %rdi\n  push %rsi\n  push %rdx\n  push %rcx\n  push %r8\n  push %r9\n  push %rax\n"
    "  call crt_marshal_opcode@PLT\n"
    "  mov %eax, %r10d\n"
    "  pop %rax\n  pop %r9\n  pop %r8\n  pop %rcx\n  pop %rdx\n  pop %rsi\n  pop %rdi\n"
    "  mov %r10d, %esi\n"
    "  mov crt_real_marshal@GOTPCREL(%rip), %r11\n"
    "  jmp *(%r11)\n"
    ".size wl_proxy_marshal, .-wl_proxy_marshal\n");
#endif

static int on(const char *name) {
  const char *value = getenv(name);
  return value != NULL && strcmp(value, "1") == 0;
}

__attribute__((constructor)) static void install(void) {
  crt_real_marshal = dlsym(RTLD_NEXT, "wl_proxy_marshal");
  desync_on = on("CRT_TV_GL_DESYNC");
  vsync_on = on("CRT_TV_GL_VSYNC");
  stats_on = on("CRT_TV_GL_STATS");

  vendor = getenv("CRT_TV_GL_VENDOR");
  if (vendor != NULL && vendor[0] == '\0') vendor = NULL;
  if (vendor != NULL) install_glGetString();

  const char *fix = getenv("CRT_TV_GL_FIX");
  if (fix != NULL && strcmp(fix, "offset") == 0) install_glUniform2f();
  if (stats_on) install_eglSwapBuffers();
  if (vsync_on) install_eglSwapInterval();
  if (on("CRT_TV_GL_FINISH")) install_eglCreateSyncKHR();

  fprintf(stderr, "CRT_TV_DIAG graphics fixes: position=%s desync=%d vsync=%d finish=%d stats=%d\n",
          fix != NULL ? fix : "off", desync_on, vsync_on, on("CRT_TV_GL_FINISH"), stats_on);
}
