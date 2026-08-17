import 'package:flutter/material.dart';

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        backgroundColor: const Color(0xFF16130F),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: const Duration(milliseconds: 2200),
        margin: const EdgeInsets.only(left: 22, right: 22, bottom: 100),
      ),
    );
}
