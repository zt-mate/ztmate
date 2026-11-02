#ifndef EVENT2_DNS_H
#define EVENT2_DNS_H

#include <event2/util.h>
#include <event2/event.h>

#ifdef __cplusplus
extern "C" {
#endif

struct evdns_base;
struct evdns_getaddrinfo_request;

typedef void (*evdns_getaddrinfo_cb)(int result, struct evutil_addrinfo *res, void *arg);

struct evdns_base *evdns_base_new(struct event_base *event_base, int initialize_nameservers);
void evdns_base_free(struct evdns_base *base, int fail_requests);
struct evdns_getaddrinfo_request *evdns_getaddrinfo(
    struct evdns_base *dns_base,
    const char *nodename,
    const char *servname,
    const struct evutil_addrinfo *hints_in,
    evdns_getaddrinfo_cb cb,
    void *arg);

#ifdef __cplusplus
}
#endif

#endif /* EVENT2_DNS_H */
