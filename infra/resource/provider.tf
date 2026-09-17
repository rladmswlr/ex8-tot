terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket         = "std16-test-bucket"
    key            = "terraformState/Ex/ex8-tot/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "std16-lab-lock-table"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-2"
}
