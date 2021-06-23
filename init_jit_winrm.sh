#! /bin/bash

# Similarly to enable_jit.sh, this script is a little hack to initiate
# JIT connection to a VM using azure's REST API assuming the user running
# the script is authorized using az login.

SUB_ID=$(az account show --query "id" -o tsv) # subscription id, assumes single subscription
RG_NAME=$1 # our resource group name
ASC_LOCATION=$(az group show --resource-group rundeck_test --query location -o tsv) # query the location of the resource group
POLICY_NAME=$2 # new jit policy name
VIRTUAL_MACHINES=$(az vm list --resource-group $RG_NAME --query "[].id" -o tsv) # lists all vms in resource group to apply the policy
POLICY_ID="/subscriptions/$SUB_ID/resourceGroups/$RG_NAME/providers/Microsoft.Security/locations/$ASC_LOCATION/jitNetworkAccessPolicies/$POLICY_NAME" # new policy id
MY_IP=$(curl ifconfig.me)

for VM_NAME in "${@:3}" # iterate through all args starting with the third
do
    VM_ID=$(az vm show --resource-group $RG_NAME --name $VM_NAME --query id -o tsv)
    if [ "$VMS_JSON" ]
    then
        VMS_JSON+=",{\"id\": \"$VM_ID\", \"ports\": [{\"number\": 5985, \"allowedSourceAddressPrefix\": \"$MY_IP\", \"duration\": \"PT1H\"}]}"
    else
        VMS_JSON="{\"id\": \"$VM_ID\", \"ports\": [{\"number\": 5985, \"allowedSourceAddressPrefix\": \"$MY_IP\", \"duration\": \"PT1H\"}]}"
    fi
done

JSON="{\"virtualMachines\": [$VMS_JSON], \"justification\": \"Ansible provisioning\"}"
echo $JSON
curl -X POST -H "Authorization: Bearer $(az account get-access-token --query accessToken -o tsv)" -H "Content-Type: application/json" -d "$JSON" "https://management.azure.com${POLICY_ID}/initiate?api-version=2020-01-01"