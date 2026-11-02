#ifndef EVENT2_EVENT_H
#define EVENT2_EVENT_H

#include <sys/types.h>
#include <sys/time.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <event2/util.h>

#ifdef __cplusplus
extern "C" {
#endif

#define EV_TIMEOUT 0x01
#define EV_READ    0x02
#define EV_WRITE   0x04
#define EV_SIGNAL  0x08
#define EV_PERSIST 0x10
#define EV_ET      0x20

#define EVLOOP_ONCE     0x01
#define EVLOOP_NONBLOCK 0x02

struct event_base;
struct evbuffer;

/* Exact size (128 bytes) and alignment for libevent 2.1 on 64-bit Linux */
struct event {
	uint64_t _opaque[16];
};

typedef void (*event_callback_fn)(evutil_socket_t, short, void *);
typedef void (*event_log_cb)(int severity, const char *msg);

struct event_base *event_init(void);
int event_reinit(struct event_base *base);
const char *event_get_version(void);
const char *event_get_method(void);
void event_set_log_callback(event_log_cb cb);
int event_loop(int flags);

struct event *event_new(struct event_base *base, evutil_socket_t fd, short events, event_callback_fn cb, void *arg);
void event_set(struct event *ev, evutil_socket_t fd, short events, void (*cb)(evutil_socket_t, short, void *), void *arg);
int event_once(evutil_socket_t fd, short events, void (*cb)(evutil_socket_t, short, void *), void *arg, const struct timeval *tv);
int event_add(struct event *ev, const struct timeval *timeout);
int event_del(struct event *ev);
void event_active(struct event *ev, int res, short ncalls);
int event_pending(const struct event *ev, short events, struct timeval *tv);
int event_initialized(const struct event *ev);
void event_free(struct event *ev);

#define evtimer_new(b, cb, arg)        event_new((b), -1, 0, (cb), (arg))
#define evtimer_set(ev, cb, arg)       event_set((ev), -1, 0, (cb), (arg))
#define evtimer_add(ev, tv)            event_add((ev), (tv))
#define evtimer_del(ev)                event_del(ev)
#define evtimer_pending(ev, tv)        event_pending((ev), EV_TIMEOUT, (tv))
#define evtimer_initialized(ev)        event_initialized(ev)

#define signal_set(ev, x, cb, arg)     event_set((ev), (x), EV_SIGNAL|EV_PERSIST, (cb), (arg))
#define signal_add(ev, tv)             event_add((ev), (tv))
#define signal_del(ev)                 event_del(ev)
#define signal_pending(ev, tv)         event_pending((ev), EV_SIGNAL, (tv))
#define signal_initialized(ev)         event_initialized(ev)

enum evbuffer_eol_style {
	EVBUFFER_EOL_ANY,
	EVBUFFER_EOL_CRLF,
	EVBUFFER_EOL_CRLF_STRICT,
	EVBUFFER_EOL_LF,
	EVBUFFER_EOL_NUL
};

struct evbuffer *evbuffer_new(void);
void evbuffer_free(struct evbuffer *buf);
size_t evbuffer_get_length(const struct evbuffer *buf);
int evbuffer_add(struct evbuffer *buf, const void *data, size_t datlen);
int evbuffer_add_buffer(struct evbuffer *outbuf, struct evbuffer *inbuf);
int evbuffer_add_printf(struct evbuffer *buf, const char *fmt, ...);
int evbuffer_add_vprintf(struct evbuffer *buf, const char *fmt, va_list ap);
int evbuffer_drain(struct evbuffer *buf, size_t len);
int evbuffer_write(struct evbuffer *buffer, evutil_socket_t fd);
int evbuffer_read(struct evbuffer *buffer, evutil_socket_t fd, int howmuch);
unsigned char *evbuffer_pullup(struct evbuffer *buf, ssize_t size);
char *evbuffer_readline(struct evbuffer *buffer);
char *evbuffer_readln(struct evbuffer *buffer, size_t *n_read_out, enum evbuffer_eol_style eol_style);

#define EVBUFFER_LENGTH(x)  evbuffer_get_length(x)
#define EVBUFFER_DATA(x)    evbuffer_pullup((x), -1)
#define EVBUFFER_INPUT(x)   (x)->input
#define EVBUFFER_OUTPUT(x)  (x)->output

struct bufferevent;
typedef void (*evbuffercb)(struct bufferevent *bev, void *ctx);
typedef void (*everrorcb)(struct bufferevent *bev, short what, void *ctx);

/* Matches libevent 2.1 x86_64 layout where input is at 0x110 and output at 0x118 */
struct bufferevent {
	struct event_base *ev_base;
	const void *be_ops;
	struct event ev_read;
	struct event ev_write;
	struct evbuffer *input;
	struct evbuffer *output;
};

struct bufferevent *bufferevent_new(evutil_socket_t fd, evbuffercb readcb, evbuffercb writecb, everrorcb errorcb, void *cbarg);
void bufferevent_free(struct bufferevent *bufev);
int bufferevent_write(struct bufferevent *bufev, const void *data, size_t size);
int bufferevent_write_buffer(struct bufferevent *bufev, struct evbuffer *buf);
size_t bufferevent_read(struct bufferevent *bufev, void *data, size_t size);
int bufferevent_enable(struct bufferevent *bufev, short event);
int bufferevent_disable(struct bufferevent *bufev, short event);
void bufferevent_settimeout(struct bufferevent *bufev, int timeout_read, int timeout_write);
void bufferevent_setwatermark(struct bufferevent *bufev, short events, size_t lowmark, size_t highmark);

#ifdef __cplusplus
}
#endif

#endif /* EVENT2_EVENT_H */
