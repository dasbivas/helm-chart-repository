#!/bin/bash
for repoRef in $(yq eval -o=j mirror-charts.yaml | jq -cr '.repositories[]'); do
  repo=$(echo $repoRef| jq -r '.repo' -)
  url=$(echo $repoRef | jq -r '.url' -)
  helm repo add $repo $url
done
helm repo --username=gitlab-ci-token --password=$CI_JOB_TOKEN add tdcnet https://gitlab.com/api/v4/projects/46954432/packages/helm/stable
helm repo update
