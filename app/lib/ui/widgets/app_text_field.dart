import 'package:flutter/material.dart';

/// 全应用统一的文本输入框。
///
/// 样式（填充、圆角、聚焦描边、helperText / errorText 排版）由
/// [AppTheme] 的 inputDecorationTheme 提供，这里只负责：
/// * 把「标签 / 提示 / 说明 / 错误」四段文案摆整齐；
/// * 前缀图标统一尺寸，后缀图标与密码可见性按钮并排；
/// * 多行输入交给 [minLines] / [maxLines] 限高。
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.minLines,
    this.maxLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// 浮动标签。
  final String? label;

  /// 空值时的占位提示。
  final String? hint;

  /// 输入框下方的说明小字。
  final String? helper;

  /// 非空时输入框进入错误态，错误文案显示在下方。
  final String? errorText;

  final Widget? prefixIcon;

  /// 额外后缀。密码框的可见性按钮会排在它后面。
  final Widget? suffixIcon;

  /// 是否为密码框（自带可见性切换）。
  final bool obscureText;

  final int? minLines;

  /// 最大行数；大于 1 时按多行排版，标签对齐首行。
  final int maxLines;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool enabled;
  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final multiline = !widget.obscureText && widget.maxLines > 1;
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText && _hidden,
      minLines: widget.obscureText ? null : widget.minLines,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        errorText: widget.errorText,
        alignLabelWithHint: multiline,
        prefixIcon: widget.prefixIcon,
        suffixIcon: _suffix(),
      ),
    );
  }

  Widget? _suffix() {
    final trailing = <Widget>[
      if (widget.suffixIcon != null) widget.suffixIcon!,
      if (widget.obscureText)
        IconButton(
          tooltip: _hidden ? '显示密码' : '隐藏密码',
          onPressed: () => setState(() => _hidden = !_hidden),
          icon: Icon(
            _hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 20,
          ),
        ),
    ];
    if (trailing.isEmpty) return null;
    if (trailing.length == 1) return trailing.first;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: trailing,
    );
  }
}
