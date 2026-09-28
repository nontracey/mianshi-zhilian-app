/// 外发端点的安全校验。
///
/// 两类端点的信任级别完全不同，不能共用一套判断：
///
/// - [isAllowedCredentialEndpoint]：用户**自己配置**的端点（AI 网关、MCP 服务、
///   embedding 服务）。这些地址是用户主动填的，允许 https，也允许明文 http 访问
///   回环/本网段地址 —— 自建模型（Ollama、LM Studio）与内网网关是真实部署形态，
///   一刀切禁 http 会把这类用户挡在门外。但跨公网明文必须拒绝：Bearer apiKey
///   与整段简历/JD 正文会裸奔过网。
///
/// - [isAllowedFetchTarget]：抓取**用户粘贴的任意链接**（JD 导入）。目标不可信，
///   因此方向相反：必须排除回环、私网与链路本地地址，否则一条链接就能探测内网
///   （含 169.254.169.254 云元数据）。
///
/// 两者都拒绝 URL 内嵌凭据（`userInfo`），避免凭据被拼进日志或跟随重定向外泄。
///
/// 实现约束：不 import `dart:io`，因为本 App 需要构建 Web 版本；地址判定全部
/// 靠字符串解析，并显式处理 IPv6 映射形式（`::ffff:127.0.0.1`）这类常见绕过写法。
library;

/// 解析点分十进制 IPv4，失败返回 null。
List<int>? _parseIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return null;
  final bytes = <int>[];
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return null;
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) return null;
    bytes.add(value);
  }
  return bytes;
}

bool _isPrivateIpv4(List<int> b) {
  // 127.0.0.0/8
  if (b[0] == 127) return true;
  // 10.0.0.0/8
  if (b[0] == 10) return true;
  // 172.16.0.0/12
  if (b[0] == 172 && b[1] >= 16 && b[1] <= 31) return true;
  // 192.168.0.0/16
  if (b[0] == 192 && b[1] == 168) return true;
  return false;
}

/// IPv6 只判私有/回环三类：::1、fc00::/7（ULA）、fe80::/10（链路本地），
/// 以及 ::ffff:<私有 IPv4> 的映射形式。
bool _isPrivateIpv6(String host) {
  final h = host.toLowerCase().trim();
  if (h == '::1' || h == '0:0:0:0:0:0:0:1') return true;
  // IPv4-mapped / IPv4-compatible：交给 v4 规则判定，防止 ::ffff:127.0.0.1 绕过。
  final mapped = RegExp(r'^::(ffff:)?(\d+\.\d+\.\d+\.\d+)$').firstMatch(h);
  if (mapped != null) {
    final v4 = _parseIpv4(mapped.group(2)!);
    return v4 != null && _isPrivateIpv4(v4);
  }
  if (h.startsWith('fc') || h.startsWith('fd')) return true;
  if (h.startsWith('fe80:') || h.startsWith('fe8') || h.startsWith('fe9')) {
    return true;
  }
  if (h.startsWith('fec') || h.startsWith('fed') || h.startsWith('fee')) {
    return true;
  }
  return false;
}

/// 明文 http 仅在回环与本网段放行（自建模型/内网网关场景）。
bool _isLoopbackOrPrivateHost(String host) {
  final h = host.trim();
  // 去掉 IPv6 字面量的方括号。
  final bare = h.startsWith('[') && h.endsWith(']')
      ? h.substring(1, h.length - 1)
      : h;
  if (bare == 'localhost' || bare.endsWith('.localhost')) return true;
  final v4 = _parseIpv4(bare);
  if (v4 != null) return _isPrivateIpv4(v4);
  return _isPrivateIpv6(bare);
}

/// 端点可否承载凭据与私有资料正文。
bool isAllowedCredentialEndpoint(Uri uri) {
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme == 'http') return _isLoopbackOrPrivateHost(uri.host);
  return false;
}

/// 用户粘贴的链接可否作为抓取目标（防内网探测 / SSRF）。
bool isAllowedFetchTarget(Uri uri) {
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return !_isLoopbackOrPrivateHost(uri.host);
}

/// 供 UI 提示使用：为什么这个地址不被接受。返回 l10n key，由界面按语言渲染。
String? endpointRejectionKey(Uri uri, {required bool credential}) {
  if (uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return 'coach_endpoint_invalid';
  }
  if (credential) {
    if (uri.scheme == 'https') return null;
    if (uri.scheme == 'http' && _isLoopbackOrPrivateHost(uri.host)) {
      return null;
    }
    return 'coach_endpoint_requires_https';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'coach_endpoint_invalid';
  }
  if (_isLoopbackOrPrivateHost(uri.host)) return 'coach_endpoint_local_blocked';
  return null;
}
