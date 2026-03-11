class Partida {
  final int? id;
  final int juegoId;
  final String juegoNombre;
  final String? juegoImagen;
  final DateTime fecha;
  final int numJugadores;
  final String? ganador;
  final String? notas;
  final List<String> jugadores;

  Partida({
    this.id,
    required this.juegoId,
    required this.juegoNombre,
    this.juegoImagen,
    required this.fecha,
    required this.numJugadores,
    this.ganador,
    this.notas,
    this.jugadores = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'juego_id': juegoId,
        'juego_nombre': juegoNombre,
        'juego_imagen': juegoImagen,
        'fecha': fecha.toIso8601String(),
        'num_jugadores': numJugadores,
        'ganador': ganador,
        'notas': notas,
        'jugadores': jugadores.join(','),
      };

  factory Partida.fromMap(Map<String, dynamic> map) {
    return Partida(
      id: map['id'],
      juegoId: map['juego_id'],
      juegoNombre: map['juego_nombre'] ?? '',
      juegoImagen: map['juego_imagen'],
      fecha: DateTime.parse(map['fecha']),
      numJugadores: map['num_jugadores'] ?? 0,
      ganador: map['ganador'],
      notas: map['notas'],
      jugadores: (map['jugadores'] as String?)?.split(',') ?? [],
    );
  }
}
