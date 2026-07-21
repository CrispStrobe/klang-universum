// Web / no-dart:io fallback: no CrispASR tab FFI. Signature matches the IO impl.

import 'package:comet_beat/features/games/composition/tab_emission_decoder.dart'
    show TabEmissionModel;

Future<TabEmissionModel?> crispasrFfiTab({bool download = false}) async => null;
