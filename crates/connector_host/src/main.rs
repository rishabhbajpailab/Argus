mod connectors;
mod envelope;
mod protocol;
mod sinks;

use std::collections::HashMap;
use std::io::{self, BufRead, Write};
use std::sync::Arc;

use rskafka::record::Record;
use tokio::sync::{mpsc, Mutex};
use tracing::{error, info, warn};

use connectors::kafka::KafkaOutput;
use protocol::{Command, Event};

// ---------------------------------------------------------------------------
// Output registry — holds producer handles keyed by output name
// ---------------------------------------------------------------------------

enum OutputHandle {
    Kafka(KafkaOutput),
    Log {
        config: HashMap<String, serde_json::Value>,
    },
}

type OutputRegistry = Arc<Mutex<HashMap<String, OutputHandle>>>;

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_writer(std::io::stderr)
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("connector_host=info".parse().unwrap()),
        )
        .init();

    info!("connector_host starting");

    // Channel for inbound events produced by connector tasks
    let (event_tx, mut event_rx) = mpsc::channel::<Event>(1024);

    let outputs: OutputRegistry = Arc::new(Mutex::new(HashMap::new()));

    // -- Stdin reader task --------------------------------------------------
    // Reads line-delimited JSON commands from stdin (sent by Elixir).
    let outputs_clone = outputs.clone();
    let event_tx_clone = event_tx.clone();

    let stdin_task = tokio::task::spawn_blocking(move || {
        let stdin = io::stdin();
        let rt = tokio::runtime::Handle::current();
        for line in stdin.lock().lines() {
            match line {
                Ok(l) if l.trim().is_empty() => continue,
                Ok(l) => match serde_json::from_str::<Command>(&l) {
                    Ok(cmd) => {
                        rt.block_on(handle_command(cmd, &outputs_clone, &event_tx_clone));
                    }
                    Err(e) => {
                        warn!("Failed to parse command: {} — line: {}", e, l);
                    }
                },
                Err(e) => {
                    info!("Stdin closed ({}), shutting down", e);
                    break;
                }
            }
        }
    });

    // -- Stdout writer task ------------------------------------------------
    // Forwards events from connector tasks to Elixir via stdout.
    let stdout_task = tokio::spawn(async move {
        let stdout = io::stdout();
        while let Some(event) = event_rx.recv().await {
            let line = event.to_line();
            let mut out = stdout.lock();
            if let Err(e) = out.write_all(line.as_bytes()) {
                error!("Failed to write event to stdout: {}", e);
            }
        }
    });

    // Wait for stdin to close (Elixir closed the port or sent shutdown)
    let _ = stdin_task.await;

    info!("connector_host shutting down");
    drop(event_tx);
    let _ = stdout_task.await;
}

// ---------------------------------------------------------------------------
// Command dispatch
// ---------------------------------------------------------------------------

async fn handle_command(
    cmd: Command,
    outputs: &OutputRegistry,
    event_tx: &mpsc::Sender<Event>,
) {
    match cmd {
        Command::StartInput { name, config } => {
            let input_type = config
                .get("type")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");

            match input_type {
                "kafka" => {
                    info!("Starting Kafka input '{}'", name);
                    connectors::kafka::spawn_consumer(name, config, event_tx.clone());
                }
                // TODO(CODEX): "mqtt" => connectors::mqtt::spawn_consumer(...)
                // TODO(CODEX): "rabbitmq" => connectors::rabbitmq::spawn_consumer(...)
                other => {
                    warn!("Unknown input type '{}' for input '{}'", other, name);
                }
            }
        }

        Command::StartOutput { name, config } => {
            let output_type = config
                .get("type")
                .and_then(|v| v.as_str())
                .unwrap_or("unknown");

            let handle = match output_type {
                "kafka" => {
                    match connectors::kafka::create_producer(&name, &config).await {
                        Ok(kafka_out) => OutputHandle::Kafka(kafka_out),
                        Err(e) => {
                            error!("Failed to create Kafka output '{}': {}", name, e);
                            return;
                        }
                    }
                }
                "log" => {
                    info!("Starting log output '{}'", name);
                    OutputHandle::Log { config }
                }
                // TODO(CODEX): "mqtt" => ...
                // TODO(CODEX): "postgres" => sinks::postgres::create_handle(...)
                other => {
                    warn!("Unknown output type '{}' for output '{}'", other, name);
                    return;
                }
            };

            outputs.lock().await.insert(name, handle);
        }

        Command::SendOutput { name, envelope } => {
            let mut registry = outputs.lock().await;

            match registry.get_mut(&name) {
                Some(OutputHandle::Kafka(kafka_out)) => {
                    let payload = serde_json::to_vec(&envelope)
                        .unwrap_or_else(|_| b"{}".to_vec());

                    let record = Record {
                        key: None,
                        value: Some(payload),
                        headers: Default::default(),
                        timestamp: chrono::Utc::now(),
                    };

                    match kafka_out.client.produce(vec![record], rskafka::client::partition::Compression::NoCompression).await {
                        Ok(_) => {
                            let ack = Event::Ack {
                                correlation_ref: Some(envelope.id.clone()),
                            };
                            let _ = event_tx.send(ack).await;
                        }
                        Err(e) => {
                            error!("Kafka produce error for output '{}': {}", name, e);
                            let err = Event::Error {
                                message: format!("Kafka produce failed: {}", e),
                                details: None,
                            };
                            let _ = event_tx.send(err).await;
                        }
                    }
                }

                Some(OutputHandle::Log { config }) => {
                    sinks::log::emit(&name, &envelope, config);
                    let ack = Event::Ack {
                        correlation_ref: Some(envelope.id.clone()),
                    };
                    let _ = event_tx.send(ack).await;
                }

                None => {
                    warn!("send_output: unknown output name '{}'", name);
                }
            }
        }

        Command::Shutdown => {
            info!("Received shutdown command");
            std::process::exit(0);
        }
    }
}
