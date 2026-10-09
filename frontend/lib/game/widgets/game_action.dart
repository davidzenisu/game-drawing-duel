import 'package:flutter/material.dart';

/// Runs a game action and shows a snack bar if it fails, instead of failing
/// silently. Completes with whether the action succeeded.
Future<bool> runGameAction(BuildContext context, Future<void> Function() action) async {
  final result = await runGameQuery<bool>(context, () async {
    await action();
    return true;
  });
  return result ?? false;
}

/// Like [runGameAction] for actions with a result; completes with `null` if
/// the action failed.
Future<T?> runGameQuery<T>(BuildContext context, Future<T> Function() action) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    return await action();
  } catch (error) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('That didn\'t work: $error'), behavior: SnackBarBehavior.floating));
    return null;
  }
}
