import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/ai/ui/chat_panel.dart';

void main() {
  test('聊天发送快捷键：⌘Enter / Ctrl+Enter 发送，单独 Enter 不发送', () {
    bool send(LogicalKeyboardKey k, {required bool apple, bool meta = false, bool control = false}) =>
        ChatPanel.isSendKey(k, apple: apple, meta: meta, control: control);
    // macOS
    expect(send(LogicalKeyboardKey.enter, apple: true), isFalse);
    expect(send(LogicalKeyboardKey.enter, apple: true, meta: true), isTrue);
    expect(send(LogicalKeyboardKey.numpadEnter, apple: true, meta: true), isTrue);
    expect(send(LogicalKeyboardKey.enter, apple: true, control: true), isFalse);
    expect(send(LogicalKeyboardKey.keyC, apple: true, meta: true), isFalse);
    // Windows / Linux
    expect(send(LogicalKeyboardKey.enter, apple: false), isFalse);
    expect(send(LogicalKeyboardKey.enter, apple: false, control: true), isTrue);
    expect(send(LogicalKeyboardKey.enter, apple: false, meta: true), isFalse);
  });
}
