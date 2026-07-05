# Factory Simulator

A Python OPC UA server that simulates a factory floor — assembly machines, process tanks, energy meters, and a packaging line. Ignition connects to it as an OPC UA client.

## Setup

```bash
cd simulator

# Create virtual environment
python -m venv .venv

# Activate — Windows
.venv\Scripts\activate

# Activate — macOS / Linux
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

## Run

```bash
# OPC UA mode (default — what Ignition connects to)
python -m simulator.main opcua

# With fault injection (randomly degrades tag quality)
python -m simulator.main opcua --test
```

Simulator starts an OPC UA server at `opc.tcp://0.0.0.0:4840/factory/`.

If Ignition is running in Docker, connect it using `opc.tcp://host.docker.internal:4840/factory/`.

## Configuration

Edit `config/factory.yaml` to change tick interval, OPC UA endpoint, or MQTT broker settings.
