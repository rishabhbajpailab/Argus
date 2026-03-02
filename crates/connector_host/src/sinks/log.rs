use std::collections::HashMap;

use tracing::info;

use crate::envelope::Envelope;

/// Log sink — print the envelope as structured JSON to stderr.
///
/// `config` is reserved for future options (e.g. log level, format).
pub fn emit(
    output_name: &str,
    envelope: &Envelope,
    _config: &HashMap<String, serde_json::Value>,
) {
    let json = serde_json::to_string(envelope).unwrap_or_else(|_| "<serialization error>".into());
    // Use tracing so the output is structured and timestamped.
    info!(output = output_name, envelope = %json, "log sink");
}
