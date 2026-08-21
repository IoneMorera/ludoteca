import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../config/app_environment.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _bggController = TextEditingController();
  final _serverController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  bool _showServerField = false;
  bool _isRegisterMode = false;

  @override
  void initState() {
    super.initState();
    _serverController.text = ApiConfig.serverUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _bggController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _applyServerUrl() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) return;
    await ApiConfig.setServerUrl(url);
    ApiService().updateBaseUrl(url);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await _applyServerUrl();

    if (!mounted) return;
    final auth = context.read<AuthProvider>();

    final success = _isRegisterMode
        ? await auth.register(
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            password: _passwordController.text,
            passwordConfirmation: _passwordConfirmController.text,
            bggUsername: _bggController.text.trim().isEmpty
                ? null
                : _bggController.text.trim(),
          )
        : await auth.login(
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
                  Text(
                    _isRegisterMode
                        ? 'Crea tu cuenta para empezar'
                        : 'Inicia sesión para continuar',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isRegisterMode) ...[
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Introduce tu nombre'
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],
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
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Introduce la contraseña';
                      }
                      if (_isRegisterMode && v.length < 8) {
                        return 'Mínimo 8 caracteres';
                      }
                      return null;
                    },
                  ),
                  if (_isRegisterMode) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordConfirmController,
                      obscureText: _obscurePasswordConfirm,
                      decoration: InputDecoration(
                        labelText: 'Confirmar contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePasswordConfirm
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () => setState(() =>
                              _obscurePasswordConfirm = !_obscurePasswordConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Confirma la contraseña';
                        }
                        if (v != _passwordController.text) {
                          return 'Las contraseñas no coinciden';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bggController,
                      decoration: const InputDecoration(
                        labelText: 'Usuario BGG (opcional)',
                        prefixIcon: Icon(Icons.extension_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (auth.error != null) ...[
                    const SizedBox(height: 12),
                    Text(auth.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: auth.loading ? null : _submit,
                      child: auth.loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(_isRegisterMode
                              ? 'Crear cuenta'
                              : 'Iniciar sesión'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: auth.loading
                        ? null
                        : () {
                            auth.clearError();
                            setState(() => _isRegisterMode = !_isRegisterMode);
                          },
                    child: Text(_isRegisterMode
                        ? '¿Ya tienes cuenta? Inicia sesión'
                        : '¿No tienes cuenta? Regístrate'),
                  ),
                  const SizedBox(height: 8),
                  if (AppEnvironment.isDev) ...[
                    InkWell(
                      onTap: () =>
                          setState(() => _showServerField = !_showServerField),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dns_outlined,
                                size: 16, color: Colors.grey[500]),
                            const SizedBox(width: 6),
                            Text(
                              'Configurar servidor',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[500]),
                            ),
                            Icon(
                              _showServerField
                                  ? Icons.expand_less
                                  : Icons.expand_more,
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
                          helperStyle:
                              TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
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
