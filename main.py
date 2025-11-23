"""
MIG Scheduler Cloud Function
Handles Pub/Sub messages to scale up/down Google Cloud Managed Instance Groups
"""

import os
import base64
import json
import logging
from google.cloud import compute_v1
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class MIGScheduler:
    """Manages MIG operations for scaling"""
    
    def __init__(self, project_id):
        self.project_id = project_id or os.environ.get('GCP_PROJECT')
        self.mig_client = compute_v1.RegionInstanceGroupManagersClient()
        
    def get_mig_info(self, region, mig_name):
        """Get MIG information"""
        try:
            request = compute_v1.GetRegionInstanceGroupManagerRequest(
                project=self.project_id,
                region=region,
                instance_group_manager=mig_name
            )
            mig = self.mig_client.get(request=request)
            return {
                'name': mig.name,
                'region': region,
                'target_size': mig.target_size,
                'status': mig.status.is_stable
            }
        except Exception as e:
            logger.error(f"Error getting MIG {mig_name} in region {region}: {e}")
            return None
    
    def scale_down_mig(self, region, mig_name):
        """Scale down MIG to 0 instances"""
        try:
            request = compute_v1.ResizeRegionInstanceGroupManagerRequest(
                project=self.project_id,
                region=region,
                instance_group_manager=mig_name,
                size=0
            )
            
            operation = self.mig_client.resize(request=request)
            logger.info(f"Scaling down MIG {mig_name} to 0 instances in region {region}")
            return {'status': 'success', 'operation': operation.name, 'target_size': 0}
            
        except Exception as e:
            logger.error(f"Error scaling down MIG {mig_name}: {e}")
            return {'status': 'error', 'message': str(e)}
    
    def scale_up_mig(self, region, mig_name, target_size):
        """Scale up MIG to specified target size"""
        try:
            request = compute_v1.ResizeRegionInstanceGroupManagerRequest(
                project=self.project_id,
                region=region,
                instance_group_manager=mig_name,
                size=target_size
            )
            
            operation = self.mig_client.resize(request=request)
            logger.info(f"Scaling up MIG {mig_name} to {target_size} instances in region {region}")
            return {'status': 'success', 'operation': operation.name, 'target_size': target_size}
            
        except Exception as e:
            logger.error(f"Error scaling up MIG {mig_name}: {e}")
            return {'status': 'error', 'message': str(e)}


def process_scale_action(action, project_id=None, mig_name=None, region=None, scale_up_size=None):
    """Process scale up or scale down action for MIG"""
    
    # Get project ID from environment
    if not project_id:
        project_id = os.environ.get('GCP_PROJECT')
    
    if not project_id:
        logger.error('Project ID not configured')
        return {'error': 'Project ID not configured'}
    
    # Get MIG name and region from environment if not provided
    if not mig_name:
        mig_name = os.environ.get('MIG_NAME', 'oracle-linux-mig')
    
    if not region:
        region = os.environ.get('MIG_REGION', 'us-central1')
    
    scheduler = MIGScheduler(project_id)
    
    # Get current MIG info
    mig_info = scheduler.get_mig_info(region, mig_name)
    if not mig_info:
        logger.error(f'MIG {mig_name} not found in region {region}')
        return {'error': f'MIG {mig_name} not found'}
    
    logger.info(f'Current MIG size: {mig_info["target_size"]}')
    
    # Perform action
    if action == 'scale_down':
        if mig_info['target_size'] == 0:
            logger.info(f'MIG {mig_name} already scaled down to 0')
            return {'message': 'MIG already scaled down', 'target_size': 0}
        
        result = scheduler.scale_down_mig(region, mig_name)
        return {
            'action': 'scale_down',
            'mig': mig_name,
            'region': region,
            'previous_size': mig_info['target_size'],
            'new_size': 0,
            'result': result
        }
    
    elif action == 'scale_up':
        # Get target size for scale up
        if not scale_up_size:
            scale_up_size = int(os.environ.get('MIG_SCALE_UP_SIZE', '3'))
        
        if mig_info['target_size'] >= scale_up_size:
            logger.info(f'MIG {mig_name} already at or above target size {scale_up_size}')
            return {'message': 'MIG already scaled up', 'target_size': mig_info['target_size']}
        
        result = scheduler.scale_up_mig(region, mig_name, scale_up_size)
        return {
            'action': 'scale_up',
            'mig': mig_name,
            'region': region,
            'previous_size': mig_info['target_size'],
            'new_size': scale_up_size,
            'result': result
        }
    
    else:
        return {'error': f'Unknown action: {action}'}


@functions_framework.cloud_event
def mig_scheduler(cloud_event):
    """
    Cloud Function triggered by Pub/Sub.
    Args:
        cloud_event: CloudEvent object containing Pub/Sub message
    """
    
    # Decode Pub/Sub message
    try:
        message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
        data = json.loads(message_data)
    except Exception as e:
        logger.error(f'Error decoding message: {e}')
        data = {}
    
    # Get parameters from message
    action = data.get('action', 'scale_down')
    project_id = data.get('project_id')
    mig_name = data.get('mig_name')
    region = data.get('region')
    scale_up_size = data.get('scale_up_size')
    
    logger.info(f'Processing action: {action} for MIG: {mig_name or os.environ.get("MIG_NAME")}')
    
    # Process the action
    result = process_scale_action(action, project_id, mig_name, region, scale_up_size)
    
    logger.info(f'Action completed: {result}')
    
    return result
