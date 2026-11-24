import 'dart:isolate';

/// Runs `work(arg)` in a background isolate and returns the result.
///
/// Use this instead of `Isolate.run(() => ...)` inside widgets and
/// controllers: a closure written there can carry its surroundings (the
/// widget's State, controllers, open ports) into the message, and sending
/// those fails ("object is unsendable"). Here the closure is made in this
/// top-level function, so only [work] (a top-level or static function) and
/// [arg] (plain data: numbers, strings, lists, typed data, records, simple
/// objects) are sent.
Future<R> runInBackground<A, R>(R Function(A arg) work, A arg) =>
    Isolate.run(() => work(arg));
