/* V30 P3.6: C vecmat with mailbox calling convention + AVX2.
 * Non-volatile data reads allow gcc to vectorize the inner loop. */
#include <stdint.h>

#define MAILBOX_ADDR 0xBEA000ULL
#define V8_GROUP_SHIFT 7
#define V8_SCALE_FP 1000000LL

/* Forward declarations for functions defined later in this file */
static int64_t c_isqrt(int64_t x);

/* Read embed_bits directly from kernel model header.
 * MDL_HDR_BASE (0xC00000) + FJM_OFF_EMBED_BITS (144) = 0xC00090.
 * This is a u32 field set during model-load. */
static inline int64_t get_model_embed_bits(void) {
    return (int64_t)(*(const uint32_t *)(uintptr_t)0xC00090ULL);
}

/* ── Embedding lookup (C bypass for 8-bit LLVM O2 sensitivity) ───── */
/* Mailbox at 0xBEA500:
 *   +0: token_id (i64)
 *   +8: out_addr (i64)
 *  +16: embed_base (i64) = STREAM_EMBED_BASE
 *  +24: vocab_size (i64)
 *  +32: d_model (i64)
 */
#define EMBED_MAILBOX (MAILBOX_ADDR + 0x500ULL)

void mdl_embed_lookup_c_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)EMBED_MAILBOX;
    int64_t token_id   = mb[0];
    int64_t out_addr   = mb[1];
    int64_t embed_base = mb[2];
    int64_t vocab_size = mb[3];
    int64_t d_model    = mb[4];
    int64_t model_type = mb[5];  /* 10/11 = Gemma 3 (apply sqrt scaling) */
    int64_t bits       = get_model_embed_bits();

    if (token_id < 0 || token_id >= vocab_size) return;

    int64_t total = vocab_size * d_model;
    int64_t packed_bytes = (bits == 8) ? total : total / 2;
    int64_t n_groups = (total + 127) >> V8_GROUP_SHIFT;
    int64_t scales_base = embed_base + packed_bytes;
    int64_t zeros_base = scales_base + n_groups * 4;

    const uint8_t *packed = (const uint8_t *)(uintptr_t)embed_base;
    const uint32_t *scales = (const uint32_t *)(uintptr_t)scales_base;
    const uint8_t *zeros_arr = (const uint8_t *)(uintptr_t)zeros_base;
    int64_t *out = (int64_t *)(uintptr_t)out_addr;
    int64_t row_start = token_id * d_model;

    if (bits == 8) {
        for (int64_t i = 0; i < d_model; i++) {
            int64_t fi = row_start + i;
            int64_t q = packed[fi];
            int64_t g = fi >> V8_GROUP_SHIFT;
            int64_t scale = (int64_t)scales[g];
            int64_t zero = (int64_t)zeros_arr[g];
            out[i] = ((q - zero) * scale) / 1000;
        }
    } else {
        for (int64_t i = 0; i < d_model; i++) {
            int64_t fi = row_start + i;
            uint8_t raw = packed[fi >> 1];
            int64_t q = (raw >> ((fi & 1) * 4)) & 15;
            int64_t g = fi >> V8_GROUP_SHIFT;
            int64_t scale = (int64_t)scales[g];
            int64_t zero = (int64_t)zeros_arr[g];
            out[i] = ((q - zero) * scale) / 1000;
        }
    }

    /* Gemma 3 embed scaling: x *= sqrt(d_model).
     * HF reference: Gemma3TextModel.forward scales by hidden_size**0.5.
     * sqrt(1152) * 1000 = 33941 in x1000 fixed-point.
     * Apply only for Gemma 3 models (type 10/11). */
    if (model_type == 10 || model_type == 11) {
        int64_t scale_x1000 = c_isqrt(d_model * 1000000);
        for (int64_t i = 0; i < d_model; i++) {
            out[i] = (out[i] * scale_x1000) / 1000;
        }
    }
}

