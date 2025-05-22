variable "aws_region" { default = "us-east-1" }
variable "db_username" { default = "admin" }
variable "db_password" { default = "admin1234" }
variable "db_name"     { default = "castopod" }
variable "cp_analytics_salt" { description = "Cadena aleatoria para Castopod" }
variable "labrole_arn" { description = "ARN del LabRole" }
