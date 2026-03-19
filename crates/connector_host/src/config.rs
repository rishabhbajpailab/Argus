//! Typed configuration structs for connectors and sinks.
//!
//! Each struct derives `serde::Deserialize` so it can be instantiated
//! directly from the `config` map in a `start_input` or `start_output` command.
//!
//! Use [`serde_json::from_value`] to convert a `serde_json::Value` (which is
//! what arrives from the IPC command) into a typed struct.

use serde::Deserialize;

/// Configuration for a Kafka consumer input.
#[derive(Debug, Deserialize)]
pub struct KafkaConsumerConfig {
    /// Comma-separated list of broker addresses. Default: `"localhost:9092"`.
    #[serde(default = "default_brokers")]
    pub brokers: String,

    /// Topic to consume from. Default: `"input.events"`.
    #[serde(default = "default_input_topic")]
    pub topic: String,
}

/// Configuration for a Kafka producer output.
#[derive(Debug, Deserialize)]
pub struct KafkaProducerConfig {
    /// Comma-separated list of broker addresses. Default: `"localhost:9092"`.
    #[serde(default = "default_brokers")]
    pub brokers: String,

    /// Topic to produce to. Default: `"output.events"`.
    #[serde(default = "default_output_topic")]
    pub topic: String,
}

/// Configuration for the log sink output.
///
/// Currently no fields are required. This struct exists as a typed placeholder
/// so future log-level or format options can be added without changing the
/// dispatch code.
#[derive(Debug, Deserialize, Default)]
pub struct LogSinkConfig {}

fn default_brokers() -> String {
    "localhost:9092".to_string()
}

fn default_input_topic() -> String {
    "input.events".to_string()
}

fn default_output_topic() -> String {
    "output.events".to_string()
}
