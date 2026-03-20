# Argus — Configuration Reference

## Top-level structure

```yaml
inputs:    { <name>: <input-spec>, ... }
outputs:   { <name>: <output-spec>, ... }
pipelines: { <name>: <pipeline-spec>, ... }
```

Environment variables may be interpolated using `${VAR:default}` syntax.

---

## Input types

### `kafka`

```yaml
inputs:
  my_input:
    type: kafka
    brokers: "localhost:9092"   # comma-separated list
    topic: my.topic
    group_id: my-consumer-group
```

### `mqtt` *(TODO — not yet implemented)*

```yaml
inputs:
  my_mqtt:
    type: mqtt
    broker: "mqtt://localhost:1883"
    topic: "sensors/#"
    client_id: argus-client
```

---

## Output types

### `log`

```yaml
outputs:
  my_log:
    type: log
    # No additional config required; prints JSON to stdout
```

### `kafka`

```yaml
outputs:
  my_kafka_out:
    type: kafka
    brokers: "localhost:9092"
    topic: output.topic
```

---

## Pipeline spec

```yaml
pipelines:
  my_pipeline:
    from: my_input          # must match an input name
    transforms:             # optional list; applied in order
      - type: add_fields
        fields:
          routed_by: argus
      # ROADMAP: Add filter, rename_fields, and jmespath_extract transform types.
    to:                     # fan-out: list of output names
      - my_log
      - my_kafka_out
```

### Supported transforms

| Type | Description |
|------|-------------|
| `add_fields` | Merges static key/value pairs into the envelope payload |
| *(no-op)*    | Omitting the transforms key passes envelopes through unchanged |

---

## Validation rules

* Every `from` must reference a declared input.
* Every `to` entry must reference a declared output.
* Unknown `type` values cause a startup error.
* Missing required fields cause a startup error with field name.
