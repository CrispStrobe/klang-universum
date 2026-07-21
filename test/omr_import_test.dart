// OMR app-side glue: the dialect router (tokens → Score) and the image decoder
// (encoded bytes → OmrImage). Pure — no native library, no model.

import 'dart:typed_data';

import 'package:comet_beat/features/workshop/omr/omr_import.dart';
import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  int noteCount(Score s) =>
      s.measures.expand((m) => m.elements).whereType<NoteElement>().length;

  group('omrTokensToScore routes by dialect', () {
    test('SMT bekern tokens → a Score with notes', () {
      // A minimal single-spine bekern data stream (digit-first, <t>/<b> markers).
      const bekern = '**kern <b> 4 c <b> 4 d <b> 4 e <b> 4 f <b> *-';
      final score = omrTokensToScore(bekern);
      expect(noteCount(score), greaterThan(0));
    });

    test('TrOMR semantic tokens → a Score with notes', () {
      // TrOMR emits a `+`-joined semantic stream.
      const semantic = 'clef-G2+keySignature-CM+timeSignature-4/4+'
          'note-C4_quarter+note-D4_quarter+note-E4_quarter+note-F4_quarter+'
          'barline';
      final score = omrTokensToScore(semantic);
      expect(omrDialectOf(semantic), OmrDialect.semantic);
      expect(noteCount(score), greaterThan(0));
    });

    test('Flova lilyNotes tokens → a Score with notes', () {
      const lily = "c'4 d'4 e'4 f'4";
      final score = omrTokensToScore(lily);
      expect(omrDialectOf(lily), OmrDialect.lilyNotes);
      expect(noteCount(score), greaterThan(0));
    });
  });

  group('imageBytesToOmr', () {
    test('decodes a PNG into a single-channel OmrImage of the right size', () {
      final src = img.Image(width: 8, height: 5);
      img.fill(src, color: img.ColorRgb8(255, 255, 255));
      final png = Uint8List.fromList(img.encodePng(src));

      final omr = imageBytesToOmr(png);
      expect(omr, isNotNull);
      expect(omr!.width, 8);
      expect(omr.height, 5);
      expect(omr.channels, 1);
      expect(omr.pixels.length, 8 * 5);
      expect(omr.pixels.first, 255); // white
    });

    test('returns null for bytes that are not an image', () {
      expect(imageBytesToOmr(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });

  group('omrImageToScore (image + engine → Score)', () {
    Uint8List whitePng() {
      final src = img.Image(width: 8, height: 5);
      img.fill(src, color: img.ColorRgb8(255, 255, 255));
      return Uint8List.fromList(img.encodePng(src));
    }

    test('decodes the image, recognises, and routes tokens to a Score',
        () async {
      final score = await omrImageToScore(
        whitePng(),
        engine: const _FakeOmr('**kern <b> 4 c <b> 4 d <b> 4 e <b> *-'),
      );
      expect(score, isNotNull);
      expect(noteCount(score!), greaterThan(0));
    });

    test('an undecodable image returns null without touching the engine',
        () async {
      final engine = _RecordingOmr();
      final score = await omrImageToScore(
        Uint8List.fromList([1, 2, 3, 4]),
        engine: engine,
      );
      expect(score, isNull);
      expect(engine.called, isFalse);
    });

    test('empty recognition output returns null (not an empty score)',
        () async {
      final score =
          await omrImageToScore(whitePng(), engine: const _FakeOmr('   '));
      expect(score, isNull);
    });
  });
}

class _FakeOmr implements OmrEngine {
  const _FakeOmr(this.tokens);
  final String tokens;
  @override
  Future<String> recognize(OmrImage image) async => tokens;
}

class _RecordingOmr implements OmrEngine {
  bool called = false;
  @override
  Future<String> recognize(OmrImage image) async {
    called = true;
    return '';
  }
}
