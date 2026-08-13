import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/bgg_collection_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late TextEditingController _nombreCtrl;
  late TextEditingController _emailCtrl;
  bool _noEnfundo = false;
  bool _ocultarPorEstrenar = false;
  bool _ocultarFaltanTraduccion = false;
  bool _ocultarExpansionOtroIdioma = false;
  bool _ocultarPorColocar = false;
  bool _saving = false;
  bool _bggBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _nombreCtrl = TextEditingController(text: auth.userName);
    _emailCtrl = TextEditingController(text: auth.userEmail);
    _noEnfundo = auth.noEnfundo;
    _ocultarPorEstrenar = auth.ocultarPorEstrenar;
    _ocultarFaltanTraduccion = auth.ocultarFaltanTraduccion;
    _ocultarExpansionOtroIdioma = auth.ocultarExpansionOtroIdioma;
    _ocultarPorColocar = auth.ocultarPorColocar;
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
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
      noEnfundo: _noEnfundo,
      ocultarPorEstrenar: _ocultarPorEstrenar,
      ocultarFaltanTraduccion: _ocultarFaltanTraduccion,
      ocultarExpansionOtroIdioma: _ocultarExpansionOtroIdioma,
      ocultarPorColocar: _ocultarPorColocar,
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

  Future<void> _showConnectBggDialog() async {
    final auth = context.read<AuthProvider>();
    final usernameCtrl =
        TextEditingController(text: auth.bggUsername ?? '');
    final passwordCtrl = TextEditingController();
    var obscure = true;
    String? dialogError;
    var connecting = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Conectar a BoardGameGeek'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Introduce tu usuario y contraseña de BGG. '
                      'La contraseña no se guarda: solo se usa para crear la sesión.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: usernameCtrl,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Usuario BGG',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) async {
                        if (connecting) return;
                        setDialogState(() {
                          connecting = true;
                          dialogError = null;
                        });
                        final err = await auth.connectBgg(
                          username: usernameCtrl.text.trim(),
                          password: passwordCtrl.text,
                        );
                        if (!ctx.mounted) return;
                        if (err == null) {
                          Navigator.of(ctx).pop();
                          return;
                        }
                        setDialogState(() {
                          connecting = false;
                          dialogError = err;
                        });
                      },
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: connecting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: connecting
                      ? null
                      : () async {
                          final username = usernameCtrl.text.trim();
                          final password = passwordCtrl.text;
                          if (username.isEmpty || password.isEmpty) {
                            setDialogState(() {
                              dialogError =
                                  'Usuario y contraseña son obligatorios.';
                            });
                            return;
                          }
                          setDialogState(() {
                            connecting = true;
                            dialogError = null;
                          });
                          final err = await auth.connectBgg(
                            username: username,
                            password: password,
                          );
                          if (!ctx.mounted) return;
                          if (err == null) {
                            Navigator.of(ctx).pop();
                            return;
                          }
                          setDialogState(() {
                            connecting = false;
                            dialogError = err;
                          });
                        },
                  child: connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Conectar'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameCtrl.dispose();
    passwordCtrl.dispose();

    if (!mounted) return;
    if (auth.bggConnected) {
      context.read<BggCollectionProvider>().fetchOwnedIds(force: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conectado a BGG como ${auth.bggUsername}'),
        ),
      );
    }
  }

  Future<void> _disconnectBgg() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar BGG'),
        content: const Text(
          '¿Quieres desconectar tu cuenta de BoardGameGeek? '
          'Podrás volver a conectarla cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _bggBusy = true);
    final err = await context.read<AuthProvider>().disconnectBgg();
    if (!mounted) return;
    context.read<BggCollectionProvider>().clear();
    setState(() => _bggBusy = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Desconectado de BoardGameGeek'),
      ),
    );
  }

  Widget _bggBadge(AuthProvider auth, ThemeData theme) {
    final connected = auth.bggConnected;
    final color = connected
        ? Colors.green.shade700
        : theme.colorScheme.onSurfaceVariant;
    final bg = connected
        ? Colors.green.shade50
        : theme.colorScheme.surfaceContainerHighest;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connected ? Icons.check_circle : Icons.link_off,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            connected
                ? 'Conectado a BGG · ${auth.bggUsername}'
                : 'No conectado a BGG',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
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
          const SizedBox(height: 12),
          Center(
            child: Text(
              auth.userName,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: _bggBadge(auth, theme)),
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
            controller: _emailCtrl,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.mail_outline),
              helperText: 'No se puede modificar',
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'BoardGameGeek',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    auth.bggConnected
                        ? 'Tu cuenta está vinculada para poder sincronizar e importar tu colección a BGG.'
                        : 'Conecta tu cuenta de BGG para poder importar tu colección a BoardGameGeek.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (auth.bggConnected)
                    OutlinedButton.icon(
                      onPressed: _bggBusy ? null : _disconnectBgg,
                      icon: _bggBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link_off),
                      label: const Text('Desconectar de la BGG'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _bggBusy ? null : _showConnectBggDialog,
                      icon: const Icon(Icons.link),
                      label: const Text('Conectar a la BGG'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Avisos en Inicio',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Ocultar aviso de fundas'),
                  subtitle: const Text(
                    'Oculta los avisos de fundas pendientes en la app',
                  ),
                  value: _noEnfundo,
                  onChanged: (v) => setState(() => _noEnfundo = v),
                  secondary: const Icon(Icons.style_outlined),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Ocultar "Por Estrenar"'),
                  subtitle: const Text(
                    'Oculta el aviso de juegos sin abrir',
                  ),
                  value: _ocultarPorEstrenar,
                  onChanged: (v) => setState(() => _ocultarPorEstrenar = v),
                  secondary: const Icon(Icons.card_giftcard),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Ocultar "Faltan Traducciones"'),
                  subtitle: const Text(
                    'Oculta el aviso de juegos por tradumaquetar',
                  ),
                  value: _ocultarFaltanTraduccion,
                  onChanged: (v) =>
                      setState(() => _ocultarFaltanTraduccion = v),
                  secondary: const Icon(Icons.translate),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Ocultar "Expansiones en Otro Idioma"'),
                  subtitle: const Text(
                    'Oculta el aviso de expansiones en otro idioma',
                  ),
                  value: _ocultarExpansionOtroIdioma,
                  onChanged: (v) =>
                      setState(() => _ocultarExpansionOtroIdioma = v),
                  secondary: const Icon(Icons.language),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Ocultar "Juegos por colocar"'),
                  subtitle: const Text(
                    'Oculta el aviso de juegos sin ubicación asignada',
                  ),
                  value: _ocultarPorColocar,
                  onChanged: (v) => setState(() => _ocultarPorColocar = v),
                  secondary: const Icon(Icons.inventory_2_outlined),
                ),
              ],
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
