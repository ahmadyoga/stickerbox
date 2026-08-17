import 'package:flutter/material.dart';

import '../theme.dart';

Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).extension<AppColors>()!.surf,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: builder(sheetContext),
    ),
  );
}

Widget sheetDragHandle(BuildContext context) {
  return Center(
    child: Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).extension<AppColors>()!.line,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
