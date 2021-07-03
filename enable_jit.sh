#! /bin/bash
#
# You can only create JIT policies from Azure Powershell or from the REST API, 
# so to stay consistent I wrote this little hack that creates a new JIT policy using simple
# curl requests and assuming you are currently logged on using az login.
# You should call this script with 2 arguments:
# $1 is the resource group name, and $2 is the wanted JIT policy name.

SUB_ID=$(az account show --query "id" -o tsv) # subscription id, assumes single subscription
RG_NAME=$1 # our resource group name
ASC_LOCATION=$(az group show --resource-group $RG_NAME --query location -o tsv) # query the location of the resource group
POLICY_NAME=$2 # new jit policy name
VIRTUAL_MACHINES=$(az vm list --resource-group $RG_NAME --query "[].id" -o tsv) # lists all vms in resource group to apply the policy
POLICY_ID="/subscriptions/$SUB_ID/resourceGroups/$RG_NAME/providers/Microsoft.Security/locations/$ASC_LOCATION/jitNetworkAccessPolicies/$POLICY_NAME" # new policy id

# add all VMs to a json so we can send it as a request
for VM_ID in $VIRTUAL_MACHINES
do
    echo $VM_ID
    if [ "$VMS_JSON" ]
    then
        VMS_JSON+=",{\"id\": \"$VM_ID\", \"ports\": \
        [{\"number\": 3389, \"protocol\": \"*\", \"allowedSourceAddressPrefix\": \"*\", \"maxRequestAccessDuration\": \"PT1H\"},\
        {\"number\": 5985, \"protocol\": \"*\", \"allowedSourceAddressPrefix\": \"*\", \"maxRequestAccessDuration\": \"PT1H\"}]}"
    else
        VMS_JSON="{\"id\": \"$VM_ID\", \"ports\": \
        [{\"number\": 3389, \"protocol\": \"*\", \"allowedSourceAddressPrefix\": \"*\", \"maxRequestAccessDuration\": \"PT1H\"},\
        {\"number\": 5985, \"protocol\": \"*\", \"allowedSourceAddressPrefix\": \"*\", \"maxRequestAccessDuration\": \"PT1H\"}]}"
    fi
done
JSON="{\"kind\": \"Basic\", \"properties\": {\"virtualMachines\": [$VMS_JSON]}, \"id\": \"$POLICY_ID\", \"name\": \"$POLICY_NAME\", \"type\": \"Microsoft.Security/locations/jitNetworkAccessPolicies\", \"location\": \"$ASC_LOCATION\"}"
curl -X PUT -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" -H "Content-Type: application/json" -d "$JSON" "https://management.azure.com${POLICY_ID}?api-version=2020-01-01"