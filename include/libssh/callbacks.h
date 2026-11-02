#ifndef LIBSSH_CALLBACKS_H
#define LIBSSH_CALLBACKS_H

#include <libssh/libssh.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

struct ssh_callbacks_struct {
	size_t size;
	void *userdata;
	ssh_auth_callback auth_function;
	ssh_log_callback log_function;
	void (*connect_status_function)(void *userdata, float status);
	void (*global_request_function)(ssh_session session, void *message, void *userdata);
	ssh_channel (*channel_open_request_x11_function)(ssh_session session,
	    const char *originator_address, int originator_port, void *userdata);
	ssh_channel (*channel_open_request_auth_agent_function)(ssh_session session,
	    void *userdata);
	ssh_channel (*channel_open_request_forwarded_tcpip_function)(ssh_session session,
	    const char *destination_address, int destination_port,
	    const char *originator_address, int originator_port, void *userdata);
};
typedef struct ssh_callbacks_struct *ssh_callbacks;

#define ssh_callbacks_init(p) do { \
	(p)->size = sizeof(*(p)); \
} while (0)

int ssh_set_callbacks(ssh_session session, ssh_callbacks cb);

#ifdef __cplusplus
}
#endif

#endif /* LIBSSH_CALLBACKS_H */
