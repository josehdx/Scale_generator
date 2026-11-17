import '../models/master_bar_event.dart';

/// For every bar, the passes (1-based) in which it is played; empty = always.
///
/// Guitar Pro stores `<AlternateEndings>` ONLY on the first bar of a volta
/// bracket. The bracket then continues over the following untagged bars up to
/// and including the bar that carries the repeat-end sign. A bracket that is not
/// closed by a repeat end (the last ending) covers just its tagged bar.
List<List<int>> effectiveAlternateEndings(List<MasterBarEvent> bars) {
  final List<List<int>> out = List.generate(bars.length, (i) => bars[i].alternateEndings);
  for (int i = 0; i < bars.length; i++) {
    final List<int> tag = bars[i].alternateEndings;
    if (tag.isEmpty) continue;
    if (bars[i].isRepeatEnd) continue; // single-bar bracket
    int end = -1;
    for (int j = i + 1; j < bars.length; j++) {
      final MasterBarEvent b = bars[j];
      if (b.alternateEndings.isNotEmpty || b.isRepeatStart) break;
      if (b.isRepeatEnd) {
        end = j;
        break;
      }
    }
    if (end != -1) {
      for (int j = i + 1; j <= end; j++) {
        out[j] = tag;
      }
    }
  }
  return out;
}

/// Unrolls repeats and alternate endings (voltas) into the sequence of master
/// bars that is actually played.
///
///  * a bar with [MasterBarEvent.isRepeatStart] marks where a repeat jumps back
///    to (default: the bar after the previous repeat, or bar 0);
///  * a bar with [MasterBarEvent.isRepeatEnd] jumps back until the section has
///    been played [MasterBarEvent.repeatCount] times IN TOTAL (verified with
///    the sample files: `count="2"` with endings 1 and 2);
///  * bars inside an alternate ending are only played on the listed passes.
///
/// [maxBars] is a safety valve against malformed files.
List<int> computePlayOrder(List<MasterBarEvent> bars, {int maxBars = 20000}) {
  final List<List<int>> endings = effectiveAlternateEndings(bars);
  final List<int> order = [];
  final int n = bars.length;
  int i = 0;
  int repeatStart = 0;
  int pass = 1;
  int? finishedPass; // pass of the repeat that has just ended (for the last ending)
  bool justJumped = false;

  while (i < n && order.length < maxBars) {
    final MasterBarEvent bar = bars[i];

    if (bar.isRepeatStart) {
      if (!justJumped) pass = 1;
      repeatStart = i;
      finishedPass = null;
    }
    justJumped = false;

    final List<int> alt = endings[i];
    if (alt.isNotEmpty) {
      final int effectivePass = finishedPass ?? pass;
      if (!alt.contains(effectivePass)) {
        i++;
        continue;
      }
    } else {
      finishedPass = null;
    }

    order.add(i);

    if (bar.isRepeatEnd) {
      final int total = bar.repeatCount < 2 ? 2 : bar.repeatCount;
      if (pass < total) {
        pass++;
        i = repeatStart;
        justJumped = true;
        continue;
      }
      // Section finished. Bars of the last ending (right after this bar) are
      // still evaluated against the pass that just ended.
      finishedPass = pass;
      pass = 1;
      repeatStart = i + 1;
    }
    i++;
  }
  return order;
}

/// Plain 0..n-1 order (no repeats), used for windowed / selection playback.
List<int> linearPlayOrder(int barCount) => List<int>.generate(barCount, (i) => i);