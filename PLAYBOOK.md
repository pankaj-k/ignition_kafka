# PLAYBOOK — Ignition + Kafka Factory Data Pipeline

Step-by-step record of how this lab was built. Each chapter is a self-contained milestone. Follow them in order to reproduce the setup from scratch.

---

## Chapter 1: Architecture — what we are building

The goal is to stream live factory sensor data into Kafka with no application code — only configuration inside Ignition SCADA.

```
Factory Simulator → OPC UA → Ignition Gateway → Event Streams → Kafka (Confluent Cloud)
     (Python)                   (Docker)                          (managed cloud)
```

**Why Ignition in the middle?**
Ignition handles OPC UA client connectivity, tag scanning, quality tracking, alarming, and historian — things you would otherwise have to build. It writes to Kafka via its built-in Event Streams and Kafka Connector modules. No custom producer code.

**Why Confluent Cloud?**
Managed Kafka — no cluster to operate. Free tier is sufficient for this demo.

---

## Chapter 2: The factory simulator

The simulator is a Python OPC UA server that publishes live sensor data from a fictional factory floor. It models four areas:

| Area | Devices | Key tags |
|------|---------|----------|
| Assembly | CNC_01, CNC_02, Robot_Arm_01 | State, PartCount, CycleTime_sec, ToolWear_pct, Alarm |
| Process | Reactor_Tank_01, Reactor_Tank_02 | Temperature_C, Pressure_bar, Level_pct, FlowRate_L_min |
| Energy | Main_Meter, Line_A_Meter, Line_B_Meter | ActivePower_kW, EnergyTotal_kWh, PowerFactor |
| Packaging | Packaging_Line_01 | Running, Throughput_units_hr, OEE_pct, SupplyFactor_pct |

Devices are causally linked — faults in Assembly cause measurable effects in Energy and Packaging.

### Running the simulator

```bash
cd simulator
python -m venv .venv
.venv\Scripts\activate        # Windows
source .venv/bin/activate     # macOS / Linux
pip install -r requirements.txt
python -m simulator.main opcua
```

The simulator starts an OPC UA server at `opc.tcp://0.0.0.0:4840/factory/`. Leave it running. Ignition connects to it as a client.

**Note:** Virtual environments are platform-specific. Always create `.venv` locally after cloning — never copy it between machines.

---

## Chapter 3: Ignition in Docker

### Why Docker?

Ignition is a Java application with an installer. Docker lets anyone clone this repo and get a running Ignition instance in one command — no installer, no licence wizard, no manual module installation.

### The image

`inductiveautomation/ignition:latest` — the official image published by Inductive Automation. Both Event Streams and Kafka Connector are **bundled** in this image. No additional `.modl` files are needed.

The `Dockerfile` in `infra/` simply extends the base image. There is nothing to copy in.

### Starting Ignition

```bash
cd infra
docker-compose up -d
```

Ignition starts at http://localhost:8088. Default credentials: `admin` / `Ignition@123`.

**Trial mode:** Ignition runs as a 2-hour trial without a licence. For permanent use, obtain a free developer licence from Inductive Automation.

### The bind mount — how Docker connects to git

`docker-compose.yml` bind-mounts the `gateway-data/` directory from this repo directly into the container as Ignition's data directory:

```yaml
volumes:
  - ./gateway-data:/usr/local/bin/ignition/data
```

The two paths are the same physical directory seen from two perspectives:

| Who sees it | Path |
|-------------|------|
| Ignition (inside container) | `/usr/local/bin/ignition/data` |
| You (on your host machine) | `infra/gateway-data/` |

When you save anything in the Ignition UI, it writes a JSON file into this directory. That file immediately appears on your host. `git status` shows the change. `git commit` captures it. No export scripts ever needed.

### Platform notes

The bind mount works identically on Windows, macOS, and Linux. Two Linux-specific things:

1. **File permissions:** Ignition runs as uid 999 inside the container. Run once after cloning on Linux:
   ```bash
   sudo chown -R 999:999 infra/gateway-data
   ```

2. **host.docker.internal:** This hostname (used by the OPC UA connection to reach the simulator on the host machine) is automatic on Docker Desktop but not on Linux Docker. `docker-compose.yml` includes `extra_hosts: host.docker.internal:host-gateway` to handle this on all platforms.

---

## Chapter 4: OPC UA connection

Ignition connects to the simulator as an OPC UA client. This connection is pre-configured in the repo — no UI steps needed.

Config file: `infra/gateway-data/config/resources/core/ignition/opc-connection/FactorySimulator/config.json`

Key setting:
```json
"endpointUrl": "opc.tcp://host.docker.internal:4840/factory/"
```

`host.docker.internal` resolves to your host machine from inside the Docker container. If the simulator is running, the connection goes green within a few seconds of Ignition starting. If the simulator is off, it shows red and reconnects automatically when the simulator starts.

**Gotcha:** Do not use `localhost` in the OPC UA endpoint URL. Inside Docker, `localhost` refers to the container itself, not your machine.

---

## Chapter 5: Confluent Cloud Kafka connection

### Creating the Confluent cluster

1. Sign up at confluent.io (free tier is sufficient)
2. Create a Basic cluster in the region closest to you
3. Go to **Cluster → Clients → New client** to get your bootstrap server address and create an API key/secret pair

### Configuring the connection in Ignition

The Kafka connection is intentionally not pre-configured in the repo. When a service connector config file exists in `gateway-data/`, Ignition treats it as file-managed and makes the Edit button read-only in the UI — which means users cannot enter their credentials.

