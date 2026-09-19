terraform {
  # optional() with a default in an object type attribute requires 1.3. 1.5 is the
  # floor used here because it is the first release with `import` blocks, which is
  # how existing topics are adopted into this configuration (see README).
  required_version = ">= 1.5"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.83"
    }
  }

  # Partial backend configuration. Bucket, key and region are supplied at init time
  # from a file that is NOT committed:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # There are deliberately no access_key or secret_key arguments here. Credentials
  # belong in the environment or, better, in a role the CI job assumes via OIDC.
  backend "s3" {}
}
