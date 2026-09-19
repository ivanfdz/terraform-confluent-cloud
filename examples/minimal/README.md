# Minimal example

Uses only `modules/topics`, against a cluster and a Kafka API key that already
exist. It shows the three things the module is for: shared defaults, a
per-topic partition override, and a per-topic config override that keeps the
rest of the defaults.

```bash
cp terraform.tfvars.example terraform.tfvars   # then edit
export TF_VAR_confluent_cloud_api_key="..."
export TF_VAR_confluent_cloud_api_secret="..."
export TF_VAR_kafka_api_key="..."
export TF_VAR_kafka_api_secret="..."

terraform init
terraform plan
```

Four topics are planned: `example.dev.orders`, `example.dev.customers`,
`example.dev.order_events` with 6 partitions, and `example.dev.order_state`
with `cleanup.policy=compact` while still inheriting `retention.ms` and
`min.insync.replicas` from `default_config`.
