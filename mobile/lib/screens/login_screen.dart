import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverController = TextEditingController();
  bool _obscurePassword = true;
  bool _showServerField = false;

  @override
  void initState() {
    super.initState();
    _serverController.text = ApiConfig.serverUrl;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _applyServerUrl() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) return;
    await ApiConfig.setServerUrl(url);
    ApiService().updateBaseUrl(url);
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    await _applyServerUrl();

    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (success && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.casino,
                      size: 72, color: theme.colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Ludoteca',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      )),
                  const SizedBox(height: 8),
                  Text('Inicia sesión para continuar',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      )),
                  const SizedBox(height: 40),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || !v.contains('@') ? 'Email inválido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Introduce la contraseña' : null,
                  ),
                  if (auth.error != null) ...[
                    const SizedBox(height: 12),
                    Text(auth.error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: auth.loading ? null : _login,
                      child: auth.loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Iniciar sesión'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setState(() => _showServerField = !_showServerField),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dns_outlined, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 6),
                          Text(
                            'Configurar servidor',
                            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                          ),
                          Icon(
                            _showServerField ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: Colors.grey[500],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showServerField) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _serverController,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        labelText: 'URL del servidor',
                        prefixIcon: const Icon(Icons.link),
                        border: const OutlineInputBorder(),
                        hintText: ApiConfig.defaultServerUrl,
                        helperText: 'Ej: http://192.168.1.100:8000',
                        helperStyle: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
