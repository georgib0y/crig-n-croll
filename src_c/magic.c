#include "magic.h"
#include "board.h"
/* #include <assert.h> */
/* #include <stdbool.h> */

/* typedef unsigned long long uint64_t; */

static BB bishop_move_table[64][512];
static BB rook_move_table[64][4096];

// magics generated previously from rook and roll
static struct SquareMagic rook_magics[64] = {
    {0x40800022400A1080, 0x101010101017e},
    {0x420401001E800, 0x202020202027c},
    {0x100402000110005, 0x404040404047a},
    {0x4288002010500008, 0x8080808080876},
    {0x60400200040001C0, 0x1010101010106e},
    {0x50001000208C400, 0x2020202020205e},
    {0x1008240803000840, 0x4040404040403e},
    {0x2000044018A2201, 0x8080808080807e},
    {0x70401040042000, 0x1010101017e00},
    {0x2882030131020803, 0x2020202027c00},
    {0x4A00100850800, 0x4040404047a00},
    {0x205400400400840, 0x8080808087600},
    {0x3012000401100620, 0x10101010106e00},
    {0x80104200008404, 0x20202020205e00},
    {0x148325380100, 0x40404040403e00},
    {0x8000120222408100, 0x80808080807e00},
    {0x8484821011400400, 0x10101017e0100},
    {0x8204044020203000, 0x20202027c0200},
    {0x88020300A0010004, 0x40404047a0400},
    {0x4120200102024280, 0x8080808760800},
    {0x100200092408044C, 0x101010106e1000},
    {0x80208014010000C0, 0x202020205e2000},
    {0x1000820820040, 0x404040403e4000},
    {0x10600A000401100, 0x808080807e8000},
    {0x4824080013020, 0x101017e010100},
    {0x8010200008844040, 0x202027c020200},
    {0x41000424044040, 0x404047a040400},
    {0x1C08008012400220, 0x8080876080800},
    {0x2200200041200, 0x1010106e101000},
    {0x1040049088460400, 0x2020205e202000},
    {0x218C4800412A0, 0x4040403e404000},
    {0x2009A008004080, 0x8080807e808000},
    {0x80010200A40808, 0x1017e01010100},
    {0x2010004801200092, 0x2027c02020200},
    {0x220B02004040005, 0x4047a04040400},
    {0xC00080080801000, 0x8087608080800},
    {0x3002110400080044, 0x10106e10101000},
    {0x40002021110C2, 0x20205e20202000},
    {0x2010081042009104, 0x40403e40404000},
    {0x460802000480104, 0x80807e80808000},
    {0x5441020100202800, 0x17e0101010100},
    {0x800810221160400, 0x27c0202020200},
    {0x1084200E0008, 0x47a0404040400},
    {0x10281003010002, 0x8760808080800},
    {0x2204004081000800, 0x106e1010101000},
    {0x1803204140100400, 0x205e2020202000},
    {0x840B002110024, 0x403e4040404000},
    {0x201805082220001, 0x807e8080808000},
    {0x7324118001006208, 0x7e010101010100},
    {0x1012402001830004, 0x7c020202020200},
    {0x100E000806002020, 0x7a040404040400},
    {0xA0201408020200, 0x76080808080800},
    {0x110100802110018, 0x6e101010101000},
    {0x30001800080, 0x5e202020202000},
    {0x2280005200911080, 0x3e404040404000},
    {0x101024220108008, 0x7e808080808000},
    {0x2000800100402011, 0x7e01010101010100},
    {0x11020080400A, 0x7c02020202020200},
    {0x200200044184111A, 0x7a04040404040400},
    {0x68900A0004121036, 0x7608080808080800},
    {0x600900100380083, 0x6e10101010101000},
    {0x8001000400020481, 0x5e20202020202000},
    {0x60068802491402, 0x3e40404040404000},
    {0x8000010038804402, 0x7e80808080808000}};

