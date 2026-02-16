import 'package:flutter/material.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final int maxLines;

  /// Email input with defaults
  factory AppTextField.email({
    required TextEditingController controller,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) =>
      AppTextField(
        controller: controller,
        label: 'Email',
        hint: 'your@email.com',
        prefixIcon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
        validator: validator,
        onChanged: onChanged,
      );

  /// Password input with defaults
  factory AppTextField.password({
    required TextEditingController controller,
    String? Function(String?)? validator,
    String label = 'Password',
  }) =>
      AppTextField(
        controller: controller,
        label: label,
        prefixIcon: Icons.lock_outlined,
        obscureText: true,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.password],
        validator: validator,
      );

  /// Generic text input
  factory AppTextField.name({
    required TextEditingController controller,
    String label = 'Name',
    ValueChanged<String>? onChanged,
  }) =>
      AppTextField(
        controller: controller,
        label: label,
        prefixIcon: Icons.person_outlined,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
        onChanged: onChanged,
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      autofillHints: autofillHints,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
