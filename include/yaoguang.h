#ifndef YAOGUANG_H
#define YAOGUANG_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct YaoguangHandle YaoguangHandle;

enum {
    YAOGUANG_FIELD_CALLSIGN = 1u << 0,
    YAOGUANG_FIELD_SPEED = 1u << 1,
    YAOGUANG_FIELD_DIRECTION = 1u << 2,
    YAOGUANG_FIELD_ALTITUDE = 1u << 3,
    YAOGUANG_FIELD_VERTICAL_RATE = 1u << 4,
    YAOGUANG_FIELD_SIGNAL = 1u << 6
};

enum {
    YAOGUANG_SPEED_GROUND = 1,
    YAOGUANG_SPEED_AIR = 2,
    YAOGUANG_DIRECTION_TRACK = 1,
    YAOGUANG_DIRECTION_MAGNETIC_HEADING = 2,
    YAOGUANG_ALTITUDE_BAROMETRIC = 1,
    YAOGUANG_ALTITUDE_GNSS = 2
};

typedef struct {
    uint32_t icao24;
    uint32_t fields;
    uint8_t callsign_len;
    uint8_t speed_kind;
    uint8_t direction_kind;
    uint8_t altitude_kind;
    double speed_kt;
    double direction_deg;
    int32_t altitude_ft;
    int16_t vertical_rate_fpm;
    uint16_t reserved;
    uint8_t reserved_callsign_storage[8];
    float signal_dbfs;
} YaoguangUpdate;

uint32_t yaoguang_abi_version(void);
YaoguangHandle *yaoguang_start(void);

/* Returns 2 when ready, 1 for an update, 0 when empty, -1 for invalid args, -2 on error. */
int32_t yaoguang_poll_update(
    YaoguangHandle *handle,
    YaoguangUpdate *output,
    char *callsign_buffer,
    size_t callsign_capacity
);

/* Returns required UTF-8 byte count excluding NUL; copies a truncated NUL-terminated string. */
size_t yaoguang_last_error(YaoguangHandle *handle, char *output, size_t capacity);

/* Stops the receiver and releases handle. Do not reuse the handle after this call. */
void yaoguang_stop(YaoguangHandle *handle);

#ifdef __cplusplus
}
#endif

#endif /* YAOGUANG_H */
