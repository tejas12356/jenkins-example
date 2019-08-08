provider "aws" {
  region     = "${var.aws_region}"
}

data "aws_caller_identity" "current" { }

# First, we need a role to play with Lambda
resource "aws_iam_role" "iam_role_for_lambda" {
  name = "iam_role_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Here is a first lambda function that will run the code `eq_lambda.handler`
module "lambda" {
  source  = "./lambda"
  name    = "FizzBuzz"
  runtime = "java8"
  role    = "${aws_iam_role.iam_role_for_lambda.arn}"
}

# This is a second lambda function that will run the code
# `eq_lambda.post_handler`
module "lambda_post" {
  source  = "./lambda"
  name    = "eq_test_lambda"
  handler = "post_handler"
  runtime = "java8"
  role    = "${aws_iam_role.iam_role_for_lambda.arn}"
}

# Now, we need an API to expose those functions publicly
resource "aws_api_gateway_rest_api" "eq_api" {
  name = "eq API"
}

# The API requires at least one "endpoint", or "resource" in AWS terminology.
# The endpoint created here is: /eq
resource "aws_api_gateway_resource" "eq_api_res_eq" {
  rest_api_id = "${aws_api_gateway_rest_api.eq_api.id}"
  parent_id   = "${aws_api_gateway_rest_api.eq_api.root_resource_id}"
  path_part   = "eq"
}

# Until now, the resource created could not respond to anything. We must set up
# a HTTP method (or verb) for that!
# This is the code for method GET /eq, that will talk to the first lambda
module "eq_get" {
  source      = "./api_method"
  rest_api_id = "${aws_api_gateway_rest_api.eq_api.id}"
  resource_id = "${aws_api_gateway_resource.eq_api_res_eq.id}"
  method      = "GET"
  path        = "${aws_api_gateway_resource.eq_api_res_eq.path}"
  lambda      = "${module.lambda.name}"
  region      = "${var.aws_region}"
  account_id  = "${data.aws_caller_identity.current.account_id}"
}

# This is the code for method POST /eq, that will talk to the second lambda
module "eq_post" {
  source      = "./api_method"
  rest_api_id = "${aws_api_gateway_rest_api.eq_api.id}"
  resource_id = "${aws_api_gateway_resource.eq_api_res_eq.id}"
  method      = "POST"
  path        = "${aws_api_gateway_resource.eq_api_res_eq.path}"
  lambda      = "${module.lambda_post.name}"
  region      = "${var.aws_region}"
  account_id  = "${data.aws_caller_identity.current.account_id}"
}

# We can deploy the API now! (i.e. make it publicly available)
resource "aws_api_gateway_deployment" "eq_api_deployment" {
  rest_api_id = "${aws_api_gateway_rest_api.eq_api.id}"
  stage_name  = "production"
  description = "Deploy methods: ${module.eq_get.http_method} ${module.eq_post.http_method}"
}
