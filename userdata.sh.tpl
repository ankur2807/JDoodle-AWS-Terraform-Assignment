Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash

# Install Cloudwatch agent
sudo yum install -y amazon-cloudwatch-agent

# Write Cloudwatch agent configuration file
sudo cat >> /opt/serverload.sh <<'EOF'
#!/usr/bin/env bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin

#Grab the load (and only the first 1 minute average)
load=$( cat /proc/loadavg | awk '{print $2;}' )

#to get the instance-ID
id=`cat /var/lib/cloud/data/instance-id`

#echo $id 
#echo $load
#aws cloudwatch put-metric-data --metric-name="5m_load"  --namespace "AWS/AutoScaling/Group Metrics"  --dimensions Instance=$id --value $load --region us-east-2
aws cloudwatch put-metric-data --namespace "aws/autoscaling" --metric-name "5m_load" --value load --dimensions AutoScalingGroupName=aws_autoscaling_group.autoscaling_group.arn


EOF

sudo chmod +x /opt/serverload.sh
sudo echo '* * * * * /bin/sh /opt/serverload.sh' | crontab

# Start Cloudwatch agent
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a start
--==BOUNDARY==--