static struct SquareMagic bishop_magics[64] = {
    {0x2140004101030008, 0x40201008040200},
    {0xA30208100100420, 0x402010080400},
    {0x102028202000101, 0x4020100A00},
    {0x141104008002500, 0x40221400},
    {0x6008142001A8002A, 0x2442800},
    {0x81402400A8300, 0x204085000},
    {0x20904410420020, 0x20408102000},
    {0x8048108804202010, 0x2040810204000},
    {0x8001480520440080, 0x20100804020000},
    {0x108920168001080, 0x40201008040000},
    {0x10821401002208, 0x4020100A0000},
    {0x9004100D000, 0x4022140000},
    {0x80A00444804C6010, 0x244280000},
    {0x8004020200240001, 0x20408500000},
    {0x10000882002A0A48, 0x2040810200000},
    {0x2000100220681412, 0x4081020400000},
    {0x2240800700410, 0x10080402000200},
    {0x38080020401082, 0x20100804000400},
    {0x12C0920100410100, 0x4020100A000A00},
    {0x220100404288000, 0x402214001400},
    {0x24009A00850000, 0x24428002800},
    {0x2422000040100180, 0x2040850005000},
    {0x322C010022820040, 0x4081020002000},
    {0x89040C010040, 0x8102040004000},
    {0x400602001022230, 0x8040200020400},
    {0x401008000128006C, 0x10080400040800},
    {0x421004420080, 0x20100A000A1000},
    {0xA420202008008020, 0x40221400142200},
    {0x1010120104000, 0x2442800284400},
    {0x8881480000882C0, 0x4085000500800},
    {0x860112C112104108, 0x8102000201000},
    {0x10A1082042000420, 0x10204000402000},
    {0x100248104100684, 0x4020002040800},
    {0x214188200A00640, 0x8040004081000},
    {0x4881008210820, 0x100A000A102000},
    {0x2000280800020A00, 0x22140014224000},
    {0x40008201610104, 0x44280028440200},
    {0x2004093020001220, 0x8500050080400},
    {0x81004501000800C, 0x10200020100800},
    {0x234841900C081016, 0x20400040201000},
    {0x704009221000402, 0x2000204081000},
    {0x4540380010000214, 0x4000408102000},
    {0x2030082000040, 0xA000A10204000},
    {0x8050808104093, 0x14001422400000},
    {0x101188107464808, 0x28002844020000},
    {0x5041020802400802, 0x50005008040200},
    {0x4010B44808850040, 0x20002010080400},
    {0x10100040088000E0, 0x40004020100800},
    {0x84C010108010, 0x20408102000},
    {0x800488140100, 0x40810204000},
    {0x1000028020218440, 0xA1020400000},
    {0x5010048A06220000, 0x142240000000},
    {0x8001040812041000, 0x284402000000},
    {0x1840026008109400, 0x500804020000},
    {0x1046002206001882, 0x201008040200},
    {0x20204400D84000, 0x402010080400},
    {0x1270C20060804000, 0x2040810204000},
    {0x2000021113042200, 0x4081020400000},
    {0x40002412282008A, 0xA102040000000},
    {0xC000000041100, 0x14224000000000},
    {0x1000200060005104, 0x28440200000000},
    {0x1840042164280880, 0x50080402000000},
    {0x964AD0002100AA00, 0x20100804020000},
    {0x2190900041002410, 0x40201008040200}};

// code to generate magics from
// https://www.chessprogramming.org/Looking_for_Magics

int count_1s(uint64_t b) {
  int r;
  for (r = 0; b; r++, b &= b - 1)
    ;
  return r;
}

const int BitTable[64] = {63, 30, 3,  32, 25, 41, 22, 33, 15, 50, 42, 13, 11,
                          53, 19, 34, 61, 29, 2,  51, 21, 43, 45, 10, 18, 47,
                          1,  54, 9,  57, 0,  35, 62, 31, 40, 4,  49, 5,  52,
                          26, 60, 6,  23, 44, 46, 27, 56, 16, 7,  39, 48, 24,
                          59, 14, 12, 55, 38, 28, 58, 20, 37, 17, 36, 8};

int pop_1st_bit(uint64_t *bb) {
  uint64_t b = *bb ^ (*bb - 1);
  unsigned int fold = (unsigned)((b & 0xffffffff) ^ (b >> 32));
  *bb &= (*bb - 1);
  return BitTable[(fold * 0x783a9b23) >> 26];
}

uint64_t index_to_uint64_t(int index, int bits, uint64_t m) {
  int i, j;
  uint64_t result = 0ULL;
  for (i = 0; i < bits; i++) {
    j = pop_1st_bit(&m);
    if (index & (1 << i))
      result |= (1ULL << j);
  }
  return result;
}

uint64_t rmask(int sq) {
  uint64_t result = 0ULL;
  int rk = sq / 8, fl = sq % 8, r, f;
  for (r = rk + 1; r <= 6; r++)
    result |= (1ULL << (fl + r * 8));
  for (r = rk - 1; r >= 1; r--)
    result |= (1ULL << (fl + r * 8));
  for (f = fl + 1; f <= 6; f++)
    result |= (1ULL << (f + rk * 8));
  for (f = fl - 1; f >= 1; f--)
    result |= (1ULL << (f + rk * 8));
  return result;
}

