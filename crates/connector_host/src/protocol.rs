use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::envelope::Envelope;

// ---------------------------------------------------------------------------
// Commands — Elixir → Rust
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum Command {
    StartInput {
        name: String,
        config: HashMap<String, serde_json::Value>,
    },
    StartOutput {
        name: String,
        config: HashMap<String, serde_json::Value>,
    },
    SendOutput {
        name: String,
        envelope: Envelope,
    },
    Shutdown,
}

// ---------------------------------------------------------------------------
// Events — Rust → Elixir
// ---------------------------------------------------------------------------

#[derive(Debug, Serialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum Event {
    Ingest {
        input: String,
        envelope: Envelope,
    },
    Ack {
        #[serde(rename = "ref", skip_serializing_if = "Option::is_none")]
        correlation_ref: Option<String>,
    },
    Error {
        message: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        details: Option<serde_json::Value>,
    },
}

impl Event {
    /// Serialize to a newline-terminated JSON string.
    /// Returns a JSON error event line if serialization fails (should never happen
    /// for derived Serialize types with no non-serializable fields).
    pub fn to_line(&self) -> String {
        serde_json::to_string(self)
            .unwrap_or_else(|e| {
                format!(
                    r#"{{"event":"error","message":"serialization failed: {}"}}"#,
                    e
                )
            })
            + "\n"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn start_input_round_trip() {
        let json = r#"{"cmd":"start_input","name":"kafka_in","config":{"type":"kafka","brokers":"localhost:9092"}}"#;
        let cmd: Command = serde_json::from_str(json).expect("should deserialize");
        match cmd {
            Command::StartInput { name, config } => {
                assert_eq!(name, "kafka_in");
                assert_eq!(config["type"], "kafka");
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn start_output_round_trip() {
        let json = r#"{"cmd":"start_output","name":"log_out","config":{"type":"log"}}"#;
        let cmd: Command = serde_json::from_str(json).expect("should deserialize");
        match cmd {
            Command::StartOutput { name, .. } => assert_eq!(name, "log_out"),
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn send_output_round_trip() {
        let json = r#"{"cmd":"send_output","name":"kafka_out","envelope":{"id":"abc123","source":"s","payload":{"v":1},"ts":1000}}"#;
        let cmd: Command = serde_json::from_str(json).expect("should deserialize");
        match cmd {
            Command::SendOutput { name, envelope } => {
                assert_eq!(name, "kafka_out");
                assert_eq!(envelope.source, "s");
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn shutdown_round_trip() {
        let json = r#"{"cmd":"shutdown"}"#;
        let cmd: Command = serde_json::from_str(json).expect("should deserialize");
        assert!(matches!(cmd, Command::Shutdown));
    }

    #[test]
    fn event_ingest_serializes() {
        use crate::envelope::Envelope;
        let env = Envelope {
            id: "id1".to_string(),
            source: "src".to_string(),
            payload: serde_json::json!({"v": 42}),
            metadata: Default::default(),
            ts: Some(12345),
        };
        let event = Event::Ingest { input: "kafka_in".to_string(), envelope: env };
        let line = event.to_line();
        assert!(line.ends_with('\n'));
        let parsed: serde_json::Value = serde_json::from_str(line.trim()).expect("valid json");
        assert_eq!(parsed["event"], "ingest");
        assert_eq!(parsed["input"], "kafka_in");
    }

    #[test]
    fn event_ack_serializes() {
        let event = Event::Ack { correlation_ref: Some("ref123".to_string()) };
        let line = event.to_line();
        let parsed: serde_json::Value = serde_json::from_str(line.trim()).expect("valid json");
        assert_eq!(parsed["event"], "ack");
        assert_eq!(parsed["ref"], "ref123");
    }

    #[test]
    fn event_error_serializes() {
        let event = Event::Error { message: "oops".to_string(), details: None };
        let line = event.to_line();
        let parsed: serde_json::Value = serde_json::from_str(line.trim()).expect("valid json");
        assert_eq!(parsed["event"], "error");
        assert_eq!(parsed["message"], "oops");
        assert!(parsed.get("details").is_none() || parsed["details"].is_null());
    }
}
