/// Tiny two-language dictionary. English is the fallback for every key.
class Strings {
  const Strings(this.lang);

  final String lang;

  bool get isUrdu => lang == 'ur';

  String t(String key) {
    return _values[lang]?[key] ?? _en[key] ?? key;
  }

  /// A friendly message for a native error code.
  String errorFor(String? code) {
    final key = 'err_${code ?? 'generic'}';
    return t(key);
  }

  /// A label for a native download stage.
  String stageFor(String? stage) {
    switch (stage) {
      case 'preparing':
        return t('preparing');
      case 'downloading':
        return t('downloading');
      case 'audio':
        return t('audio');
      case 'merging':
        return t('merging');
      case 'optimizing':
        return t('optimizing');
      case 'trimming':
        return t('trimming');
      case 'retrying':
        return t('retrying');
      case 'saving':
        return t('saving');
      default:
        return t('preparing');
    }
  }

  static const Map<String, Map<String, String>> _values = {
    'en': _en,
    'ur': _ur,
  };

  static const Map<String, String> _en = {
    'appName': 'Save & Send',
    'appSubtitle': 'Your private video saver',
    'tagline': 'Save any video.\nSend it in one tap.',
    'taglineSub': 'Paste a link or share one from your favourite app.',
    'heroEyebrow': 'Private & simple',
    'trustPrivate': 'Stays on this phone',
    'trustNoAccount': 'No sign-in needed',
    'step1Title': 'Share a link',
    'step1Body': 'From Instagram, Facebook, YouTube or TikTok, tap Share and pick this app.',
    'step2Title': 'We download it',
    'step2Body': 'Video and sound are saved to your Gallery.',
    'step3Title': 'Send it',
    'step3Body': 'One tap for WhatsApp or Status.',
    'worksWith': 'Works with Instagram, Facebook, YouTube, TikTok and more.',
    'linkLabel': 'Video link',
    'linkHelp': 'Paste a link from any app.',
    'pasteHint': 'https://instagram.com/reel/…',
    'paste': 'Paste',
    'download': 'Download video',
    'downloadHint': 'MP4 with sound • up to 60 seconds',
    'preparing': 'Getting ready…',
    'preparingFirst': 'First-time setup…\nThis takes a few seconds.',
    'downloading': 'Downloading video…',
    'audio': 'Downloading sound…',
    'merging': 'Adding sound…',
    'optimizing': 'Making it WhatsApp-ready…',
    'trimming': 'Keeping the first 60 seconds…',
    'retrying': 'Trying another way…',
    'saving': 'Saving to your Gallery…',
    'progressEyebrow': 'Downloading',
    'progressHelp': 'Keep this screen open while it downloads. It only takes a moment.',
    'cancel': 'Cancel',
    'cancelTitle': 'Stop this download?',
    'cancelBody': 'The video will not be saved.',
    'keepDownloading': 'Keep downloading',
    'stop': 'Stop',
    'readyTitle': 'Ready to send!',
    'readySubtitle': 'Your video is saved and ready.',
    'savedGallery': 'Saved to your Gallery',
    'notSavedGallery': "Couldn't save to Gallery",
    'saveGallery': 'Save to Gallery',
    'sound': 'With sound',
    'noSound': 'No sound in this video',
    'trimmedNote': 'The first 60 seconds were kept for Status.',
    'sendSection': 'Send it',
    'sendHelp': 'Choose where it should go.',
    'saveSection': 'Saved to your phone',
    'sendWhatsApp': 'Send on WhatsApp',
    'sendStatus': 'Post to Status',
    'moreApps': 'More apps',
    'done': 'Done',
    'errorTitle': "Couldn't download this video",
    'tryAgain': 'Try again',
    'shareLink': 'Share the link instead',
    'details': 'Details',
    'hideDetails': 'Hide details',
    'noLinkTitle': 'No link found',
    'noLinkBody': 'Share a video link from Instagram, Facebook, YouTube or TikTok.',
    'settings': 'Settings',
    'settingsSubtitle': 'Make it work the way you like.',
    'language': 'Language',
    'languageHelp': 'Choose the language for buttons and messages.',
    'english': 'English',
    'urdu': 'اردو',
    'downloader': 'Downloader',
    'engineUpdates': 'YouTube updates',
    'downloaderHelp': 'Keep it fresh when YouTube changes.',
    'version': 'Version',
    'update': 'Update downloader',
    'updating': 'Updating…',
    'updateDone': 'Downloader updated.',
    'updateFailed': "Couldn't update. Check your internet.",
    'cookiesSaved': 'Cookies saved.',
    'cookiesRemoved': 'Cookies removed.',
    'saveFailed': "Couldn't save.",
    'timeLeft': 'About {time} left',
    'loginCookies': 'Login cookies',
    'instagramCookies': 'Instagram cookies',
    'cookiesAdded': 'Added',
    'cookiesNotAdded': 'Not added',
    'addReplace': 'Add / replace',
    'cookiesHelp':
        'Only needed when Instagram, Facebook or YouTube asks for a login. Export a cookies.txt file from a browser and paste it here. It stays on this phone.',
    'save': 'Save',
    'remove': 'Remove',
    'about': 'About',
    'aboutBody':
        'A personal app for saving public videos and sending them on WhatsApp. Videos belong to their owners. Please respect copyright.',
    'howTo': 'How to use',
    'howItWorks': 'How it works',
    'howItWorksHelp': 'Three small steps, then it is ready to send.',
    'close': 'Close',
    'busy': 'Please wait for the current download to finish.',
    'statusFallback':
        "Your WhatsApp doesn't support direct Status. Pick a contact instead.",
    'whatsappMissing': 'WhatsApp is not installed.',
    'shareFailed': "Couldn't open the share screen.",
    'galleryPermission': 'Allow storage access to save videos to your Gallery.',
    'engineErrorTitle': "Couldn't start the downloader",
    'engineErrorBody': 'Try again. If it keeps failing, reinstall the app.',
    'retrySetup': 'Try again',
    'firstTime': 'First-time setup',
    'privacy': 'No account. No sign-in.',
    'personalNote': 'Personal use',
    'statusNote': 'Up to 60 seconds for Status',
    'preview': 'Preview',
    'play': 'Play',
    'pause': 'Pause',
    'mute': 'Mute',
    'unmute': 'Sound on',
    'openSettings': 'Open Settings',
    'engineReady': 'Downloader ready',
    'enginePreparing': 'Preparing downloader…',
    'err_private': 'This video is private. Only public videos can be downloaded.',
    'err_login':
        'This video needs a login. Add login cookies in Settings (advanced).',
    'err_youtube_block':
        'YouTube is blocking this download. Update the downloader in Settings, or add YouTube cookies, then try again.',
    'err_unsupported': "This link isn't supported.",
    'err_unavailable': 'This video is no longer available.',
    'err_not_found': "This video couldn't be found. The link may have expired.",
    'err_drm': "This video is protected and can't be downloaded.",
    'err_age':
        "This video is age-restricted and can't be downloaded without a login.",
    'err_network': 'No internet connection. Check your connection and try again.',
    'err_processing':
        "The video downloaded, but it couldn't be prepared. Try again.",
    'err_no_video': 'No downloadable video was found at this link.',
    'err_busy': 'Please wait for the current download to finish.',
    'err_storage': "There isn't enough storage space for this video.",
    'err_engine': "Couldn't start the downloader. Try again.",
    'err_no_link': 'No link found in what you shared.',
    'err_generic':
        "Couldn't download this video. It may be private, deleted, or the link may be wrong.",
  };

