// Die Nummer des Karten-Reiters — als Zahl, die man importieren kann.
//
// Eigene Datei, weil `router.dart` jeden Bildschirm importiert: Ein
// Bildschirm, der von dort eine Konstante holt, schlösse den Kreis.
//
// Ein Wächter dafür wäre eine Textprüfung auf der Reihenfolge der
// Branches — und damit eine Prüfung, die erst recht niemand liest. Die
// Zahl hält stattdessen `test/flows/spots_tab_flow_test.dart` fest: Er
// tippt in der Liste auf „Auf der Karte zeigen" und verlangt die Karte.
// Eine falsche Zahl landet auf einem anderen Reiter und fällt sofort
// auf.
const kMapBranchIndex = 0;
