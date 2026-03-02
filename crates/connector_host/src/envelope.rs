use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Canonical event envelope — mirrors RouterCore.Envelope in Elixir.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Envelope {
    pub id: String,
    pub source: String,
    pub payload: serde_json::Value,
    #[serde(default)]
    pub metadata: HashMap<String, serde_json::Value>,
    pub ts: Option<i64>,
}

impl Envelope {
    pub fn new(source: impl Into<String>, payload: serde_json::Value) -> Self {
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as i64)
            .unwrap_or(0);

        Self {
            id: uuid::Uuid::new_v4().to_string(),
            source: source.into(),
            payload,
            metadata: HashMap::new(),
            ts: Some(ts),
        }
    }
}
