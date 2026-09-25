/// Turning failures into something a household can act on.
///
/// Services throw for developers: [ShoppingException], [PlanningException] and
/// sqflite's own `DatabaseException` all carry text meant for a stack trace,
/// not for someone standing in a kitchen. Screens therefore never render an
/// error object — they call [PrepErrorMessages.forError], which returns the
/// one sentence that is safe and useful to show.
library;

/// A failure whose own message is written for the household.
///
/// Implement this on validation-style exceptions — "you have not selected a
/// meal yet" — that the UI is meant to repeat verbatim. Anything that does
/// not implement it is treated as internal and replaced with a fallback,
/// which is what keeps raw SQLite text off the screen by default rather than
/// by remembering to sanitise it at each call site.
abstract class PrepUserFacingException implements Exception {
  /// The sentence to show. Concise, specific, and about what to do next.
  String get userMessage;
}

/// Maps a caught error to display copy.
class PrepErrorMessages {
  const PrepErrorMessages._();

  /// The generic line, used whenever the failure is internal.
  static const String genericMessage =
      'Something went wrong. Please try again.';

  /// Copy for [error], or [fallback] when it has nothing safe to say.
  ///
  /// Returns null for a null error so callers can write
  /// `final message = PrepErrorMessages.forError(provider.error)` and branch
  /// on the result rather than on the error itself.
  static String? forError(Object? error, {String fallback = genericMessage}) {
    if (error == null) return null;
    if (error is PrepUserFacingException) return error.userMessage;
    return fallback;
  }
}
