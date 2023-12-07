# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A CI/CD PIPELINE WITH CODECOMMIT USING AWS
# This module creates a CodePipeline with CodeBuild that is linked to a CodeCommit repository.
# Note: CodeCommit does not create a master branch initially. Once this script is run, you must clone the repo, and
# then push to origin master.
# ---------------------------------------------------------------------------------------------------------------------

#provider "aws" {
#  access_key = var.aws-access-key
#  secret_key = var.aws-secret-key
#  region     = var.aws-region
#}

# Generae a unique label for naming resources
module "unique_label" {
  source     = "./uniqueLabel"
  namespace  = var.organization_name
  name       = var.repo_name
  stage      = var.environment
  delimiter  = var.char_delimiter
  attributes = []
  tags       = {}
}

provider "aws" {
  alias   = "destination"
  profile = "core-prod"
  region  = "us-east-1"
}

data "aws_caller_identity" "dest" {
  provider = aws.destination
}

# CodeCommit resources
resource "aws_codecommit_repository" "repo" {
  repository_name = var.repo_name
  description     = "${var.repo_name} repository."
  default_branch  = var.repo_default_branch
}

# CodePipeline resources
resource "aws_s3_bucket" "build_artifact_bucket" {
  bucket        = module.unique_label.id
  acl           = "private"
  force_destroy = var.force_artifact_destroy
}

data "aws_iam_policy_document" "codepipeline_assume_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "${module.unique_label.name}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume_policy.json
}

resource "aws_iam_role_policy" "attach_codepipeline_policy" {
  name = "${module.unique_label.name}-codepipeline-policy"
  role = aws_iam_role.codepipeline_role.id
  depends_on = [aws_s3_bucket.build_artifact_bucket]
  policy = templatefile(
              "${path.module}/iam-policies/codepipeline.tpl",
               {
                artifact_bucket= aws_s3_bucket.build_artifact_bucket.arn
               }
              )
}

# kms
# Encryption key for build artifacts
# resource "aws_kms_key" "artifact_encryption_key" {
#   description             = "artifact-encryption-key"
#   deletion_window_in_days = 10
# }

# CodeBuild IAM Permissions

resource "aws_iam_role" "codebuild_assume_role" {
  name               = "${module.unique_label.name}-codebuild-role"
  assume_role_policy =  templatefile(
              "${path.module}/iam-policies/codebuild_assume_role.tpl",
               {
                 config = {}
               }
              )
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${module.unique_label.name}-codebuild-policy"
  role = aws_iam_role.codebuild_assume_role.id
  depends_on = [aws_s3_bucket.build_artifact_bucket, aws_codebuild_project.build_project]

  policy = templatefile(
              "${path.module}/iam-policies/codebuild.tpl",
               {
                  account_dest            = data.aws_caller_identity.dest.account_id
                  artifact_bucket         = aws_s3_bucket.build_artifact_bucket.arn
                  codebuild_project_build = aws_codebuild_project.build_project.id
               }
              )
}

# CodeBuild Section for the Package stage
resource "aws_codebuild_project" "build_project" {
  name           = "${var.repo_name}-package"
  description    = "The CodeBuild project for ${var.repo_name}"
  service_role   = aws_iam_role.codebuild_assume_role.arn
  build_timeout  = var.build_timeout
  #encryption_key = aws_kms_key.artifact_encryption_key.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = var.build_compute_type
    image           = var.build_image
    type            = "LINUX_CONTAINER"
    privileged_mode = var.build_privileged_override
  }

  source {
    type      = "CODECOMMIT"
    location = aws_codecommit_repository.repo.clone_url_ssh
    buildspec = var.package_buildspec
  }

  source_version = "master"

  depends_on = [
    aws_codecommit_repository.repo
  ]
}

# Full CodePipeline
resource "aws_codepipeline" "codepipeline" {
  name     = var.repo_name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.build_artifact_bucket.bucket
    type     = "S3"

    #encryption_key {
    #  id   = aws_kms_key.artifact_encryption_key.arn
    #  type = "KMS"
    #}
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source"]

      configuration = {
        RepositoryName = var.repo_name
        BranchName     = var.repo_default_branch
      }
    }
  }

  stage {
    name = "Package"

    action {
      name             = "Package"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source"]
      output_artifacts = ["packaged"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.build_project.name
      }
    }
  }
  depends_on = [
    aws_codebuild_project.build_project
  ]
}

data "aws_iam_policy_document" "assume_role" {
  provider = aws.destination
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession",
      "sts:SetSourceIdentity"
    ]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.codebuild_assume_role.arn]
    }
  }
}

resource "aws_iam_role" "assume_role" {
  provider            = aws.destination
  name                = "crossA_PIPE_${module.unique_label.id}"
  assume_role_policy  = data.aws_iam_policy_document.assume_role.json
  tags                = {}

}

resource "aws_iam_role_policy" "attach_assume_policy" {
  provider            = aws.destination
  name = "${module.unique_label.name}-2bassumed-policy"
  role = aws_iam_role.assume_role.id
  policy = templatefile(
              "${path.module}/iam-policies/2bassumed.tpl",
                {
                  account_dest   = data.aws_caller_identity.dest.account_id
                  artifact_bucket= "arn:aws:s3:::shared-artifacts-sessionm"
                }
          )
  depends_on = [aws_iam_role.assume_role]
}