/* ── RoPE: Rotary Position Embedding (C bypass) ──────────────────── */
/* V31.A.P1 (H3 precision hypothesis): replace Bhaskara I sin approx
 * (0.16% error) with a millisecond-resolution LUT at x10000 scale
 * (~0.01% error). Downstream multipliers in the mailbox divide by
 * 10000 instead of 1000. Table size = 1572 * 2 bytes = 3 KB.
 * Reason: cumulative RoPE rotation error compounds across 26 layers;
 * tighter per-op precision is the only way to isolate H3 from H1/H2/H4. */
#define ROPE_PI_MRAD 3142
#define ROPE_TWO_PI_MRAD 6283

static const int16_t c_rope_sin_lut_x10000[1572] = {
        0,    10,    20,    30,    40,    50,    60,    70,    80,    90, 
      100,   110,   120,   130,   140,   150,   160,   170,   180,   190, 
      200,   210,   220,   230,   240,   250,   260,   270,   280,   290, 
      300,   310,   320,   330,   340,   350,   360,   370,   380,   390, 
      400,   410,   420,   430,   440,   450,   460,   470,   480,   490, 
      500,   510,   520,   530,   540,   550,   560,   570,   580,   590, 
      600,   610,   620,   630,   640,   650,   660,   669,   679,   689, 
      699,   709,   719,   729,   739,   749,   759,   769,   779,   789, 
      799,   809,   819,   829,   839,   849,   859,   869,   879,   889, 
      899,   909,   919,   929,   939,   949,   959,   968,   978,   988, 
      998,  1008,  1018,  1028,  1038,  1048,  1058,  1068,  1078,  1088, 
     1098,  1108,  1118,  1128,  1138,  1147,  1157,  1167,  1177,  1187, 
     1197,  1207,  1217,  1227,  1237,  1247,  1257,  1267,  1277,  1286, 
     1296,  1306,  1316,  1326,  1336,  1346,  1356,  1366,  1376,  1386, 
     1395,  1405,  1415,  1425,  1435,  1445,  1455,  1465,  1475,  1484, 
     1494,  1504,  1514,  1524,  1534,  1544,  1554,  1564,  1573,  1583, 
     1593,  1603,  1613,  1623,  1633,  1643,  1652,  1662,  1672,  1682, 
     1692,  1702,  1712,  1721,  1731,  1741,  1751,  1761,  1771,  1780, 
     1790,  1800,  1810,  1820,  1830,  1839,  1849,  1859,  1869,  1879, 
     1889,  1898,  1908,  1918,  1928,  1938,  1947,  1957,  1967,  1977, 
     1987,  1996,  2006,  2016,  2026,  2036,  2045,  2055,  2065,  2075, 
     2085,  2094,  2104,  2114,  2124,  2133,  2143,  2153,  2163,  2173, 
     2182,  2192,  2202,  2212,  2221,  2231,  2241,  2251,  2260,  2270, 
     2280,  2290,  2299,  2309,  2319,  2328,  2338,  2348,  2358,  2367, 
     2377,  2387,  2396,  2406,  2416,  2426,  2435,  2445,  2455,  2464, 
     2474,  2484,  2493,  2503,  2513,  2522,  2532,  2542,  2551,  2561, 
     2571,  2580,  2590,  2600,  2609,  2619,  2629,  2638,  2648,  2658, 
     2667,  2677,  2687,  2696,  2706,  2715,  2725,  2735,  2744,  2754, 
     2764,  2773,  2783,  2792,  2802,  2812,  2821,  2831,  2840,  2850, 
     2860,  2869,  2879,  2888,  2898,  2907,  2917,  2927,  2936,  2946, 
     2955,  2965,  2974,  2984,  2993,  3003,  3012,  3022,  3032,  3041, 
     3051,  3060,  3070,  3079,  3089,  3098,  3108,  3117,  3127,  3136, 
     3146,  3155,  3165,  3174,  3184,  3193,  3203,  3212,  3222,  3231, 
     3240,  3250,  3259,  3269,  3278,  3288,  3297,  3307,  3316,  3325, 
     3335,  3344,  3354,  3363,  3373,  3382,  3391,  3401,  3410,  3420, 
     3429,  3438,  3448,  3457,  3467,  3476,  3485,  3495,  3504,  3513, 
     3523,  3532,  3541,  3551,  3560,  3569,  3579,  3588,  3598,  3607, 
     3616,  3625,  3635,  3644,  3653,  3663,  3672,  3681,  3691,  3700, 
     3709,  3718,  3728,  3737,  3746,  3756,  3765,  3774,  3783,  3793, 
     3802,  3811,  3820,  3830,  3839,  3848,  3857,  3867,  3876,  3885, 
     3894,  3903,  3913,  3922,  3931,  3940,  3949,  3959,  3968,  3977, 
     3986,  3995,  4004,  4014,  4023,  4032,  4041,  4050,  4059,  4068, 
     4078,  4087,  4096,  4105,  4114,  4123,  4132,  4141,  4151,  4160, 
     4169,  4178,  4187,  4196,  4205,  4214,  4223,  4232,  4241,  4250, 
     4259,  4268,  4277,  4287,  4296,  4305,  4314,  4323,  4332,  4341, 
     4350,  4359,  4368,  4377,  4386,  4395,  4404,  4413,  4422,  4431, 
     4439,  4448,  4457,  4466,  4475,  4484,  4493,  4502,  4511,  4520, 
     4529,  4538,  4547,  4556,  4564,  4573,  4582,  4591,  4600,  4609, 
     4618,  4627,  4636,  4644,  4653,  4662,  4671,  4680,  4689,  4697, 
     4706,  4715,  4724,  4733,  4742,  4750,  4759,  4768,  4777,  4785, 
     4794,  4803,  4812,  4821,  4829,  4838,  4847,  4856,  4864,  4873, 
     4882,  4890,  4899,  4908,  4917,  4925,  4934,  4943,  4951,  4960, 
     4969,  4977,  4986,  4995,  5003,  5012,  5021,  5029,  5038,  5047, 
     5055,  5064,  5073,  5081,  5090,  5098,  5107,  5116,  5124,  5133, 
     5141,  5150,  5159,  5167,  5176,  5184,  5193,  5201,  5210,  5218, 
     5227,  5235,  5244,  5252,  5261,  5269,  5278,  5286,  5295,  5303, 
     5312,  5320,  5329,  5337,  5346,  5354,  5363,  5371,  5379,  5388, 
     5396,  5405,  5413,  5422,  5430,  5438,  5447,  5455,  5463,  5472, 
     5480,  5489,  5497,  5505,  5514,  5522,  5530,  5539,  5547,  5555, 
     5564,  5572,  5580,  5589,  5597,  5605,  5613,  5622,  5630,  5638, 
     5646,  5655,  5663,  5671,  5679,  5688,  5696,  5704,  5712,  5720, 
     5729,  5737,  5745,  5753,  5761,  5770,  5778,  5786,  5794,  5802, 
     5810,  5818,  5827,  5835,  5843,  5851,  5859,  5867,  5875,  5883, 
     5891,  5900,  5908,  5916,  5924,  5932,  5940,  5948,  5956,  5964, 
     5972,  5980,  5988,  5996,  6004,  6012,  6020,  6028,  6036,  6044, 
     6052,  6060,  6068,  6076,  6084,  6092,  6100,  6107,  6115,  6123, 
     6131,  6139,  6147,  6155,  6163,  6171,  6178,  6186,  6194,  6202, 
     6210,  6218,  6226,  6233,  6241,  6249,  6257,  6265,  6272,  6280, 
     6288,  6296,  6303,  6311,  6319,  6327,  6334,  6342,  6350,  6358, 
     6365,  6373,  6381,  6388,  6396,  6404,  6412,  6419,  6427,  6435, 
     6442,  6450,  6457,  6465,  6473,  6480,  6488,  6496,  6503,  6511, 
     6518,  6526,  6533,  6541,  6549,  6556,  6564,  6571,  6579,  6586, 
     6594,  6601,  6609,  6616,  6624,  6631,  6639,  6646,  6654,  6661, 
     6669,  6676,  6684,  6691,  6698,  6706,  6713,  6721,  6728,  6735, 
     6743,  6750,  6758,  6765,  6772,  6780,  6787,  6794,  6802,  6809, 
     6816,  6824,  6831,  6838,  6846,  6853,  6860,  6867,  6875,  6882, 
     6889,  6896,  6904,  6911,  6918,  6925,  6933,  6940,  6947,  6954, 
     6961,  6969,  6976,  6983,  6990,  6997,  7004,  7011,  7019,  7026, 
     7033,  7040,  7047,  7054,  7061,  7068,  7075,  7082,  7089,  7096, 
     7104,  7111,  7118,  7125,  7132,  7139,  7146,  7153,  7160,  7167, 
     7174,  7181,  7187,  7194,  7201,  7208,  7215,  7222,  7229,  7236, 
     7243,  7250,  7257,  7264,  7270,  7277,  7284,  7291,  7298,  7305, 
     7311,  7318,  7325,  7332,  7339,  7345,  7352,  7359,  7366,  7373, 
     7379,  7386,  7393,  7400,  7406,  7413,  7420,  7426,  7433,  7440, 
     7446,  7453,  7460,  7466,  7473,  7480,  7486,  7493,  7500,  7506, 
     7513,  7519,  7526,  7533,  7539,  7546,  7552,  7559,  7565,  7572, 
     7578,  7585,  7591,  7598,  7604,  7611,  7617,  7624,  7630,  7637, 
     7643,  7650,  7656,  7663,  7669,  7675,  7682,  7688,  7695,  7701, 
     7707,  7714,  7720,  7726,  7733,  7739,  7745,  7752,  7758,  7764, 
     7771,  7777,  7783,  7790,  7796,  7802,  7808,  7815,  7821,  7827, 
     7833,  7839,  7846,  7852,  7858,  7864,  7870,  7877,  7883,  7889, 
     7895,  7901,  7907,  7913,  7920,  7926,  7932,  7938,  7944,  7950, 
     7956,  7962,  7968,  7974,  7980,  7986,  7992,  7998,  8004,  8010, 
     8016,  8022,  8028,  8034,  8040,  8046,  8052,  8058,  8064,  8070, 
     8076,  8081,  8087,  8093,  8099,  8105,  8111,  8117,  8123,  8128, 
     8134,  8140,  8146,  8152,  8157,  8163,  8169,  8175,  8180,  8186, 
     8192,  8198,  8203,  8209,  8215,  8220,  8226,  8232,  8238,  8243, 
     8249,  8255,  8260,  8266,  8271,  8277,  8283,  8288,  8294,  8299, 
     8305,  8311,  8316,  8322,  8327,  8333,  8338,  8344,  8349,  8355, 
     8360,  8366,  8371,  8377,  8382,  8388,  8393,  8398,  8404,  8409, 
     8415,  8420,  8425,  8431,  8436,  8442,  8447,  8452,  8458,  8463, 
     8468,  8474,  8479,  8484,  8490,  8495,  8500,  8505,  8511,  8516, 
     8521,  8526,  8532,  8537,  8542,  8547,  8552,  8558,  8563,  8568, 
     8573,  8578,  8583,  8588,  8594,  8599,  8604,  8609,  8614,  8619, 
     8624,  8629,  8634,  8639,  8644,  8649,  8654,  8659,  8664,  8669, 
     8674,  8679,  8684,  8689,  8694,  8699,  8704,  8709,  8714,  8719, 
     8724,  8728,  8733,  8738,  8743,  8748,  8753,  8758,  8762,  8767, 
     8772,  8777,  8782,  8786,  8791,  8796,  8801,  8805,  8810,  8815, 
     8820,  8824,  8829,  8834,  8838,  8843,  8848,  8852,  8857,  8862, 
     8866,  8871,  8876,  8880,  8885,  8889,  8894,  8898,  8903,  8908, 
     8912,  8917,  8921,  8926,  8930,  8935,  8939,  8944,  8948,  8953, 
     8957,  8961,  8966,  8970,  8975,  8979,  8984,  8988,  8992,  8997, 
     9001,  9005,  9010,  9014,  9018,  9023,  9027,  9031,  9036,  9040, 
     9044,  9048,  9053,  9057,  9061,  9065,  9070,  9074,  9078,  9082, 
     9086,  9091,  9095,  9099,  9103,  9107,  9111,  9115,  9119,  9124, 
     9128,  9132,  9136,  9140,  9144,  9148,  9152,  9156,  9160,  9164, 
     9168,  9172,  9176,  9180,  9184,  9188,  9192,  9196,  9200,  9204, 
     9208,  9211,  9215,  9219,  9223,  9227,  9231,  9235,  9238,  9242, 
     9246,  9250,  9254,  9257,  9261,  9265,  9269,  9272,  9276,  9280, 
     9284,  9287,  9291,  9295,  9298,  9302,  9306,  9309,  9313,  9317, 
     9320,  9324,  9328,  9331,  9335,  9338,  9342,  9346,  9349,  9353, 
     9356,  9360,  9363,  9367,  9370,  9374,  9377,  9381,  9384,  9388, 
     9391,  9394,  9398,  9401,  9405,  9408,  9411,  9415,  9418,  9422, 
     9425,  9428,  9432,  9435,  9438,  9441,  9445,  9448,  9451,  9455, 
     9458,  9461,  9464,  9468,  9471,  9474,  9477,  9480,  9484,  9487, 
     9490,  9493,  9496,  9499,  9502,  9505,  9509,  9512,  9515,  9518, 
     9521,  9524,  9527,  9530,  9533,  9536,  9539,  9542,  9545,  9548, 
     9551,  9554,  9557,  9560,  9563,  9566,  9569,  9572,  9574,  9577, 
     9580,  9583,  9586,  9589,  9592,  9594,  9597,  9600,  9603,  9606, 
     9608,  9611,  9614,  9617,  9619,  9622,  9625,  9628,  9630,  9633, 
     9636,  9638,  9641,  9644,  9646,  9649,  9651,  9654,  9657,  9659, 
     9662,  9664,  9667,  9670,  9672,  9675,  9677,  9680,  9682,  9685, 
     9687,  9690,  9692,  9695,  9697,  9699,  9702,  9704,  9707,  9709, 
     9711,  9714,  9716,  9719,  9721,  9723,  9726,  9728,  9730,  9733, 
     9735,  9737,  9739,  9742,  9744,  9746,  9748,  9751,  9753,  9755, 
     9757,  9759,  9762,  9764,  9766,  9768,  9770,  9772,  9774,  9777, 
     9779,  9781,  9783,  9785,  9787,  9789,  9791,  9793,  9795,  9797, 
     9799,  9801,  9803,  9805,  9807,  9809,  9811,  9813,  9815,  9817, 
     9819,  9820,  9822,  9824,  9826,  9828,  9830,  9832,  9833,  9835, 
     9837,  9839,  9841,  9842,  9844,  9846,  9848,  9849,  9851,  9853, 
     9854,  9856,  9858,  9860,  9861,  9863,  9865,  9866,  9868,  9869, 
     9871,  9873,  9874,  9876,  9877,  9879,  9880,  9882,  9883,  9885, 
     9887,  9888,  9890,  9891,  9892,  9894,  9895,  9897,  9898,  9900, 
     9901,  9902,  9904,  9905,  9907,  9908,  9909,  9911,  9912,  9913, 
     9915,  9916,  9917,  9918,  9920,  9921,  9922,  9923,  9925,  9926, 
     9927,  9928,  9930,  9931,  9932,  9933,  9934,  9935,  9936,  9938, 
     9939,  9940,  9941,  9942,  9943,  9944,  9945,  9946,  9947,  9948, 
     9949,  9950,  9951,  9952,  9953,  9954,  9955,  9956,  9957,  9958, 
     9959,  9960,  9961,  9961,  9962,  9963,  9964,  9965,  9966,  9967, 
     9967,  9968,  9969,  9970,  9971,  9971,  9972,  9973,  9974,  9974, 
     9975,  9976,  9976,  9977,  9978,  9978,  9979,  9980,  9980,  9981, 
     9982,  9982,  9983,  9983,  9984,  9984,  9985,  9986,  9986,  9987, 
     9987,  9988,  9988,  9989,  9989,  9990,  9990,  9990,  9991,  9991, 
     9992,  9992,  9992,  9993,  9993,  9994,  9994,  9994,  9995,  9995, 
     9995,  9996,  9996,  9996,  9996,  9997,  9997,  9997,  9997,  9998, 
     9998,  9998,  9998,  9998,  9999,  9999,  9999,  9999,  9999,  9999, 
     9999, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 10000, 
    10000, 10000 
};

