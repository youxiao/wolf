import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 桌面窗口控制器：负责窗口全屏切换。
///
/// 当前仅在 Windows 端实现了原生全屏（通过 MethodChannel 调用原生
/// C++ 代码），其余平台会静默降级、不展示全屏入口。
class WindowController {
  WindowController._();

  static final WindowController instance = WindowController._();

  static const MethodChannel _channel = MethodChannel('moonveil/window');

  /// 当前是否处于全屏状态，供界面监听并切换图标。
  final ValueNotifier<bool> fullScreen = ValueNotifier<bool>(false);

  /// 当前平台是否支持窗口全屏。
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// 应用启动时读取一次原生全屏状态。
  Future<void> init() async {
    if (!isSupported) return;
    try {
      final v = await _channel.invokeMethod<bool>('isFullScreen');
      fullScreen.value = v ?? false;
    } catch (_) {
      fullScreen.value = false;
    }
  }

  /// 切换全屏，并同步最新的全屏状态。
  Future<void> toggle() async {
    if (!isSupported) return;
    try {
      final v = await _channel.invokeMethod<bool>('toggleFullScreen');
      fullScreen.value = v ?? fullScreen.value;
    } catch (_) {
      // 原生未实现时本地翻转，保持界面状态一致。
      fullScreen.value = !fullScreen.value;
    }
  }
}
