 variable "smtp_user" {
    description = "The SMTP username for sending emails"
    type        = string
    sensitive = true
  }

  variable "smtp_password" {
    description = "The SMTP password for sending emails"
    type        = string
    sensitive = true
  }