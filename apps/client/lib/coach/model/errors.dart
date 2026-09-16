/// 模型网关错误分类（§8.1：429/超时/鉴权失败不反复重试等）。
library;

/// 网关基础错误。
class ModelGatewayException implements Exception {
  ModelGatewayException(this.message, {this.statusCode, this.body});
  final String message;
  final int? statusCode;
  final String? body;
  @override
  String toString() =>
      'ModelGatewayException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

/// 鉴权失败：不反复重试。
class ModelAuthException extends ModelGatewayException {
  ModelAuthException([super.message = '鉴权失败']) : super(statusCode: 401);
}

/// 额度/限流耗尽：允许换模型，原答继续保留。
class ModelRateLimitException extends ModelGatewayException {
  ModelRateLimitException([super.message = '额度或限流耗尽']) : super(statusCode: 429);
}

/// 请求超时。
class ModelTimeoutException extends ModelGatewayException {
  ModelTimeoutException([super.message = '请求超时']) : super(statusCode: 408);
}

/// 被取消（与网关自身取消区分于外部网络取消）。
class ModelCanceledException extends ModelGatewayException {
  ModelCanceledException([super.message = '请求已取消']) : super(statusCode: 499);
}
