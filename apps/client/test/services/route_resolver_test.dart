import 'package:flutter_test/flutter_test.dart';
import 'package:mianshi_zhilian/services/route_resolver.dart';

void main() {
  test('resolves appApi primary and backup candidates', () {
    final candidates = const RouteResolver().resolveCandidates(
      RouteService.appApi,
      '/auth/login',
      mode: RouteMode.primaryFirst,
    );

    expect(candidates, hasLength(2));
    expect(
      candidates.first.url.toString(),
      '${RouteResolver.appApiPrimary}/auth/login',
    );
    expect(
      candidates.last.url.toString(),
      '${RouteResolver.appApiBackup}/auth/login',
    );
  });

  test('honors backup only mode', () {
    final candidates = const RouteResolver().resolveCandidates(
      RouteService.content,
      'manifest.json',
      mode: RouteMode.backupOnly,
    );

    expect(candidates, hasLength(1));
    expect(
      candidates.single.url.toString(),
      '${RouteResolver.contentBackup}/manifest.json',
    );
  });

  test('active lane changes auto ordering', () {
    final candidates = const RouteResolver().resolveCandidates(
      RouteService.appApi,
      '/admin/users',
      activeLane: RouteLane.backup,
    );

    expect(
      candidates.first.url.host,
      Uri.parse(RouteResolver.appApiBackup).host,
    );
    expect(
      candidates.last.url.host,
      Uri.parse(RouteResolver.appApiPrimary).host,
    );
  });
}
