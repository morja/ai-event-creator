# AI Event Creator für macOS

Die App heißt im macOS-Dienste-Menü und im Build derzeit **AIEventExtractor**. Dieses Repository veröffentlicht ihren Quellcode als Open-Source-Vorschau unter der MIT-Lizenz.

AIEventExtractor macht aus markiertem Text einen Kalendertermin. Im Kontextmenü eines Programms wählst du unter **Dienste** den Eintrag **Termin mit AIEventExtractor erstellen**. Die App liest den ausgewählten Text, lässt ihn vom eingerichteten Modell auswerten und zeigt eine kurze, editierbare Vorschau. Erst ein Klick auf **Termin erstellen** schreibt den Termin in deinen Kalender. Du kannst die App auch direkt öffnen und Text einfügen.

Die App ist in SwiftUI und AppKit geschrieben, nutzt EventKit für den Kalender und braucht kein Hammerspoon. Version 0.2.11 ist ein lokaler Build, signiert mit dem selbst erstellten Zertifikat „AIEventExtractor Local“, falls es im Schlüsselbund liegt (sonst ad hoc). Sie ist nicht notarisiert. Es gibt noch keinen fertig geprüften App-Download; baue die Vorschau bei Bedarf aus dem Quellcode.

## Bauen und starten

Voraussetzung ist macOS 14 oder neuer mit einem Swift-6-Toolchain, etwa Xcode 16. Externe Swift-Pakete gibt es nicht.

```sh
./scripts/test.sh
./scripts/build.sh
open "dist/AIEventExtractor.app"
```

Der Build liegt unter `dist/AIEventExtractor.app`. Mit `./scripts/install.sh` kannst du ihn nach `~/Applications` kopieren und als macOS-Dienst registrieren. Das Skript überschreibt keine vorhandene AIEventExtractor-App. Die neue App hat die eigene Bundle-Kennung `org.aieventextractor.mac`, damit macOS ihren Dienst nicht mit dem früheren `Create Event` verwechselt. Einstellungen und Kalenderfreigabe musst du in der neuen App gegebenenfalls erneut hinterlegen. Der alte Build wurde im Projekt als `dist/Create Event.app.disabled` aufbewahrt, damit sein Dienst nicht wieder im Menü erscheint; er wurde nicht gelöscht.

**OpenRouter-Schlüssel während der Entwicklung:** Auf diesem Mac liest AIEventExtractor zuerst `~/.config/send-to-hammerspoon/openrouter-api-key`. Die Datei bleibt am bisherigen Ort; weder der Schlüssel noch eine Kopie davon kommen ins Repository oder App-Bundle. Die App akzeptiert nur eine kleine reguläre Datei, auf die Gruppe und andere Benutzer keinen Zugriff haben (`chmod 600`). Ist sie vorhanden, fragt AIEventExtractor den Schlüsselbund weder beim Extrahieren noch beim Öffnen der Einstellungen ab. Ist sie nicht vorhanden, bleibt der eigene Schlüsselbund-Eintrag `org.aieventextractor.mac.openrouter` als Fallback. Eine vorhandene, aber ungültige Datei führt zu einer Fehlermeldung statt zu einer Schlüsselbund-Abfrage. Für eine spätere Veröffentlichung soll diese Entwicklungsregel durch eine stabile Apple-Signieridentität und eine passende Schlüsselverwaltung ersetzt werden. Ad-hoc signierte Neu-Builds können beim Schlüsselbund-Fallback weiterhin Zugriffsabfragen auslösen.

## Einrichtung

Öffne **Einstellungen…** und wähle die Texterkennung:

- **OpenRouter:** Auf diesem Entwicklungs-Mac verwendet die App die oben genannte lokale Schlüsseldatei. Wenn sie fehlt, kannst du deinen eigenen API-Schlüssel in **Einstellungen…** im macOS-Schlüsselbund speichern. Trage außerdem eine Modell-ID ein. `openrouter/free` ist der kostenlose Standard. Für ein konkretes bezahltes Modell wie `openai/gpt-4o-mini` aktiviere **Bezahlte OpenRouter-Modelle erlauben**. Ohne dieses Häkchen akzeptiert die App nur `openrouter/free` und IDs mit `:free`. `openrouter/auto` bleibt gesperrt, weil dabei kein bestimmtes Modell feststeht. Die App versucht keinen Modell-Fallback.
- **Ollama oder LM Studio:** Starte den lokalen Server, aktualisiere die Modellliste und wähle ein Textmodell. Dafür ist kein OpenRouter-Schlüssel nötig. Die App verbindet sich nur mit `127.0.0.1:11434` für Ollama oder `127.0.0.1:1234` für LM Studio. Sie lädt keine Modelle herunter und startet keinen Server.

