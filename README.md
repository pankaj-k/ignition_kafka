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

### 2. Start Ignition

```bash
cd infra
docker-compose up -d
```

Ignition starts at http://localhost:8088 (admin / Ignition@123).

> **Trial mode:** Ignition runs in trial mode and resets every 2 hours. This is fine for evaluation. For a permanent setup, obtain a free developer license from [Inductive Automation](https://inductiveautomation.com).

### 3. Connect Ignition to the simulator

In the Ignition Gateway UI:

**Config → OPC UA → Connections → Add**

| Field | Value |
|-------|-------|
| Endpoint URL | `opc.tcp://host.docker.internal:4840/factory/` |

> `host.docker.internal` resolves to your host machine from inside the Docker container. Do not use `localhost`.

### 4. Configure Kafka

**Connections → Service Connectors → Connections → Create Connection → Kafka**

You will need three values from your Confluent Cloud cluster — found under **Cluster → Clients → New client**:

| Field | Value |
|-------|-------|
| Bootstrap Servers | `pkc-xxxxx.region.provider.confluent.cloud:9092` |
| SASL Mechanism | `PLAIN` |
| Security Protocol | `SASL_SSL` |
| Username | your Confluent Cloud API Key |
| Password | select **Embedded** → enter your API Secret |
| TLS Protocol | `TLSv1.3` |
| Key Password | None |
| Keystore Type | leave blank |
| Keystore Password | None |
| Keystore Key | None |
| Truststore Password | None |

> Confluent Cloud's certificate is signed by a standard CA already in the JVM trust store — no custom keystore or truststore files needed.

### 5. Set up an Event Stream

**Config → Event Streams → Add**

- **Source:** Tag Event — tag path `[default]Factory/**`
- **Handler:** Kafka — select your configured Kafka connection and target topic

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

## Troubleshooting

**`Connection refused: /0.0.0.0:4840`**
The simulator is not running. Start it first with `python -m simulator.main opcua`, then retry the Ignition OPC UA connection.

**Ignition can't reach the simulator**
Make sure the OPC UA endpoint uses `host.docker.internal:4840`, not `localhost:4840`. Inside Docker, `localhost` refers to the container, not your machine.

**Kafka connection shows "Errored" with no detail**
Open **Config → System → Logs** and filter for `kafka`. The most common cause: Security Protocol is set to `SASL_PLAINTEXT` instead of `SASL_SSL`. The UI defaults to `SASL_PLAINTEXT`; Confluent Cloud requires `SASL_SSL` on port 9092. Change the field and save.

**Event Stream shows Events Received: 0**
Check the Source block — editing any part of an Event Stream can silently clear the tag path subscription. Click the Source block, verify the tag path is still set, re-enter it if blank.
