import 'l10n/app_localizations.dart';

export 'l10n/app_localizations.dart';

/// A language the app ships with.
///
/// [label] is always written in the language itself, never translated: people
/// look for `العربية` or `বাংলা` in a list, not for "Arabic" or "Bengali".
class AppLanguage {
  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  /// Picker order: the default first, then the languages we actually ship.
  static const List<AppLanguage> all = [
    AppLanguage('en', 'English'),
    AppLanguage('ur', 'اردو'),
    AppLanguage('hi', 'हिन्दी'),
    AppLanguage('ar', 'العربية'),
    AppLanguage('bn', 'বাংলা'),
  ];

  static AppLanguage byCode(String code) {
    return all.firstWhere(
      (language) => language.code == code,
      orElse: () => all.first,
    );
  }

  static bool supports(String code) {
    return all.any((language) => language.code == code);
  }

  /// Languages written right to left. The layout mirrors automatically once
  /// the locale is set; this is here for the few places that need to know.
  static bool isRightToLeft(String code) {
    return const {'ur', 'ar', 'fa', 'ps', 'sd', 'ug', 'ckb', 'he'}.contains(code);
  }

  /// Languages that use the Arabic script and therefore the bundled font.
  static bool usesArabicScript(String code) {
    return const {'ur', 'ar', 'fa', 'ps', 'sd', 'ug', 'ckb'}.contains(code);
  }
}

/// String lookups that key off values coming from the native side.
extension AppStrings on AppLocalizations {
  /// A friendly message for a native error code, or null when the code is
  /// unknown so the caller can fall back to the native message.
  String? errorFor(String? code) {
    switch (code) {
      case 'private':
        return errPrivate;
      case 'login':
        return errLogin;
      case 'youtube_block':
        return errYoutubeBlock;
      case 'unsupported':
        return errUnsupported;
      case 'unavailable':
        return errUnavailable;
      case 'not_found':
        return errNotFound;
      case 'drm':
        return errDrm;
      case 'age':
        return errAge;
      case 'network':
        return errNetwork;
      case 'processing':
        return errProcessing;
      case 'no_video':
        return errNoVideo;
      case 'busy':
        return errBusy;
      case 'storage':
        return errStorage;
      case 'engine':
        return errEngine;
      case 'no_link':
        return errNoLink;
      case 'generic':
        return errGeneric;
      default:
        return null;
    }
  }

  /// A label for a native download stage.
  String stageFor(String? stage) {
    switch (stage) {
      case 'preparing':
        return preparing;
      case 'downloading':
        return downloading;
      case 'audio':
        return audio;
      case 'merging':
        return merging;
      case 'optimizing':
        return optimizing;
      case 'trimming':
        return trimming;
      case 'retrying':
        return retrying;
      case 'saving':
        return saving;
      default:
        return preparing;
    }
  }
}