/* LUT lookup — returns x10000 scale (vs Bhaskara's x1000).
 * x must be in [0, ROPE_PI_MRAD/2] = [0, 1571]. */
static int64_t c_rope_sin_q1(int64_t x) {
    if (x < 0) return 0;
    if (x >= 1572) return 10000;  /* clamp: should not happen post-mod */
    return (int64_t)c_rope_sin_lut_x10000[x];
}

static int64_t c_rope_sin(int64_t angle) {
    int64_t raw = angle % ROPE_TWO_PI_MRAD;
    int64_t a = (raw < 0) ? raw + ROPE_TWO_PI_MRAD : raw;
    int64_t hpi = ROPE_PI_MRAD / 2;
    if (a <= hpi)                    return  c_rope_sin_q1(a);
    if (a <= ROPE_PI_MRAD)           return  c_rope_sin_q1(ROPE_PI_MRAD - a);
    if (a <= ROPE_PI_MRAD + hpi)     return -c_rope_sin_q1(a - ROPE_PI_MRAD);
    return -c_rope_sin_q1(ROPE_TWO_PI_MRAD - a);
}

static int64_t c_rope_cos(int64_t angle) {
    return c_rope_sin(angle + ROPE_PI_MRAD / 2);
}


/* Mailbox at 0xBEA600:
 *   +0: q_data    (i64)
 *   +8: k_data    (i64)
 *  +16: pos       (i64)
 *  +24: n_heads   (i64)
 *  +32: n_kv_heads(i64)
 *  +40: d_head    (i64)
 *  +48: freq_base (i64, address of inv_freq table)
 */
