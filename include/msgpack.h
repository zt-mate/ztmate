#ifndef MSGPACK_H
#define MSGPACK_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*msgpack_packer_write)(void *data, const char *buf, size_t len);

typedef struct msgpack_packer {
	void *data;
	msgpack_packer_write callback;
} msgpack_packer;

typedef enum {
	MSGPACK_OBJECT_NIL               = 0x00,
	MSGPACK_OBJECT_BOOLEAN           = 0x01,
	MSGPACK_OBJECT_POSITIVE_INTEGER  = 0x02,
	MSGPACK_OBJECT_NEGATIVE_INTEGER  = 0x03,
	MSGPACK_OBJECT_FLOAT32           = 0x0a,
	MSGPACK_OBJECT_FLOAT64           = 0x04,
	MSGPACK_OBJECT_FLOAT             = 0x04,
	MSGPACK_OBJECT_STR               = 0x05,
	MSGPACK_OBJECT_ARRAY             = 0x06,
	MSGPACK_OBJECT_MAP               = 0x07,
	MSGPACK_OBJECT_BIN               = 0x08,
	MSGPACK_OBJECT_EXT               = 0x09
} msgpack_object_type;

struct msgpack_object;
struct msgpack_object_kv;

typedef struct {
	uint32_t size;
	struct msgpack_object *ptr;
} msgpack_object_array;

typedef struct {
	uint32_t size;
	struct msgpack_object_kv *ptr;
} msgpack_object_map;

typedef struct {
	uint32_t size;
	const char *ptr;
} msgpack_object_str;

typedef struct {
	uint32_t size;
	const char *ptr;
} msgpack_object_bin;

typedef struct {
	int8_t type;
	uint32_t size;
	const char *ptr;
} msgpack_object_ext;

typedef union {
	bool boolean;
	uint64_t u64;
	int64_t i64;
	double f64;
	msgpack_object_array array;
	msgpack_object_map map;
	msgpack_object_str str;
	msgpack_object_bin bin;
	msgpack_object_ext ext;
} msgpack_object_union;

typedef struct msgpack_object {
	msgpack_object_type type;
	msgpack_object_union via;
} msgpack_object;

typedef struct msgpack_object_kv {
	msgpack_object key;
	msgpack_object val;
} msgpack_object_kv;

typedef struct msgpack_unpacker {
	char *buffer;
	size_t used;
	size_t free;
	size_t off;
	size_t parsed;
	void *z;
	size_t initial_buffer_size;
	int ctx;
} msgpack_unpacker;

typedef struct msgpack_unpacked {
	void *zone;
	msgpack_object data;
} msgpack_unpacked;

void msgpack_packer_init(msgpack_packer *pk, void *data, msgpack_packer_write callback);
int msgpack_pack_int(msgpack_packer *pk, int d);
int msgpack_pack_unsigned_int(msgpack_packer *pk, unsigned int d);
int msgpack_pack_int64(msgpack_packer *pk, int64_t d);
int msgpack_pack_uint64(msgpack_packer *pk, uint64_t d);
int msgpack_pack_nil(msgpack_packer *pk);
int msgpack_pack_true(msgpack_packer *pk);
int msgpack_pack_false(msgpack_packer *pk);
int msgpack_pack_array(msgpack_packer *pk, size_t n);
int msgpack_pack_str(msgpack_packer *pk, size_t l);
int msgpack_pack_str_body(msgpack_packer *pk, const void *b, size_t l);
int msgpack_pack_bin(msgpack_packer *pk, size_t l);
int msgpack_pack_bin_body(msgpack_packer *pk, const void *b, size_t l);

bool msgpack_unpacker_init(msgpack_unpacker *mpac, size_t initial_buffer_size);
void msgpack_unpacker_destroy(msgpack_unpacker *mpac);
bool msgpack_unpacker_reserve_buffer(msgpack_unpacker *mpac, size_t size);
char *msgpack_unpacker_buffer(msgpack_unpacker *mpac);
size_t msgpack_unpacker_buffer_capacity(const msgpack_unpacker *mpac);
void msgpack_unpacker_buffer_consumed(msgpack_unpacker *mpac, size_t size);
bool msgpack_unpacker_next(msgpack_unpacker *mpac, msgpack_unpacked *pac);
void msgpack_unpacked_init(msgpack_unpacked *result);
void msgpack_unpacked_destroy(msgpack_unpacked *result);

#ifdef __cplusplus
}
#endif

#endif /* MSGPACK_H */
