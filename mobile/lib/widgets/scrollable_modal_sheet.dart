import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Panel inferior que no compite con el scroll de su contenido.
///
/// [showModalBottomSheet] arrastra la hoja con el mismo gesto vertical que
/// el ListView, y el [touchSlop] global de la app (36) agrava el conflicto.
/// Este diálogo no registra drag vertical en el contenedor.
Future<T?> showScrollableModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  double heightFactor = 0.6,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _ScrollableModalSheetHost(
        heightFactor: heightFactor,
        builder: builder,
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _ScrollableModalSheetHost extends StatelessWidget {
  const _ScrollableModalSheetHost({
    required this.builder,
    required this.heightFactor,
  });

  final WidgetBuilder builder;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    final height = (mq.size.height - keyboard) * heightFactor;

    return MediaQuery(
      data: mq.copyWith(
        gestureSettings: const DeviceGestureSettings(touchSlop: 8),
        viewInsets: EdgeInsets.zero,
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 8,
            clipBehavior: Clip.antiAlias,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: SafeArea(
                top: false,
                child: builder(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
