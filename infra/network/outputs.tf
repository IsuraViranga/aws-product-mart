# Re-exported so infra/eks can read them via terraform_remote_state.

output "vpc_id" { value = module.networking.vpc_id }
output "vpc_cidr" { value = module.networking.vpc_cidr }
output "public_subnet_ids" { value = module.networking.public_subnet_ids }
output "private_app_subnet_ids" { value = module.networking.private_app_subnet_ids }
output "private_data_subnet_ids" { value = module.networking.private_data_subnet_ids }
output "availability_zones" { value = module.networking.availability_zones }
output "nat_gateway_enabled" { value = module.networking.nat_gateway_enabled }
