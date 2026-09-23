-- Patch 035: Feedback-Bilder dürfen größer sein (#569 Teil b).
--
-- > Ist auch sichergestellt, dass die Auflösung der Feedback-Fotos groß
-- > genug ist? — Vorschlag ok. (Betreiber, 2026-09-23)
--
-- Bilder aus dem Art-Hinweis dürfen mit Einwilligung in die Artgalerie
-- (Patch 034), und die zeigt vergrößert 1200x1200. Mit 1024er Kante
-- blieben aus einem 4:3-Foto 768 px im Quadrat. Die App lädt diese
-- Bilder deshalb seit 1.199.0 mit 2048er Kante und Qualität 85 hoch
-- (`prepareGalleryPhoto`) — und das Hochgeladene ist bei einem fremden
-- Melder die einzige Kopie, die es je gibt.
--
-- GEMESSEN an elf echten Fundfotos (Pixel, 2026-09-23): 581–1186 KB.
-- Die alte Grenze von 600 KB hätte fast jedes davon abgewiesen; 2 MB
-- lassen dem größten gut 70 % Luft.
--
-- Nur die Grenze, nicht der Bucket: kein neues Recht, keine neue
-- Policy. Ältere Clients laden weiter 1024er Bilder, die ohnehin
-- darunter liegen.
update storage.buckets
   set file_size_limit = 2000000
 where id = 'feedback-photos';
