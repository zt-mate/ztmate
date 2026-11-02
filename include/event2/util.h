#ifndef EVENT2_UTIL_H
#define EVENT2_UTIL_H

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int evutil_socket_t;

#define evutil_addrinfo addrinfo

#define EVUTIL_AI_PASSIVE     0x0001
#define EVUTIL_AI_CANONNAME   0x0002
#define EVUTIL_AI_NUMERICHOST 0x0004
#define EVUTIL_AI_NUMERICSERV 0x0400
#define EVUTIL_AI_V4MAPPED    0x0008
#define EVUTIL_AI_ALL         0x0010
#define EVUTIL_AI_ADDRCONFIG  0x0020

void evutil_freeaddrinfo(struct evutil_addrinfo *ai);
const char *evutil_gai_strerror(int err);
const char *evutil_inet_ntop(int af, const void *src, char *dst, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* EVENT2_UTIL_H */
