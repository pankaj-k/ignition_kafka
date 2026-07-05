# Ignition + Kafka — Factory Data Pipeline

A working example of streaming live factory sensor data from an OPC UA simulator through Ignition SCADA into Confluent Cloud Kafka — with no code, just configuration.

---

## What this does

A Python factory simulator publishes live sensor data over OPC UA. Ignition connects to it as an OPC UA client, collects the tags, and streams them to Kafka via the built-in Event Streams and Kafka Connector modules.

```
Factory Simulator (OPC UA) → Ignition Gateway → Kafka (Confluent Cloud)
```

---

## Repository structure

```
ignition_kafka/
├── simulator/        ← Python OPC UA server (the factory data source)
└── infra/            ← Ignition Docker setup
    ├── gateway-data/ ← Ignition gateway config (version-controlled per IA docs)
    │   ├── config/   ← OPC UA connection + Kafka connector (edit credentials here)
    │   └── projects/ ← Event Streams, alarm pipelines, Perspective skeleton
    ├── Dockerfile
    └── docker-compose.yml
```

---

## Quick start

### 1. Start the simulator

```bash
cd simulator

# Create and activate virtual environment
python -m venv .venv
.venv\Scripts\activate          # Windows
source .venv/bin/activate       # macOS / Linux

pip install -r requirements.txt
python -m simulator.main opcua
```

Simulator starts an OPC UA server at `opc.tcp://0.0.0.0:4840/factory/`.

Run with no arguments to see all options:

```bash
python -m simulator.main
```

**Simulator modes:**

| Mode | Description |
|------|-------------|
| `opcua` | OPC UA server on port 4840 — what Ignition connects to |
| `mqtt` | Plain MQTT JSON publisher |
| `sparkplug` | Sparkplug B publisher (requires MQTT broker) |

**Flags:**

| Flag | Description |
|------|-------------|
| `--test` | Fault injection — tags randomly go Bad and recover, for testing alarm pipelines |

### 2. Configure your Confluent Cloud credentials

Open `infra/gateway-data/config/resources/core/ignition/service-connector/ignition_confluent_kafka/config.json` and fill in your two values:

```json
"bootstrapServers": ["YOUR_BOOTSTRAP_SERVER.confluent.cloud:9092"],
"username": "YOUR_CONFLUENT_API_KEY"
```

> Both values are found under **Confluent Cloud → Cluster → Clients → New client**.

The OPC UA connection to the simulator and all Event Streams are pre-configured — no other UI steps needed.

### 3. Start Ignition

```bash
cd infra
docker-compose up -d
```

Ignition starts at http://localhost:8088 (admin / Ignition@123).

