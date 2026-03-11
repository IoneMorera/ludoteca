import '../config/api_config.dart';

class Juego {
  final int id;
  final String nombre;
  final String? descripcion;
  final String? imagen;
  final int? edadMinima;
  final int? edadMaxima;
  final int? numJugadoresMin;
  final int? numJugadoresMax;
  final int? categoriaId;
  final String? estado;
  final String? fechaCompra;
  final int? juegoBaseId;
  final Categoria? categoria;
  final Ubicacion? ubicacion;
  final List<Propietario> propietarios;
  final List<Juego> expansiones;
  final Juego? juegoBase;

  Juego({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.imagen,
    this.edadMinima,
    this.edadMaxima,
    this.numJugadoresMin,
    this.numJugadoresMax,
    this.categoriaId,
    this.estado,
    this.fechaCompra,
    this.juegoBaseId,
    this.categoria,
    this.ubicacion,
    this.propietarios = const [],
    this.expansiones = const [],
    this.juegoBase,
  });

  factory Juego.fromJson(Map<String, dynamic> json) {
    return Juego(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      descripcion: json['descripcion'],
      imagen: json['imagen'],
      edadMinima: json['edad_minima'],
      edadMaxima: json['edad_maxima'],
      numJugadoresMin: json['num_jugadores_min'],
      numJugadoresMax: json['num_jugadores_max'],
      categoriaId: json['categoria_id'],
      estado: json['estado'],
      fechaCompra: json['fecha_compra'],
      juegoBaseId: json['juego_base_id'],
      categoria: json['categoria'] != null
          ? Categoria.fromJson(json['categoria'])
          : null,
      ubicacion: json['ubicacion'] != null
          ? Ubicacion.fromJson(json['ubicacion'])
          : null,
      propietarios: (json['propietarios'] as List?)
              ?.map((p) => Propietario.fromJson(p))
              .toList() ??
          [],
      expansiones: (json['expansiones'] as List?)
              ?.map((e) => Juego.fromJson(e))
              .toList() ??
          [],
      juegoBase: json['juego_base'] != null
          ? Juego.fromJson(json['juego_base'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'nombre': nombre,
        'descripcion': descripcion,
        'edad_minima': edadMinima,
        'edad_maxima': edadMaxima,
        'num_jugadores_min': numJugadoresMin,
        'num_jugadores_max': numJugadoresMax,
        'categoria_id': categoriaId,
        'estado': estado,
        'fecha_compra': fechaCompra,
        'juego_base_id': juegoBaseId,
        'ubicacion_id': ubicacion?.id,
        'propietario_ids': propietarios.map((p) => p.id).toList(),
      };

  bool get esExpansion => juegoBaseId != null;
  String get jugadoresTexto =>
      '${numJugadoresMin ?? '?'}–${numJugadoresMax ?? '?'}';
  String get edadTexto => '${edadMinima ?? '?'}+';

  String? get imagenUrl {
    if (imagen == null || imagen!.isEmpty) return null;
    if (imagen!.startsWith('http://') || imagen!.startsWith('https://')) {
      return imagen;
    }
    final path = imagen!.startsWith('/') ? imagen! : '/$imagen';
    return '${ApiConfig.storageUrl}$path';
  }
}

class Categoria {
  final int id;
  final String nombre;

  Categoria({required this.id, required this.nombre});

  factory Categoria.fromJson(Map<String, dynamic> json) {
    return Categoria(id: json['id'], nombre: json['nombre'] ?? '');
  }
}

class Propietario {
  final int id;
  final String nombre;
  final String? bggUsername;
  final bool esPrincipal;

  Propietario({
    required this.id,
    required this.nombre,
    this.bggUsername,
    this.esPrincipal = false,
  });

  factory Propietario.fromJson(Map<String, dynamic> json) {
    return Propietario(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      bggUsername: json['bgg_username'],
      esPrincipal: json['es_principal'] == true || json['es_principal'] == 1,
    );
  }
}

class Ubicacion {
  final int id;
  final String nombre;
  final Mueble? mueble;

  Ubicacion({required this.id, required this.nombre, this.mueble});

  factory Ubicacion.fromJson(Map<String, dynamic> json) {
    return Ubicacion(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      mueble:
          json['mueble'] != null ? Mueble.fromJson(json['mueble']) : null,
    );
  }

  String get rutaCompleta {
    if (mueble == null) return nombre;
    return '${mueble!.habitacion?.nombre ?? ''} › ${mueble!.nombre} › $nombre';
  }
}

class Mueble {
  final int id;
  final String nombre;
  final Habitacion? habitacion;

  Mueble({required this.id, required this.nombre, this.habitacion});

  factory Mueble.fromJson(Map<String, dynamic> json) {
    return Mueble(
      id: json['id'],
      nombre: json['nombre'] ?? '',
      habitacion: json['habitacion'] != null
          ? Habitacion.fromJson(json['habitacion'])
          : null,
    );
  }
}

class Habitacion {
  final int id;
  final String nombre;

  Habitacion({required this.id, required this.nombre});

  factory Habitacion.fromJson(Map<String, dynamic> json) {
    return Habitacion(id: json['id'], nombre: json['nombre'] ?? '');
  }
}
