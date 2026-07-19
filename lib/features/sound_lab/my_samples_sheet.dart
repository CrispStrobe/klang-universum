// The shared "My Samples" browser over [SampleClipStore].
//
// The library is filled from several places — the Voice Lab saves a shaped
// voice, the Sample Extractor adds samples lifted out of modules and packs —
// so browsing it belongs in one reusable sheet rather than re-implemented per
// screen. Preview and delete work everywhere; whether tapping a row PICKS the
// clip is up to the host (the Voice Lab loads it, the Extractor just manages).

import 'package:comet_beat/core/services/audio_service.dart';
import 'package:comet_beat/features/sound_lab/sample_clip_store.dart';
import 'package:comet_beat/l10n/app_localizations.dart';
import 'package:comet_beat/shared/music_io/audio_export.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shows the library. Resolves to the picked clip, or null (cancelled, or the
/// sheet was opened with [pickable] false).
Future<SampleClip?> showMySamplesSheet(
  BuildContext context, {
  SampleClipStore? store,
  bool pickable = true,
}) {
  return showModalBottomSheet<SampleClip>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => MySamplesSheet(
      store: store ?? SampleClipStore(),
      pickable: pickable,
    ),
  );
}

/// Test seam — drive the sheet without tapping through the UI.
abstract class MySamplesTester {
  List<SampleClip> get clips;
  Future<void> deleteAt(int index);
}

@visibleForTesting
class MySamplesSheet extends StatefulWidget {
  const MySamplesSheet({
    required this.store,
    this.pickable = true,
    super.key,
  });

  final SampleClipStore store;
  final bool pickable;

  @override
  State<MySamplesSheet> createState() => _MySamplesSheetState();
}

class _MySamplesSheetState extends State<MySamplesSheet>
    implements MySamplesTester {
  List<SampleClip> _clips = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((list) {
      if (mounted) {
        setState(() {
          _clips = list;
          _loading = false;
        });
      }
    });
  }

  @override
  List<SampleClip> get clips => _clips;

  @override
  Future<void> deleteAt(int index) async {
    final list = await widget.store.delete(_clips[index].name);
    if (mounted) setState(() => _clips = list);
  }

  void _preview(SampleClip clip) {
    if (clip.pcm.isEmpty) return;
    context.read<AudioService>().playWavBytes(
          pcmFloatToWav(clip.pcm, sampleRate: clip.sampleRate),
        );
  }

  String _duration(SampleClip clip) {
    if (clip.sampleRate <= 0) return '';
    return '${(clip.pcm.length / clip.sampleRate).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.bookmarks_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.mySamplesTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (_clips.isNotEmpty)
                    Text(
                      '${_clips.length}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _clips.isEmpty && !_loading
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.mySamplesEmpty,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _clips.length,
                      itemBuilder: (ctx, i) {
                        final clip = _clips[i];
                        final detail = [
                          if (clip.source != null) clip.source!,
                          _duration(clip),
                        ].where((s) => s.isNotEmpty).join(' · ');
                        return ListTile(
                          leading: const Icon(Icons.graphic_eq),
                          title: Text(clip.name),
                          subtitle: detail.isEmpty ? null : Text(detail),
                          onTap: widget.pickable
                              ? () => Navigator.of(context).pop(clip)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow),
                                tooltip: l10n.mySamplesPreview,
                                onPressed: () => _preview(clip),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: l10n.mySamplesDelete,
                                onPressed: () => deleteAt(i),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
