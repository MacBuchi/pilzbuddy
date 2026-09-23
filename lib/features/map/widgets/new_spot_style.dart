// „Neuer Spot" — EIN Name, EINE Farbe, zwei Wege dorthin: der Knopf
// unten rechts und der erste Eintrag im Kontextmenü (#513).
//
// Bis 1.192.0 stand im Menü „Spot anlegen" in `AppColors.forestGreen`,
// am Knopf „Neuer Spot" in der Theme-Farbe des FAB — ein helleres Grün.
// Der Kommentar am Menü behauptete, die Farbe leite sich vom Knopf ab;
// tatsächlich war sie eine Konstante, und der Test prüfte genau diese
// Konstante. Gemeldet vom Betreiber: zwei Namen und zwei Farben für
// denselben Vorgang lesen sich wie zwei verschiedene.
//
// Jetzt setzen BEIDE ihre Farbe aus [newSpotColors] und ihren Text aus
// [kNewSpotLabel]. Die Farbe ist die, die der Knopf schon hatte (die
// Material-3-Vorgabe eines FAB) — er ist die bekannte Hauptaktion, und
// Hilfe, Tour und Hinweise nennen ihn beim Namen.
import 'package:flutter/material.dart';

const kNewSpotLabel = 'Neuer Spot';
const kNewSpotIcon = Icons.add_location_alt;

({Color background, Color foreground}) newSpotColors(ThemeData theme) => (
      background: theme.colorScheme.primaryContainer,
      foreground: theme.colorScheme.onPrimaryContainer,
    );
