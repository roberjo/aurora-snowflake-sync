# ---------------------------------------------------------------------------------------------------------------------
# STATE MODULE: VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

variable "project_name" {
  description = "Project name used for naming resources."
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
