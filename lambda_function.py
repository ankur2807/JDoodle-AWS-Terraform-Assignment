# Import the necessary modules
import boto3
import datetime

def lambda_handler(event, context):
    # Specify your Auto Scaling Group name
    auto_scaling_group_name = 'autoscaling_group'

    # Specify your AWS region
    region = 'us-east-2'

    # Create an EC2 Auto Scaling client
    autoscaling_client = boto3.client('autoscaling', region_name=region)

    # Get the current date and time in UTC
    current_utc_time = datetime.datetime.utcnow()
    
    # Check if the current time is not 12:00 AM UTC
    if current_utc_time.hour != 0 or current_utc_time.minute != 0:
        print("Not triggering the refresh at this time.")
        return {
            'statusCode': 200,
            'body': 'Not triggering the refresh at this time.'
        }

    try:
        # Set desired capacity to 0 to terminate instances
        response = autoscaling_client.update_auto_scaling_group(
            AutoScalingGroupName=auto_scaling_group_name,
            DesiredCapacity=0
        )
        print(f"Auto Scaling Group '{auto_scaling_group_name}' set to DesiredCapacity 0: {response}")

        # Wait for instances to terminate (you may adjust the wait time)
        waiter = autoscaling_client.get_waiter('group_exists')
        waiter.wait(
            AutoScalingGroupName=auto_scaling_group_name,
            WaiterConfig={'Delay': 30, 'MaxAttempts': 60}
        )

        # Set the desired capacity back to the original value to launch new instances
        response = autoscaling_client.update_auto_scaling_group(
            AutoScalingGroupName=auto_scaling_group_name,
            DesiredCapacity=your_original_desired_capacity
        )
        print(f"Auto Scaling Group '{auto_scaling_group_name}' set back to original DesiredCapacity: {response}")

        return {
            'statusCode': 200,
            'body': 'Auto Scaling Group refreshed successfully!'
        }

    except Exception as e:
        print(f"Error refreshing Auto Scaling Group: {e}")
        return {
            'statusCode': 500,
            'body': f'Error refreshing Auto Scaling Group: {e}'
        }
