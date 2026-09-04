output "repository_urls" {
  value = {
    for k, v in aws_ecr_repository.services : k => v.repository_url
  }
}

output "registry_id" {
  value = "175342148842.dkr.ecr.us-east-1.amazonaws.com"
}