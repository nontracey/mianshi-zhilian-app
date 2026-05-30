import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mianshi_zhilian/providers/auth_provider.dart';
import 'package:mianshi_zhilian/providers/progress_provider.dart';
import 'package:mianshi_zhilian/providers/settings_provider.dart';
import 'package:mianshi_zhilian/widgets/work_panel.dart';

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
      await _mergeLocalDataToCloud();
      widget.onLoginSuccess?.call();
    } else if (mounted) {
      setState(() {
        _error = authProvider.error;
        _isLoading = false;
      });
    }
  }

  Future<void> _mergeLocalDataToCloud() async {
    final authProvider = context.read<AuthProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    final progressMap = progressProvider.exportProgress();
    final settings = settingsProvider.settings.toJson();

    await authProvider.syncToCloud(progressMap, settings);

    final cloudData = await authProvider.getCloudProgress();
    if (cloudData != null && cloudData['progressMap'] != null) {
      await progressProvider.mergeFromCloud(
        cloudData['progressMap'] as Map<String, dynamic>,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? '注册账号' : '登录')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: WorkPanel(
              title: _isRegister ? '创建新账号' : '登录账号',
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 用户名
                      TextFormField(
                        controller: _usernameController,
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          hintText: '3-20 个字符',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入用户名';
                          }
                          if (value.trim().length < 3) {
                            return '用户名至少 3 个字符';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // 密码
                      TextFormField(
                        controller: _passwordController,
                        decoration: const InputDecoration(
                          labelText: '密码',
                          hintText: '至少 6 个字符',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入密码';
                          }
                          if (value.length < 6) {
                            return '密码至少 6 个字符';
                          }
                          return null;
                        },
                      ),
                      
                      // 确认密码（仅注册时显示）
                      if (_isRegister) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          decoration: const InputDecoration(
                            labelText: '确认密码',
                            hintText: '再次输入密码',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          validator: (value) {
                            if (!_isRegister) return null;
                            if (value == null || value.isEmpty) {
                              return '请再次输入密码';
                            }
                            if (value != _passwordController.text) {
                              return '两次输入的密码不一致';
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
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isRegister ? '注册' : '登录'),
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
                        child: Text(_isRegister ? '已有账号？去登录' : '没有账号？去注册'),
                      ),
                      
                      // 忘记密码
                      if (!_isRegister) ...[
                        TextButton(
                          onPressed: () {
                            // TODO: 跳转到忘记密码页面
                          },
                          child: const Text('忘记密码？'),
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
