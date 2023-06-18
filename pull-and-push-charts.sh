#!/bin/bash

# Variables for testing purpose:
export CI_API_V4_URL=https://gitlab.com/api/v4
export CI_PROJECT_ID=46954432
export CHANNEL=stable

for chartRef in $(yq eval -o=j mirror-charts.yaml | jq -cr '.charts[]'); do
  repo=$(echo $chartRef| jq -r '.repo' -)
  chart=$(echo $chartRef | jq -r '.chart' -)
  version=$(echo $chartRef | jq -r '.version' -)

  exists=`helm search repo tdcnet/$chart --version $version | grep -v $chart- | grep -c $chart`
  if [[ $exists == 1 ]]; then
    echo "$chart $version already exists"
    #echo "Verify downloadable"
    #helm pull tdcnet/$chart --version $version --debug
    #if [[ $? == 0 ]]; then
      continue;
    #fi
  fi

  echo pull $repo/$chart $version
  helm pull $repo/$chart --version $version

  echo push $chart $version
  success=0
  # Sometimes the upload does not work, most likely a bug in GitLab. Retry up to 5 times
  for retry in {1..5}; do
    echo "Push chart"
    curl --request POST --user "gitlab-ci-token:$CI_JOB_TOKEN" --form "chart=@$chart-$version.tgz" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/helm/api/${CHANNEL}/charts"
    sleep 5
    echo ""
    helm repo update tdcnet $repo
    mv $chart-$version.tgz $chart-$version-org.tgz 
    helm pull tdcnet/$chart --version $version
    if diff -b $chart-$version-org.tgz $chart-$version.tgz >/dev/null 2>&1
    then
      echo "Uploaded successful"
      success=1
      break
    else
      echo "Failed to upload chart. Will retry by deleting existing chart before uploading again"
      # Find the id of the package
      curl --header "PRIVATE-TOKEN:$PROJECT_TOKEN" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages?package_type=helm&package_name=$chart&exclude_subgroups=true&" --silent -o packages.json -w "%{http_code}\n" >http_code.log
      declare statusCode=$(cat http_code.log)
      echo "Fetch ID of chart returned HTTP code: ${statusCode}"
      if (( $statusCode < 300 )); then
        id=`cat packages.json | jq --arg version "$version" -c '.[] | select(.version == ($version))  | .id'`
        if [[ $id < 1000 ]]; then
          echo Probably not a correct ID "$id"
          echo output from GitLap get packages:
          cat packages.json
          exit 10
        fi
        echo Deleting package $chart-$version with ID $id
        curl --request DELETE --header "PRIVATE-TOKEN:$PROJECT_TOKEN" "${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/$id"
      else
        echo "ERROR: Failed to get ID of helm chart. Status code $statusCode. Payload:"
        cat packages.json
      fi
      # Restore file to upload
      mv $chart-$version-org.tgz $chart-$version.tgz 
    fi
  done
  if [[ $success != 1 ]]; then
    echo "Failed to upload chart. Retry failed"
    exit 11
  fi
done
