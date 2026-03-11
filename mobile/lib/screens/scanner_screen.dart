import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/api_service.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;
  String? _lastCode;
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(String code) async {
    if (_scanned) return;
    setState(() {
      _scanned = true;
      _lastCode = code;
      _searching = true;
    });

    try {
      final api = ApiService();
      final response = await api.get('/bgg/search', params: {'query': code});
      final games = response.data['games'] as List?;

      if (games != null && games.isNotEmpty) {
        if (mounted) {
          _showResultDialog(games.first);
        }
      } else {
        _showManualSearchDialog(code);
      }
    } catch (_) {
      _showManualSearchDialog(code);
    } finally {
      setState(() => _searching = false);
    }
  }

  void _showResultDialog(Map<String, dynamic> game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Juego encontrado'),
        content: Text(game['name'] ?? 'Sin nombre'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _resetScanner();
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context)
                  .pushNamed('/quick-add', arguments: game);
            },
            child: const Text('Añadir'),
          ),
        ],
      ),
    );
  }

  void _showManualSearchDialog(String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No encontrado'),
        content: Text(
            'No se encontró un juego con el código $code.\n¿Quieres buscarlo manualmente?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _resetScanner();
            },
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushNamed('/quick-add');
            },
            child: const Text('Buscar manual'),
          ),
        ],
      ),
    );
  }

  void _resetScanner() {
    setState(() {
      _scanned = false;
      _lastCode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear código'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                _onBarcodeDetected(barcodes.first.rawValue!);
              }
            },
          ),
          // Overlay
          Center(
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white54, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          // Bottom info
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searching)
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 12),
                        Text('Buscando...',
                            style: TextStyle(color: Colors.white)),
                      ],
                    )
                  else if (_lastCode != null)
                    Text('Código: $_lastCode',
                        style: const TextStyle(color: Colors.white70))
                  else
                    const Text('Apunta al código de barras del juego',
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
