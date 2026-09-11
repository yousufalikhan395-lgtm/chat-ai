class BotModel {
  final String botId;
  final String name;
  final String service;
  final String model;
  final bool isVip;
  final String type;
  final String mimeSupport;
  final int maxFiles;
  final bool stream;

  bool get supportsImage => mimeSupport.isNotEmpty;
  bool get isImageBot => type == 'chat-image' || type == 'gen-image' || !stream;

  BotModel({
    required this.botId, required this.name,
    required this.service, required this.model,
    this.isVip = false, this.type = 'chat', this.mimeSupport = '', this.maxFiles = 0,
    this.stream = true,
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
    stream: (j['stream'] ?? true) is bool ? j['stream'] as bool : j['stream'] == 'true',
  );
}