In den Einstellungen kannst du außerdem einen Kalender festlegen. Ohne Auswahl nimmt die App nach deiner Bestätigung den beschreibbaren Standardkalender. Beim ersten Speichern fragt macOS nach Kalenderzugriff. Die App ruft keine bestehenden Termine ab.

**Wichtig bei bezahlten Modellen:** Ein Aufruf über das Dienste-Menü startet die Extraktion sofort und kann deshalb Kosten verursachen. Der Text geht dabei an OpenRouter und den Modellanbieter. Der Kalendereintrag entsteht trotzdem erst nach deiner Bestätigung.

## Verwendung über Rechtsklick oder Tastatur

Markiere Text in einer App, die macOS-Dienste für ausgewählten Text unterstützt. Wähle im Kontextmenü **Dienste → Termin mit AIEventExtractor erstellen**. macOS kann den Dienst in manchen Apps direkt im Kontextmenü anzeigen; die App kann diese Platzierung nicht erzwingen. Der englische Menüeintrag heißt **Create event with AIEventExtractor**.

Für ein Tastaturkürzel öffne **Systemeinstellungen → Tastatur → Tastaturkurzbefehle → Dienste** und weise dem Eintrag dort ein Kürzel zu. Das ist derselbe Auswahl-Workflow, kein Zwischenablage-Hotkey. Wenn der neue Name nicht erscheint, starte die Quell-App neu. Gegebenenfalls ist eine erneute Anmeldung bei macOS nötig.

AIEventExtractor muss vorher nicht laufen. macOS startet die App erst beim Dienste-Aufruf. Während das Modell arbeitet, bleibt sie ohne Fenster, Dock-Symbol und Menüleisteneintrag im Hintergrund. Danach öffnet sie nur die Vorschau oder eine Fehlermeldung. Beim ersten Test kann das einige Sekunden dauern. Ein zusätzlicher Hintergrunddienst oder Anmeldeobjekt ist nicht nötig. [Apple beschreibt diesen Startmechanismus für macOS-Dienste](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/overview.html).

In der Vorschau lassen sich Titel, Daten, Uhrzeiten und Ort korrigieren. Neben den Datums- und Uhrzeitfeldern öffnen kleine Symbole die macOS-Auswahl. **Weitere Angaben** ist anfangs geöffnet und enthält Zeitzone, Notizen, Kalender und den zunächst eingeklappten Originaltext. **Aktualisieren** steht direkt neben der Kalenderwahl. Das Fenster nutzt mehr Höhe, bleibt aber innerhalb des sichtbaren Bildschirmbereichs; auf kleinen Bildschirmen bleibt Scrollen möglich. Bei fehlendem Schlüssel, nicht verfügbarem Modell oder einem Antwortfehler zeigt die App **Erneut versuchen** und **Text bearbeiten**. Ein zweiter Dienstaufruf fragt, bevor er einen ungespeicherten Entwurf ersetzt. **Termin erstellen** speichert den Termin und beendet die App. **Verwerfen** oder das Schließen des Fensters beendet sie ebenfalls. Nur wenn du die App selbst direkt öffnest, erscheint das Eingabefenster.

## Datumsregeln

Bei einem eindeutigen Tag und Monat ohne Jahr verwendet die Extraktion das **aktuelle Kalenderjahr in der lokalen Zeitzone**. Beispiel: Am 13. September 2026 wird „18. bis 20. September“ als 18. bis 20. September 2026 vorgeschlagen. Ein vergangenes Datum springt nicht heimlich ins nächste Jahr. Wenn das Modell bei genau einem deutschen Datum oder Datumsbereich leere Felder liefert, ergänzt die App das Datum aus dem Text. Ein ausdrücklich genanntes Jahr bleibt erhalten. Mehrdeutige oder ungültige Daten bleiben offen.

