use std::sync::Arc;

use rskafka::client::partition::UnknownTopicHandling;
use rskafka::client::ClientBuilder;
use rskafka::record::RecordAndOffset;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

use crate::config::{KafkaConsumerConfig, KafkaProducerConfig};
use crate::envelope::Envelope;
use crate::protocol::Event;

// ---------------------------------------------------------------------------
// Shared setup helper
// ---------------------------------------------------------------------------

async fn build_partition_client(
    name: &str,
    brokers: &str,
    topic: &str,
) -> Result<(rskafka::client::partition::PartitionClient, String), String> {
    let broker_addrs: Vec<String> = brokers
        .split(',')
        .map(|s| s.trim().to_string())
        .collect();

    info!(
        "{} connecting to {:?}, topic '{}'",
        name, broker_addrs, topic
    );

    let client = ClientBuilder::new(broker_addrs)
        .build()
        .await
        .map_err(|e| format!("Failed to create Kafka client for '{}': {}", name, e))?;

    let client = Arc::new(client);

    let partition_client = client
        .partition_client(topic.to_string(), 0, UnknownTopicHandling::Error)
        .await
        .map_err(|e| {
            format!(
                "Failed to get partition client for '{}' topic '{}': {}",
                name, topic, e
            )
        })?;

    Ok((partition_client, topic.to_string()))
}

// ---------------------------------------------------------------------------
// Consumer
// ---------------------------------------------------------------------------

/// Spawn a Kafka consumer that reads `topic` and forwards `Event::Ingest`
/// messages to `event_tx`.
///
/// Runs until `event_tx` is dropped or the consumer encounters a fatal error.
pub fn spawn_consumer(
    input_name: String,
    cfg: KafkaConsumerConfig,
    event_tx: mpsc::Sender<Event>,
) {
    tokio::spawn(async move {
        let (pc, topic) =
            match build_partition_client(&input_name, &cfg.brokers, &cfg.topic).await {
                Ok(pair) => pair,
                Err(e) => {
                    error!("{}", e);
                    return;
                }
            };
        let partition_client = Arc::new(pc);

        let mut offset: i64 = 0;
        info!(
            "Kafka consumer '{}' started on topic '{}', polling from offset {}",
            input_name, topic, offset
        );

        loop {
            match partition_client
                .fetch_records(offset, 1..1_000_000, 1_000)
                .await
            {
                Ok((records, _high_watermark)) => {
                    if records.is_empty() {
                        // No new records — yield and retry.
                        tokio::time::sleep(tokio::time::Duration::from_millis(200)).await;
                        continue;
                    }

                    for RecordAndOffset { record, offset: rec_offset } in &records {
                        let payload: serde_json::Value = record
                            .value
                            .as_deref()
                            .and_then(|b| serde_json::from_slice(b).ok())
                            .unwrap_or(serde_json::Value::Null);

                        let envelope = Envelope::new(input_name.clone(), payload);
                        let event = Event::Ingest {
                            input: input_name.clone(),
                            envelope,
                        };

                        if event_tx.send(event).await.is_err() {
                            info!(
                                "Event channel closed, stopping consumer '{}'",
                                input_name
                            );
                            return;
                        }

                        offset = rec_offset + 1;
                    }
                }
                Err(e) => {
                    warn!("Kafka fetch error for input '{}': {}", input_name, e);
                    tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                }
            }
        }
    });
}

// ---------------------------------------------------------------------------
// Producer
// ---------------------------------------------------------------------------

/// Create a Kafka producer handle (topic + client) for use by the output dispatcher.
pub async fn create_producer(
    output_name: &str,
    cfg: KafkaProducerConfig,
) -> Result<KafkaOutput, String> {
    let (partition_client, topic) =
        build_partition_client(output_name, &cfg.brokers, &cfg.topic).await?;

    Ok(KafkaOutput {
        client: Arc::new(partition_client),
        topic,
    })
}

/// Handle to a Kafka output partition.
pub struct KafkaOutput {
    pub client: Arc<rskafka::client::partition::PartitionClient>,
    pub topic: String,
}
