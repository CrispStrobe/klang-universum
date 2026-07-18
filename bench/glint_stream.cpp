// bench/glint_stream.cpp — dump glint's streaming mdct_flat for a chosen
// granule, to compare against the Dart encoder's streaming forward transform
// (the golden test only pins ONE warmup granule; this checks later ones).
//
//   glint_stream <raw_f32_mono> <granuleIndex> > mdct_flat.txt
#include "subband.hpp"
#include "mdct.hpp"
#include "tables.hpp"
#include <cstdio>
#include <cstdlib>
#include <vector>
using namespace glint;

int main(int argc, char** argv) {
  if (argc < 3) { fprintf(stderr, "usage: glint_stream raw.f32 gran\n"); return 2; }
  glint::tables::init_tables();
  int target = atoi(argv[2]);

  FILE* f = fopen(argv[1], "rb");
  std::vector<float> pcm;
  float v;
  while (fread(&v, 4, 1, f) == 1) pcm.push_back(v);
  fclose(f);

  SubbandAnalysis sb; MDCT mdct;
  double sbout[32][36];
  double subband[32][18], mdctout[32][18];
  int nGran = (int)pcm.size() / 576;
  for (int g = 0; g <= target && g < nGran; g++) {
    sb.analyze_float(&pcm[g * 576], sbout, 18);
    for (int b = 0; b < 32; b++) for (int n = 0; n < 18; n++)
      subband[b][n] = sbout[b][n];
    mdct.process(subband, mdctout);
    alias_reduce_d(mdctout);
    if (g == target) {
      for (int b = 0; b < 32; b++) for (int n = 0; n < 18; n++)
        printf("%.17g\n", mdctout[b][n]);
    }
  }
  return 0;
}
