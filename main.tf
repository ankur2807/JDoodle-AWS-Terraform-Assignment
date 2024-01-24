provider "aws" {
  region = "us-east-2"  
}


# Create VPC
resource "aws_vpc" "main" {
  cidr_block = "10.10.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
}

# Create Subnets
resource "aws_subnet" "subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "us-east-2a"  
}

resource "aws_subnet" "subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "us-east-2b"  
}

# Create IAM Role and Policy for Auto Scaling
resource "aws_iam_role" "autoscaling_role" {
  name = "autoscaling_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com",
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "autoscaling_policy" {
  name        = "autoscaling_policy"
  description = "IAM policy for Auto Scaling"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "autoscaling:Describe*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "autoscaling:UpdateAutoScalingGroup",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "ec2:Describe*",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "autoscaling_attachment" {
  policy_arn = aws_iam_policy.autoscaling_policy.arn
  role       = aws_iam_role.autoscaling_role.name
}


# Create Auto Scaling Group

resource "aws_launch_configuration" "autoscaling_config" {
  name = "autoscaling_config"
  image_id = "ami-0c55b159cbfafe1f0"  # Replace with your desired Ubuntu AMI
  instance_type = "t2.micro"
}

resource "aws_autoscaling_group" "autoscaling_group" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 2
  health_check_type    = "EC2"
  health_check_grace_period = 300
  force_delete          = true
  vpc_zone_identifier  = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  launch_configuration = aws_launch_configuration.autoscaling_config.id

  tag {
    key                 = "Name"
    value               = "MyAutoScalingGroup"
    propagate_at_launch = true
  }
}

# Create CloudWatch Alarms for Auto Scaling Policies
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "ScaleUpAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupDesiredCapacity"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 4  # Trigger when desired capacity is greater than or equal to 4
  alarm_actions       = [aws_autoscaling_policy.scale_up_policy.arn]
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "ScaleDownAlarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "GroupDesiredCapacity"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 2  # Trigger when desired capacity is less than or equal to 2
  alarm_actions       = [aws_autoscaling_policy.scale_down_policy.arn]
}

# Create Auto Scaling Policies
resource "aws_autoscaling_policy" "scale_up_policy" {
  name                   = "ScaleUpPolicy"
  scaling_adjustment    = 1
  cooldown              = 300
  adjustment_type       = "ChangeInCapacity"
  #cooldown_action       = "Default"
  #estimated_instance_warmup = 300

  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
}

resource "aws_autoscaling_policy" "scale_down_policy" {
  name                   = "ScaleDownPolicy"
  scaling_adjustment    = -1
  cooldown              = 300
  adjustment_type       = "ChangeInCapacity"
  #cooldown_action       = "Default"
  #estimated_instance_warmup = 300

  autoscaling_group_name = aws_autoscaling_group.autoscaling_group.name
}

# Create EventBridge Rules
resource "aws_cloudwatch_event_rule" "scale_up_event_rule" {
  name        = "ScaleUpEventRule"
  description = "Event rule for scaling up"
  event_pattern = <<PATTERN
{
  "source": ["aws.autoscaling"],
  "detail-type": ["EC2 Instance Launch Successful"],
  "resources": ["${aws_autoscaling_group.autoscaling_group.arn}"]
}
PATTERN
}

resource "aws_cloudwatch_event_rule" "scale_down_event_rule" {
  name        = "ScaleDownEventRule"
  description = "Event rule for scaling down"
  event_pattern = <<PATTERN
{
  "source": ["aws.autoscaling"],
  "detail-type": ["EC2 Instance Terminate Successful"],
  "resources": ["${aws_autoscaling_group.autoscaling_group.arn}"]
}
PATTERN
}


# Email Notification for Scaling Events
resource "aws_sns_topic" "scaling_alerts" {
  name = "ScalingAlerts"
}

resource "aws_cloudwatch_event_target" "scale_up_email_target" {
  rule      = aws_cloudwatch_event_rule.scale_up_event_rule.name
  arn       = aws_sns_topic.scaling_alerts.arn
}

resource "aws_cloudwatch_event_target" "scale_down_email_target" {
  rule      = aws_cloudwatch_event_rule.scale_down_event_rule.name
  arn       = aws_sns_topic.scaling_alerts.arn
}


#Lambda Function 

resource "aws_cloudwatch_event_rule" "daily_refresh_rule" {
  name        = "DailyRefreshRule"
  description = "Event rule for daily refresh at UTC 12 am"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_target" "daily_refresh_target" {
  rule      = aws_cloudwatch_event_rule.daily_refresh_rule.name
  arn       = aws_lambda_function.daily_refresh_function.arn
}

resource "aws_lambda_function" "daily_refresh_function" {
  function_name = "DailyRefreshFunction"
  handler      = "lambda_function.lambda_handler"
  runtime      = "python3.8"
  role         = aws_iam_role.autoscaling_role.arn
  filename     = "${path.module}/lambda_function.zip"
}

# Use a data block to include the Lambda function code in the deployment package
data "archive_file" "lambda_function" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}