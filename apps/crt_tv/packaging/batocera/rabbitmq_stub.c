/* Stand-in for librabbitmq.so.4 with no OpenSSL dependency.
   Only satisfies the symbols libavformat imports; every call reports failure,
   so FFmpeg's amqp:// protocol is effectively disabled. */
#include <stddef.h>
#include <stdint.h>

typedef struct { size_t len; void *bytes; } amqp_bytes_t;
typedef struct { int num_entries; void *entries; } amqp_table_t;
typedef struct { int num_entries; void *entries; } amqp_array_t;
typedef struct { uint32_t id; void *decoded; } amqp_method_t;
typedef struct { int reply_type; amqp_method_t reply; int library_error; } amqp_rpc_reply_t;

#define AMQP_RESPONSE_LIBRARY_EXCEPTION 2
#define AMQP_STATUS_SOCKET_ERROR (-9)

const amqp_bytes_t amqp_empty_bytes = {0, NULL};
const amqp_table_t amqp_empty_table = {0, NULL};
const amqp_array_t amqp_empty_array = {0, NULL};

static amqp_rpc_reply_t fail_reply(void) {
    amqp_rpc_reply_t r = {AMQP_RESPONSE_LIBRARY_EXCEPTION, {0, NULL}, AMQP_STATUS_SOCKET_ERROR};
    return r;
}

void *amqp_new_connection(void) { return NULL; }
int amqp_destroy_connection(void *c) { (void)c; return AMQP_STATUS_SOCKET_ERROR; }
void *amqp_tcp_socket_new(void *c) { (void)c; return NULL; }
int amqp_socket_open_noblock(void *s, const char *h, int p, void *t) { (void)s; (void)h; (void)p; (void)t; return AMQP_STATUS_SOCKET_ERROR; }
int amqp_socket_get_sockfd(void *s) { (void)s; return -1; }
const char *amqp_error_string2(int e) { (void)e; return "amqp support not available"; }
amqp_bytes_t amqp_cstring_bytes(const char *s) { (void)s; amqp_bytes_t b = {0, NULL}; return b; }

amqp_rpc_reply_t amqp_login(void *c, const char *v, int ch, int fm, int hb, int m, ...) {
    (void)c; (void)v; (void)ch; (void)fm; (void)hb; (void)m; return fail_reply();
}
amqp_rpc_reply_t amqp_get_rpc_reply(void *c) { (void)c; return fail_reply(); }
amqp_rpc_reply_t amqp_channel_close(void *c, int ch, int code) { (void)c; (void)ch; (void)code; return fail_reply(); }
amqp_rpc_reply_t amqp_connection_close(void *c, int code) { (void)c; (void)code; return fail_reply(); }
amqp_rpc_reply_t amqp_consume_message(void *c, void *env, void *tv, int flags) {
    (void)c; (void)env; (void)tv; (void)flags; return fail_reply();
}

void *amqp_channel_open(void *c, int ch) { (void)c; (void)ch; return NULL; }
void *amqp_queue_declare(void *c, int ch, amqp_bytes_t q, int pa, int du, int ex, int ad, amqp_table_t a) {
    (void)c; (void)ch; (void)q; (void)pa; (void)du; (void)ex; (void)ad; (void)a; return NULL;
}
void *amqp_queue_bind(void *c, int ch, amqp_bytes_t q, amqp_bytes_t e, amqp_bytes_t k, amqp_table_t a) {
    (void)c; (void)ch; (void)q; (void)e; (void)k; (void)a; return NULL;
}
void *amqp_basic_consume(void *c, int ch, amqp_bytes_t q, amqp_bytes_t t, int nl, int na, int ex, amqp_table_t a) {
    (void)c; (void)ch; (void)q; (void)t; (void)nl; (void)na; (void)ex; (void)a; return NULL;
}
int amqp_basic_publish(void *c, int ch, amqp_bytes_t e, amqp_bytes_t k, int m, int i, const void *p, amqp_bytes_t b) {
    (void)c; (void)ch; (void)e; (void)k; (void)m; (void)i; (void)p; (void)b; return AMQP_STATUS_SOCKET_ERROR;
}

void amqp_destroy_envelope(void *env) { (void)env; }
void amqp_maybe_release_buffers(void *c) { (void)c; }
