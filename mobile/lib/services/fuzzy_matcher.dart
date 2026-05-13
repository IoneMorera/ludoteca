/// Utilidades de comparaci\u00f3n difusa de cadenas.
///
/// Implementa una similitud combinada de Levenshtein normalizado y
/// solapamiento de trigramas, ambas con normalizaci\u00f3n unicode b\u00e1sica.
class FuzzyMatcher {
  /// Devuelve una puntuaci\u00f3n entre 0 y 1 (1 = iguales).
  static double similarity(String a, String b) {
    final na = _normalize(a);
    final nb = _normalize(b);
    if (na.isEmpty || nb.isEmpty) return 0;
    if (na == nb) return 1;

    // Contains: si el corto est\u00e1 contenido en el largo, alta puntuaci\u00f3n.
    final short = na.length <= nb.length ? na : nb;
    final long = na.length > nb.length ? na : nb;
    if (long.contains(short)) {
      return 0.85 + 0.15 * (short.length / long.length);
    }

    final lev = _levenshteinSim(na, nb);
    final tri = _trigramSim(na, nb);
    return (lev * 0.6) + (tri * 0.4);
  }

  static String _normalize(String s) {
    var out = s.toLowerCase().trim();
    const ascii = 'a a a a a a c e e e e i i i i n o o o o o u u u u y';
    const accents = '\u00e0 \u00e1 \u00e2 \u00e3 \u00e4 \u00e5 \u00e7 \u00e8 \u00e9 \u00ea \u00eb \u00ec \u00ed \u00ee \u00ef \u00f1 \u00f2 \u00f3 \u00f4 \u00f5 \u00f6 \u00f9 \u00fa \u00fb \u00fc \u00fd';
    final asciiList = ascii.split(' ');
    final accentList = accents.split(' ');
    for (var i = 0; i < accentList.length; i++) {
      out = out.replaceAll(accentList[i], asciiList[i]);
    }
    out = out.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  static double _levenshteinSim(String a, String b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 || m == 0) return 0;
    final dp = List<List<int>>.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1,
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost,
        ].reduce((v, e) => v < e ? v : e);
      }
    }
    final dist = dp[n][m];
    final longest = n > m ? n : m;
    return 1 - (dist / longest);
  }

  static double _trigramSim(String a, String b) {
    final ta = _trigrams(a);
    final tb = _trigrams(b);
    if (ta.isEmpty || tb.isEmpty) return 0;
    final intersection = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    return intersection / union;
  }

  static Set<String> _trigrams(String s) {
    final padded = '  $s  ';
    final set = <String>{};
    for (var i = 0; i < padded.length - 2; i++) {
      set.add(padded.substring(i, i + 3));
    }
    return set;
  }
}
