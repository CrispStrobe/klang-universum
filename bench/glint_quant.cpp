// bench/glint_quant.cpp — file-driven dump of glint's quantize_granule output.
//
// Reads exactly 576 doubles (one per line) from <mdct_file> — the SAME
// mdct_flat[576] the Dart port feeds its quantizer — runs glint's real
// quantizer/psycho/NMR loop, and dumps the full GranuleInfo. Used to freeze
// golden fixtures for a stage-by-stage A/B against the pure-Dart port, with
// zero front-end drift (identical input both sides).
//
//   glint_quant <mdct_file> <gr_bits> [quality=2] [block_type=0] > gi.txt
#include "quantize.hpp"
#include "tables.hpp"
#include <cstdio>
#include <cstdlib>
using namespace glint;

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr, "usage: glint_quant <mdct_file> <gr_bits> [q=2] [bt=0]\n");
    return 2;
  }
  glint::tables::init_tables();
  const char* path = argv[1];
  int grBits = atoi(argv[2]);
  int quality = argc > 3 ? atoi(argv[3]) : 2;
  int blockType = argc > 4 ? atoi(argv[4]) : 0;

  double mdct[576];
  FILE* f = fopen(path, "r");
  if (!f) { fprintf(stderr, "cannot open %s\n", path); return 1; }
  for (int i = 0; i < 576; i++) {
    if (fscanf(f, "%lf", &mdct[i]) != 1) {
      fprintf(stderr, "short read at %d\n", i); return 1;
    }
  }
  fclose(f);

  GranuleInfo gi = quantize_granule(mdct, grBits, /*sr_index=*/0, quality,
                                    blockType, /*gain_floor=*/0,
                                    /*allow_psy=*/true, false, false);
  printf("global_gain %d\n", gi.global_gain);
  printf("rc_gain %d\n", gi.rc_gain);
  printf("scalefac_compress %d\n", gi.scalefac_compress);
  printf("scalefac_scale %d\n", gi.scalefac_scale);
  printf("preflag %d\n", gi.preflag);
  printf("part2_3_length %d\n", gi.part2_3_length);
  printf("part2_length %d\n", gi.part2_length);
  printf("block_type %d\n", gi.block_type);
  printf("big_values %d\n", gi.regions.big_values);
  printf("region0_count %d\n", gi.regions.region0_count);
  printf("region1_count %d\n", gi.regions.region1_count);
  printf("table0 %d\n", gi.regions.table_select[0]);
  printf("table1 %d\n", gi.regions.table_select[1]);
  printf("table2 %d\n", gi.regions.table_select[2]);
  printf("count1table %d\n", gi.regions.count1table);
  for (int i = 0; i < 21; i++) printf("sf%d %d\n", i, gi.scalefac[i]);
  printf("ix");
  for (int i = 0; i < 576; i++) printf(" %d", (int)gi.ix[i]);
  printf("\n");
  return 0;
}
