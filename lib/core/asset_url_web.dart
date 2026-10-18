import 'dart:ui_web' as ui_web;

/// Die Adresse, unter der Flutter das Asset [key] ausliefert.
String assetUrl(String key) => ui_web.assetManager.getAssetUrl(key);