#define ROPE_MAILBOX (MAILBOX_ADDR + 0x600ULL)

void tfm_rope_apply_c_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)ROPE_MAILBOX;
    int64_t q_data     = mb[0];
    int64_t k_data     = mb[1];
    int64_t pos        = mb[2];
    int64_t n_heads    = mb[3];
    int64_t n_kv_heads = mb[4];
    int64_t d_head     = mb[5];
    int64_t freq_base  = mb[6];

    int64_t n_pairs = d_head / 2;
    const int64_t *freq = (const int64_t *)(uintptr_t)freq_base;

    /* V31.A.P1: cos/sin now x10000 scale → divide by 10000. */
    /* Apply to each Q head */
    for (int64_t h = 0; h < n_heads; h++) {
        int64_t *data = (int64_t *)(uintptr_t)(q_data + h * d_head * 8);
        for (int64_t i = 0; i < n_pairs; i++) {
            int64_t angle = pos * freq[i];
            int64_t cos_a = c_rope_cos(angle);
            int64_t sin_a = c_rope_sin(angle);
            int64_t x0 = data[2 * i];
            int64_t x1 = data[2 * i + 1];
            data[2 * i]     = (x0 * cos_a - x1 * sin_a) / 10000;
            data[2 * i + 1] = (x0 * sin_a + x1 * cos_a) / 10000;
        }
    }
    /* Apply to each KV head */
    for (int64_t h = 0; h < n_kv_heads; h++) {
        int64_t *data = (int64_t *)(uintptr_t)(k_data + h * d_head * 8);
        for (int64_t i = 0; i < n_pairs; i++) {
            int64_t angle = pos * freq[i];
            int64_t cos_a = c_rope_cos(angle);
            int64_t sin_a = c_rope_sin(angle);
            int64_t x0 = data[2 * i];
            int64_t x1 = data[2 * i + 1];
            data[2 * i]     = (x0 * cos_a - x1 * sin_a) / 10000;
            data[2 * i + 1] = (x0 * sin_a + x1 * cos_a) / 10000;
        }
    }
}

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
    int64_t bits       = get_model_embed_bits();

    int64_t total = vocab_size * d_model;
    int64_t packed_bytes = (bits == 8) ? total : total / 2;
    int64_t n_groups = (total + 127) >> V8_GROUP_SHIFT;
    int64_t scales_base = embed_base + packed_bytes;
    int64_t zeros_base = scales_base + n_groups * 4;

    const uint8_t *packed = (const uint8_t *)(uintptr_t)embed_base;
    const uint32_t *scales = (const uint32_t *)(uintptr_t)scales_base;
    const uint8_t *zeros_arr = (const uint8_t *)(uintptr_t)zeros_base;
    const int64_t *x = (const int64_t *)(uintptr_t)x_addr;

    int64_t best_token = 0;
    int64_t best_score = -999999999LL;

    /* Gemma 3 vocab: 255902 real tokens + 6242 <unused> entries.
     * Quantization noise on untrained <unused> weights produces
     * spuriously high scores, drowning out the correct answer.
     * Mask to real tokens only (0..255901). */
    int64_t effective_vocab = vocab_size < 255902 ? vocab_size : 255902;

    if (bits == 8) {
        /* 8-bit: direct byte read, no nibble unpacking */
        for (int64_t v = 0; v < effective_vocab; v++) {
            int64_t row_start = v * d_model;
            int64_t sum = 0;
            for (int64_t i = 0; i < d_model; i++) {
                int64_t fi = row_start + i;
                int64_t q = packed[fi];
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
    } else {
        /* 4-bit: nibble unpacking */
        for (int64_t v = 0; v < effective_vocab; v++) {
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
    int64_t bits      = get_model_embed_bits();

    int64_t total = m * n;
    int64_t packed_bytes = (bits == 8) ? total : total / 2;
    int64_t n_groups = (total + 127) >> V8_GROUP_SHIFT;
    int64_t scales_base = mat_addr + packed_bytes;
    int64_t zeros_base = scales_base + n_groups * 4;

    const uint8_t *packed = (const uint8_t*)(uintptr_t)mat_addr;
    const uint32_t *scales = (const uint32_t*)(uintptr_t)scales_base;
    const uint8_t *zeros = (const uint8_t*)(uintptr_t)zeros_base;
    const int64_t *x = (const int64_t*)(uintptr_t)x_addr;
    int64_t *out = (int64_t*)(uintptr_t)out_addr;

    if (bits == 8) {
        /* 8-bit: direct byte read */
        for (int64_t j = 0; j < n; j++) {
            int64_t sum = 0;
            for (int64_t k = 0; k < m; k++) {
                int64_t fi = k * n + j;
                int64_t q = packed[fi];
                int64_t g = fi >> V8_GROUP_SHIFT;
                int64_t scale = (int64_t)scales[g];
                int64_t zero = (int64_t)zeros[g];
                int64_t w = (q - zero) * scale;
                sum += (x[k] * w) / V8_SCALE_FP;
            }
            out[j] = sum;
        }
    } else {
        /* 4-bit: nibble unpacking */
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
                sum += (x[k] * w) / V8_SCALE_FP;
            }
            out[j] = sum;
        }
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

/* ── tfm_attention scoring + softmax + V weighted sum ──────────── */
/* Mailbox at 0xBEA400:
 *   +0:  q_data          (i64, query vector addr)
 *   +8:  out_data        (i64, output vector addr)
 *  +16:  kv_layer_off    (i64, KV cache base for this layer)
 *  +24:  n_heads         (i64)
 *  +32:  n_kv_heads      (i64)
 *  +40:  d_head          (i64)
 *  +48:  attn_start      (i64)
 *  +56:  attn_len        (i64)
 *  +64:  attn_scale      (i64)
 *  +72:  scores_addr     (i64, TFM_SCRATCH)
 *  +80:  kv_pos_stride   (i64)
 *  +88:  kv_d            (i64, n_kv_heads * d_head)
 */
#define ATTN_MAILBOX (MAILBOX_ADDR + 0x400ULL)

void tfm_attention_score_c_mailbox(void)
{
    volatile int64_t *mb = (volatile int64_t *)(uintptr_t)ATTN_MAILBOX;
    const int64_t *q_data     = (const int64_t *)(uintptr_t)mb[0];
    int64_t *out_data         = (int64_t *)(uintptr_t)mb[1];
    int64_t  kv_layer_off     = mb[2];
    int64_t  n_heads          = mb[3];
    int64_t  n_kv_heads       = mb[4];
    int64_t  d_head           = mb[5];
    int64_t  attn_start       = mb[6];
    int64_t  attn_len         = mb[7];
    int64_t  attn_scale       = mb[8];
    int64_t *scores           = (int64_t *)(uintptr_t)mb[9];
    int64_t  kv_pos_stride    = mb[10];
    int64_t  kv_d             = mb[11];

    int64_t heads_per_kv = n_heads / n_kv_heads;
    int64_t seq_len = attn_start + attn_len;

    for (int64_t h = 0; h < n_heads; h++) {
        int64_t q_head_off = h * d_head;
        int64_t kv_head = h / heads_per_kv;
        int64_t kv_head_off = kv_head * d_head;

        /* Dot-product scoring: Q · K for each position */
        for (int64_t si = 0; si < attn_len; si++) {
            int64_t p = attn_start + si;
            const int64_t *k_cache = (const int64_t *)(uintptr_t)(
                kv_layer_off + p * kv_pos_stride);
            int64_t dot = 0;
            for (int64_t d = 0; d < d_head; d++) {
                int64_t qi = q_data[q_head_off + d];
                int64_t ki = k_cache[kv_head_off + d];
                dot += (qi * ki) / 1000;
            }
            scores[si] = (dot * attn_scale) / 1000;
        }

        /* Softmax: max → exp → normalize */
        int64_t max_score = scores[0];
        for (int64_t si = 1; si < attn_len; si++) {
            if (scores[si] > max_score) max_score = scores[si];
        }
        int64_t exp_sum = 0;
        for (int64_t si = 0; si < attn_len; si++) {
            int64_t e = c_exp_approx(scores[si] - max_score);
            scores[si] = e;
            exp_sum += e;
        }
        if (exp_sum > 0) {
            for (int64_t si = 0; si < attn_len; si++) {
                scores[si] = (scores[si] * 1000) / exp_sum;
            }
        }

        /* Weighted sum of V */
        for (int64_t d = 0; d < d_head; d++) {
            int64_t weighted = 0;
            for (int64_t si = 0; si < attn_len; si++) {
                int64_t p = attn_start + si;
                const int64_t *v_cache = (const int64_t *)(uintptr_t)(
                    kv_layer_off + p * kv_pos_stride + kv_d * 8);
                weighted += (scores[si] * v_cache[kv_head_off + d]) / 1000;
            }
            out_data[q_head_off + d] = weighted;
        }
    }
}
