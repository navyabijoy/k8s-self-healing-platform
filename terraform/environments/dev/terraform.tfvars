project_name = "self-healing-eks"
environment  = "dev"
aws_region   = "us-east-1"

on_demand_desired_size = 2
on_demand_min_size     = 1
on_demand_max_size     = 3
spot_desired_size      = 1
spot_min_size          = 0
spot_max_size          = 3

db_name           = "appdb"
db_username       = "appuser"
db_instance_class = "db.t3.micro"
