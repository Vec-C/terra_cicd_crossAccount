# terra_cicd_crossAccount

With the aws-cli tool configure a DESTINATION account profile.

Inside the main.tf file at root level replace the <<PROFILE>> tag with the profile name.

Create a file inside the create_repo directory named secrets.tf with the following structure:

#PROFILE\
aws-access-key = "XXXXXXXXXXXXX"\
aws-secret-key = "XXXXXXXXXXXXXXXXXX"

Replace the values with your AWS SOURCE Access and Secret keys.

In the terminal at the create_repo directory level type:

terraform init
terraform plan -var-file="secrets.tf"
terraform apply -var-file="secrets.tf"

____________________________________________

Verify that the owners of the access keys has being properly configured to use the policies inside the iam-policies directory.

DESTINATION: account where a pipeline will be triggered by a new commit (prod).
SOURCE:      account where the repository is created (dev).
