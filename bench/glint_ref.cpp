#include "subband.hpp"
#include "mdct.hpp"
#include "tables.hpp"
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
