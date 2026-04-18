/* V30 P3.6: C vecmat with mailbox calling convention + AVX2.
 * Non-volatile data reads allow gcc to vectorize the inner loop. */
#include <stdint.h>

#define MAILBOX_ADDR 0xBEA000ULL
#define V8_GROUP_SHIFT 7
#define V8_SCALE_FP 1000000LL

/* Non-volatile reads for DATA (weight bytes, input vector).
 * These are safe because the data doesn't change during the vecmat. */
static inline uint8_t rd8(uint64_t a) { return *(const uint8_t*)(uintptr_t)a; }
static inline int64_t rd64(uint64_t a) { return *(const int64_t*)(uintptr_t)a; }
static inline void wr64(uint64_t a, int64_t v) { *(int64_t*)(uintptr_t)a = v; }

static inline int64_t ru32(uint64_t a) {
    return (int64_t)(*(const uint32_t*)(uintptr_t)a);
}

/* Mailbox layout for lmhead argmax (at MAILBOX_ADDR + 0x100):
 *   +0: x_addr       (i64)
 *   +8: embed_base   (i64) = STREAM_EMBED_BASE
 *  +16: vocab_size   (i64)
 *  +24: d_model      (i64)
 * Returns: best_token stored at MAILBOX_ADDR + 0x100 + 32
 */
#define LMHEAD_MAILBOX (MAILBOX_ADDR + 0x100ULL)

void mdl_lmhead_argmax_v8_tied_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)LMHEAD_MAILBOX;
    int64_t x_addr     = mb[0];
    int64_t embed_base = mb[1];
    int64_t vocab_size = mb[2];
    int64_t d_model    = mb[3];

    int64_t total = vocab_size * d_model;
    int64_t packed_bytes = total / 2;
    int64_t n_groups = (total + 127) >> V8_GROUP_SHIFT;
    int64_t scales_base = embed_base + packed_bytes;
    int64_t zeros_base = scales_base + n_groups * 4;

    const uint8_t *packed = (const uint8_t *)(uintptr_t)embed_base;
    const uint32_t *scales = (const uint32_t *)(uintptr_t)scales_base;
    const uint8_t *zeros_arr = (const uint8_t *)(uintptr_t)zeros_base;
    const int64_t *x = (const int64_t *)(uintptr_t)x_addr;

    int64_t best_token = 0;
    int64_t best_score = -999999999LL;

    for (int64_t v = 0; v < vocab_size; v++) {
        int64_t row_start = v * d_model;
        int64_t sum = 0;
        for (int64_t i = 0; i < d_model; i++) {
            int64_t fi = row_start + i;
            uint8_t raw = packed[fi >> 1];
            int64_t q = (raw >> ((fi & 1) * 4)) & 15;
            int64_t g = fi >> V8_GROUP_SHIFT;
            int64_t scale = (int64_t)scales[g];
            int64_t zero = (int64_t)zeros_arr[g];
            int64_t w = (q - zero) * scale;
            sum += (x[i] * w) / V8_SCALE_FP;
        }
        if (sum > best_score) {
            best_score = sum;
            best_token = v;
        }
    }

    /* Return best_token + best_score via mailbox */
    mb[4] = best_token;
    mb[5] = best_score;
}

void km_vecmat_packed_v8_mailbox(void)
{
    /* Read args from mailbox (volatile — FJ just wrote them) */
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)MAILBOX_ADDR;
    int64_t x_addr   = mb[0];
    int64_t mat_addr  = mb[1];
    int64_t m         = mb[2];
    int64_t n         = mb[3];
    int64_t out_addr  = mb[4];

    int64_t total = m * n;
    int64_t packed_bytes = total / 2;
    int64_t n_groups = (total + 127) >> V8_GROUP_SHIFT;
    int64_t scales_base = mat_addr + packed_bytes;
    int64_t zeros_base = scales_base + n_groups * 4;

    const uint8_t *packed = (const uint8_t*)(uintptr_t)mat_addr;
    const uint32_t *scales = (const uint32_t*)(uintptr_t)scales_base;
    const uint8_t *zeros = (const uint8_t*)(uintptr_t)zeros_base;
    const int64_t *x = (const int64_t*)(uintptr_t)x_addr;
    int64_t *out = (int64_t*)(uintptr_t)out_addr;

    for (int64_t j = 0; j < n; j++) {
        int64_t sum = 0;
        for (int64_t k = 0; k < m; k++) {
            int64_t fi = k * n + j;
            uint8_t raw = packed[fi >> 1];
            int64_t q = (raw >> ((fi & 1) * 4)) & 15;
            int64_t g = fi >> V8_GROUP_SHIFT;
            int64_t scale = (int64_t)scales[g];
            int64_t zero = (int64_t)zeros[g];
            int64_t w = (q - zero) * scale;
            int64_t v = x[k];
            sum += (v * w) / V8_SCALE_FP;
        }
        out[j] = sum;
    }
}
