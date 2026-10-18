import '../../core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../layout/app_shell.dart';
import 'auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  void _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      final success = await ref.read(authProvider.notifier).login(
            _usernameController.text,
            _passwordController.text,
          );

      if (!mounted) return;
      setState(() => _isLoading = false);

      final authState = ref.read(authProvider);

      if (authState.isMfaRequired) {
        await _showTotpDialog();
        return;
      }

      if (success && authState.isAuthenticated) {
        _navigateToApp();
      } else {
        final errorMsg = authState.errorMessage ?? 'Register number or password is incorrect.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _showTotpDialog() async {
    final totpController = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Two-Factor Authentication (TOTP)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the 6-digit code from your authenticator app to proceed:'),
            const SizedBox(height: 16),
            TextField(
              controller: totpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '123456',
                prefixIcon: Icon(Icons.security),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, totpController.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (code != null && code.length == 6) {
      setState(() => _isLoading = true);
      final verified = await ref.read(authProvider.notifier).verifyTotp(code);
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (verified) {
        _navigateToApp();
      } else {
        final authState = ref.read(authProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authState.errorMessage ?? 'Invalid TOTP code.'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  void _navigateToApp() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const AppShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Row(
        children: [
          // Left Side: Branding / Institutional Area
          Expanded(
            flex: 5,
            child: Container(
              color: AppColors.brandDark,
              child: Stack(
                children: [
                  // Abstract geometric background or overlay could go here
                  Positioned.fill(
                    child: Opacity(
                      opacity: 0.05,
                      child: Image.asset('assets/images/mips_logo.png', repeat: ImageRepeat.repeat),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(64.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Image.asset('assets/images/mips_logo.png', width: 120, height: 120, errorBuilder: (c,e,s) => Icon(Icons.school, size: 120, color: Colors.white)),
                          const SizedBox(height: 32),
                          Text(
                            'Empowering\nHealthcare Education',
                            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: Colors.white,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Malabar Institute of Paramedical Science',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.brandTint,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Right Side: Login Form
          Expanded(
            flex: 4,
            child: Container(
              color: AppTheme.surface,
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome back',
                          style: Theme.of(context).textTheme.displayMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please enter your credentials to access the ERP.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 48),
                        
                        // Custom styled field avoiding floating labels
                        Text('Username', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            hintText: 'Enter your username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                        ),
                        
                        const SizedBox(height: 24),
                        
                        Text('Password', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            prefixIcon: Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
                        ),
                        
                        const SizedBox(height: 24),
                        
                        Row(
                          children: [
                            Checkbox(
                              value: true,
                              onChanged: (v) {},
                              activeColor: AppTheme.primaryColor,
                            ),
                            Text('Remember me', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                        
                        const SizedBox(height: 32),
                        
                        ElevatedButton(
                          onPressed: _isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                          ),
                          child: _isLoading 
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Sign In'),
                        ),
                        
                        const SizedBox(height: 64),
                        Center(
                          child: Text(
                            'MIPS ERP System v1.0.0',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 12, color: AppTheme.textTertiary),
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