Create it fresh via the UI instead:

1. Start Ignition: `docker-compose up -d`
2. Go to **Connections → Service Connectors → Connections → Create Connection → Kafka**
3. Name it `ignition_confluent_kafka` (the Event Streams reference this name)

### Exact field values

| Field | Value |
|-------|-------|
| SASL Mechanism | `PLAIN` |
| Security Protocol | `SASL_SSL` |
| Username | your Confluent API Key |
| Password | Embedded → your Confluent API Secret |
| TLS Protocol | `TLSv1.3` |
| Key Password | None |
| Keystore Type | leave blank |
| Keystore Password | None |
| Keystore Key | None |
| Truststore Password | None |

Confluent Cloud uses publicly trusted certificates — no custom keystore or truststore needed.

### Known gotchas

**SASL_PLAINTEXT vs SASL_SSL:** The Ignition UI defaults `Security Protocol` to `SASL_PLAINTEXT`. Confluent Cloud requires `SASL_SSL`. The connection will show "Errored" with no visible reason in the UI. Check **Config → System → Logs** and filter for `kafka` to see the real error.

**Edit button greyed out:** This happens when a service-connector config file exists in `gateway-data/` — Ignition treats file-managed resources as read-only in the UI. The fix is to not pre-commit the service-connector config at all. Users create the connection fresh via the UI, which is always editable.

**SQLite persistence:** If you restart the container without deleting `gateway-data/db/`, Ignition reloads credentials from the previous SQLite database. To simulate a truly fresh start (as a new user cloning the repo would experience), delete `gateway-data/db/` before restarting.

---

## Chapter 6: Event Streams

Event Streams are Ignition's mechanism for routing tag change events to external systems. Each stream has a source (which tags to watch) and a handler (where to send the data).

Five streams are pre-configured in this repo under `projects/FactorySimulator_OPC_UA/com.inductiveautomation.eventstream/event-streams/`:

| Stream | Watches |
|--------|---------|
| `assembly_stream` | `[default]Factory/Assembly/**` |
| `process_stream` | `[default]Factory/Process/**` |
| `energy_stream` | `[default]Factory/Energy/**` |
| `packaging_stream` | `[default]Factory/Packaging/**` |
| `factory-alarm-listener` | Factory alarm events |

The `**` wildcard matches every tag at any depth under the folder. New tags added to the simulator appear automatically in the stream with no reconfiguration.

### Where Event Streams live on disk

Unlike older Ignition versions where all config lived in a SQLite database, Event Streams in Ignition 8.3 are stored as JSON files inside the project directory:

```
gateway-data/projects/FactorySimulator_OPC_UA/
  com.inductiveautomation.eventstream/
    event-streams/
      assembly_stream/
        config.json
        resource.json
```

This means Event Streams are version-controlled automatically — create or edit one in the UI and it appears as a git diff.

### Known gotcha — Events Received: 0

If an Event Stream shows `Events Received: 0` after the simulator is running, check the Source block. Editing any part of an Event Stream can silently clear the tag path subscription. Click the Source block, verify the tag path is still set, re-enter it if blank.

---

## Chapter 7: Version control workflow

### How it works

The bind mount (Chapter 3) means any config change made in the Ignition UI immediately appears as a file change in `infra/gateway-data/` on your host. The git workflow is identical to working with code:

```
Change something in Ignition UI
    ↓
git status            # see which files changed
git diff              # see exact field-level changes
git add <files>
git commit -m "..."
```

### What gets committed

Ignition's data directory contains a mix of config files (worth tracking) and runtime files (not worth tracking). The `.gitignore` inside `gateway-data/` uses the official patterns published by Inductive Automation to separate them.

Committed — the config you authored:
- OPC UA connections (`config/resources/core/ignition/opc-connection/`)
- Service connectors (`config/resources/core/ignition/service-connector/`)
- Projects and Event Streams (`projects/`)
- Gateway settings (`gateway.xml`, `modules.json`, etc.)

Gitignored — runtime files that change constantly:
- `db/` — SQLite database (tag values, session state)
- `jar-cache/` — Java jar cache (233 MB)
- `var/` — working files (336 MB)
- `certificates/` — TLS certificates
- `config/local/` — environment-specific overrides

### How the repo was seeded (one-time only)

When this repo was created, Ignition had already been configured through the UI on a running container. The config files were extracted with:

```bash
docker cp <container>:/usr/local/bin/ignition/data/config/resources/core/ignition/opc-connection ./gateway-data/config/...
docker cp <container>:/usr/local/bin/ignition/data/projects ./gateway-data/projects
```

Credentials were then redacted from the Kafka connector config before committing. This step will never be repeated — the bind mount keeps everything in sync from here on.

---

## Chapter 8: Testing a fresh clone

To verify the repo works for someone cloning it for the first time:

1. Stop the container: `docker-compose down`
2. Remove the Docker image: `docker rmi ignition_kafka-gateway`
3. Delete the SQLite database (simulates no prior state): `rm -rf gateway-data/db`
4. Edit `gateway-data/config/resources/core/ignition/service-connector/ignition_confluent_kafka/config.json` with your real bootstrap server and API key
5. Rebuild and start: `docker-compose up -d`
6. Open http://localhost:8088
7. Go to **Connections → Service Connectors → ignition_confluent_kafka → Edit**, enter API Secret, save
8. Start the simulator: `python -m simulator.main opcua`
9. Verify OPC UA connection goes green, Kafka connection goes Connected, Event Streams show events flowing

If all nine steps work, the repo is ready to publish.
