class BotModel {
  final String botId;
  final String name;
  final String service;
  final String model;
  final bool isVip;
  final String type;
  final String mimeSupport;
  final int maxFiles;

  bool get supportsImage => mimeSupport.isNotEmpty;

  BotModel({
    required this.botId, required this.name,
    required this.service, required this.model,
    this.isVip = false, this.type = 'chat', this.mimeSupport = '', this.maxFiles = 0,
  });

  factory BotModel.fromJson(Map<String, dynamic> j) => BotModel(
    botId: j['bot_id'] ?? j['_id'] ?? '',
    name: j['name'] ?? '?',
    service: j['service'] ?? '',
    model: j['model'] ?? '',
    isVip: j['is_vip'] == true || j['is_vip'] == 1,
    type: j['type'] ?? 'chat',
    mimeSupport: j['mime_support'] ?? '',
    maxFiles: j['max_files'] ?? 1,
  );
}
