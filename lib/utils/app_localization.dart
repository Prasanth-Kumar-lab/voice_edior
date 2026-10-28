import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/fx_slot.dart';
import '../models/mix_project.dart';

/// Phase 5 (P4): One-tap Use-Case Presets for creators.
class UseCasePreset {
  const UseCasePreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.lufsPreset,
    required this.targetLufs,
    required this.fxTypes,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final LufsPreset lufsPreset;
  final double targetLufs;
  final List<FxType> fxTypes;

  List<FxSlot> buildChain() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    return [
      for (int i = 0; i < fxTypes.length; i++)
        FxSlot(id: 'uc_${id}_${fxTypes[i].id}_${now + i}', type: fxTypes[i]),
    ];
  }

  static List<UseCasePreset> get defaults => const [
        UseCasePreset(
          id: 'youtube_vo',
          title: 'YouTube Voiceover',
          subtitle: '-14 LUFS · Broadcast EQ + De-Esser + Glue Comp',
          icon: Icons.ondemand_video_rounded,
          lufsPreset: LufsPreset.youtube14,
          targetLufs: -14.0,
          fxTypes: [
            FxType.noiseReduction,
            FxType.deEsser,
            FxType.eq8,
            FxType.compressor,
            FxType.limiter,
          ],
        ),
        UseCasePreset(
          id: 'ig_reel',
          title: 'Instagram Reel',
          subtitle: '-14 LUFS · Punchy Presence + Exciter + Stereo Width',
          icon: Icons.burst_mode_rounded,
          lufsPreset: LufsPreset.spotify14,
          targetLufs: -14.0,
          fxTypes: [
            FxType.gate,
            FxType.eq8,
            FxType.saturator,
            FxType.stereoWidener,
            FxType.limiter,
          ],
        ),
        UseCasePreset(
          id: 'zoom_lecture',
          title: 'Zoom / Lecture Cleanup',
          subtitle: '-16 LUFS · Deep Denoise + Filter + Gate',
          icon: Icons.school_rounded,
          lufsPreset: LufsPreset.podcast16,
          targetLufs: -16.0,
          fxTypes: [
            FxType.noiseReduction,
            FxType.filter,
            FxType.gate,
            FxType.compressor,
          ],
        ),
        UseCasePreset(
          id: 'audiobook_acx',
          title: 'Audiobook ACX',
          subtitle: '-19 LUFS · De-Click/De-Breath + Warmth + -3 dBTP Ceiling',
          icon: Icons.menu_book_rounded,
          lufsPreset: LufsPreset.custom,
          targetLufs: -19.0,
          fxTypes: [
            FxType.noiseReduction,
            FxType.gate,
            FxType.deEsser,
            FxType.compressor,
            FxType.limiter,
          ],
        ),
        UseCasePreset(
          id: 'kirtan_bhajan',
          title: 'Kirtan / Bhajan',
          subtitle: '-14 LUFS · Devotional Hall Reverb + Chorus + Warmth',
          icon: Icons.auto_awesome_rounded,
          lufsPreset: LufsPreset.spotify14,
          targetLufs: -14.0,
          fxTypes: [
            FxType.eq8,
            FxType.compressor,
            FxType.chorus,
            FxType.reverb,
            FxType.limiter,
          ],
        ),
        UseCasePreset(
          id: 'whatsapp_note',
          title: 'WhatsApp Voice Note',
          subtitle: '-16 LUFS · Fast Speech Clarity + Plosive Cut',
          icon: Icons.chat_bubble_outline_rounded,
          lufsPreset: LufsPreset.podcast16,
          targetLufs: -16.0,
          fxTypes: [
            FxType.noiseReduction,
            FxType.eq8,
            FxType.compressor,
          ],
        ),
      ];
}

/// Global preferences controller for Light/Dark/System ThemeMode and English/Hindi/Telugu Localization.
class AppPreferencesController extends GetxController {
  final Rx<ThemeMode> themeMode = ThemeMode.dark.obs;
  final RxString languageCode = 'en'.obs;

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'studio': 'Studio',
      'mix': 'Mix',
      'pro': 'Pro',
      'profile': 'Profile',
      'creator_profile': 'Creator Profile',
      'appearance_language': 'Appearance & Language',
      'theme_mode': 'Studio Theme',
      'language': 'Interface Language',
      'privacy_terms': 'Privacy, Terms & Data Safety',
      'delete_account': 'Delete Account & Cloud Data',
    },
    'hi': {
      'studio': 'स्टूडियो',
      'mix': 'मिक्स',
      'pro': 'प्रो',
      'profile': 'प्रोफ़ाइल',
      'creator_profile': 'क्रिएटर प्रोफ़ाइल',
      'appearance_language': 'थीम और भाषा',
      'theme_mode': 'स्टूडियो थीम',
      'language': 'भाषा (Language)',
      'privacy_terms': 'गोपनीयता, शर्तें और डेटा सुरक्षा',
      'delete_account': 'खाता और डेटा हटाएं',
    },
    'te': {
      'studio': 'స్టూడియో',
      'mix': 'మిక్స్',
      'pro': 'प्रो',
      'profile': 'ప్రొఫైల్',
      'creator_profile': 'క్రియేటర్ ప్రొఫైల్',
      'appearance_language': 'థీమ్ & భాష',
      'theme_mode': 'స్టూడియో థీమ్',
      'language': 'భాష (Language)',
      'privacy_terms': 'గోప్యత, నిబంధనలు & డేటా భద్రత',
      'delete_account': 'ఖాతా & డేటాను తొలగించండి',
    },
  };

  String trKey(String key) {
    final map = _strings[languageCode.value] ?? _strings['en']!;
    return map[key] ?? _strings['en']![key] ?? key;
  }

  void setThemeMode(ThemeMode mode) {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
  }

  void setLanguage(String code) {
    if (_strings.containsKey(code)) {
      languageCode.value = code;
    }
  }
}
