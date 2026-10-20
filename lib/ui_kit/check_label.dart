import 'package:flutter/material.dart';

import '../app/theme/app_palette.dart';

/// 紧凑的“复选框 + 文字”：文字紧贴复选框，整行可点击，可选灰色说明跟在文字后。
/// 替代 CheckboxListTile（其标题与复选框间距过大）
class CheckLabel extends StatelessWidget {
  const CheckLabel({super.key, required this.value, required this.onChanged, required this.label, this.helper});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  /// 跟在文字后的说明
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label, style: TextStyle(fontSize: 14, color: p.text)),
            ),
            if (helper != null) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  helper!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textFaint),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