Wenn der Quelltext keine Uhrzeit nennt, schlägt die App einen ganztägigen Termin vor. Schaltest du **Ganztägig** aus, stehen 09:00–10:00 Uhr als bearbeitbarer Vorschlag bereit. Bei einem Termin mit Startzeit, aber ohne Endzeit, ergänzt sie genau eine Stunde ab dem Startzeitpunkt, auch über Mitternacht oder eine Zeitumstellung hinweg. Nennt der Text eine spätere Endzeit, aber kein eigenes Enddatum, übernimmt die App das Startdatum. Eine Endzeit vor der Startzeit bleibt ohne Enddatum offen, weil daraus nicht eindeutig hervorgeht, ob der Termin über Mitternacht geht. Bei der herbstlichen Zeitumstellung kann die lokale Enduhrzeit doppelt vorkommen. In diesem Sonderfall zeigt die Vorschau den einstündigen Termin eindeutig in UTC an.

Ganztägige Bereiche zeigen als Ende den letzten eingeschlossenen Tag. Für EventKit rechnet die App beim Speichern auf den folgenden Tagesanfang um. Nicht existierende oder doppelte ausdrücklich angegebene lokale Uhrzeiten bei einer Zeitumstellung lehnt sie ab. Prüfe die Vorschau immer am Originaltext: Auch ein formal gültiges Datum kann inhaltlich falsch sein. Die App erstellt jeweils einen Termin und erkennt keine Wiederholungen oder Teilnehmer.

Steht bei einer Uhrzeit ausdrücklich **PT** oder **Pacific Time**, interpretiert die App sie in `America/Los_Angeles` und rechnet sie für die Vorschau in die aktuelle macOS-Zeitzone um. Am 13. September 2026 wird beispielsweise 11:00 Uhr PT zu 20:00 Uhr in Berlin. Die Umrechnung berücksichtigt die Sommerzeit am Termintag und kann auch das Datum in der Vorschau ändern. **PST** und **PDT** gelten als ausdrücklich angegebene feste Offsets von UTC−8 beziehungsweise UTC−7. „Heute“ und „morgen“ beziehen sich bei solchen Angaben auf den Tag an der Pazifikküste. Ohne Quell-Zeitzone verwendet die App die aktuelle Mac-Zeitzone. Eine zusätzliche Standard-Zeitzonen-Einstellung ist nicht nötig: EventKit erhält einen absoluten Zeitpunkt und die Zeitzone des Termins. Ist eine Pazifik-Uhrzeit wegen einer Zeitumstellung doppeldeutig, muss sie vor dem Speichern korrigiert werden. Andere Zeitzonen soll das Modell gemäß Extraktionsanweisung berücksichtigen; die zusätzliche rechnerische Plausibilisierung deckt derzeit Pacific Time ab.

## Datenschutz und lokale Modelle

Der Dienste-Aufruf sendet nur den ausgewählten Text, den aktuellen Zeitpunkt und die Standard-Zeitzone an den gewählten Extraktionsanbieter. Kalenderinhalte gehen nicht mit. Entwürfe bleiben im Speicher. Die App liest den OpenRouter-Schlüssel zur Laufzeit aus der lokalen Entwicklungsdatei oder, falls diese fehlt, aus ihrem eigenen macOS-Schlüsselbund-Eintrag. Modell-, Anbieter- und Anzeigeeinstellungen liegen in UserDefaults. Die App schreibt ausgewählten Text und Schlüssel nicht in Logs.