  static const Map<String, String> _ur = {
    'appName': 'Save & Send',
    'appSubtitle': 'آپ کی نجی ویڈیو سیور',
    'tagline': 'کوئی بھی ویڈیو محفوظ کریں۔\nایک ٹیپ میں بھیجیں۔',
    'taglineSub': 'لنک پیسٹ کریں یا کسی بھی ایپ سے شیئر کریں۔',
    'heroEyebrow': 'نجی اور آسان',
    'trustPrivate': 'صرف اسی فون پر',
    'trustNoAccount': 'لاگ ان کی ضرورت نہیں',
    'step1Title': 'لنک شیئر کریں',
    'step1Body':
        'انسٹاگرام، فیس بک، یوٹیوب یا ٹک ٹاک سے Share دبائیں اور یہ ایپ چنیں۔',
    'step2Title': 'ہم ڈاؤن لوڈ کرتے ہیں',
    'step2Body': 'ویڈیو اور آواز گیلری میں محفوظ ہو جاتی ہے۔',
    'step3Title': 'بھیجیں',
    'step3Body': 'واٹس ایپ یا اسٹیٹس کے لیے ایک ٹیپ۔',
    'worksWith': 'انسٹاگرام، فیس بک، یوٹیوب، ٹک ٹاک اور مزید۔',
    'linkLabel': 'ویڈیو لنک',
    'linkHelp': 'کسی بھی ایپ سے لنک پیسٹ کریں۔',
    'pasteHint': 'https://instagram.com/reel/…',
    'paste': 'پیسٹ',
    'download': 'ویڈیو ڈاؤن لوڈ کریں',
    'downloadHint': 'آواز کے ساتھ MP4 • 60 سیکنڈ تک',
    'preparing': 'تیاری ہو رہی ہے…',
    'preparingFirst': 'پہلی بار سیٹ اپ…\nچند سیکنڈ لگیں گے۔',
    'downloading': 'ویڈیو ڈاؤن لوڈ ہو رہی ہے…',
    'audio': 'آواز ڈاؤن لوڈ ہو رہی ہے…',
    'merging': 'آواز شامل کی جا رہی ہے…',
    'optimizing': 'واٹس ایپ کے لیے تیار کیا جا رہا ہے…',
    'trimming': 'پہلے 60 سیکنڈ رکھے جا رہے ہیں…',
    'retrying': 'دوسرا طریقہ آزمایا جا رہا ہے…',
    'saving': 'گیلری میں محفوظ کیا جا رہا ہے…',
    'progressEyebrow': 'ڈاؤن لوڈ ہو رہا ہے',
    'progressHelp': 'ڈاؤن لوڈ کے دوران یہ اسکرین کھلی رکھیں۔ صرف چند لمحے لگیں گے۔',
    'cancel': 'منسوخ کریں',
    'cancelTitle': 'ڈاؤن لوڈ روکیں؟',
    'cancelBody': 'ویڈیو محفوظ نہیں ہوگی۔',
    'keepDownloading': 'جاری رکھیں',
    'stop': 'روکیں',
    'readyTitle': 'بھیجنے کے لیے تیار!',
    'readySubtitle': 'ویڈیو محفوظ اور تیار ہے۔',
    'savedGallery': 'گیلری میں محفوظ ہو گئی',
    'notSavedGallery': 'گیلری میں محفوظ نہیں ہو سکی',
    'saveGallery': 'گیلری میں محفوظ کریں',
    'sound': 'آواز کے ساتھ',
    'noSound': 'اس ویڈیو میں آواز نہیں',
    'trimmedNote': 'اسٹیٹس کے لیے پہلے 60 سیکنڈ محفوظ کیے گئے۔',
    'sendSection': 'بھیجیں',
    'sendHelp': 'منزل چنیں۔',
    'saveSection': 'آپ کے فون میں محفوظ',
    'sendWhatsApp': 'واٹس ایپ پر بھیجیں',
    'sendStatus': 'اسٹیٹس پر لگائیں',
    'moreApps': 'مزید ایپس',
    'done': 'ہو گیا',
    'errorTitle': 'ویڈیو ڈاؤن لوڈ نہیں ہو سکی',
    'tryAgain': 'دوبارہ کوشش کریں',
    'shareLink': 'لنک شیئر کریں',
    'details': 'تفصیل',
    'hideDetails': 'تفصیل چھپائیں',
    'noLinkTitle': 'کوئی لنک نہیں ملا',
    'noLinkBody':
        'انسٹاگرام، فیس بک، یوٹیوب یا ٹک ٹاک سے ویڈیو کا لنک شیئر کریں۔',
    'settings': 'ترتیبات',
    'settingsSubtitle': 'اپنی پسند کے مطابق بنائیں۔',
    'language': 'زبان',
    'languageHelp': 'بٹنوں اور پیغامات کی زبان چنیں۔',
    'english': 'English',
    'urdu': 'اردو',
    'downloader': 'ڈاؤن لوڈر',
    'engineUpdates': 'یوٹیوب اپ ڈیٹس',
    'downloaderHelp': 'یوٹیوب بدلے تو اسے تازہ رکھیں۔',
    'version': 'ورژن',
    'update': 'ڈاؤن لوڈر اپ ڈیٹ کریں',
    'updating': 'اپ ڈیٹ ہو رہا ہے…',
    'updateDone': 'ڈاؤن لوڈر اپ ڈیٹ ہو گیا۔',
    'updateFailed': 'اپ ڈیٹ نہیں ہو سکا۔ انٹرنیٹ چیک کریں۔',
    'cookiesSaved': 'کوکیز محفوظ ہو گئیں۔',
    'cookiesRemoved': 'کوکیز ہٹا دی گئیں۔',
    'saveFailed': 'محفوظ نہیں ہو سکا۔',
    'timeLeft': 'تقریباً {time} باقی',
    'loginCookies': 'لاگ ان کوکیز',
    'instagramCookies': 'انسٹاگرام کوکیز',
    'cookiesAdded': 'شامل ہیں',
    'cookiesNotAdded': 'شامل نہیں',
    'addReplace': 'شامل / تبدیل کریں',
    'cookiesHelp':
        'صرف اس وقت ضروری ہے جب انسٹاگرام، فیس بک یا یوٹیوب لاگ ان مانگے۔ براؤزر سے cookies.txt نکالیں اور یہاں پیسٹ کریں۔ یہ صرف اس فون پر رہتی ہیں۔',
    'save': 'محفوظ کریں',
    'remove': 'ہٹائیں',
    'about': 'ایپ کے بارے میں',
    'aboutBody':
        'یہ ایک ذاتی ایپ ہے جو عوامی ویڈیوز محفوظ کر کے واٹس ایپ پر بھیجنے کے لیے بنی ہے۔ ویڈیوز ان کے مالکان کی ملکیت ہیں۔ کاپی رائٹ کا خیال رکھیں۔',
    'howTo': 'استعمال کا طریقہ',
    'howItWorks': 'یہ کیسے کام کرتا ہے',
    'howItWorksHelp': 'تین چھوٹے قدم، پھر بھیجنے کے لیے تیار۔',
    'close': 'بند کریں',
    'busy': 'پہلے موجودہ ڈاؤن لوڈ مکمل ہونے دیں۔',
    'statusFallback':
        'آپ کا واٹس ایپ سیدھا اسٹیٹس سپورٹ نہیں کرتا۔ رابطہ چنیں۔',
    'whatsappMissing': 'واٹس ایپ انسٹال نہیں ہے۔',
    'shareFailed': 'شیئر اسکرین نہیں کھل سکی۔',
    'galleryPermission':
        'گیلری میں محفوظ کرنے کے لیے اسٹوریج کی اجازت دیں۔',
    'engineErrorTitle': 'ڈاؤن لوڈر شروع نہیں ہو سکا',
    'engineErrorBody': 'دوبارہ کوشش کریں۔ اگر پھر بھی نہ ہو تو ایپ دوبارہ انسٹال کریں۔',
    'retrySetup': 'دوبارہ کوشش کریں',
    'firstTime': 'پہلی بار سیٹ اپ',
    'privacy': 'کوئی اکاؤنٹ نہیں۔ کوئی لاگ ان نہیں۔',
    'personalNote': 'ذاتی استعمال',
    'statusNote': 'اسٹیٹس کے لیے 60 سیکنڈ تک',
    'preview': 'پیش منظر',
    'play': 'چلائیں',
    'pause': 'روکیں',
    'mute': 'آواز بند',
    'unmute': 'آواز چالو',
    'openSettings': 'ترتیبات کھولیں',
    'engineReady': 'ڈاؤن لوڈر تیار ہے',
    'enginePreparing': 'ڈاؤن لوڈر تیار ہو رہا ہے…',
    'err_private': 'یہ ویڈیو نجی ہے۔ صرف عوامی ویڈیوز ڈاؤن لوڈ ہو سکتی ہیں۔',
    'err_login':
        'اس ویڈیو کے لیے لاگ ان ضروری ہے۔ ترتیبات میں لاگ ان کوکیز شامل کریں۔',
    'err_youtube_block':
        'یوٹیوب ڈاؤن لوڈ روک رہا ہے۔ ترتیبات میں ڈاؤن لوڈر اپ ڈیٹ کریں یا یوٹیوب کوکیز شامل کریں، پھر دوبارہ کوشش کریں۔',
    'err_unsupported': 'یہ لنک سپورٹ نہیں ہوتا۔',
    'err_unavailable': 'یہ ویڈیو اب دستیاب نہیں۔',
    'err_not_found': 'یہ ویڈیو نہیں ملی۔ لنک کی مدت ختم ہو سکتی ہے۔',
    'err_drm': 'یہ ویڈیو محفوظ ہے اور ڈاؤن لوڈ نہیں ہو سکتی۔',
    'err_age':
        'یہ ویڈیو عمر کی پابندی والی ہے اور لاگ ان کے بغیر ڈاؤن لوڈ نہیں ہو سکتی۔',
    'err_network': 'انٹرنیٹ نہیں ہے۔ کنکشن چیک کریں اور دوبارہ کوشش کریں۔',
    'err_processing':
        'ویڈیو ڈاؤن لوڈ ہوئی لیکن تیار نہیں ہو سکی۔ دوبارہ کوشش کریں۔',
    'err_no_video': 'اس لنک پر کوئی ڈاؤن لوڈ ہونے والی ویڈیو نہیں ملی۔',
    'err_busy': 'پہلے موجودہ ڈاؤن لوڈ مکمل ہونے دیں۔',
    'err_storage': 'اس ویڈیو کے لیے کافی اسٹوریج نہیں ہے۔',
    'err_engine': 'ڈاؤن لوڈر شروع نہیں ہو سکا۔ دوبارہ کوشش کریں۔',
    'err_no_link': 'آپ نے جو شیئر کیا اس میں کوئی لنک نہیں تھا۔',
    'err_generic':
        'یہ ویڈیو ڈاؤن لوڈ نہیں ہو سکی۔ یہ نجی، حذف شدہ یا غلط لنک ہو سکتا ہے۔',
  };
}
