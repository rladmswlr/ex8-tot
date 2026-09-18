variable "project_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cluster_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "cluster_role_arn" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "current_aws_arn" {
  type = string
}
