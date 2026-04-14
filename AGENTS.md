# AGENTS.md — Atraxis

## Scope

Diese Datei liegt im Repo-Root und gilt für das gesamte Atraxis-Repo, solange keine tiefer liegenden `AGENTS.md`-Dateien speziellere Regeln definieren.

## Projektkontext

Atraxis ist ein Godot-basiertes Simulationsprojekt mit Schwerpunkt auf Gravitation, Worldgen, Materialisierung und Debug-Diagnostik.
Die Codebasis ist überwiegend GDScript.
Arbeite repo-konform, inkrementell und mit Fokus auf Stabilität, Lesbarkeit und Performance.

## Arbeitsstil

- Bevorzuge kleine, lokale und überprüfbare Änderungen statt großer Rewrites.
- Erfinde keine neue Architektur, die nicht durch den aktuellen Code, Tests oder vorhandene Projektstruktur gestützt wird.
- Vermische nicht gleichzeitig Solver-Umbau, Spawn-Umbau, Debug-Umbau und Rendering-Umbau, wenn sie getrennt geprüft werden können.
- Wenn mehrere Lösungswege möglich sind, wähle die kleinste robuste Variante, die mit der vorhandenen Architektur harmoniert.
- Markiere Unsicherheit klar, statt versteckte Annahmen einzubauen.

## Zentrale Repo-Struktur

- `simulation/sim_world.gd` ist die zentrale Simulationsinstanz.
- `SimWorld.step_sim()` ist der zentrale Einstiegspunkt für Simulationsfortschritt.
- `SimWorld` emittiert Signale für Rendering/UI; diese sollen nicht zurück in die Simulationslogik schreiben.
- `simulation/sim_body.gd` ist ein `RefCounted`-Datencontainer für Sim-Körper.
- Respektiere die vorhandenen Zustandsmodelle in `SimBody`, insbesondere:
  - `BodyType`
  - `InfluenceLevel`
  - `OrbitBindingState`
- `simulation/gravity_solver.gd` nutzt eine vorhandene A/B/C-Gravitationshierarchie. Ändere diese nicht breitflächig ohne klaren Grund.
- `simulation/sim_constants.gd` ist das zentrale Tuning- und Konstantenmodul.

## Wichtige Simulationsregeln

- Behandle den Integrator nicht vorschnell als Hauptursache, wenn ein Problem eher in Spawn-, Host-, Dominanz-, Builder- oder Interaktionslogik liegen kann.
- Wenn du Orbit- oder Gravitätsverhalten änderst, prüfe immer die Auswirkungen auf:
  - `SimBody`
  - `GravitySolver`
  - `SimWorld`
  - `WorldBuilder`
  - `simulation/anchor_field.gd`
  - `debug/debug_metrics.gd`
  - relevante Tests
- Wenn möglich, Änderungen so schneiden, dass Produktverhalten gezielt verbessert wird, ohne unnötig viele Subsysteme gleichzeitig umzubauen.

## Konstanten und Skalierung

- Verwende `simulation/sim_constants.gd` als zentrales Tuning- und Konstantenmodul.
- Füge neue Schwellenwerte, Skalierungsfaktoren und Simulationsparameter bevorzugt dort ein.
- Vermeide Magic Numbers in Solver-, Builder- oder Debug-Logik.
- Wenn du neue Konstanten einführst, wähle klare, semantische Namen.
- Beachte bei Skalierungsänderungen:
  - Die Körperradien in `sim_constants.gd` sind als stilisierte Größen für Lesbarkeit dokumentiert.
  - `SIM_TO_SCREEN` steuert separat die Standard-Sichtbarkeit.
  - Änderungen an Radien und Änderungen an Sichtmaßstab sind nicht automatisch dasselbe und sollen bewusst getrennt geprüft werden.

## WorldBuilder, Registry und Materialisierung

- `simulation/world_builder.gd` enthält zentrale Spawn-, Session-, Preview- und Materialisierungslogik.
- Dynamische Sterne werden derzeit host-bezogen erzeugt und als `FREE_DYNAMIC` gesetzt.
- Host-Zuordnung läuft über bestehende Orbit-/Parent-Felder wie `orbit_parent_id`.
- `WorldBuilder` materialisiert registrierte Cluster-Objekte deterministisch in die lokale `SimWorld`.
- Änderungen an Worldgen, Preview, Registry oder Materialisierung dürfen die Zuordnung zwischen registrierten Objektzuständen und materialisierten Sim-Körpern nicht versehentlich brechen.
- Wenn eine Änderung Geometrie oder Skalierung betrifft, prüfe immer Auswirkungen auf:
  - Spawn-Clearance
  - Orbitabstände
  - Kollisionen
  - Materialisierung / Preview-Konsistenz
  - bestehende Builder- und Kamera-/Renderer-Tests

## Multi-BH-Sensitivität

- Bevorzuge bei multi-BH-relevanten Änderungen `get_black_holes()` statt Logik, die stillschweigend nur mit einem einzelnen BH arbeitet.
- Sei vorsichtig mit Legacy-Helfern, die bewusst nur ein einzelnes aktives BH zurückgeben.

## Debug und Diagnose

- `debug/debug_metrics.gd` ist Teil der Diagnoseoberfläche, nicht bloß Beiwerk.
- Wenn du Hostwechsel, Dominanzverhalten, Sternbegegnungen oder Systemstabilität veränderst, pflege die zugehörigen Debugmetriken mit.
- Bevorzuge diagnostisch sichtbare Änderungen gegenüber schwer nachvollziehbarer impliziter Logik.
- Nutze vorhandene Diagnosepfade wie Host-/Dominanz-/Handoff-/Encounter-Daten, statt parallele Black-Box-Strukturen zu bauen.

## Tests

- Nutze die vorhandenen GUT-Tests.
- Standard-Testpfad laut Repo:
  - `powershell -ExecutionPolicy Bypass -File .\scripts\run-gut-tests.ps1`
- Wenn du Simulationsverhalten änderst, prüfe besonders bestehende Tests rund um:
  - `test_sim_world.gd`
  - `test_gravity.gd`
  - `test_world_builder.gd`
  - `test_debug_metrics.gd`
  - `test_anchor_field.gd`
- Wenn du Kamera-, Sicht- oder Darstellungsverhalten berührst, prüfe zusätzlich passende Tests wie:
  - `test_sim_camera.gd`
  - `test_world_renderer.gd`
- Erweitere bestehende Tests bevorzugt, statt parallele redundante Testpfade zu bauen.

## Erwartetes Abschlussformat

Gib nach einer Änderung immer kurz an:
- welche Dateien geändert wurden
- was geändert wurde
- warum diese Variante gewählt wurde
- welche Tests ausgeführt wurden
- ob etwas ungetestet blieb
- welche sinnvollen nächsten Schritte es gibt