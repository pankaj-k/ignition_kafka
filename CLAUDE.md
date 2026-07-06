# CLAUDE.md — ignition_kafka

## What this project is

A self-contained demo showing how to stream live factory sensor data from an OPC UA simulator through Ignition SCADA into Confluent Cloud Kafka — with no application code, just configuration. Intended for a LinkedIn blog post and as a reusable reference for anyone connecting Ignition to Kafka.

Target stack: Ignition 8.3 (Docker) + Confluent Cloud + Python OPC UA simulator.

## Repository structure

```
ignition_kafka/
├── simulator/                  ← Python OPC UA server (copied from factory_simulator repo)
│   ├── simulator/              ← importable package
│   │   ├── factory/            ← device simulation logic
│   │   └── connectors/         ← OPC UA / MQTT / Sparkplug connectors
│   ├── config/factory.yaml     ← tick interval, endpoint, broker settings
│   └── requirements.txt
└── infra/
    ├── Dockerfile              ← extends inductiveautomation/ignition:latest
    ├── docker-compose.yml      ← bind mounts gateway-data/, exposes port 8088
    └── gateway-data/           ← Ignition data directory, version-controlled
        ├── .gitignore          ← official IA patterns (excludes db/, jar-cache/, var/, etc.)
        ├── config/resources/core/ignition/
        │   ├── opc-connection/FactorySimulator/    ← OPC UA client connection config
        │   └── service-connector/ignition_confluent_kafka/  ← Kafka connector config (credentials redacted)
        └── projects/FactorySimulator_OPC_UA/
            └── com.inductiveautomation.eventstream/event-streams/  ← 5 Event Stream definitions
```

## Key architectural decisions

### Ignition modules — bundled, not installed
Event Streams and Kafka Connector are bundled in `inductiveautomation/ignition:latest`. No `.modl` files to copy, no certificate acceptance needed. The Dockerfile is essentially a one-liner extending the base image.

### Version control via bind mount
`docker-compose.yml` bind-mounts `./gateway-data` to `/usr/local/bin/ignition/data` inside the container. Ignition's file-based config (Ignition 8.3 feature) writes JSON files there directly. `git status` on the host shows changes in real time — no export scripts needed.

### What is and isn't file-based in Ignition 8.3
- **File-based (committed):** OPC UA connections, service connectors, Event Streams, projects
- **SQLite only (gitignored):** runtime tag values, session state, alarm history
- **gitignored entirely:** `db/`, `jar-cache/`, `var/`, `certificates/`, `config/local/`

### Committing after Kafka connection changes

After creating or editing the Kafka connection via the UI, Ignition writes `service-connector/ignition_confluent_kafka/config.json`. Before pushing to a public repo, always redact `bootstrapServers` and `username`. The encrypted `password.data` block is safe to commit — it is JWE-encrypted with the instance's private key and is useless on any other Ignition instance.

### Kafka credentials — not stored in repo
The `service-connector` config.json is committed with placeholder values (`YOUR_BOOTSTRAP_SERVER`, `YOUR_CONFLUENT_API_KEY`). The password cannot be stored in plain text. Users fill in bootstrap server and API key in the JSON file before first start, then enter the API Secret via the Ignition UI once.

## Known gotchas

### SASL_PLAINTEXT vs SASL_SSL
The Ignition Kafka connector UI defaults to `Security Protocol: SASL_PLAINTEXT`. Confluent Cloud requires `SASL_SSL`. The connection will show "Errored" with no detail in the UI — check **Config → System → Logs** for the actual error. This is documented in README step 4.

### File-managed resources are read-only in the UI
When a resource (e.g. the Kafka service connector) exists as a file in `gateway-data/`, the Ignition UI shows it as read-only — the Edit button is greyed out. This is by design: the file is the source of truth.

After a fresh start with a redacted config file, Ignition shows the connection as Faulted (placeholder credentials). The user must edit the JSON file directly with real values, then restart. The password field remains empty and must be entered via the UI — but the Edit button will only be active after Ignition writes the file with real non-placeholder credentials and the user enters the password.

### SQLite persists across container restarts
`gateway-data/db/config.idb` is gitignored but lives on disk. A container restart reads from the existing SQLite, so credentials entered previously still work. To simulate a truly fresh clone, delete `gateway-data/db/` before restarting.

### host.docker.internal on Linux
Not automatic on Linux Docker (unlike Docker Desktop on Windows/macOS). `docker-compose.yml` includes `extra_hosts: host.docker.internal:host-gateway` to handle this. Works on all platforms — harmless on Windows/macOS.

### Linux file permissions
Ignition runs as uid 999 inside the container. On Linux hosts, `gateway-data/` must be owned by uid 999: `sudo chown -R 999:999 infra/gateway-data`.

### migration-log files
Ignition writes `migration-log-*.md` files into `gateway-data/config/resources/` on version upgrades. These are gitignored by the `**/migration-log-*.md` pattern in `gateway-data/.gitignore`.

## Simulator entry point

```
python -m simulator.main opcua           # OPC UA server on port 4840
python -m simulator.main opcua --test    # with fault injection
```

Config lives in `simulator/config/factory.yaml`. OPC UA endpoint defaults to `opc.tcp://0.0.0.0:4840/factory/`. From inside Docker, connect using `opc.tcp://host.docker.internal:4840/factory/`.

## Ignition connection details

| Setting | Value |
|---------|-------|
| Gateway URL | http://localhost:8088 |
| Admin username | admin |
| Admin password | Ignition@123 |
| OPC UA endpoint (from Docker) | `opc.tcp://host.docker.internal:4840/factory/` |
| Kafka connection name | `confluent-kafka` ← must match exactly, Event Streams reference this |
| Project name | `FactorySimulator_OPC_UA` |

## Event Streams

Five streams in `projects/FactorySimulator_OPC_UA/com.inductiveautomation.eventstream/event-streams/`:

| Stream | Tag path |
|--------|----------|
| `assembly_stream` | `[default]Factory/Assembly/**` |
| `process_stream` | `[default]Factory/Process/**` |
| `energy_stream` | `[default]Factory/Energy/**` |
| `packaging_stream` | `[default]Factory/Packaging/**` |
| `factory-alarm-listener` | Alarm pipeline stream |

## Adding a new Event Stream

1. Create it in the Ignition UI under the `FactorySimulator_OPC_UA` project
2. Ignition writes `config.json` and `resource.json` to `gateway-data/projects/FactorySimulator_OPC_UA/com.inductiveautomation.eventstream/event-streams/<name>/`
3. `git add` and `git commit` — done
