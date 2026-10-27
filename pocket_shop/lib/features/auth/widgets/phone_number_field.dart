import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';

/// Phone input with a fixed "+260" country-code prefix, matching the
/// approved auth-screens design. Accepts a bare local number (with or
/// without the leading 0); [PhoneFormat] already parses that shape
/// alongside the full "097xxxxxxx" / "+26097xxxxxxx" forms.
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTheme.body(
            fontSize: 12.5.sp,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        SizedBox(height: 7.h),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: _focused ? AppTheme.primaryCyan : AppTheme.divider,
              width: _focused ? 1.5 : 1,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          child: Row(
            children: [
              Text(
                '+260',
                style: AppTheme.body(
                  fontSize: 14.5.sp,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              SizedBox(width: 10.w),
              Container(width: 1, height: 20.h, color: AppTheme.divider),
              SizedBox(width: 10.w),
              Expanded(
                child: TextFormField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: widget.validator,
                  style: AppTheme.body(fontSize: 14.5.sp),
                  decoration: InputDecoration(
                    hintText: '97 123 4567',
                    hintStyle: AppTheme.body(
                      fontSize: 14.5.sp,
                      color: AppTheme.placeholder,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 16.h),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
