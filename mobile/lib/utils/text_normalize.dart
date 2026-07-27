/// Utilidades para normalizar texto (minúsculas + sin acentos) de forma
/// consistente en toda la app.
///
/// Se usa tanto para rellenar la columna persistente `nombre_norm` de la tabla
/// `juegos` como para normalizar términos de búsqueda y ordenar listas en Dart.
/// De esta forma la búsqueda y el orden son insensibles a tildes sin depender
/// de expresiones SQL frágiles (REPLACE anidados) que fallan en algunos SQLite.
const Map<String, String> kAccentMap = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Devuelve [input] en minúsculas y sin acentos.
String normalizeText(String input) {
  var out = input.toLowerCase();
  kAccentMap.forEach((k, v) {
    out = out.replaceAll(k, v);
  });
  return out;
}
