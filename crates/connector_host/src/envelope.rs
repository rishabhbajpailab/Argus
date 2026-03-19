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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_populates_all_fields() {
        let env = Envelope::new("sensor_1", serde_json::json!({"v": 21.5}));

        assert!(!env.id.is_empty(), "id should be set");
        assert_eq!(env.source, "sensor_1");
        assert_eq!(env.payload, serde_json::json!({"v": 21.5}));
        assert!(env.metadata.is_empty(), "metadata should default to empty");
        assert!(env.ts.is_some(), "ts should be set");
        assert!(env.ts.unwrap() > 0, "ts should be positive");
    }

    #[test]
    fn id_is_uuid_format() {
        let env = Envelope::new("s", serde_json::Value::Null);
        // UUID v4 as string is 36 chars: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        assert_eq!(env.id.len(), 36);
        assert!(env.id.contains('-'));
    }

    #[test]
    fn two_envelopes_have_different_ids() {
        let a = Envelope::new("s", serde_json::Value::Null);
        let b = Envelope::new("s", serde_json::Value::Null);
        assert_ne!(a.id, b.id);
    }

    #[test]
    fn serializes_and_deserializes() {
        let original = Envelope::new("src", serde_json::json!({"key": "val"}));
        let json = serde_json::to_string(&original).expect("serialize");
        let restored: Envelope = serde_json::from_str(&json).expect("deserialize");

        assert_eq!(restored.id, original.id);
        assert_eq!(restored.source, original.source);
        assert_eq!(restored.payload, original.payload);
        assert_eq!(restored.ts, original.ts);
    }
}