OpenRouter und sein Modellanbieter haben eigene Datenschutzregeln. Lies vor sensiblen Inhalten die [OpenRouter-Datenschutzhinweise](https://openrouter.ai/privacy) und die Regeln des gewählten Anbieters. Bei Ollama oder LM Studio geht die Anfrage an einen Server auf diesem Mac; die App lehnt HTTP-Weiterleitungen ab. Ein lokaler Ollama-Server kann allerdings selbst Cloud-Modelle verwenden. Wenn du echte Offline-Verarbeitung brauchst, [deaktiviere Ollamas Cloud-Funktionen](https://docs.ollama.com/cloud#local-only) und prüfe die Einstellungen von LM Studio.

Ollama wird über `/api/tags` und `/api/show` abgefragt. Die zweite Prüfung verhindert, dass kaputte Modell-Manifeste als verwendbar erscheinen. Auf dem Entwicklungs-Mac meldet `ollama list` derzeit `gemma3:4b`, aber `ollama show gemma3:4b` findet das Modell nicht. Die Gewichte fehlen. AIEventExtractor bietet es daher nicht an. Lade ein funktionierendes Modell nach, wenn du diese lokale Route nutzen willst. LM Studios `/v1/models` kann je nach Just-in-time-Einstellung geladene oder heruntergeladene Modelle melden; reine Embedding-Modelle eignen sich nicht für Termine.

## Tests und Grenzen

`./scripts/test.sh` prüft Datumsvalidierung, Zeitzonen einschließlich PT-Umrechnung und Sommerzeit, die Jahresergänzung, ganztägige und einstündige Vorgaben, OpenRouter-Freigabe für bezahlte Modelle, den Vorrang der lokalen Schlüsseldatei und den Schlüsselbund-Fallback, lokale Endpunkte und Modellantworten. Der Test mit der echten lokalen Schlüsseldatei gibt deren Inhalt nicht aus und sendet keine Netzwerkanfrage. Mit einem funktionierenden Ollama-Modell ist ein optionaler Test ohne Kalenderzugriff möglich:

```sh
OLLAMA_SMOKE_MODEL=dein-modell ./scripts/test.sh --filter EventCoreTests/testOptionalOllamaSmoke
```

Auf dem Entwicklungs-Mac bestanden am 3. Oktober 2026 36 automatisierte Tests; der optionale Ollama-Test wurde ohne Modellwahl übersprungen. Ein früherer Test mit erfundenem Text über `openrouter/free` erzeugte die kurze Vorschau mit dem ergänzten Jahr 2026. Das zuvor gespeicherte konkrete Free-Modell unterstützte die angeforderte strukturierte Ausgabe nicht; `openrouter/free` wurde deshalb als funktionierende kostenlose Einstellung gewählt. Der vorherige Versuch mit `gemma3:4b` scheiterte, weil Ollama das unvollständige Modell nicht öffnen kann. Es wurde kein Modell heruntergeladen und kein Kalendereintrag erzeugt.

Im TextEdit-Dienste-Menü ist nach der Bereinigung nur noch ein AIEventExtractor-Eintrag sichtbar; der Hammerspoon-Dienst bleibt separat erhalten. Ein früherer Aufruf bei beendeter App startete AIEventExtractor ohne Standardfenster, übergab den ausgewählten Testtext und erzeugte eine Vorschau. Die Oberflächenautomation konnte sich nach der Umbenennung nicht erneut mit dem laufenden App-Fenster verbinden. Inhaltsfreie Diagnosemeldungen bestätigen den Ablauf bis zur Vorschau. Ein späterer Test ohne hinterlegten Schlüsselbund-Eintrag zeigte erwartungsgemäß keine Vorschau. Seit Version 0.2.6 kann der vorhandene lokale Entwicklungsschlüssel diesen Test ermöglichen, ohne ihn neu im Schlüsselbund zu speichern.

Vor einer Veröffentlichung bleiben manuelle Prüfungen nötig: die Vorschau des Dienstaufrufs in der neuen App direkt ansehen, OpenRouter mit Dateischlüssel und Schlüsselbund-Fallback testen, Kalenderfreigabe und Speichern prüfen, Intel-Unterstützung klären sowie die App mit einer stabilen Developer-ID signieren und notarisieren. Die App ist nicht für den Mac App Store sandboxed.

Das benachbarte Projekt `send-to-hammerspoon-calendar` bleibt unverändert. Sein Dienst **Termin erstellen** und dieser Dienst haben unterschiedliche Namen und können nebeneinander bestehen.

Technische Referenzen: [Apple-Dienste](https://developer.apple.com/documentation/bundleresources/information-property-list/nsservices), [EventKit-Kalenderzugriff](https://developer.apple.com/documentation/eventkit/accessing-the-event-store), [OpenRouter Structured Outputs](https://openrouter.ai/docs/guides/features/structured-outputs), [Ollama Structured Outputs](https://docs.ollama.com/capabilities/structured-outputs), [LM Studio Structured Output](https://lmstudio.ai/docs/developer/openai-compat/structured-output).
