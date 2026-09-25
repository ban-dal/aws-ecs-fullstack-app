variable "account_id" { type = string }
variable "region" { type = string }
variable "environments" { type = set(string) }
variable "repository_subject" { type = string }
variable "state_bucket_arn" { type = string }
variable "audit_trail_arn" { type = string }
variable "audit_bucket_arn" { type = string }
