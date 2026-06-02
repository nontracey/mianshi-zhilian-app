import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/localization_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';
import 'submit_ticket_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.onLoginSuccess});

  final VoidCallback? onLoginSuccess;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isRegister = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // 防注入：过滤特殊字符
  String _sanitizeInput(String input) {
    return input.replaceAll(RegExp(r'[<>"\x27;\(\)]'), '').trim();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authProvider = context.read<AuthProvider>();
    final username = _sanitizeInput(_usernameController.text);
    final password = _passwordController.text;
    bool success;

    if (_isRegister) {
      success = await authProvider.register(username, password);
    } else {
      success = await authProvider.login(username, password);
    }

    if (success && mounted) {
      setState(() => _isLoading = false);
      await _mergeLocalDataToCloud();
      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!.call();
      } else if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } else if (mounted) {
      setState(() {
        _error = authProvider.error;
        _isLoading = false;
      });
    }
  }

  Future<void> _mergeLocalDataToCloud() async {
    // Account cloud sync is temporarily unavailable to avoid platform quota use.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LocalizationProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isRegister ? l10n.get('register_account') : l10n.get('login'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: WorkPanel(
              title: _isRegister
                  ? l10n.get('create_new_account')
                  : l10n.get('login_account'),
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 用户名
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: l10n.get('username'),
                          hintText: l10n.get('char_3to20'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.get('please_enter_username');
                          }
                          if (value.trim().length < 3) {
                            return l10n.get('username_min_3_chars');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // 密码
                      TextFormField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: l10n.get('password'),
                          hintText: l10n.get('min_6_chars'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.get('please_enter_password');
                          }
                          if (value.length < 6) {
                            return l10n.get('password_min_6_chars');
                          }
                          return null;
                        },
                      ),

                      // 确认密码（仅注册时显示）
                      if (_isRegister) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          decoration: InputDecoration(
                            labelText: l10n.get('confirm_password'),
                            hintText: l10n.get('confirm_password_hint'),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (!_isRegister) return null;
                            if (value == null || value.isEmpty) {
                              return l10n.get('please_confirm_password_again');
                            }
                            if (value != _passwordController.text) {
                              return l10n.get('passwords_do_not_match');
                            }
                            return null;
                          },
                        ),
                      ],

                      // 错误提示
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            _error!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // 提交按钮
                      FilledButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _isRegister
                                    ? l10n.get('register')
                                    : l10n.get('login'),
                              ),
                      ),
                      const SizedBox(height: 12),

                      // 切换登录/注册
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() {
                                _isRegister = !_isRegister;
                                _error = null;
                                _confirmPasswordController.clear();
                              }),
                        child: Text(
                          _isRegister
                              ? l10n.get('have_account_login')
                              : l10n.get('no_account_register'),
                        ),
                      ),

                      // 忘记密码
                      if (!_isRegister) ...[
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SubmitTicketPage(
                                  type: 'password_reset',
                                ),
                              ),
                            );
                          },
                          child: Text(l10n.get('forgot_password_q')),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
