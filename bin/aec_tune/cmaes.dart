// bin/aec_tune/cmaes.dart
//
// A compact separable CMA-ES (Covariance Matrix Adaptation Evolution Strategy;
// Hansen & Ostermeier 2001, with the diagonal-covariance simplification of Ros
// & Hansen 2008). CMA-ES is the standard derivative-free optimizer for exactly
// this shape of problem: a handful of continuous parameters, a noisy black-box
// objective, no gradient. The SEPARABLE variant keeps the covariance diagonal —
// a per-coordinate variance vector instead of a full matrix — so it needs no
// eigendecomposition and stays a few dozen lines of pure Dart, at the cost of
// not modelling correlations between parameters (fine here: the AEC knobs are
// roughly independent).
//
// The implementation is verified against known test functions (sphere,
// Rosenbrock) in test/cmaes_test.dart — the objective transcription is not
// something to take on faith, so a separate ground-truth check pins it.
//
// This minimizes; callers maximizing a score pass its negation.

import 'dart:math';

/// Result of a run: the best point found and its objective value.
class CmaesResult {
  CmaesResult(this.best, this.bestValue, this.generations, this.evaluations);
  final List<double> best;
  final double bestValue;
  final int generations;
  final int evaluations;
}

/// Minimize [f] over [dim] dimensions, starting from [initialMean] with initial
/// step [sigma0]. Runs until [maxEvals] objective evaluations or [tol]
/// stagnation. [rng] seeds sampling for reproducibility.
CmaesResult cmaesMinimize(
  double Function(List<double>) f, {
  required List<double> initialMean,
  double sigma0 = 0.3,
  int maxEvals = 600,
  double tol = 1e-6,
  Random? rng,
}) {
  final random = rng ?? Random(12345);
  final n = initialMean.length;

  // Selection & recombination.
  final lambda = 4 + (3 * log(n)).floor(); // offspring per generation
  final mu = lambda ~/ 2; // parents
  final weights = List<double>.generate(
    mu,
    (i) => log(mu + 0.5) - log(i + 1.0),
  );
  final wSum = weights.reduce((a, b) => a + b);
  for (var i = 0; i < mu; i++) {
    weights[i] /= wSum;
  }
  final muEff =
      1.0 / weights.map((w) => w * w).reduce((a, b) => a + b); // variance-eff.

  // Adaptation constants (standard CMA-ES, with the sep-CMA speedup on c1/cmu).
  final cc = (4 + muEff / n) / (n + 4 + 2 * muEff / n);
  final cs = (muEff + 2) / (n + muEff + 5);
  var c1 = 2 / (pow(n + 1.3, 2) + muEff);
  var cmu = min(1 - c1, 2 * (muEff - 2 + 1 / muEff) / (pow(n + 2, 2) + muEff));
  final sepSpeedup = (n + 2) / 3.0; // Ros & Hansen: diagonal C learns faster
  c1 = min(1.0, c1 * sepSpeedup);
  cmu = min(1 - c1, cmu * sepSpeedup);
  final damps = 1 + 2 * max(0.0, sqrt((muEff - 1) / (n + 1)) - 1) + cs;
  final chiN = sqrt(n) * (1 - 1 / (4.0 * n) + 1 / (21.0 * n * n));

  // State.
  final mean = List<double>.of(initialMean);
  var sigma = sigma0;
  final pc = List<double>.filled(n, 0); // covariance evolution path
  final ps = List<double>.filled(n, 0); // step-size evolution path
  final C = List<double>.filled(n, 1); // DIAGONAL covariance (per-coord var)

  var evals = 0;
  var gen = 0;
  var best = List<double>.of(mean);
  var bestVal = double.infinity;
  var prevBestVal = double.infinity;
  var stagnant = 0;

  double gauss() {
    // Box–Muller.
    final u1 = max(1e-12, random.nextDouble());
    final u2 = random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  while (evals < maxEvals) {
    // Sample and evaluate lambda offspring.
    final pop = <List<double>>[];
    final zs = <List<double>>[];
    final vals = <double>[];
    for (var k = 0; k < lambda; k++) {
      final z = List<double>.generate(n, (_) => gauss());
      final x = List<double>.generate(
        n,
        (j) => mean[j] + sigma * sqrt(C[j]) * z[j],
      );
      final v = f(x);
      evals += 1;
      zs.add(z);
      pop.add(x);
      vals.add(v);
      if (v < bestVal) {
        bestVal = v;
        best = List<double>.of(x);
      }
    }

    // Select the mu best (ascending — we minimize).
    final order = List<int>.generate(lambda, (i) => i)
      ..sort((a, b) => vals[a].compareTo(vals[b]));

    // Weighted recombination of the mean and of the selected z's (the latter
    // drives the step-size path).
    final oldMean = List<double>.of(mean);
    final zMean = List<double>.filled(n, 0);
    for (var j = 0; j < n; j++) {
      var m = 0.0;
      for (var i = 0; i < mu; i++) {
        m += weights[i] * pop[order[i]][j];
        zMean[j] += weights[i] * zs[order[i]][j];
      }
      mean[j] = m;
    }

    // Step-size path ps (uses C^{-1/2}, elementwise for a diagonal C).
    for (var j = 0; j < n; j++) {
      ps[j] = (1 - cs) * ps[j] + sqrt(cs * (2 - cs) * muEff) * zMean[j];
    }
    final psNorm = sqrt(ps.map((v) => v * v).reduce((a, b) => a + b));

    // Heaviside stall on the covariance path when ps is large.
    final hsig = psNorm / sqrt(1 - pow(1 - cs, 2 * (gen + 1))) / chiN <
            1.4 + 2 / (n + 1.0)
        ? 1.0
        : 0.0;

    for (var j = 0; j < n; j++) {
      pc[j] = (1 - cc) * pc[j] +
          hsig * sqrt(cc * (2 - cc) * muEff) * (mean[j] - oldMean[j]) / sigma;
    }

    // Rank-one + rank-mu update of the diagonal covariance.
    for (var j = 0; j < n; j++) {
      var rankMu = 0.0;
      for (var i = 0; i < mu; i++) {
        final d = (pop[order[i]][j] - oldMean[j]) / sigma;
        rankMu += weights[i] * d * d;
      }
      final rankOne = pc[j] * pc[j] + (1 - hsig) * cc * (2 - cc) * C[j];
      C[j] = (1 - c1 - cmu) * C[j] + c1 * rankOne + cmu * rankMu;
      if (C[j] < 1e-20) C[j] = 1e-20;
    }

    // Cumulative step-size adaptation.
    sigma *= exp((cs / damps) * (psNorm / chiN - 1));

    gen += 1;
    if ((prevBestVal - bestVal).abs() < tol) {
      stagnant += 1;
      if (stagnant >= 10 + n) break; // converged
    } else {
      stagnant = 0;
    }
    prevBestVal = bestVal;
  }

  return CmaesResult(best, bestVal, gen, evals);
}
