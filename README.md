# EAI — Interoperability server

Part of **Mini-Hospital 2026**, a teaching hospital built for the course on
hospital, e-health and connected-medical-device informatics.

> Start here if you are new: the
> [course guide](https://github.com/LucaProcaryote/Dev_Central/blob/main/COURSE.md)
> explains how the six repositories fit together and contains the lab exercises.

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

**Nineteen block types in three families.** Sources produce messages (an HTTP
endpoint, the device feed, ADT events, a timer, an MQTT subscription, an HL7 v2
message). Processors change or drop them (filter, field mapper, patient
enricher, FHIR validator, code translator, router, a device-payload decoder,
an HL7 v2 to FHIR translator). Destinations deliver them (the FHIR store, an
application, an HTTP call, a log, HL7 v2 out).

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

## The five worked flows

They are meant to be read before they are run.

1. **Bedside monitors to the record** — the whole chain a hospital actually
   runs. A monitor publishes on MQTT, the engine decodes the device payload
   into an `ORU^R01` — the message a real monitor sends — translates that to a
   FHIR Observation, and files it. Three formats, one reading, every step on
   the trace.
2. **HL7 v2 admissions to FHIR** — the job an interface engine does all day.
   An `ADT^A01` arrives as pipes, its segments are parsed, inpatients are kept
   (`PV1-2 = I`), and the visit becomes a FHIR `Encounter`.
3. **Device vitals to the record** — validate, enrich with the patient's
   demographics, then store in FHIR *and* push to the EHR. The fan-out from one
   processor to two destinations is the pattern to notice.
4. **ADT movements fan-out** — a router sends admissions, transfers and
   discharges down three different branches.
5. **Low SpO2 alert** — two filters in series, then a mapper that reshapes a
   FHIR Observation into a flat alert. Everything else is dropped, so the alert
   channel stays quiet until it matters.

## HL7 v2

Open any message and switch between **HL7 v2** and **JSON**. The v2 view lays
out one segment per line, because the wire format separates them with a
carriage return that no text widget renders as a line break.

Parsed segments are addressable the way the HL7 documentation writes them —
`PID.5.1`, `PV1.2`, `OBX.0.5` — so the filter and mapper blocks work on a v2
message with no special handling. A segment that repeats by nature, such as
`OBX`, is always a list; otherwise a flow written for one reading would break
on the second.

The translation to FHIR is lossy in both directions, and that is the lesson,
not a defect. `PID-5` is five components where FHIR `HumanName` is a list and a
use code. The v2 trigger event has no FHIR element at all, so it rides along as
an extension rather than being dropped.

**MLLP is not here and cannot be.** The real transport for v2 is raw TCP with
framing bytes; Cloud Run carries no raw TCP and a browser cannot open a socket.
The hosted build sends the same bytes over HTTP, and the block's properties
panel says so. MLLP belongs in the local Docker stack.

## MQTT

When a broker is configured, the engine holds a live subscription while the
page is open and a band above the message list shows the link, how many
readings arrived, how many went through a flow, and how many devices are
online.

That connection lives in the browser, with the page — which is a real
limitation worth stating to students rather than hiding: readings published
while nobody has the engine open are not queued anywhere, they are missed. A
production engine is a server that never closes its tab.

The *MQTT subscription* block holds a topic filter. `#` takes the rest of the
tree, `+` takes exactly one level:

```
hospital/ward/ward-icu/#                    everything in intensive care
hospital/ward/+/bed/+/device/+/heartRate    every heart rate, anywhere
```

The *Decode device reading* block turns the compact payload a device publishes
into either a FHIR Observation or an `ORU^R01`. Its resource id is derived from
the device and the instant rather than generated, so a redelivery — which
at-least-once makes a certainty, not a corner case — produces one resource
instead of two.

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
| `MQTT_URL` | broker, `wss://…` | empty — no broker, the band stays hidden |
| `MQTT_USERNAME` | broker account | empty |
| `MQTT_PASSWORD` | broker password | empty |

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
