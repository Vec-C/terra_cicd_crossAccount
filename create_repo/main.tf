provider "aws" {
  access_key = var.aws-access-key
  secret_key = var.aws-secret-key
  region     = var.aws-region
}

module "basic_example" {
  source                    = "../"
  /* __ NOMENCLATURA: <servicio><pais>-<cluster>. EJEMPLO: "rappiordersmx-integration" __ */
  repo_name                 = "repoPipeTest-delete-crossA" 
  organization_name         = "company"
  repo_default_branch       = "master"
  char_delimiter            = "-"
  environment               = "Prod"
  build_timeout             = "15"
  build_compute_type        = "BUILD_GENERAL1_SMALL"
  build_image               = "aws/codebuild/standard:3.0"
  build_privileged_override = true
  package_buildspec         = "./buildspec.yml"
  force_artifact_destroy    = false
}

