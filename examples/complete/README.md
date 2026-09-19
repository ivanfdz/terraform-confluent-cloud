# Complete example

Consumes the root module: looks up an existing environment and Kafka cluster,
creates a service account with a role binding and a Kafka API key, then manages
22 topics across three groups (compacted CDC, retained producer events, stream
output).

Requires an existing Confluent Cloud environment named `dev` containing a
cluster named `shared-dev-cluster`. Change `environment` and `cluster_name` in
`main.tf` to match yours.

```bash
export TF_VAR_confluent_cloud_api_key="..."
export TF_VAR_confluent_cloud_api_secret="..."

terraform init
terraform plan
```

State is local here on purpose, so the example runs without configuring the S3
backend the root module declares. Do not do that for anything real: the plan
puts the generated Kafka API secret in state in plain text.

`terraform validate` emits one warning here:

```
Warning: Backend configuration ignored
  on ../../versions.tf line 21, in terraform:
  21:   backend "s3" {}
```

That is expected and harmless. The root module declares a backend, and a backend
only applies to the configuration that is actually the root. Calling a root
module as a child, which is exactly what this example does, means the block is
ignored. Terraform reports it as a warning rather than an error for this case.
