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
