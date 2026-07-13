// miniaudio_impl.c — the single translation unit that compiles miniaudio.
//
// MA_IMPLEMENTATION must appear in exactly one TU; everywhere else (aec_shim.c)
// includes miniaudio.h for declarations only. We trim the parts we don't use
// (decoding/encoding/resource manager/node graph) to keep the compile fast and
// the binary small — the duplex device path stays intact.
//
// miniaudio is MIT-0 (see LICENSES/miniaudio.txt), so bundling it keeps the
// tree MIT-clean.

#define MA_IMPLEMENTATION
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#include "vendor/miniaudio.h"
