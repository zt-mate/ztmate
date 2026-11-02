#ifndef LIBSSH_H
#define LIBSSH_H

#include <sys/types.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define SSH_VERSION_INT(a, b, c) (((a) << 16) | ((b) << 8) | (c))
#define LIBSSH_VERSION_INT SSH_VERSION_INT(0, 10, 5)

#define SSH_OK    0
#define SSH_ERROR (-1)
#define SSH_AGAIN (-2)
#define SSH_EOF   (-127)

enum {
	SSH_LOG_NOLOG = 0,
	SSH_LOG_WARNING,
	SSH_LOG_PROTOCOL,
	SSH_LOG_PACKET,
	SSH_LOG_FUNCTIONS
};

enum ssh_auth_e {
	SSH_AUTH_SUCCESS = 0,
	SSH_AUTH_DENIED,
	SSH_AUTH_PARTIAL,
	SSH_AUTH_INFO,
	SSH_AUTH_AGAIN,
	SSH_AUTH_ERROR = -1
};

enum ssh_options_e {
	SSH_OPTIONS_HOST,
	SSH_OPTIONS_PORT,
	SSH_OPTIONS_PORT_STR,
	SSH_OPTIONS_FD,
	SSH_OPTIONS_USER,
	SSH_OPTIONS_SSH_DIR,
	SSH_OPTIONS_IDENTITY,
	SSH_OPTIONS_ADD_IDENTITY,
	SSH_OPTIONS_KNOWNHOSTS,
	SSH_OPTIONS_TIMEOUT,
	SSH_OPTIONS_TIMEOUT_USEC,
	SSH_OPTIONS_SSH1,
	SSH_OPTIONS_SSH2,
	SSH_OPTIONS_LOG_VERBOSITY,
	SSH_OPTIONS_LOG_VERBOSITY_STR,
	SSH_OPTIONS_CIPHERS_C_S,
	SSH_OPTIONS_CIPHERS_S_C,
	SSH_OPTIONS_COMPRESSION_C_S,
	SSH_OPTIONS_COMPRESSION_S_C,
	SSH_OPTIONS_PROXYCOMMAND,
	SSH_OPTIONS_BINDADDR,
	SSH_OPTIONS_STRICTHOSTKEYCHECK,
	SSH_OPTIONS_COMPRESSION,
	SSH_OPTIONS_COMPRESSION_LEVEL,
	SSH_OPTIONS_KEY_EXCHANGE,
	SSH_OPTIONS_HOSTKEYS,
	SSH_OPTIONS_GSSAPI_SERVER_IDENTITY,
	SSH_OPTIONS_GSSAPI_CLIENT_IDENTITY,
	SSH_OPTIONS_GSSAPI_DELEGATE_CREDENTIALS,
	SSH_OPTIONS_HMAC_C_S,
	SSH_OPTIONS_HMAC_S_C,
	SSH_OPTIONS_PASSWORD_AUTH,
	SSH_OPTIONS_PUBKEY_AUTH,
	SSH_OPTIONS_KBDINT_AUTH,
	SSH_OPTIONS_GSSAPI_AUTH,
	SSH_OPTIONS_GLOBAL_KNOWNHOSTS,
	SSH_OPTIONS_NODELAY,
	SSH_OPTIONS_PUBLICKEY_ACCEPTED_TYPES,
	SSH_OPTIONS_PROCESS_CONFIG,
	SSH_OPTIONS_REKEY_DATA,
	SSH_OPTIONS_REKEY_TIME,
	SSH_OPTIONS_RSA_MIN_SIZE,
	SSH_OPTIONS_IDENTITY_AGENT,
	SSH_OPTIONS_IDENTITIES_ONLY
};

enum ssh_keytypes_e {
	SSH_KEYTYPE_UNKNOWN = 0,
	SSH_KEYTYPE_DSS,
	SSH_KEYTYPE_RSA,
	SSH_KEYTYPE_RSA1,
	SSH_KEYTYPE_ECDSA,
	SSH_KEYTYPE_ED25519,
	SSH_KEYTYPE_DSS_CERT01,
	SSH_KEYTYPE_RSA_CERT01,
	SSH_KEYTYPE_ECDSA_P256,
	SSH_KEYTYPE_ECDSA_P384,
	SSH_KEYTYPE_ECDSA_P521,
	SSH_KEYTYPE_ECDSA_P256_CERT01,
	SSH_KEYTYPE_ECDSA_P384_CERT01,
	SSH_KEYTYPE_ECDSA_P521_CERT01,
	SSH_KEYTYPE_ED25519_CERT01,
	SSH_KEYTYPE_SK_ECDSA,
	SSH_KEYTYPE_SK_ECDSA_CERT01,
	SSH_KEYTYPE_SK_ED25519,
	SSH_KEYTYPE_SK_ED25519_CERT01
};

enum ssh_publickey_hash_type {
	SSH_PUBLICKEY_HASH_SHA1,
	SSH_PUBLICKEY_HASH_MD5,
	SSH_PUBLICKEY_HASH_SHA256
};

typedef struct ssh_session_struct *ssh_session;
typedef struct ssh_channel_struct *ssh_channel;
typedef struct ssh_key_struct *ssh_key;

typedef int (*ssh_auth_callback)(const char *prompt, char *buf, size_t len,
    int echo, int verify, void *userdata);
typedef void (*ssh_log_callback)(int priority, const char *function,
    const char *buffer, void *userdata);

ssh_session ssh_new(void);
void ssh_free(ssh_session session);
int ssh_connect(ssh_session session);
void ssh_disconnect(ssh_session session);
void ssh_set_blocking(ssh_session session, int blocking);
int ssh_get_fd(ssh_session session);
const char *ssh_get_error(void *error);
int ssh_options_set(ssh_session session, enum ssh_options_e type, const void *value);

int ssh_get_server_publickey(ssh_session session, ssh_key *key);
int ssh_get_publickey(ssh_session session, ssh_key *key);
int ssh_get_publickey_hash(const ssh_key key, enum ssh_publickey_hash_type type,
    unsigned char **hash, size_t *hlen);
char *ssh_get_fingerprint_hash(enum ssh_publickey_hash_type type,
    unsigned char *hash, size_t len);
enum ssh_keytypes_e ssh_key_type(const ssh_key key);
void ssh_key_free(ssh_key key);
void ssh_clean_pubkey_hash(unsigned char **hash);

int ssh_userauth_none(ssh_session session, const char *username);
int ssh_userauth_publickey_auto(ssh_session session, const char *username,
    const char *passphrase);

ssh_channel ssh_channel_new(ssh_session session);
int ssh_channel_open_session(ssh_channel channel);
int ssh_channel_request_subsystem(ssh_channel channel, const char *subsystem);
int ssh_channel_read_nonblocking(ssh_channel channel, void *dest, uint32_t count, int is_stderr);
int ssh_channel_write(ssh_channel channel, const void *data, uint32_t len);
void ssh_channel_free(ssh_channel channel);

int ssh_set_log_callback(ssh_log_callback cb);

#ifdef __cplusplus
}
#endif

#endif /* LIBSSH_H */
