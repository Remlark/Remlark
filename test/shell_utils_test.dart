import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/utils/shell_utils.dart';

void main() {
  test('同名按 Finder 规则改名', () {
    expect(ShellUtils.uniqueName('a.txt', {}), 'a.txt');
    expect(ShellUtils.uniqueName('a.txt', {'a.txt'}), 'a 2.txt');
    expect(ShellUtils.uniqueName('a.txt', {'a.txt', 'a 2.txt'}), 'a 3.txt');
    expect(ShellUtils.uniqueName('资料', {'资料'}, isDir: true), '资料 2');
    expect(ShellUtils.uniqueName('v1.2', {'v1.2'}, isDir: true), 'v1.2 2');
    expect(ShellUtils.uniqueName('.zshrc', {'.zshrc'}), '.zshrc 2');
  });

  test('远程路径文件名', () {
    expect(ShellUtils.basenameRemote('/Users/u/a b.txt'), 'a b.txt');
    expect(ShellUtils.basenameRemote('/Users/u/dir/'), 'dir');
    expect(ShellUtils.basenameRemote('name'), 'name');
  });
}
