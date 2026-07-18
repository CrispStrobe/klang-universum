#include "subband.hpp"
#include "mdct.hpp"
#include "tables.hpp"
#include "quantize.hpp"
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <chrono>
using namespace glint;

static uint32_t g_s = 0x12345u;
static inline double next_sample() {
  g_s = (uint32_t)(g_s * 1664525u + 1013904223u);
  return ((double)((g_s >> 8) & 0xFFFFu) / 65536.0) * 2.0 - 1.0;
}

int main(int argc, char** argv) {
  glint::tables::init_tables();
  int G = argc > 1 ? atoi(argv[1]) : 3000;
  const char* out = argc > 2 ? argv[2] : "ref.txt";
  const int W = 5;
  SubbandAnalysis sb; MDCT mdct;
  double sbout[32][36];   // analyze_float writes [32][kTimeSlots=36]
  double subband[32][18], mdctout[32][18];

  auto do_granule = [&](){
    float pcm[576];
    for (int i=0;i<576;i++) pcm[i] = (float)next_sample();
    sb.analyze_float(pcm, sbout, 18);
    for (int b=0;b<32;b++) for (int n=0;n<18;n++) subband[b][n]=sbout[b][n];
    mdct.process(subband, mdctout);
    alias_reduce_d(mdctout);
  };

  for (int gr=0; gr<W; gr++) do_granule();
  do_granule();
  FILE* f = fopen(out, "w");
  for (int b=0;b<32;b++) for (int n=0;n<18;n++) fprintf(f, "%.17g\n", subband[b][n]);
  for (int b=0;b<32;b++) for (int n=0;n<18;n++) fprintf(f, "%.17g\n", mdctout[b][n]);

  // --- Stage A/B: feed the SAME mdct_flat[576] (band-major, = &mdct_out[0][0]
  // for long blocks, encoder.cpp:1547) to glint's psycho + quantizer, dump the
  // full GranuleInfo so the Dart port can be compared field-by-field. ---
  double mdct_flat[576];
  for (int b=0;b<32;b++) for (int n=0;n<18;n++) mdct_flat[b*18+n] = mdctout[b][n];
  // NB: glint's REAL masking model lives inside quantize.cpp (compute_src_band
  // -> get_mask_model -> compute_band_masks); PsychoModel in psycho.cpp is dead
  // code. Those are file-static, so we observe the loop at its public output
  // boundary: the full GranuleInfo from quantize_granule (below).

  // Quantize a long block at a fixed per-granule budget, quality=best(2).
  const int kGrBits = argc > 3 ? atoi(argv[3]) : 1584;
  GranuleInfo gi = quantize_granule(mdct_flat, kGrBits, /*sr_index=*/0,
                                    /*quality_mode=*/2, /*block_type=*/0,
                                    /*gain_floor=*/0, /*allow_psy=*/true,
                                    false, false);
  fprintf(f, "GRBITS %d\n", kGrBits);
  fprintf(f, "global_gain %d\n", gi.global_gain);
  fprintf(f, "rc_gain %d\n", gi.rc_gain);
  fprintf(f, "scalefac_compress %d\n", gi.scalefac_compress);
  fprintf(f, "scalefac_scale %d\n", gi.scalefac_scale);
  fprintf(f, "preflag %d\n", gi.preflag);
  fprintf(f, "part2_3_length %d\n", gi.part2_3_length);
  fprintf(f, "part2_length %d\n", gi.part2_length);
  fprintf(f, "block_type %d\n", gi.block_type);
  fprintf(f, "big_values %d\n", gi.regions.big_values);
  fprintf(f, "region0_count %d\n", gi.regions.region0_count);
  fprintf(f, "region1_count %d\n", gi.regions.region1_count);
  fprintf(f, "table0 %d\n", gi.regions.table_select[0]);
  fprintf(f, "table1 %d\n", gi.regions.table_select[1]);
  fprintf(f, "table2 %d\n", gi.regions.table_select[2]);
  fprintf(f, "count1table %d\n", gi.regions.count1table);
  for (int i=0;i<21;i++) fprintf(f, "sf%d %d\n", i, gi.scalefac[i]);
  for (int i=0;i<576;i++) fprintf(f, "%d\n", (int)gi.ix[i]);
  fclose(f);

  sb.reset(); mdct.reset(); g_s=0x12345u;
  auto t0=std::chrono::high_resolution_clock::now();
  volatile double acc=0;
  for (int gr=0; gr<G; gr++) { do_granule(); acc += mdctout[0][0]; }
  auto t1=std::chrono::high_resolution_clock::now();
  double ms = std::chrono::duration<double,std::milli>(t1-t0).count();
  fprintf(stderr, "GLINT_BENCH granules=%d ms=%.3f granules_per_s=%.0f acc=%g\n",
          G, ms, G/(ms/1000.0), (double)acc);
  return 0;
}