uint64_t bmask(int sq) {
  uint64_t result = 0ULL;
  int rk = sq / 8, fl = sq % 8, r, f;
  for (r = rk + 1, f = fl + 1; r <= 6 && f <= 6; r++, f++)
    result |= (1ULL << (f + r * 8));
  for (r = rk + 1, f = fl - 1; r <= 6 && f >= 1; r++, f--)
    result |= (1ULL << (f + r * 8));
  for (r = rk - 1, f = fl + 1; r >= 1 && f <= 6; r--, f++)
    result |= (1ULL << (f + r * 8));
  for (r = rk - 1, f = fl - 1; r >= 1 && f >= 1; r--, f--)
    result |= (1ULL << (f + r * 8));
  return result;
}

uint64_t ratt(int sq, uint64_t block) {
  uint64_t result = 0ULL;
  int rk = sq / 8, fl = sq % 8, r, f;
  for (r = rk + 1; r <= 7; r++) {
    result |= (1ULL << (fl + r * 8));
    if (block & (1ULL << (fl + r * 8)))
      break;
  }
  for (r = rk - 1; r >= 0; r--) {
    result |= (1ULL << (fl + r * 8));
    if (block & (1ULL << (fl + r * 8)))
      break;
  }
  for (f = fl + 1; f <= 7; f++) {
    result |= (1ULL << (f + rk * 8));
    if (block & (1ULL << (f + rk * 8)))
      break;
  }
  for (f = fl - 1; f >= 0; f--) {
    result |= (1ULL << (f + rk * 8));
    if (block & (1ULL << (f + rk * 8)))
      break;
  }
  return result;
}

uint64_t batt(int sq, uint64_t block) {
  uint64_t result = 0ULL;
  int rk = sq / 8, fl = sq % 8, r, f;
  for (r = rk + 1, f = fl + 1; r <= 7 && f <= 7; r++, f++) {
    result |= (1ULL << (f + r * 8));
    if (block & (1ULL << (f + r * 8)))
      break;
  }
  for (r = rk + 1, f = fl - 1; r <= 7 && f >= 0; r++, f--) {
    result |= (1ULL << (f + r * 8));
    if (block & (1ULL << (f + r * 8)))
      break;
  }
  for (r = rk - 1, f = fl + 1; r >= 0 && f <= 7; r--, f++) {
    result |= (1ULL << (f + r * 8));
    if (block & (1ULL << (f + r * 8)))
      break;
  }
  for (r = rk - 1, f = fl - 1; r >= 0 && f >= 0; r--, f--) {
    result |= (1ULL << (f + r * 8));
    if (block & (1ULL << (f + r * 8)))
      break;
  }
  return result;
}

int transform(uint64_t b, uint64_t magic, int bits) {
  return (int)((b * magic) >> (64 - bits));
}

void populate_move_table(BB move_table[], struct SquareMagic m, int sq,
                         int shift, bool is_bishop) {
  BB occs[4096], atts[4096];

  int bits = count_1s(m.mask);

  for (int i = 0; i < (1 << bits); i++) {
    occs[i] = index_to_uint64_t(i, bits, m.mask);
    atts[i] = is_bishop ? batt(sq, occs[i]) : ratt(sq, occs[i]);
  }

  for (int i = 0; i < (1 << bits); i++) {
    move_table[i] = 0;
  }

  for (int i = 0; i < (1 << bits); i++) {
    int idx = transform(occs[i], m.magic, shift);
    move_table[idx] = atts[i];
  }
}

void init_magics(void) {
  for (int sq = 0; sq < 64; sq++) {
    populate_move_table(rook_move_table[sq], rook_magics[sq], sq, ROOK_SHIFT,
                        false);
    populate_move_table(bishop_move_table[sq], bishop_magics[sq], sq,
                        BISHOP_SHIFT, true);
  }
}

BB lookup_bishop(BB occ, int sq) {
  occ &= bishop_magics[sq].mask;
  occ *= bishop_magics[sq].magic;
  occ >>= 64 - BISHOP_SHIFT;
  return bishop_move_table[sq][occ];
}

BB lookup_bishop_xray(BB occ, BB blockers, int sq) {
  BB atts = lookup_bishop(occ, sq);
  blockers &= atts;
  return atts ^ lookup_bishop(occ ^ blockers, sq);
}

BB lookup_rook(BB occ, int sq) {
  occ &= rook_magics[sq].mask;
  occ *= rook_magics[sq].magic;
  occ >>= 64 - ROOK_SHIFT;
  return rook_move_table[sq][occ];
}

BB lookup_rook_xray(BB occ, BB blockers, int sq) {
  BB atts = lookup_rook(occ, sq);
  blockers &= atts;
  return atts ^ lookup_rook(occ ^ blockers, sq);
}

BB lookup_queen(BB occ, int sq) {
  return lookup_bishop(occ, sq) | lookup_rook(occ, sq);
}

BB rook_mask(int sq) { return rook_magics[sq].mask; }

BB bishop_mask(int sq) { return bishop_magics[sq].mask; }
