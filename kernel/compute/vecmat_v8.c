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

/* ═══════════════════════════════════════════════════════════════════
 * V30.GEMMA3 Path A: C bypass for numerical hot-path functions.
 *
 * Fajar Lang's LLVM O2 codegen is sensitive to code context —
 * the same source produces different numerical results depending on
 * whether FJTRACE emit calls are present (changes register allocation
 * and instruction scheduling). Moving these functions to gcc-compiled
 * C makes the results deterministic regardless of FJTRACE state.
 * ═══════════════════════════════════════════════════════════════════ */

/* ── Integer square root (Newton's method) ─────────────────────── */
static int64_t c_isqrt(int64_t x) {
    if (x <= 0) return 1;
    if (x == 1) return 1;
    int64_t guess = x / 2;
    if (guess == 0) return 1;
    int64_t prev = guess + 1;
    while (guess < prev) {
        prev = guess;
        guess = (guess + x / guess) / 2;
    }
    return prev == 0 ? 1 : prev;
}

/* ── Piecewise tanh approximation (×1000 fixed-point) ──────────── */
static int64_t c_tanh_approx(int64_t x) {
    if (x > 2500) return 1000;
    if (x > 1500) return 900 + (x - 1500) / 10;
    if (x > 500)  return 500 + (x - 500) * 400 / 1000;
    if (x > -500) return x;
    if (x > -1500) return -500 + (x + 500) * 400 / 1000;
    if (x > -2500) return -900 + (x + 1500) / 10;
    return -1000;
}

/* ── Exponential lookup tables ──────────────────────────────────── */
static int64_t c_exp_pos_lookup(int64_t q) {
    static const int64_t tbl[] = {1000, 2718, 7389, 20086, 54598, 148413};
    return (q >= 0 && q <= 5) ? tbl[q] : 148413;
}

static int64_t c_exp_neg_lookup(int64_t q) {
    static const int64_t tbl[] = {1000, 368, 135, 50, 18, 7, 2, 1};
    return (q >= 0 && q <= 7) ? tbl[q] : 1;
}

static int64_t c_exp_approx(int64_t x) {
    if (x > 5000) return 148413;
    if (x < -7000) return 0;
    if (x >= 0) {
        int64_t q = x / 1000;
        int64_t r = x - q * 1000;
        int64_t base = c_exp_pos_lookup(q);
        int64_t frac = 1000 + r + (r * r) / 2000;
        return (base * frac) / 1000;
    }
    int64_t abs_x = -x;
    int64_t q = abs_x / 1000;
    int64_t r = abs_x - q * 1000;
    int64_t base = c_exp_neg_lookup(q);
    int64_t frac = 1000 - r + (r * r) / 2000;
    int64_t result = (base * frac) / 1000;
    return result < 1 ? 1 : result;
}

/* ── km_rmsnorm ────────────────────────────────────────────────── */
/* Mailbox at 0xBEA200:
 *   +0: data_addr (i64)
 *   +8: dim       (i64)
 *  +16: gamma_addr (i64, 0 = no gamma)
 *  +24: gamma_mode (i64, 0 = Gemma (1+g), 1 = Llama (g))
 */
#define RMSNORM_MAILBOX (MAILBOX_ADDR + 0x200ULL)

void km_rmsnorm_c_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)RMSNORM_MAILBOX;
    int64_t data_addr  = mb[0];
    int64_t dim        = mb[1];
    int64_t gamma_addr = mb[2];
    int64_t gamma_mode = mb[3];

    if (dim <= 0 || dim > 8192) return;
    if (data_addr <= 0 || data_addr > 0x40000000LL) return;

    int64_t *data = (int64_t *)(uintptr_t)data_addr;
    const int64_t *gamma = gamma_addr ? (const int64_t *)(uintptr_t)gamma_addr : 0;

    /* Pass 1: find max|x| */
    int64_t max_abs = 0;
    for (int64_t i = 0; i < dim; i++) {
        int64_t x = data[i];
        int64_t ax = x < 0 ? -x : x;
        if (ax > max_abs) max_abs = ax;
    }
    if (max_abs <= 0) return;

    int64_t k_scale = 10000;

    /* Pass 2: accumulate rescaled sum-of-squares / dim */
    int64_t rss = 0;
    for (int64_t i = 0; i < dim; i++) {
        int64_t x_rs = data[i] * k_scale / max_abs;
        rss += (x_rs * x_rs) / dim;
    }

    int64_t rms_rs = c_isqrt(rss + 1);
    if (rms_rs <= 0) return;

    /* Pass 3: normalize and apply gamma */
    for (int64_t i = 0; i < dim; i++) {
        int64_t x_rs = data[i] * k_scale / max_abs;
        int64_t normed = (x_rs * 1000) / rms_rs;
        if (gamma) {
            int64_t g = gamma[i];
            if (gamma_mode == 1) {
                data[i] = (normed * g) / 1000;
            } else {
                data[i] = (normed * (1000 + g)) / 1000;
            }
        } else {
            data[i] = normed;
        }
    }
}

/* ── km_gelu_tanh ──────────────────────────────────────────────── */
/* Mailbox at 0xBEA280:
 *   +0: data_addr (i64)
 *   +8: dim       (i64)
 */
#define GELU_MAILBOX (MAILBOX_ADDR + 0x280ULL)

void km_gelu_tanh_c_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)GELU_MAILBOX;
    int64_t data_addr = mb[0];
    int64_t dim       = mb[1];

    int64_t *data = (int64_t *)(uintptr_t)data_addr;

    for (int64_t i = 0; i < dim; i++) {
        int64_t x = data[i];
        int64_t x2 = (x * x) / 1000;
        int64_t x3 = (x2 * x) / 1000;
        int64_t inner = (798 * (x + (45 * x3) / 1000)) / 1000;
        int64_t t = c_tanh_approx(inner);
        data[i] = (x * (1000 + t)) / 2000;
    }
}

/* ── km_add_raw ────────────────────────────────────────────────── */
/* Mailbox at 0xBEA300:
 *   +0: a_addr (i64)  — modified in-place: a[i] += b[i]
 *   +8: b_addr (i64)
 *  +16: dim    (i64)
 */
#define ADD_MAILBOX (MAILBOX_ADDR + 0x300ULL)

void km_add_raw_c_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)ADD_MAILBOX;
    int64_t a_addr = mb[0];
    int64_t b_addr = mb[1];
    int64_t dim    = mb[2];

    int64_t *a = (int64_t *)(uintptr_t)a_addr;
    const int64_t *b = (const int64_t *)(uintptr_t)b_addr;

    for (int64_t i = 0; i < dim; i++) {
        a[i] += b[i];
    }
}

/* ── km_mul_raw ────────────────────────────────────────────────── */
/* Mailbox at 0xBEA340:
 *   +0: a_addr (i64)  — modified in-place: a[i] = a[i]*b[i]/1000
 *   +8: b_addr (i64)
 *  +16: dim    (i64)
 */
#define MUL_MAILBOX (MAILBOX_ADDR + 0x340ULL)

void km_mul_raw_c_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)MUL_MAILBOX;
    int64_t a_addr = mb[0];
    int64_t b_addr = mb[1];
    int64_t dim    = mb[2];

    int64_t *a = (int64_t *)(uintptr_t)a_addr;
    const int64_t *b = (const int64_t *)(uintptr_t)b_addr;

    for (int64_t i = 0; i < dim; i++) {
        a[i] = (a[i] * b[i]) / 1000;
    }
}
