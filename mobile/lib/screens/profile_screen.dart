import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nombreCtrl;
  late TextEditingController _bggCtrl;
  bool _noEnfundo = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _nombreCtrl = TextEditingController(text: auth.userName);
    _bggCtrl = TextEditingController(text: auth.bggUsername ?? '');
    _noEnfundo = auth.noEnfundo;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _bggCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateProfile(
      name: _nombreCtrl.text.trim(),
      bggUsername: _bggCtrl.text.trim(),
      noEnfundo: _noEnfundo,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = ok ? null : 'No se pudo guardar el perfil';
    });
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: theme.colorScheme.primary,
              child: Text(
                auth.userName.isNotEmpty
                    ? auth.userName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nombreCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: TextEditingController(text: auth.userEmail),
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.mail_outline),
              helperText: 'No se puede modificar',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bggCtrl,
            decoration: const InputDecoration(
              labelText: 'Usuario de BoardGameGeek',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.casino_outlined),
              helperText: 'Se usa para importar tu colecci\u00f3n desde BGG',
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SwitchListTile(
              title: const Text('No enfundo'),
              subtitle: const Text(
                'Oculta los avisos de fundas pendientes en la app',
              ),
              value: _noEnfundo,
              onChanged: (v) => setState(() => _noEnfundo = v),
              secondary: const Icon(Icons.style_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }
}
