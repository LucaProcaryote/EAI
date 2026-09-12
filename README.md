# EAI — Interoperability server

Part of **Mini-Hospital 2026**, a teaching hospital built for the course on
hospital, e-health and connected-medical-device informatics.

This is the plumbing between the other applications: a FHIR repository, a
message log, and a visual editor for building the flows that move data around.

## Run it

```bash
flutter pub get
flutter run -d chrome
```

For the FHIR repository as well:

```bash
cd fhir-server && docker compose up -d      # first boot takes ~3 minutes
cd .. && flutter run -d chrome --dart-define=FHIR_BASE=http://localhost:8080/fhir
```

## What is in it

| Screen | What it does |
|---|---|
| **Integration flows** | The flows, with their message counts and any structural problems. Open one to edit it. |
| **Message log** | Everything the engine has handled, expandable to the full payload and the step-by-step trace. |
| **FHIR resources** | Server status, a resource browser with search, and one button to load the fictive hospital into FHIR. |

## The visual flow builder

Drag a block from the palette onto the canvas, click one block's output port and
then another's input port to wire them together, and set the block up in the
properties panel on the right.

**Fourteen block types in three families.** Sources produce messages (an HTTP
endpoint, the device feed, ADT events, a timer). Processors change or drop them
(filter, field mapper, patient enricher, FHIR validator, code translator,
router). Destinations deliver them (the FHIR store, an application, an HTTP
call, a log).

Each family has its own colour **and** its name written on every block, so the
shape of a flow is readable at a glance without colour being the only signal.

**Validation is live.** The properties panel lists everything that would stop
the flow running — a block with no incoming wire, a flow with no destination —
and clicking an issue selects the block that caused it.

**The properties panel is shaped like the configuration**, not a JSON box. A
filter gets a field, an operator and a value; a mapper gets a table of
source → target rows each with its own transformation. Students are learning
what a field mapper *is*, and a text area full of braces teaches them nothing
about that.

**Deleting a block deletes its wires.** A dangling edge would break the flow
silently.

**Undo** treats a whole drag as one step rather than one per pixel.

## The test panel is the point

A flow that only reports "delivered" or "failed" teaches nothing. Press **Run**
and every step is listed with what it did and the payload as it left that step —
so you can watch a FHIR Observation get flattened into an alert by the mapper,
and see precisely which filter dropped the message that did not arrive.

Test runs are always dry: pressing Run on a half-built flow never writes to the
FHIR server or to another application.

Five ready-made payloads are built in, including one that is deliberately not
FHIR at all, so students can see what the validator says about it.

## The three worked flows

They are meant to be read before they are run.

1. **Device vitals to the record** — validate, enrich with the patient's
   demographics, then store in FHIR *and* push to the EHR. The fan-out from one
   processor to two destinations is the pattern to notice.
2. **ADT movements fan-out** — a router sends admissions, transfers and
   discharges down three different branches.
3. **Low SpO2 alert** — two filters in series, then a mapper that reshapes a
   FHIR Observation into a flat alert. Everything else is dropped, so the alert
   channel stays quiet until it matters.

## The FHIR server

`fhir-server/` holds a docker-compose stack running the real HAPI FHIR R4 JPA
server on PostgreSQL — not a mock. Students get proper search parameters,
`_include`, history, `$validate` and a capability statement. See
[`fhir-server/README.md`](fhir-server/README.md) for the exercises.

The *Load the fictive patients into FHIR* button posts one transaction bundle
using `PUT Patient/pat-001` rather than `POST` — update-as-create — so the ids
in the FHIR server match the ones in the application databases and references
resolve across both.

## Configuration

| Define | Values | Default |
|---|---|---|
| `BACKEND` | `memory`, `restApi`, `dataConnect` | `memory` |
| `AUTH` | `demo`, `firebase` | `demo` |
| `FHIR_BASE` | the HAPI FHIR endpoint | `http://localhost:8080/fhir` |
| `API_BASE` | this application's API | `http://localhost:8084` |

Outbound HTTP from the *HTTP call* block is disabled in the classroom build,
and the properties panel says so rather than letting a student discover it as a
runtime failure.

## Tests

```bash
flutter test
```

Twenty-five tests. The editor tests build a flow node by node — including the
low-SpO2 alert, wired by hand — and then **run it**, asserting that a saturation
of 88 is delivered and 97 is filtered. Others check that a wire cannot be drawn
twice, that nothing can be wired into a source, that deleting a block removes
its edges, and that a whole drag is one undo step.

One bug these tests caught: the flow editor is a pushed route, so it builds on
the root navigator — above the provider the application installs. The test panel
therefore could not find the engine and threw the moment anyone pressed *Run*.
Fixed by handing the engine down with the route.
