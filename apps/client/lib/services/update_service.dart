class UpdateService {
  final String repoUrl;

  UpdateService({this.repoUrl = ''});

  Future<Map<String, dynamic>?> checkForUpdate(String currentVersion) async {
    // TODO: implement actual update check
    return null;
  }
}
