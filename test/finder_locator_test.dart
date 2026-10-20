import 'package:flutter_test/flutter_test.dart';
import 'package:remlark/modules/remote_desktop/vnc/finder_locator.dart';

void main() {
  // 主屏 1440×900 点；两个 Finder 窗口，Downloads 在最前并与 Documents 重叠
  const out =
      '1440,900\n'
      '/Users/u/Desktop/\n'
      '100,100,700,600\t/Users/u/Downloads/\n'
      '400,300,1200,800\t/Users/u/Documents/\n';

  test('解析 Finder 布局', () {
    final l = FinderLayout.parse(out)!;
    expect(l.screenWidth, 1440);
    expect(l.desktop, '/Users/u/Desktop/');
    expect(l.windows.map((w) => w.path), ['/Users/u/Downloads/', '/Users/u/Documents/']);
    expect(FinderLayout.parse(''), isNull);
    expect(FinderLayout.parse('execution error'), isNull);
  });

  test('按拖放点选择文件夹：重叠处取最前窗口，空白处为桌面，Retina 帧缓冲按 2 倍换算', () {
    final l = FinderLayout.parse(out)!;
    // 帧缓冲 2880 宽（Retina），像素坐标需除以 2
    expect(l.folderAt(const Offset(1000, 800), 2880), '/Users/u/Downloads/'); // 点 (500,400)：两窗口重叠
    expect(l.folderAt(const Offset(2000, 1200), 2880), '/Users/u/Documents/'); // 点 (1000,600)
    expect(l.folderAt(const Offset(2700, 1700), 2880), '/Users/u/Desktop/'); // 点 (1350,850)：空白
    // 非 Retina
    expect(l.folderAt(const Offset(500, 400), 1440), '/Users/u/Downloads/');
    // 没有拖放点（按钮选择文件）：最前面的窗口；没有窗口时为桌面
    expect(l.folderAt(null, 2880), '/Users/u/Downloads/');
    expect(FinderLayout.parse('1440,900\n/Users/u/Desktop/\n')!.folderAt(null, 1440), '/Users/u/Desktop/');
  });

  test('解析插入位置（Finder 粘贴目标）', () {
    final l = FinderLayout.parse('1440,900\n/Users/u/Desktop/\n@insertion\t/Users/u/Documents/\n0,0,10,10\t/Users/u/A/\n')!;
    expect(l.insertion, '/Users/u/Documents/');
    expect(l.windows.single.path, '/Users/u/A/');
    expect(FinderLayout.parse(out)!.insertion, isNull);
  });
}
