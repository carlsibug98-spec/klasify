import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// A golden-file comparator that tolerates a small fraction of differing
/// pixels so goldens recorded on one platform still match on another.
///
/// Font rasterisation drifts between platforms (DirectWrite on Windows vs
/// FreeType on Linux anti-alias glyph edges slightly differently), which
/// shows up as ~0.7–3% of pixels differing while the layout is identical.
/// The stock [LocalFileComparator] requires a bit-exact match, so a suite
/// recorded on Windows can never run green on Linux — the app README
/// documents exactly this caveat.
///
/// Everything else stays strict:
/// - Image sizes must match. A size change is a layout regression, not
///   antialiasing, and always fails.
/// - The differing-pixel fraction must stay within [maxDiffPercent]. Whole
///   regions moving (wrong colour, missing widget, shifted block) land far
///   above the threshold and still fail, with the standard master / masked
///   / isolated diff images written under `test/failures`.
class TolerantLocalFileComparator extends LocalFileComparator {
  TolerantLocalFileComparator(super.testFile);

  /// Fraction of pixels allowed to differ (0.05 = 5%). Observed
  /// cross-platform drift on this suite is 0.71–3.81% (worst: the
  /// text-heavy onboarding pages); the isolated diff images confirm every
  /// differing pixel sits on a glyph edge. Real regressions (wrong colour,
  /// missing widget, shifted block) move whole regions and land far above.
  static const double maxDiffPercent = 0.05;

  /// Builds the comparator for the calling test file. [anchor] must be the
  /// test's own file name: the default comparator only exposes its basedir,
  /// and goldens resolve relative to that directory, so anchoring on the
  /// test file keeps the same lookup paths as the stock comparator.
  static TolerantLocalFileComparator forTest(
    LocalFileComparator current,
    String anchor,
  ) {
    return TolerantLocalFileComparator(current.basedir.resolve(anchor));
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    // Same engine the stock comparator uses: full per-pixel diff, sizes
    // checked first, exact-zero pass. Only the final verdict relaxes.
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );

    if (result.passed) {
      result.dispose();
      return true;
    }

    final bool sizeMismatch =
        result.error != null && result.error!.contains('sizes do not match');
    final bool withinTolerance =
        !sizeMismatch && result.diffPercent <= maxDiffPercent;
    if (withinTolerance) {
      result.dispose();
      return true;
    }

    // Over tolerance (or a size mismatch): fail with the standard output,
    // which writes the diff artefacts under test/failures for inspection.
    final String error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
