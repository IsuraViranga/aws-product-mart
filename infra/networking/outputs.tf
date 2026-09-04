output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  value = aws_subnet.private_data[*].id
}

output "sg_alb_id" {
  value = aws_security_group.alb.id
}

output "sg_eks_nodes_id" {
  value = aws_security_group.eks_nodes.id
}

output "sg_rds_id" {
  value = aws_security_group.rds.id
}