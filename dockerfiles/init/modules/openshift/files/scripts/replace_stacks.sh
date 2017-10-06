#!/bin/bash
# Copyright (c) 2012-2017 Red Hat, Inc
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#

set -e


DEFAULT_CHE_ADMIN_USERNAME="admin"
DEFAULT_CHE_ADMIN_PASSWORD="admin"
CHE_ADMIN_USERNAME=${CHE_ADMIN_USERNAME:-${DEFAULT_CHE_ADMIN_USERNAME}}
CHE_ADMIN_PASSWORD=${CHE_ADMIN_PASSWORD:-${DEFAULT_CHE_ADMIN_PASSWORD}}

echo "[CHE] This script is going to replace Che stacks for current Che instance"

command -v oc >/dev/null 2>&1 || { echo >&2 "[CHE] [ERROR] Command line tool oc (https://docs.openshift.org/latest/cli_reference/get_started_cli.html) is required but it's not installed. Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "[CHE] [ERROR] Command line tool jq (https://stedolan.github.io/jq) is required but it's not installed. Aborting."; exit 1; }

if [ -z "${CHE_API_ENDPOINT+x}" ]; then
    echo -n "[CHE] Inferring $CHE_API_ENDPOINT..."
    che_host=$(oc get route che -o jsonpath='{.spec.host}')
    if [ -z "${che_host}" ]; then echo >&2 "[CHE] [ERROR] Failed to infer environment variable $CHE_API_ENDPOINT. Aborting. Please set it and run ${0} script again."; exit 1; fi
    if [[ $(oc get route che -o jsonpath='{.spec.tls}') ]]; then protocol="https" ; else protocol="http"; fi
    CHE_API_ENDPOINT="${protocol}://${che_host}/api"
    echo "done (${CHE_API_ENDPOINT})"
fi

if [ $CHE_MULTI_USER == "true" ];then
   keycloak_url=$(oc get route keycloak -o jsonpath='{.spec.host}' || echo "")
   keycloak_token=$(curl -s --data "grant_type=password&client_id=che-public&username=${CHE_ADMIN_USERNAME}&password=${CHE_ADMIN_PASSWORD}" $keycloak_url/auth/realms/che/protocol/openid-connect/token | jq -r '.access_token' )
fi

DEFAULT_NEW_STACKS_URL="https://raw.githubusercontent.com/redhat-developer/rh-che/master/assembly/fabric8-stacks/src/main/resources/stacks.json"
NEW_STACKS_URL=${NEW_STACKS_URL:-${DEFAULT_NEW_STACKS_URL}}

echo -n "[CHE] Fetching the list of current Che stacks..."
if [ $CHE_MULTI_USER == "true" ];then
    original_stacks_json=$(curl -X GET -s -H 'Accept: application/json' -H "Authorization: Bearer $keycloak_token" "${CHE_API_ENDPOINT}/stack?skipCount=0&maxItems=100")
else
    original_stacks_json=$(curl -X GET -s -H 'Accept: application/json' "${CHE_API_ENDPOINT}/stack?skipCount=0&maxItems=100")
fi

IFS=$'\n' original_stacks_ids=($(echo "${original_stacks_json}" | jq '.[].id'))
echo "done (${#original_stacks_ids[@]} stacks found)."

echo "[CHE] These stacks are going to be deleted."

for stack_id in "${original_stacks_ids[@]}"; do
    stack_id_no_quotes="${stack_id%\"}"
    stack_id_no_quotes="${stack_id_no_quotes#\"}"
    stack_id_no_spaces=${stack_id_no_quotes// /+}
    echo -n "[CHE] Deleting stack ${stack_id_no_spaces}..."
    if [ $CHE_MULTI_USER == "true" ];then
        http_code=$(curl -w '%{http_code}'  -s --output /dev/null -X DELETE -H 'Accept: application/json' -H "Authorization: Bearer $keycloak_token" "${CHE_API_ENDPOINT}/stack/${stack_id_no_spaces}")
    else
        http_code=$(curl -w '%{http_code}'  -s --output /dev/null -X DELETE --header 'Accept: application/json' "${CHE_API_ENDPOINT}/stack/${stack_id_no_spaces}")
    fi
    echo "done (HTTP code ${http_code})."
done
echo ""

echo -n "[CHE] Fetching the list of new Che stacks..."
#new_stacks_json=$(curl -X GET -s --header 'Accept: application/json' "${NEW_STACKS_URL}" | sed 's/\\\"//g' | sed 's/\"com\.redhat\.bayesian\.lsp\"//g' | sed 's/ws-agent\",/ws-agent\"/g')
new_stacks_json=$(curl -X GET -s --header 'Accept: application/json' "${NEW_STACKS_URL}" | sed 's/\"com\.redhat\.bayesian\.lsp\"//g' | sed 's/ws-agent\",/ws-agent\"/g')
echo "done."

echo "[CHE] These stacks will be added."
echo "${new_stacks_json}" | jq -c '.[]' | while read -r stack; do
     stack_id=$(echo "${stack}" | jq '.id')
     stack_id_no_quotes="${stack_id%\"}"
     stack_id_no_quotes="${stack_id_no_quotes#\"}"
     echo -n "[CHE] Adding stack ${stack_id_no_quotes}..."
     if [ $CHE_MULTI_USER == "true" ];then
         http_code=$(curl -w '%{http_code}' -s --output /dev/null -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' -H "Authorization: Bearer $keycloak_token" -d "${stack}" "${CHE_API_ENDPOINT}/stack")
     else
         http_code=$(curl -w '%{http_code}' -s --output /dev/null -X POST --header 'Content-Type: application/json' --header 'Accept: application/json' -d "${stack}" "${CHE_API_ENDPOINT}/stack")
     fi
     echo "done (HTTP code ${http_code})"
done

echo
echo