> **Trial mode:** Ignition runs in trial mode and resets every 2 hours. For a permanent setup, obtain a free developer license from [Inductive Automation](https://inductiveautomation.com).

### 4. Enter the Kafka API Secret

In the Ignition Gateway UI: **Connections → Service Connectors → Connections → ignition_confluent_kafka → Edit**

Find the **Password** field, select **Embedded**, and enter your Confluent API Secret. Save.

The connection status should change from Errored to Connected within a few seconds.

---

## What the simulator models

The factory has four areas. Devices are causally linked — faults in Assembly produce measurable effects in Energy and Packaging.

| Area | Devices | Key tags |
|------|---------|----------|
| **Assembly** | CNC_01, CNC_02, Robot_Arm_01 | State, PartCount, CycleTime_sec, ToolWear_pct, Alarm |
| **Process** | Reactor_Tank_01, Reactor_Tank_02 | Temperature_C, Pressure_bar, Level_pct, FlowRate_L_min |
| **Energy** | Main_Meter, Line_A_Meter, Line_B_Meter | ActivePower_kW, EnergyTotal_kWh, PowerFactor |
| **Packaging** | Packaging_Line_01 | Running, Throughput_units_hr, OEE_pct, SupplyFactor_pct |

---

## How configuration version control works

This is one of the more interesting aspects of this setup, worth understanding before you start making changes.

### The problem with SCADA and version control

Traditional SCADA systems (including older Ignition versions) store all their configuration — connections, tag definitions, pipelines — in a proprietary database inside the application. To back up your work you export a binary blob (Ignition calls this a `.gwbk` file). There is no diff, no history, no way to review what changed or roll back a single setting.

Ignition 8.3 changed this. All meaningful gateway configuration is now stored as human-readable JSON files on disk. The database still exists for runtime state (tag values, session data), but the configuration you actually author lives in files.

### How the bind mount connects Docker to git

Docker lets you replace a directory inside a container with a directory from your host machine. This is called a **bind mount**. When the container reads or writes that directory, it is actually reading and writing your host directory directly — the container has no private copy.

This repo's `docker-compose.yml` does exactly this — one line in the `volumes:` section:

```yaml
services:
  gateway:
    volumes:
      - ./gateway-data:/usr/local/bin/ignition/data   # ← the bind mount
```

`./gateway-data` (a directory in your cloned repo) is mounted as Ignition's data directory inside the container. The two paths point at the same physical files, viewed from two different perspectives:

| Who sees it | Path |
|-------------|------|
| Ignition (inside container) | `/usr/local/bin/ignition/data` |
| You (on your host machine) | `infra/gateway-data/` |

When you click **Save** in the Ignition gateway UI, Ignition writes a JSON file. That file appears immediately in `infra/gateway-data/` on your host. Running `git status` shows the change. Running `git commit` captures it. No export step, no scripts.

### Does this work on Windows, macOS, and Linux?

The bind mount syntax (`./gateway-data:/usr/local/bin/ignition/data`) is identical on all platforms — Docker handles the translation.

One thing to be aware of on **Linux hosts**: Docker containers run as a specific internal user (Ignition uses uid 999). On Linux, the bind-mounted directory must be writable by that uid. Run this once after cloning:

```bash
sudo chown -R 999:999 infra/gateway-data
```

On **Windows and macOS**, Docker Desktop handles permissions automatically — this step is not needed.

> **Linux note:** `host.docker.internal` (the hostname the OPC UA connection uses to reach the simulator) is not automatic on Linux Docker the way it is on Docker Desktop. The `docker-compose.yml` already includes `extra_hosts: host.docker.internal:host-gateway` to handle this — no action needed on your part, just be aware of why it is there.

### The everyday workflow

```
Make a change in Ignition UI
        ↓
Ignition writes JSON to /usr/local/bin/ignition/data/...
        ↓  (same directory, via bind mount)
File appears in infra/gateway-data/... on your laptop
        ↓
git status   ← see what changed
git diff     ← see exactly which fields changed
git commit   ← save it to history
```

This is the same workflow as editing code in a text editor — except the "editor" is the Ignition UI.

### What is and isn't tracked

Not everything in Ignition's data directory belongs in git. Runtime files — the tag value database, Java jar cache, logs, certificates — change constantly and have no value in version history. The `.gitignore` inside `gateway-data/` filters these out, following the patterns published in Inductive Automation's official version control documentation.

What remains — and what is committed in this repo — is only the configuration you authored:

| Path | What it contains |
|------|-----------------|
| `config/resources/core/ignition/opc-connection/` | OPC UA connection to the simulator |
| `config/resources/core/ignition/service-connector/` | Kafka connection settings |
| `projects/FactorySimulator_OPC_UA/com.inductiveautomation.eventstream/` | Event Stream definitions |

### First-time setup vs ongoing use

When this repo was first created, the Ignition container had already been configured through the UI. A one-time copy (`docker cp`) pulled those files out of the running container and into `gateway-data/` to seed the repo. That step is done and will never be needed again.

For any future changes — adding a new Event Stream, changing a connection setting, creating a Perspective dashboard — the workflow above applies automatically. The bind mount is always active.

---

## Troubleshooting

**`Connection refused: /0.0.0.0:4840`**
The simulator is not running. Start it first with `python -m simulator.main opcua`, then retry the Ignition OPC UA connection.

**Ignition can't reach the simulator**
Make sure the OPC UA endpoint uses `host.docker.internal:4840`, not `localhost:4840`. Inside Docker, `localhost` refers to the container, not your machine.

**Kafka connection shows "Errored" with no detail**
Open **Config → System → Logs** and filter for `kafka`. The most common cause: Security Protocol is set to `SASL_PLAINTEXT` instead of `SASL_SSL`. The UI defaults to `SASL_PLAINTEXT`; Confluent Cloud requires `SASL_SSL` on port 9092. Change the field and save.

**Event Stream shows Events Received: 0**
Check the Source block — editing any part of an Event Stream can silently clear the tag path subscription. Click the Source block, verify the tag path is still set, re-enter it if blank.
