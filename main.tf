provider "aws" {
  region = "us-east-2"  # Change this to your desired region
}
# Create VPC
data "aws_vpc" "default" {
  id = "vpc-06715e7197852424f"
}

data "aws_subnet" "subnet1" {
  id = "subnet-0b6b31310178f04fd"
}

data "aws_subnet" "subnet2" {
  id = "subnet-011b0512b6d93aff6"

}

data "template_file" "user_data" {
  template = file("${path.module}/userdata.sh.tpl")

  
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
        "Service": ["ec2.amazonaws.com", "lambda.amazonaws.com"]
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

resource "aws_iam_role" "cloudwatch_agent_role" {
  name = "CloudWatchAgentRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "cloudwatch_agent_policy" {
  name        = "CloudWatchAgentPolicy"
  description = "Policy for CloudWatch Agent"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "cloudwatch:PutMetricData",
          "ec2:DescribeTags",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_attachment" {
  policy_arn = aws_iam_policy.cloudwatch_agent_policy.arn
  role       = aws_iam_role.cloudwatch_agent_role.name
}

resource "aws_iam_instance_profile" "cloudwatch_agent_instance_profile" {
  name = "InsProfileExample"

  role = aws_iam_role.cloudwatch_agent_role.name
}


# Create Auto Scaling Group

resource "aws_launch_configuration" "autoscaling_config" {
  name = "autoscaling_config"
  image_id = "ami-0a9a47155910e782f"  # Replace with your desired Ubuntu AMI
  instance_type = "t2.micro"
  key_name = "test"
  associate_public_ip_address = true
  user_data     = data.template_file.user_data.rendered


  # Add user data to install and configure CloudWatch agent
  

  iam_instance_profile = aws_iam_instance_profile.cloudwatch_agent_instance_profile.name
}

resource "aws_autoscaling_group" "autoscaling_group" {
  desired_capacity     = 2
  max_size             = 5
  min_size             = 2
  health_check_type    = "EC2"
  health_check_grace_period = 300
  force_delete          = true
  vpc_zone_identifier  = [data.aws_subnet.subnet1.id, data.aws_subnet.subnet2.id]
  launch_configuration = aws_launch_configuration.autoscaling_config.id

  tag {
    key                 = "Name"
    value               = "MyAutoScalingGroup"
    propagate_at_launch = true
  }
}

#resource "aws_iam_instance_profile" "cloudwatch_agent_instance_profile" {
  #name = "InsProfileExample"

  #role = aws_iam_role.cloudwatch_agent_role.name
#}

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


# Create CloudWatch Alarms for Auto Scaling Policies
resource "aws_cloudwatch_metric_alarm" "scale_up_alarm" {
  alarm_name          = "tf-ScaleUpAlarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "5m_load"
  namespace           = "AWS/AutoScaling/"
  period              = "300"
  statistic           = "Average"
  threshold           = "10"  # Trigger when desired capacity is greater than or equal to 4

  #dimensions = {
    #InstanceId = "i-08a80e7bc0011ef4b"
  #}

  dimensions = {
  AutoScalingGroupName=aws_autoscaling_group.autoscaling_group.arn
  }
  #ok_actions          = [aws_sns_topic.scaling_alerts.arn]
  #ok_actions          = [aws_autoscaling_policy.scale_up_policy.arn]
  alarm_actions       = [aws_autoscaling_policy.scale_up_policy.arn]
}

resource "aws_cloudwatch_metric_alarm" "scale_down_alarm" {
  alarm_name          = "ScaleDownAlarm"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "5m_load"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 50  # Trigger when desired capacity is less than or equal to 2

  alarm_actions       = [aws_autoscaling_policy.scale_down_policy.arn]
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

