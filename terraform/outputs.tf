output "topics_created" {
  description = "Kafka topics created for the factory pipeline"
  value       = [for t in confluent_kafka_topic.factory_topics : t.topic_name]
}

output "bootstrap_server" {
  description = "Bootstrap server — use this in the Ignition Kafka connection"
  value       = var.confluent_bootstrap_server
}
