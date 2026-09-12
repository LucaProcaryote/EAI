# FHIR server

The interoperability repository for Mini-Hospital 2026: a real
[HAPI FHIR](https://hapifhir.io) R4 JPA server backed by PostgreSQL.

It is the genuine article rather than a mock, so the students get proper search
parameters, `_include`, resource history, validation and a capability
statement — everything a FHIR client is entitled to expect. Standing up the
real thing turned out to be less work than faking a convincing subset of it.

## Start it

```bash
cd fhir-server
docker compose up -d
```

First boot takes two or three minutes while HAPI builds its schema. Watch it:

```bash
docker compose logs -f fhir
```

Then:

- web console: <http://localhost:8080>
- FHIR endpoint: <http://localhost:8080/fhir>
- capability statement: <http://localhost:8080/fhir/metadata>

## Load the fictive hospital

Open the **EAI** application, go to *FHIR resources*, and press *Load the
fictive patients into FHIR*. It posts one transaction bundle containing the
patients, their allergies, encounters, devices, prescriptions and a slice of
the observations.

The bundle uses `PUT Patient/pat-001` rather than `POST Patient` —
update-as-create. The mini-hospital already owns stable identifiers, and
keeping them means a reference like `Patient/pat-001` resolves identically in
the FHIR server and in every application database.

Or from the command line, once the applications have written something:

```bash
curl -s 'http://localhost:8080/fhir/Patient?_count=5' | jq '.entry[].resource.name'
curl -s 'http://localhost:8080/fhir/Observation?code=2708-6&_sort=-date&_count=10' | jq
curl -s 'http://localhost:8080/fhir/Patient/pat-001/$everything' | jq '.total'
```

## Things worth trying with the students

```bash
# Every oxygen saturation below 92, newest first
curl -s 'http://localhost:8080/fhir/Observation?code=2708-6&value-quantity=lt92&_sort=-date' | jq '.total'

# One patient's whole record in a single request
curl -s 'http://localhost:8080/fhir/Patient/pat-008/$everything' | jq '[.entry[].resource.resourceType] | group_by(.) | map({(.[0]): length}) | add'

# Search by the Belgian national register number
curl -s 'http://localhost:8080/fhir/Patient?identifier=urn:oid:2.16.56.1.1.1.1|48.03.12-057.30' | jq '.entry[0].resource.name'

# Ask the server to validate a resource before you send it for real
curl -s -X POST http://localhost:8080/fhir/Observation/\$validate \
  -H 'Content-Type: application/fhir+json' \
  -d '{"resourceType":"Observation"}' | jq '.issue[].diagnostics'
```

That last one is a good exercise: the server explains exactly which required
elements are missing, and the same rules are what the *FHIR validator* node in
the integration flows applies in miniature.

## Configuration notes

**CORS is wide open.** The Flutter applications are served from a different
origin, and without `HAPI_FHIR_CORS_ALLOWED_ORIGIN_PATTERNS` the browser
refuses to talk to the server at all. That setting is right for a classroom on
a laptop and wrong for anything else.

**Referential integrity is off.** The applications write resources in whatever
order the flows produce them, and an Observation may reach the server before
its Encounter does. Enforcing integrity on write would reject perfectly good
messages for arriving in an inconvenient order.

**The password is `hapi`.** So is the username. This holds fictive data on a
classroom network; treat every credential in this file as a placeholder.

## Reset it

```bash
docker compose down -v     # -v also drops the database volume
docker compose up -d
```

## Pointing the applications at it

```bash
flutter run -d chrome --dart-define=FHIR_BASE=http://localhost:8080/fhir
```

The EAI application shows a green *Online* chip when it can reach the server,
and a red *Offline* one with the command to start it when it cannot.
